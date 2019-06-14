#!/usr/bin/rake -T

require 'simp/rake/pupmod/helpers'

Simp::Rake::Beaker.new(File.dirname(__FILE__))

begin
  require 'simp/rake/build/helpers'
  BASEDIR    = File.dirname(__FILE__)
  Simp::Rake::Build::Helpers.new( BASEDIR )
rescue LoadError => e
  warn "WARNING: #{e.message}"
end

task :metadata_lint do
  sh 'metadata-json-lint --strict-dependencies --strict-license --fail-on-warnings metadata.json'
end

task :default do
  help
end

namespace :deps do
  desc <<-EOM
  Remove all checked-out dependency repos

  Uses specified Puppetfile to identify the checked-out repos.

  Arguments:
    * :suffix       => The Puppetfile suffix to use (Default => 'tracking')
    * :remove_cache => Whether to remove the R10K cache after removing the
                       checked-out repos (Default => false)
  EOM
  task :clean, [:suffix,:remove_cache] do |t,args|
    args.with_defaults(:suffix => 'tracking')
    args.with_defaults(:remove_cache => false)
    base_dir = File.dirname(__FILE__)

    r10k_helper = R10KHelper.new("Puppetfile.#{args[:suffix]}")

    r10k_issues = Parallel.map(
      Array(r10k_helper.modules),
        :in_processes => get_cpu_limit,
        :progress => 'Dependency Removal'
    ) do |mod|
      Dir.chdir(base_dir) do
        FileUtils.rm_rf(mod[:path])
      end
    end

    if args[:remove_cache]
      cache_dir = File.join(base_dir, '.r10k_cache')
      FileUtils.rm_rf(cache_dir)
    end
  end
end

namespace :pkg do
  desc <<-EOM
  Remove all built artifacts in build/

  Arguments:
    * :remove_yum_cache   => Whether to remove the yum cache (Default => true)
    * :remove_dev_gpgkeys => Whether to remove the SIMP Dev GPG keys (Default => true)
  EOM
  task :build_clean, [:remove_yum_cache,:remove_dev_gpgkeys] do |t,args|
    args.with_defaults(:remove_yum_cache => 'true')
    args.with_defaults(:remove_dev_gpgkeys => 'true')

    base_dir = File.dirname(__FILE__)
    #                                                          OS   ver  arch
    distr_glob = File.join(base_dir, 'build', 'distributions', '*', '*', '*')

    dirs_to_remove = [
      Dir.glob(File.join(distr_glob, 'SIMP*')),
      Dir.glob(File.join(distr_glob, 'DVD_Overlay')),
      File.join(base_dir, 'src', 'assets', 'simp', 'dist')
    ]

    if args[:remove_yum_cache] == 'true'
      dirs_to_remove += Dir.glob(File.join(distr_glob, 'yum_data', 'packages'))
    end

    if args[:remove_dev_gpgkeys] == 'true'
      dirs_to_remove += Dir.glob(File.join(distr_glob, 'build_keys', 'dev'))
      dirs_to_remove += Dir.glob(File.join(distr_glob, 'DVD', 'RPM-GPG-KEY-SIMP-Dev'))
    end
    dirs_to_remove.flatten.each { |dir| FileUtils.rm_rf(dir, :verbose =>true) }
  end
end

def load_modules(puppetfile)
  require 'r10k/puppetfile'

  fail "Could not find file '#{puppetfile}'" unless File.exist?(puppetfile)

  r10k = R10K::Puppetfile.new(Dir.pwd, nil, puppetfile)
  r10k.load!

  modules = {}

  Parallel.map(
    r10k.modules,
    :in_processes => get_cpu_limit,
    finish: -> (item, i, result) {
      modules.merge!(result) if result
    }
  ) do |mod|
    # Skip anything that's not pinned

    next unless mod.instance_variable_get('@args').keys.include?(:tag)

    {
      mod.name => {
        :id          => mod.name,
        :owner       => mod.owner,
        :path        => mod.path.to_s,
        :remote      => mod.repo.instance_variable_get('@remote'),
        :desired_ref => mod.desired_ref,
        :version     => mod.desired_ref,
        :git_source  => mod.repo.repo.origin,
        :git_ref     => mod.repo.head,
        :module_dir  => mod.basedir,
        :r10k_cache  => mod.repo.repo.cache_repo,
        # This doesn't play well with parallel but leaving it for future
        # reference/debugging.
        #
        #:r10k_module => mod
      }
    }
  end

  return modules
end

def update_module_github_status!(mod)
  require 'json'
  require 'nokogiri'
  require 'open-uri'

  require 'highline'
  HighLine.colorize_strings

  mod[:published] ||= {}
  mod[:published]['GitHub'] ||= 'unknown'
  mod[:published]['Puppet Forge'] ||= 'unknown'

  # See if we have a valid release on GitHub
  github_releases_url = mod[:remote] + '/releases'

  begin
    github_query = Nokogiri::HTML(open(github_releases_url).read)

    if github_query.xpath('//a/@title').map(&:value).include?(mod[:version])
      mod[:published]['GitHub'] = 'yes'.green
    else
      mod[:published]['GitHub'] = 'no'.red
    end
  rescue
    mod[:published]['GitHub'] = 'no'.red
  end

  # See if we're a module and update the version information if necessary
  begin
    open(
      mod[:remote].gsub('github.com','raw.githubusercontent.com') +
      '/' +
      mod[:desired_ref] +
      '/' +
      'metadata.json'
    ) do |fh|
      mod_info = JSON.parse(fh.read)

      mod[:version] = mod_info['version']
    end
  rescue StandardError => e
    # If we get here, we're not a module
    mod[:published]['Puppet Forge'] = 'N/A'
  end
end

def update_module_puppet_forge_status!(mod)
  require 'open-uri'

  require 'highline'
  HighLine.colorize_strings

  forge_url_base  = 'https://forgeapi.puppet.com/v3/releases/'

  mod[:published] ||= {}
  mod[:published]['Puppet Forge'] ||= 'unknown'

  unless mod[:published]['Puppet Forge'] == 'N/A'
    begin
      # Now, check the Puppet Forge for the released module
      open(URI.parse(forge_url_base + mod[:owner] + '-' + mod[:id] + '-' + mod[:version])) do |fh|
        mod[:published]['Puppet Forge'] = 'yes'.green
      end
    rescue StandardError => e
      mod[:published]['Puppet Forge'] = 'no'.red
    end
  end
end

def update_module_package_cloud_status!(mod)
  require 'open-uri'
  require 'nokogiri'

  require 'highline'
  HighLine.colorize_strings

  pcloud_url_base = 'https://packagecloud.io/app/simp-project/6_X/search?'

  mod[:published] ||= {}

  ['6','7'].each do |ver|
    mod[:published]["Package Cloud #{ver}"] ||= 'unknown'

    # Finally, check to see if we're published on Package Cloud (as best we can)
    url = pcloud_url_base + 'q='

    unless ['unknown', 'N/A'].include?(mod[:published]['Puppet Forge'])
      url = url + 'pupmod-'
    end

    url = url + mod[:owner] + '-' + mod[:id] + '-' + mod[:version]

    url = url + "&dist=el/#{ver}"

    begin
      package_cloud_query = Nokogiri::HTML(open(url).read)

      pkg_info = package_cloud_query.xpath("//*[contains(@class, 'package-info-details')]")

      if pkg_info.empty?
        mod[:published]["Package Cloud #{ver}"] = 'no'.red
      else
        mod[:published]["Package Cloud #{ver}"] = pkg_info.css('a').first.text.green
      end
    rescue StandardError => e
      mod[:published]["Package Cloud #{ver}"] = 'no'.red
    end
  end
end

def print_module_status(mod)
  puts "== #{mod[:owner]}-#{mod[:id]} #{mod[:version]} =="
  puts mod[:published].to_a.map{|x,y| "   * #{x} => #{y}"}.join("\n")
end

namespace :puppetfile do
  desc <<-EOM
  Check the deployment status of a specific item from the puppetfile.

  Usage: puppetfile:check_module[<module name>] (exclude the author)
  EOM
  task :check_module, [:module_name, :puppetfile] do |t,args|
    args.with_defaults(:puppetfile => 'tracking')

    fail 'Need a module name' unless args[:module_name]

    puppetfile = 'Puppetfile.' + args[:puppetfile]

    modules = load_modules(puppetfile)

    target_module = modules.select do |id, mod|
      id == args[:module_name].strip
    end

    if target_module.empty?
      fail "Could not find a tagged version of '#{args[:module_name]}' in '#{puppetfile}'"
    end

    target_module = target_module[target_module.keys.first]

    update_module_github_status!(target_module)
    update_module_puppet_forge_status!(target_module)
    update_module_package_cloud_status!(target_module)

    print_module_status(target_module)
  end

  desc <<-EOM
  Check all tagged modules in the Puppetfile and determine if they have been
  published to the Puppet Forge, GitHub, and/or Package Cloud as appropriate
  EOM
  task :check, [:puppetfile] do |t,args|
    # TODO: Add local caching for repeated queries

    args.with_defaults(:puppetfile => 'tracking')

    puppetfile = 'Puppetfile.' + args[:puppetfile]

    modules = load_modules(puppetfile)

    modules.each do |id, mod|
      print "Processing: #{mod[:owner]}-#{id}".ljust(55,' ') + "\r"
      $stdout.flush

      update_module_github_status!(mod)
      update_module_puppet_forge_status!(mod)
      update_module_package_cloud_status!(mod)

      # Be kind, rewind...
      sleep 0.5
    end

    # Return past the status line
    puts ''

    modules.each do |id, mod|
      print_module_status(mod)
    end
  end

  task :acceptance_test_count, [:puppetfile] do |t,args|
    args.with_defaults(:puppetfile => 'tracking')

    puppetfile = 'Puppetfile.' + args[:puppetfile]

    modules = load_modules(puppetfile)

    test_count = {
      :acceptance_total => 0,
      :extrapolated_total => 0
    }

    Parallel.map(
      modules,
      #:in_processes => get_cpu_limit,
      :in_processes => 1,
      :progress => "Acceptance Test Count",
      finish: -> (item, i, result){
        if result
          id,mod = item
          test_count["#{mod[:owner]}-#{id}"] ||= {}
          test_count["#{mod[:owner]}-#{id}"][:acceptance] ||= 0
          test_count["#{mod[:owner]}-#{id}"][:acceptance_extrapolated] ||= 0

          test_count[:acceptance_total] += result[:base]
          test_count["#{mod[:owner]}-#{id}"][:acceptance] += result[:base]

          test_count[:extrapolated_total] += result[:extrapolated]
          test_count["#{mod[:owner]}-#{id}"][:acceptance_extrapolated] += result[:extrapolated]
        end
      }
    ) do |id, mod|
      next unless mod[:owner] == 'simp'
      next unless File.directory?(File.join(mod[:path], 'spec', 'acceptance'))

      num_examples = {
        :base => 0,
        :extrapolated => 0
      }

      Dir.chdir(mod[:path]) do
        Find.find('spec/acceptance') do |path|
          filename = File.basename(path)

          if filename =~ /_spec.rb$/
            num_examples[:base] += File.read(path).lines.grep(/^\s*it\s+(({|do)|.+\s+do)\s*$/).count

            # Test count extrapolation
            Dir.chdir(File.dirname(path)) do
              nodeset = nil
              if File.exist?(File.join('nodesets','default.yml'))
                nodeset = File.join('nodesets','default.yml')
              elsif File.exist?(File.join('..','..','nodesets','default.yml'))
                nodeset = File.join('..','..','nodesets','default.yml')
              end

              if nodeset
                begin
                  nodeset_data = YAML.load(ERB.new(File.read(nodeset), nil, '-').result(binding))

                  if nodeset_data['HOSTS']
                    num_examples[:extrapolated] = num_examples[:base] * nodeset_data['HOSTS'].keys.count
                  end
                rescue
                  #noop
                end
              end
            end
          end
        end
      end

      num_examples
    end

    puts ''
    puts 'Total Base Acceptance Tests: ' + test_count[:acceptance_total].to_s
    puts 'Total Acceptance Tests with Nodeset Extrapolation: ' + test_count[:extrapolated_total].to_s
  end

  task :unit_test_count, [:puppetfile] do |t,args|
    num_match_regex = %r{(?<num_examples>\d+) examples}

    args.with_defaults(:puppetfile => 'tracking')

    puppetfile = 'Puppetfile.' + args[:puppetfile]

    modules = load_modules(puppetfile)

    test_count = {
      :unit_total => 0
    }

    modules.each do |id, mod|
      next unless mod[:owner] == 'simp'
      next unless File.directory?(File.join(mod[:path], 'spec'))

      Dir.chdir(mod[:path]) do
        if File.directory?('spec')
          print "Processing: #{mod[:owner]}-#{id}".ljust(55,' ') + "\r"
          $stdout.flush

          spec_tests = []
          Find.find('spec') do |path|
            filename = File.basename(path)

            Find.prune if filename == 'acceptance'

            if filename =~ /_spec.rb$/
              spec_tests << path
            end
          end

          test_count["#{mod[:owner]}-#{id}"] ||= {}
          test_count["#{mod[:owner]}-#{id}"][:unit] ||= 0

          Parallel.map(
            spec_tests,
            :in_processes => get_cpu_limit,
            :progress => "#{mod[:owner]}-#{id}",
            finish: -> (item, i, result){
              test_count[:unit_total] += result
              test_count["#{mod[:owner]}-#{id}"][:unit] += result
            }
          ) do |path|
            num_examples = 0

            ::Bundler.with_clean_env do
              output = %x{ bundle exec rspec -f d --dry-run #{path} 2>&1}
              if matches = output.match(num_match_regex)
                num_examples = matches[:num_examples].to_i if matches[:num_examples]
              end
            end

            num_examples
          end
        end
      end
    end

    puts ''
    puts 'Total Unit Tests: ' + test_count[:unit_total].to_s
  end
end
