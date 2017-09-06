require 'spec_helper_rpm'

test_name 'RPM build'

# Custom Gemfile Support
gemfile = nil
gemfile_path = File.expand_path(File.join(fixtures_path,'Gemfile'))

if File.file?(gemfile_path)
  gemfile = gemfile_path
end

describe 'RPM build' do
  let(:local_basedir) { File.absolute_path(File.join(fixtures_path, '..', '..')) }

  # We need a normal user for building the RPMs
  let(:build_user) { 'build_user' }
  let(:run_cmd) { %(runuser #{build_user} -l -c ) }

  hosts.each do |host|
    next if host[:roles].include?('disabled')

    it 'should clone the repo if necessary' do
      unless host.file_exist?('/simp-core/metadata.json')
        # Handle Travis CI first
        if ENV['TRAVIS_BUILD_DIR']
          base_dir = File.dirname(ENV['TRAVIS_BUILD_DIR'])

          %x(docker cp #{ENV['TRAVIS_BUILD_DIR']} #{host.name}:/simp-core)

          host.mkdir_p(base_dir)
          on(host, %(cd #{base_dir}; ln -s /simp-core .))
        else
          # Just clone the main simp repo
          on(host, %(git clone https://github.com/simp/simp-core /simp-core))
        end

        on(host, %(chown -R #{build_user}:#{build_user} /simp-core))
      end
    end

    it 'should have access to the local simp-core' do

      # This is to work around irritating artifacts left around by r10k
      unless local_basedir == '/simp-core'
        host.mkdir_p(File.dirname(local_basedir))

        on(host, %(cd #{File.dirname(local_basedir)}; ln -s /simp-core #{File.basename(local_basedir)}))
      end

      host.file_exist?("#{local_basedir}/metadata.json")
    end

    it 'should align the build user uid and gid with the mounted filesystem' do
      on(host, %(groupmod -g `stat --printf="%u" /simp-core` #{build_user}))
      on(host, %(usermod -u `stat --printf="%u" /simp-core` -g `stat --printf="%u" /simp-core` #{build_user}))
      on(host, %(chown -R #{build_user}:#{build_user} ~#{build_user}))
    end

    it 'should have the latest gems' do
      on(host, "#{run_cmd} 'cd #{local_basedir}; bundle update'")
    end

    if host.file_exist?('/simp-core/ISO')
      it 'should be able to build the ISO' do
        on(host, "#{run_cmd} 'cd #{local_basedir}; bundle exec rake build:auto[ISO]'")
      end
    else
      it 'should be able to build all modules ' do
        on(host, "#{run_cmd} 'cd #{local_basedir}; bundle exec rake pkg:modules'")
      end

      it 'should be able to build aux packages ' do
        on(host, "#{run_cmd} 'cd #{local_basedir}; bundle exec rake pkg:aux'")
      end
    end
  end
end
