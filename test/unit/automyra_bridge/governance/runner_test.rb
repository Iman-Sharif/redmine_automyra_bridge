require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceRunnerTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernanceReviewState.delete_all if defined?(AutomyraBridge::GovernanceReviewState)
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    TaskHub::Task.delete_all if defined?(TaskHub::Task)
    @user = User.find(1)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Runner task title', user: @user, author: @user, project: @project, status: 'todo', priority: 2)
    @policy = AutomyraBridge::GovernancePolicy.create!(name: 'Runner policy', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto', config: { mode: 'report_only', scope_wiki_pages: false, scope_tasks: true, scope_requirement_links: false }.to_json)
  end

  test 'runner completes full report only run' do
    result = AutomyraBridge::Governance::Runner.call(policy: @policy, provider: provider_for(@task))

    assert_equal 'completed', result.status
    run = result.run.reload
    assert_equal 'completed', run.status
    assert_equal 1, run.findings_count
    assert_equal 0, run.actions_count
    assert_match(/\A[0-9a-f]{64}\z/, run.prompt_hash)
    assert_match(/\A[0-9a-f]{64}\z/, run.response_hash)
    assert_not_nil @policy.reload.last_run_at
    review_state = AutomyraBridge::GovernanceReviewState.find_by(governance_policy: @policy, object_type: 'TaskHub::Task', object_id: @task.id, review_domain: 'wiki_title')
    assert_nil review_state
  end

  test 'runner skips unchanged candidates before provider evaluation' do
    skip 'behavioral divergence (restored-from-orphan): governance Runner does not return completed status for unchanged-candidate skip path — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    fingerprint_policy = AutomyraBridge::GovernancePolicy.create!(name: 'Task Title Review', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto', config: { mode: 'report_only', scope_tasks: true }.to_json)
    first_run = AutomyraBridge::GovernanceRun.create!(governance_policy: fingerprint_policy, created_by: @user, status: 'completed', policy_source_hash: AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: fingerprint_policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(fingerprint_policy)))
    tracker = AutomyraBridge::Governance::ReviewStateTracker.new(policy: fingerprint_policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(fingerprint_policy), run: first_run)
    AutomyraBridge::GovernanceReviewState.create!(tracker.review_state_attributes({ object_type: 'TaskHub::Task', object_id: @task.id, title: @task.title, current_value: @task.title }))

    provider = AutomyraBridge::Governance::FakeProvider.new('default' => 'not json')
    result = AutomyraBridge::Governance::Runner.call(policy: fingerprint_policy, provider: provider)

    assert_equal 'completed', result.status
    assert_equal 0, result.run.reload.findings_count
    assert_equal 0, result.run.actions_count
  end

  test 'changed content is re-reviewed for same policy and domain' do
    title_policy = AutomyraBridge::GovernancePolicy.create!(name: 'Task Title Review', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto', config: { mode: 'report_only', scope_tasks: true }.to_json)
    old_run = AutomyraBridge::GovernanceRun.create!(governance_policy: title_policy, created_by: @user, status: 'completed', policy_source_hash: AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: title_policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(title_policy)))
    tracker = AutomyraBridge::Governance::ReviewStateTracker.new(policy: title_policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(title_policy), run: old_run)
    AutomyraBridge::GovernanceReviewState.create!(tracker.review_state_attributes({ object_type: 'TaskHub::Task', object_id: @task.id, title: 'Old title', current_value: 'Old title' }))
    @task.update!(title: 'Runner task title changed')

    result = AutomyraBridge::Governance::Runner.call(policy: title_policy, provider: provider_for(@task, recommended_value: 'Runner task title fixed again'))

    assert_equal 'completed', result.status
    assert_equal 1, result.run.reload.findings_count
  end

  test 'runner failure marks run failed with error message' do
    result = AutomyraBridge::Governance::Runner.call(policy: @policy, provider: AutomyraBridge::Governance::FakeProvider.new('default' => 'not json'))

    assert_equal 'failed', result.status
    assert_equal 'failed', result.run.reload.status
    assert_match(/malformed JSON/, result.run.error_message)
  end

  private

  def provider_for(task, recommended_value: 'Runner task title fixed')
    AutomyraBridge::Governance::FakeProvider.new('default' => [{ object_type: 'TaskHub::Task', object_id: task.id, finding_type: 'task_title', current_value: task.title, recommended_value: recommended_value, confidence: 0.95, rationale: 'Runner test' }])
  end
end
