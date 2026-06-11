require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceSchedulerTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernancePolicy.delete_all
    @user = User.find(1)
    @project = Project.find(1)
  end

  test 'selects enabled due policies only' do
    never_run = create_policy('Never run', last_run_at: nil, frequency_hours: 24)
    due = create_policy('Due', last_run_at: 25.hours.ago, frequency_hours: 24)
    not_due = create_policy('Not due', last_run_at: 1.hour.ago, frequency_hours: 24)
    disabled = create_policy('Disabled', enabled: false)

    policies = AutomyraBridge::Governance::Scheduler.call

    assert_includes policies, never_run
    assert_includes policies, due
    assert_not_includes policies, not_due
    assert_not_includes policies, disabled
  end

  private

  def create_policy(name, attrs = {})
    AutomyraBridge::GovernancePolicy.create!({ name: name, project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto' }.merge(attrs))
  end
end
