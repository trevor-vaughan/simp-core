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
        :progress     => 'Dependency Removal'
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

namespace :simp do
  CLOBBER.include('.gource')

  task :gource, [:render, :resolution, :tmpdir] do |t,args|
    args.with_defaults(:tmpdir => '.gource')
    tmpdir = args[:tmpdir]

    args.with_defaults(:render => 'false')
    render = (args[:render] == 'true') ? true : false
    render_file = 'gource.webm'
    ffmpeg = "ffmpeg -y -r 60 -f image2pipe -vcodec ppm -i - -vcodec libvpx -b:v 10000K #{File.join(tmpdir, render_file)}"

    args.with_defaults(:resolution => '1920x1080')
    resolution = args[:resolution]

    start_date = '2015-05-12 22:20:30'

    logo_file = 'src/doc/docs/images/SIMP_Logo.png'

    collect_file = 'full.gource'

    moduledirs_to_include = [
      'src',
      'src/puppet/modules'
    ]

    file_extensions = [
      'e?pp',
      'e?rb',
      'json',
      'md',
      'py',
      'rst',
      'ya?ml'
    ]

    FileUtils.rm_rf(tmpdir) if File.directory?(tmpdir)

    FileUtils.mkdir(tmpdir)

    r10k_helper = R10KHelper.new('Puppetfile.tracking')

    gource_cmdline = "gource -#{resolution} " +
      '--auto-skip-seconds 1 ' +
      '-seconds-per-day 0.025 ' +
      '--camera-mode overview ' +
      '--file-idle-time 0 ' +
      '--max-file-lag 0.1 ' +
      '--disable-bloom ' +
      '--date-format "%Y" ' +
      '--hide users,dirnames,mouse,filenames ' +
      '--title "Code Over Time" '

    if File.exist?(logo_file)
      gource_cmdline += "--logo #{logo_file} "
    end

    if render
      gource_cmdline += '-o - '
    end

    gource_cmdline += File.join(tmpdir, collect_file)

    need_deps_checkout = false

    modules_to_process = r10k_helper.modules.select do |mod|
      do_include = false

      moduledirs_to_include.each do |mod_dir|
        if %r(/#{mod_dir}$).match?(mod[:module_dir])
          do_include = true

          need_deps_checkout = true unless File.directory?(mod[:path])

          break
        end
      end

      do_include
    end

    if need_deps_checkout
      Rake::Task['deps:checkout'].invoke
    end

    Parallel.map(
      Array(modules_to_process),
        :in_processes => get_cpu_limit,
        :progress     => 'Gource Analysis'
    ) do |mod|
      sub_dir = mod[:path].split(Dir.pwd).last[1..-1]
      outfile = File.join(tmpdir, mod[:r10k_module].title) + '.txt'

      %x{gource --start-date '#{start_date}' --output-custom-log #{outfile} #{mod[:path]}}

      file_content = File.read(outfile).lines

      file_content.delete_if do |line|
        match = false

        file_extensions.each do |ext|
          if %r(\.#{ext}$).match?(line)
            match = true
            break
          end
        end

        !match
      end

      file_content.map! do |line|
        # Timestamp, Username, Action, Path
        parts = line.split('|')

        # Update the Path so that there is no overlap
        parts[-1] = File.join(sub_dir, parts.last)

        parts.join('|')
      end

      if file_content.empty?
        FileUtils.rm(outfile)
      else
        File.open(outfile, 'w') do |fh|
          fh.puts(file_content.join)
        end
      end
    end

    # This makes things too unreadable
    #%x{gource --output-custom-log #{File.join(tmpdir, 'simp-core.txt')}}

    Dir.chdir(tmpdir) do
      %x{cat *.txt | sort -n > #{collect_file}}
    end

    if render
      %x{#{gource_cmdline} | #{ffmpeg}}
    else
      puts("Run with: #{gource_cmdline}")
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
      Dir.glob(File.join(distr_glob, 'DVD_Overlay'))
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
