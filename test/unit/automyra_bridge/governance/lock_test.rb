require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceLockTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    @user = User.find(1)
    @project = Project.find(1)
    @policy = AutomyraBridge::GovernancePolicy.create!(name: 'Lock policy', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto')
  end

  test 'runner skips when policy already has running run' do
    active = AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, created_by: @user, status: 'running')

    result = AutomyraBridge::Governance::Runner.call(policy: @policy, provider: AutomyraBridge::Governance::FakeProvider.new('default' => []))

    assert result.skipped?
    assert_equal active, AutomyraBridge::GovernanceRun.running.last
    assert_equal 1, AutomyraBridge::GovernanceRun.count
  end

  test 'runner recovers stale active run and starts a fresh run' do
    stale = AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, created_by: @user, status: 'running', started_at: 31.minutes.ago, created_at: 31.minutes.ago, updated_at: 31.minutes.ago)

    result = AutomyraBridge::Governance::Runner.call(policy: @policy, provider: AutomyraBridge::Governance::FakeProvider.new('default' => []))

    assert_equal 'completed', result.status
    assert_equal 'failed', stale.reload.status
    assert_match(/automatically marked failed/i, stale.error_message)
    assert_equal 2, AutomyraBridge::GovernanceRun.count
    assert_equal 'completed', AutomyraBridge::GovernanceRun.order(:id).last.status
  end
end
