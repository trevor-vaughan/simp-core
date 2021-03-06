require 'spec_helper_tar'
require 'erb'
require 'pathname'

test_name 'puppetserver via tarball'

describe 'install SIMP via tarball' do

  use_puppet_repo = ENV['BEAKER_puppet_repo'] || true

  # TODO Rework tests to really work with multiple masters
  masters        = hosts_with_role(hosts, 'master')
  agents         = hosts_with_role(hosts, 'agent')
  syslog_servers = hosts_with_role(hosts, 'syslog_server')  # needed for simp_conf.yaml template
  syslog_servers_names = syslog_servers.map { |server| fact_on(server, 'fqdn') }
  domain         = fact_on(master, 'domain')

  # Use first found 'master' FQDN
  master_fqdn    = fact_on(master, 'fqdn')

  # This command assumes a single Puppet master
  puppetserver_status_cmd = [
    'curl -sk',
    "--cert /etc/puppetlabs/puppet/ssl/certs/#{master_fqdn}.pem",
    "--key /etc/puppetlabs/puppet/ssl/private_keys/#{master_fqdn}.pem",
    "https://#{master_fqdn}:8140/status/v1/services",
    '| python -m json.tool',
    '| grep state',
    '| grep running'
  ].join(' ')

  let(:majver) { fact_on(master, 'operatingsystemmajrelease') }
  let(:osname) { fact_on(master, 'operatingsystem') }

  # Needed for simp_conf.yaml template
  let(:trusted_nets) do
    require 'json'
    require 'ipaddr'
    networking = JSON.load(on(master, 'facter --json networking').stdout)
    networking['networking']['interfaces'].delete_if { |key,value| key == 'lo' }
    trusted_nets = networking['networking']['interfaces'].map do |key,value|
      net_mask = IPAddr.new(value['netmask']).to_i.to_s(2).count("1")
      "#{value['network']}/#{net_mask}"
    end
  end

  let(:default_hieradata) {
    # hieradata that allows beaker operations access
    beaker_hiera = YAML.load(File.read('spec/acceptance/common_files/beaker_hiera.yaml'))

    # set up syslog forwarding
    hiera        = beaker_hiera.merge( {
      'simp::rsync_stunnel'         => master_fqdn,
      'rsyslog::enable_tls_logging' => true,
      'simp_rsyslog::forward_logs'  => true
    } )
    hiera
  }

  let(:syslog_server_hieradata) { {
    'rsyslog::tls_tcp_server'    => true,
    'simp_rsyslog::is_server'    => true,
    'simp_rsyslog::forward_logs' => false
  } }

  context 'all hosts prep' do
    it 'should install repos and set root pw' do
      block_on(hosts, :run_in_parallel => false) do |host|
        # set the root password
        on(host, "sed -i 's/enforce_for_root//g' /etc/pam.d/*")
        on(host, "echo '#{test_password}' | passwd root --stdin")
        # set up needed repositories
        if use_puppet_repo
          if host.host_hash[:platform] =~ /el-7/
            on(host, 'rpm -q puppetlabs-release-pc1 || yum install http://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm -y')
          else
            on(host, 'rpm -q puppetlabs-release-pc1 || yum install http://yum.puppetlabs.com/puppetlabs-release-pc1-el-6.noarch.rpm -y')
          end
        end
      end
    end
  end

  context 'master' do
    let(:simp_conf_template) { File.read('spec/acceptance/common_files/simp_conf.yaml.erb') }
    masters.each do |master|
      it 'should set up SIMP repositories' do
        master.install_package('epel-release')

        tarball = find_tarball(majver, osname)
        if tarball.nil?
          fail("Tarball not found")
        else
          tarball_yumrepos(master, tarball)
        end
        on(master, 'yum makecache')
      end

      if use_puppet_repo
        if master.host_hash[:platform] =~ /el-7/
          master.install_package('http://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm')
        else
          master.install_package('http://yum.puppetlabs.com/puppetlabs-release-pc1-el-6.noarch.rpm')
        end
      end

      # Set up the simp project dependency repo
      internet_deprepo(master)

      it 'should install simp' do
        master.install_package('simp-adapter-foss')
        master.install_package('simp')
      end

      it 'should run simp config' do
        create_remote_file(master, '/root/simp_conf.yaml', ERB.new(simp_conf_template).result(binding))

        cmd = [
          'simp config',
          '-A /root/simp_conf.yaml'
        ].join(' ')

        input = [
          'no', # do not autogenerate GRUB password
          test_password,
          test_password,
          'no', # do not autogenerate LDAP Root password
          test_password,
          test_password,
          ''  # make sure to end with \n
        ].join("\n")

        on(master, cmd, { :pty => true, :stdin => input } )
      end

      it 'should provide default hieradata' do
        create_remote_file(master, '/etc/puppetlabs/code/environments/simp/hieradata/default.yaml', default_hieradata.to_yaml)
        on(master, 'chown root.puppet /etc/puppetlabs/code/environments/simp/hieradata/default.yaml')
        on(master, 'chmod g+r /etc/puppetlabs/code/environments/simp/hieradata/default.yaml')
      end

      it 'should provide syslog server hieradata' do
        syslog_servers_names.each do |server|
          host_yaml_file = "/etc/puppetlabs/code/environments/simp/hieradata/hosts/#{server}.yaml"
          create_remote_file(master, host_yaml_file, syslog_server_hieradata.to_yaml)
          on(master, "chown root.puppet #{host_yaml_file}")
          on(master, "chmod g+r #{host_yaml_file}")
        end
      end

      it 'should enable autosign' do
        #FIXME:  Use trusted_nets to set allowed networks in autosign config
        on(master, 'puppet config --section master set autosign true')
      end

      it 'should run simp bootstrap' do
        # Remove the lock file because we've already added the vagrant user
        # access and won't be locked out of the VM
        on(master, 'rm -f /root/.simp/simp_bootstrap_start_lock')
        on(master, 'simp bootstrap --no-verbose -u --remove_ssldir > /dev/null')
      end

      it 'should reboot the master' do
        master.reboot
        retry_on(master, puppetserver_status_cmd, :retry_interval => 10)
      end

      it 'should settle after reboot' do
        on(master, '/opt/puppetlabs/bin/puppet agent -t', :acceptable_exit_codes => [0,2,4,6])
        on(master, '/opt/puppetlabs/bin/puppet agent -t', :acceptable_exit_codes => [0] )
      end

      it 'should generate agent certs' do
        togen = []
        agents.each do |agent|
          togen << agent.hostname + '.' + domain
        end
        create_remote_file(master, '/var/simp/environments/production/FakeCA/togen', togen.join("\n"))
        on(master, 'cd /var/simp/environments/production/FakeCA; ./gencerts_nopass.sh')
      end
    end
  end

  context 'agents' do
    it 'set up and run puppet' do
      block_on(agents, :run_in_parallel => false) do |agent|
        agent.install_package('epel-release')
        agent.install_package('puppet-agent')
        agent.install_package('net-tools')
        internet_deprepo(agent)

        on(agent, "puppet config set server #{master_fqdn}")
        on(agent, 'puppet config set masterport 8140')
        on(agent, 'puppet config set ca_port 8141')

        # Run puppet and expect changes
        retry_on(agent, 'puppet agent -t',
          :desired_exit_codes => [0],
          :retry_interval     => 15,
          :max_retries        => 5,
          :verbose            => true
        )

        # Wait for machine to come back up
        agent.reboot
        retry_on(master, puppetserver_status_cmd, :retry_interval => 10)
        retry_on(agent, 'uptime', :retry_interval => 15 )

        # Wait for things to settle and stop making changes
        retry_on(agent, 'puppet agent -t',
          :desired_exit_codes => [0],
          :retry_interval     => 15,
          :max_retries        => 3,
          :verbose            => true
        )
      end
    end
  end
end
