require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceRunJobTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    @user = User.find(1)
    @project = Project.find(1)
    @policy = AutomyraBridge::GovernancePolicy.create!(name: 'Job policy', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto')
  end

  test 'job invokes governance runner with policy and mode' do
    AutomyraBridge::Governance::Runner.expects(:call).with(policy: @policy, mode: 'report_only').returns(AutomyraBridge::Governance::Runner::Result.new(run: nil, status: 'completed', message: 'completed'))

    AutomyraBridge::GovernanceRunJob.perform_now(@policy.id, 'report_only')
  end
end
