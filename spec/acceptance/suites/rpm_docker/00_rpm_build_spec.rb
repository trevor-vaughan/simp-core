require 'spec_helper_rpm'

test_name 'RPM build'

simp_core_dir = File.expand_path(File.join(fixtures_path, '..', '..'))

# Custom Gemfile Support
gemfile = nil
gemfile_path = File.expand_path(File.join(fixtures_path,'Gemfile'))

if File.file?(gemfile_path)
  gemfile = gemfile_path
end

describe 'RPM build' do
  # We need a normal user for building the RPMs
  let(:build_user) { 'build_user' }
  let(:run_cmd) { %(runuser #{build_user} -l -c ) }

  hosts.each do |host|
    it 'should have access to the local simp-core' do
      host.file_exist?('/simp-core/metadata.json')
    end
  end
end
