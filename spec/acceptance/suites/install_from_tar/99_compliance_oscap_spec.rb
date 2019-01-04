require 'spec_helper_tar'

test_name 'Check SCAP for stig profile'

describe 'run the SSG against the appropriate fixtures' do

  hosts.each do |host|
    context "on #{host}" do
      before(:all) do
        @ssg = Simp::BeakerHelpers::SSG.new(host)

        # If we don't do this, the variable gets reset
        @ssg_report = { :data => nil }
      end

      it 'should run the SSG' do
        os = pfact_on(host, 'operatingsystemmajrelease')
        profile = "rhel#{os}-disa"

        @ssg.evaluate(profile)
      end

      it 'should have an SSG report' do
        expect(@ssg_report[:data]).to_not be_nil

        @ssg.write_report(@ssg_report[:data])
      end

      it 'should have run some tests' do
        expect(@ssg_report[:data][:failed].count + @ssg_report[:data][:passed].count).to be > 0
      end

      it 'should not have any failing tests' do
        if @ssg_report[:data][:failed].count > 0
          puts @ssg_report[:data][:report]
        end

        skip 'Full check'
        expect(@ssg_report[:data][:score]).to eq(100)
      end
    end
  end
end
