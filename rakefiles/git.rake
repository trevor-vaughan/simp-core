#!/usr/bin/rake -T
require 'rake'
require 'rake/tasklib'
require 'fileutils'

module Simp
  # A collection of git tasks needed to clone or reset a SIMP development tree
  class Git
    MASTER_BRANCH_VERSION = '4.1.X'

    class << self
      # execute shell commands with ability to dry run or accept a hash of
      # mocked { cmd => string output } results
      def exec_sh( cmd, verbose=false, _fake_cmds={} )
        puts "  == %x: #{cmd}" if (verbose || $VERBOSE )
        %x(#{cmd})
      end

      def supermodule_branch
        exec_sh('git name-rev --name-only HEAD').chomp
      end


      # Array of remote names
      def list_remotes
        %x(git remote).split("\n")
      end


      # Hash of remotes as { name => url, ... }
      def list_remotes_with_urls
        extra = %q{-v  | sed 's/ *(\(fetch\|push\))//'}
        Hash[
          %x(git remote #{extra})
            .split("\n")
            .map{ |x| x.split(/\t|\s+/)[0..1] }
       ]
      end


      # Array of remote 'gerrit/' branches
      def list_remote_gerrit_branches
        %x(git branch -r | grep gerrit | cut -f2 -d'/' | grep -vw ^HEAD)
          .split("\n")
          .map{ |x| x.strip }
      end


      # true if a git repo is detected in the submodule path
      def submodule_repo_exists?(subm)
        File.directory?("#{subm}/.git")
      end


      # Array of paths to submodules (as recorded in the index)
      def list_submodules_in_index
        # substantially less I/O intensive than 'git submodule status'
        %x(git ls-files --stage | grep -w ^160000)
          .chomp
          .split("\n")
          .map{ |x| x.split(/\s+/).last }
      end


      # returns Hash of path=>url mapping from .git/config
      def submodules_in_gitconfig(file = nil)
        extra    = file.nil? ? '' : "-f #{file}"
        cmd      = %Q(git config #{extra} --get-regexp ^submodule\. | sed -e 's/^submodule\.//')
        lines    = %x(#{cmd}).chomp.split("\n")
        sections = {}
        lines.each do |line|
          key, value = line.split(/\s+/)
          key        = key.split('.')
          git_key    = key.pop         # 'url', 'path', 'branch', etc
          section    = key.join('.')
          sections[section]          = {} unless sections.fetch(section, false)
          sections[section][git_key] = value
        end

        # Despite all modelling work above, everything currently squashes into a
        # simple data structure: {path => url, ...}.  This might seem like a
        # waste, but there are two reasons:
        #
        #   - lookups based on `git submodule status` return the paths, not
        #     name (which is often the same as path but can be relabeled w/
        #     `git submodule add --name`).  So we needed capture .path.
        #
        #   - the code above is future-ready in that it captures *all*
        #     submodule keys such as .branch [which will be very handy in case
        #     we end up using submodule branch tracking (new in git 1.8 and
        #     available in el7)].
        Hash[sections.map{ |k, v| [(v['path'] || k), v['url']] }]
      end


      # returns path=>url mapping from the .gitmodules file
      def submodules_in_gitmodules
        submodules_in_gitconfig('.gitmodules')
      end


      # Test a branch version to see if it matches our crazy logic about which
      # submodule branches are acceptable to use with a target branch
      # ------------------------------------------------------------------------
      # The rules:
      #    Given supermodule 'Maj.min.X', a subm branch is valid if its name is:
      #       - 'Maj.min.X'
      #       - an earlier revision of the Maj.*.X release
      #       - the master branch (use MASTER_BRANCH_VERSION for numeric ops)
      #       - a branch named 'Maj.X' should work as well
      #
      # Notes:
      #   - Gem::Verison's requirements logic handles the comparisons.
      #   - By convention, SIMP devs use 'X' as a wildcard # in branch versions.
      # ------------------------------------------------------------------------
      def version_acceptable?(test_branch, target)
        vers = target.split('.')
        major_release_x = [
                            vers.shift,
                            vers[0..-2].map{ '0' }.join('.'),
                            'X',
                          ].reject{ |x| x.empty? }.join('.')

        # Use Gem::Version requirements logic to validate version
        requirements = Gem::Requirement.new([
          "~> #{major_release_x}",       # should be within the major release
          "<= #{target}",                # can't be higher than the supermodule
          ">= #{MASTER_BRANCH_VERSION}", # never drop lower than 'master'
                                            ])

        # decide if the current test target matches this target's requirements
        if requirements.satisfied_by?(Gem::Version.new(test_branch)) ||
           test_branch == MASTER_BRANCH_VERSION
          true
        else
          false
        end
      end


      # Given a target branch, return the most current "safe" branch from a list
      # of branches.
      #
      # Returns safest branch (String) if found, otherwise false.
      def find_best_branch(branches=[], target_branch)
        result        = false
        branches      = branches.dup.map{ |x| x.gsub('master', MASTER_BRANCH_VERSION) }
        target_branch = target_branch.gsub('master', MASTER_BRANCH_VERSION)
        test_branch   = branches.shift

        # allow custom target_branches (like Rakemegeddon) to match themselves:
        re = /\d+\.(\d+\.)*(\d+|X)+?/ # allow semver or variants ending with 'X'
        if (target_branch !~ re) || (test_branch !~ re)
          return test_branch if test_branch == target_branch
          return find_best_branch(branches, target_branch) unless branches.empty?
          return false
        end

        result = test_branch if version_acceptable?(test_branch, target_branch)

        # check to see if there are better matches available
        if !branches.empty?
          other_result = find_best_branch(branches, target_branch)
          if result && other_result
            if (Gem::Version.new(other_result.gsub('master', MASTER_BRANCH_VERSION)) >
                 Gem::Version.new(result))
              result = other_result
            end
          elsif !result && other_result
            result = other_result
          end
        end

        result = 'master' if result == MASTER_BRANCH_VERSION # can't gsub when false
        result
      end



      # ensure that the best available remote branch (for *project_branch*) is
      # checked out to the latest revision from the remote.
      # ------------------------------------------------------------------------
      # NOTE: this sets HEAD to the latest revision, which could revert more
      #       recent local commits (find them with `git reflog`).
      # TODO: should we try to rebase in order to avoid that?
      # ------------------------------------------------------------------------
      def ensure_latest_checkout(project_branch)
        branch         = find_best_branch(list_remote_gerrit_branches, project_branch)
        remote_branch  = "gerrit/#{branch}"

        puts "  -- Checking out '#{branch}' in #{Dir.pwd}"
        fail "no safe branch found for target '#{project_branch}' in #{Dir.pwd}" unless branch

        %x(git fetch gerrit 2>&1)
        fail "'git fetch gerrit' (#{remote_branch}) failed in #{Dir.pwd} (exit code: #{$?.exitstatus})" unless $?.success?

        %x(git checkout -q #{remote_branch})
        fail "checkout to #{remote_branch} failed in #{Dir.pwd} (exit code: #{$?.exitstatus})" unless $?.success?

        puts "  -- Branching '#{branch}' in #{Dir.pwd}"
        %x(git branch -f #{branch})
        %x(git checkout #{branch})
      end



      # Ensure that .git/config has the same URL for a submodule as .gitmodules
      # -----------------------------------------------------------------------
      # TODO: should we *remove* extra submodules in .git/config?
      # TODO: should we *remove* extra submodules in the index?
      # -----------------------------------------------------------------------
      # Let's fix weird things about 'git submodule sync!'
      #
      # 'git submodule sync' does two things of interest:
      #   1. it will update .git/config and the index w/info from .gitmodules
      #   2. it will update the submodule's 'origin' remote w/the same info
      #
      # Re #1: Despite claims in the man page, it does NOT update the URL of
      #        a submodule already in .git/config.  So we do that here.
      #
      # Re #2: A potentially unwanted side effect of updating the submodule's
      #        remote 'origin' is that if 'origin' is missing, git adds it!
      #
      # So, this method is careful to:
      #   - update 'gerrit' to the new URL if origin was updated
      #   - remove 'origin' ONLY if it was added by our 'git submodule sync'
      #
      def sync_submodule_url(subm)
        puts "  -- submodule URL sync: #{subm}"
        pwd = Dir.pwd
        keep_origin = false  # git
        if submodule_repo_exists?(subm)
          Dir.chdir subm
          keep_origin = list_remotes.include?('origin')
          Dir.chdir pwd
        elsif !list_submodules_in_index.include? subm
          puts "  -- adding submodule #{subm} to index & cloning"
          url = submodules_in_gitmodules[subm]
          exec_sh("git submodule add #{url} #{subm}")
        end

        # Add *missing* submodule + URL to .git/config
        exec_sh("git submodule sync -- #{subm}")

        # Update *existing* submodule URL in .git/config to match .gitmodules
        gf_url = submodules_in_gitconfig.fetch( subm, false)
        gm_url = submodules_in_gitmodules.fetch(subm, false)
        if (gm_url && gf_url) && (gf_url != gm_url)
          puts "    -- Updating URL for '#{subm}':"
          puts "      .git/config (old): #{gf_url}"
          puts "      .gitmodules (new): #{gm_url}"
          exec_sh("git config submodule.#{subm}.url #{gm_url}")
        end

        if submodule_repo_exists?(subm)
          Dir.chdir subm
          ensure_gerrit_remote
          if !keep_origin && list_remotes.include?('origin')
            exec_sh('git remote rm origin')
          end
          Dir.chdir pwd
        end
      end


      # Ensure that the remote 'gerrit' exists and its URL is up-to-date
      def ensure_gerrit_remote
        remotes = list_remotes_with_urls
        if remotes.keys.include? 'origin'
          if !remotes.keys.include? 'gerrit'
            # assume a fresh clone and rename 'origin'
            puts "  -- ensuring remote 'gerrit' exists in #{Dir.pwd}"
            %x(git remote rename origin gerrit)
          else
            # ensure URL for 'gerrit' is up-to-date (preserves 'origin')
            origin_url = remotes.fetch('origin', false)
            gerrit_url = remotes.fetch('gerrit', false)
            if origin_url && (origin_url != gerrit_url)
              puts "  -- updating remote URL for 'gerrit' to '#{gerrit_url}'"
              warn "     TODO: rebase?"
              %x(git remote set-url gerrit #{origin_url})
            end
          end
        elsif !remotes.keys.include? 'gerrit'
          # totally freak out
          raise("No remote 'gerrit' or 'origin' at #{Dir.pwd}:\n#{list_remotes}")
        end
      end


      # Reset git repository in *dir* to a clean state to work with supermodule
      # ------------------------------------------------------------------------
      # Actions:
      #  - ensures gerrit exists as a remote (updating URL, if needed)
      #  - fetches latest revisions from gerrit
      #  - checks out the branch that best matches the supermodule
      #
      # Notes:
      #  - works for any repo (super or submodule)
      #  - assumed to run from supermodule directory
      # ------------------------------------------------------------------------
      def reset(dir=Dir.pwd)
        pwd = Dir.pwd
        target_branch = supermodule_branch
        begin
          Dir.chdir dir
          ensure_gerrit_remote
          ensure_latest_checkout(target_branch)
        ensure
          Dir.chdir pwd
        end
      end


      def clone_submodule(subm)
        sync_submodule_url subm
        puts "  == Cloning submodule: #{subm}"

        # elaborate error-handling for indexes that contain non-existent refspecs
        require 'open3'
        Open3.popen2e( "git submodule update --init #{subm} 2>&1" ) do |_in, outerr, thr|
          text = ''
          while line = outerr.gets
            puts line
            text << line
          end

          unless thr.value.success?
            msg = "'git submodule update --init #{subm}' failed (exit code: #{$?.exitstatus})"
            if text =~ /fatal: reference is not a tree/
              warn "WARNING: #{msg}"
              warn '-- This is probably a refspec in the index for a branch that is locally'
              warn '   unavailable (likely a gerrit review).  It is probably safe to leave the '
              warn '   latest commit in the current branch as-is.'
            else
              fail "ERROR: #{msg}"
            end
          end
        end


        puts "  -- Submodule '#{subm}' cloned"
      end


      # best efforts to check out & ready a list of submodules for SIMP dev
      def reset_submodules(list_of_submodules)
        list_of_submodules.each do |subm|
          puts "== Resetting submodule '#{subm}':"

          if !submodule_repo_exists?(subm)
            clone_submodule(subm)
          else
            sync_submodule_url subm
          end
          reset subm

          puts
          puts
        end

        warn_on_gitmodules_discrepancies
      end


      # warn about submodules that are known to the local repo but not in .gitmodules
      def warn_on_gitmodules_discrepancies
        missing_from_gitmodules = (list_submodules_in_index - submodules_in_gitmodules.keys)
        unless missing_from_gitmodules.empty?
          warn ''
          warn 'WARNING: these submodules are known to the index, but are not in .gitmodules:'
          missing_from_gitmodules.each{ |m| warn "\t#{m}" }
          warn ''
        end

        missing_from_gitmodules = (submodules_in_gitconfig.keys - submodules_in_gitmodules.keys)
        unless missing_from_gitmodules.empty?
          warn ''
          warn 'WARNING: these submodules are known to .git/config, but are not in .gitmodules:'
          missing_from_gitmodules.each{ |m| warn "\t#{m}" }
          warn ''
        end
      end

      def print_remotes dir=Dir.pwd
        pwd = Dir.pwd
        Dir.chdir dir
        list_remotes_with_urls.each{ |r, url| puts "    #{r.ljust(8)}#{url}" }
        Dir.chdir pwd
      end
    end
  end
end


module Simp::Rake
  class Git < ::Rake::TaskLib
    def initialize
       define
    end


    # define & namespace each rake task
    def define
      namespace :git do
        define_tasks
        namespace :submodules  do
          define_submodule_tasks
        end
      end
    end


    def define_tasks
      desc <<-EOM
      lists git remotes
      EOM
      task :list_remotes, :with_urls do |_t, args|
        if args[:with_urls]
          puts Simp::Git.print_remotes
        else
          Simp::Git.list_remotes.each{ |x| puts x }
        end
      end

      desc <<-EOM
      Reset git configs for supermodule
        - ensure that the 'gerrit' remote is present in the supermodule
      EOM
      task :reset do
        Simp::Git.reset
      end
    end


    def define_submodule_tasks
      desc <<-EOM
      This taske shall Un-jacketh all manner of submodule ailments

      It will:
        - ensure that the 'gerrit' remote is present in the supermodule
        - for each submodule:
          - clone if missing
          - keep the submodule's URL up-to-date in .git/config
          - ensure that the 'gerrit' remote exists and its URL is up-to-date
          - fetch and check out the most recent updates
          - set each submodule branch to the closest version to the supermodule
        - warn if .gitmodules is missing submodules in the index or .git/config

      NOTE: .gitmodules is used as the authorative source for these actions.

        * :submodules - [optional] list of specific submodules (by path)
                      - if left blank, resets all submodules
                      - a minus (e.g., '-build') will ignore a submodule

      EOM
      task :reset, [:submodules] => ['git:reset'] do |_t, args|
        submodules     = args[:submodules].to_s.split + args.extras
        all_submodules = (Simp::Git.submodules_in_gitmodules.keys).sort.uniq
        neg_submodules = submodules.select{|x| x =~ /^-/ }

        submodules     = submodules - neg_submodules
        neg_submodules.map!{|x| x.gsub(/^-/,'')}

        submodules = all_submodules if submodules.empty?

        Simp::Git.reset_submodules(submodules - neg_submodules)
      end


      desc <<-EOM
      Display submodules
        * :source - source of submodule information.  Can be:
             'gitmodules' - use .gitmodules
             'gitconfig'  - use supermodule's .git/config
             'index'      - use supermodule's index
             'compare'    - compare submodule presence (abences marked w/'x') in:
                               .gitmodules (M)
                               .git/config (C)
                               index (I)
      EOM
      task :list, :source do |_t, args|
        source = (args[:source] || 'gitmodules').to_s.strip
        list   = nil
        case source
        when /compare/
        when /git.?config/
          list = Simp::Git.submodules_in_gitconfig.keys
        when /index/
          list = Simp::Git.list_submodules_in_index
        when /gitmodules/
          list = Simp::Git.submodules_in_gitmodules.keys
        else
          fail ArgumentError, "WARNING: '#{source}' is not a recognized option!"
        end

        if source == 'compare'
          puts compare_submodule_sources.join("\n")
        else
          list.sort.each{ |x| puts x }
        end
      end

      desc <<-EOM
      Display submodule discrepencies (abences marked w/'x') between:
         M = .gitmodules
         C = .git/config
         I =  index
         x = missing
      EOM
      task :lint do
        puts compare_submodule_sources.grep(/\bx\b/).join("\n")
      end

    end


    # returns an Array of Strings describing submodule statuses
    #   one line per submodule in the format: "I C M path/to/submodule"
    #      I = present in index
    #      C = preent in .git/config
    #      M = present in .gitmodules
    #      x = missing from source
    def compare_submodule_sources
      result     = []
      index      = Simp::Git.list_submodules_in_index
      gitconfig  = Simp::Git.submodules_in_gitconfig.keys
      gitmodules = Simp::Git.submodules_in_gitmodules.keys
      (gitmodules + gitconfig + index).sort.uniq.each do |subm|
        entries = { :m => 'x', :c => 'x', :i => 'x' }
        entries[:i] = 'I' if index.include? subm
        entries[:c] = 'C' if gitconfig.include? subm
        entries[:m] = 'M' if gitmodules.include? subm
        result << "#{entries[:i]} #{entries[:c]} #{entries[:m]} #{subm}"
      end
      result
    end
  end
end

Simp::Rake::Git.new
