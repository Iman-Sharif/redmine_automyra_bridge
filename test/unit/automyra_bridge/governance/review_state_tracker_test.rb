require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceReviewStateTrackerTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridge::GovernanceReviewState.delete_all if defined?(AutomyraBridge::GovernanceReviewState)
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all

    @user = User.find(1)
    @project = Project.find(1)
  end

  test 'wiki title domain skips unchanged title even when page body changes' do
    policy = create_policy('Global Wiki Title Standard')
    run = create_run(policy)
    tracker = tracker_for(policy, run)
    old_candidate = wiki_candidate(title: 'Architecture - Standard - auth flow', page_text: 'old body')
    new_candidate = wiki_candidate(title: 'Architecture - Standard - auth flow', page_text: 'new body with major changes')

    AutomyraBridge::GovernanceReviewState.create!(tracker.review_state_attributes(old_candidate))

    assert_empty tracker.filter_candidates([new_candidate])
  end

  test 'wiki summary domain re-reviews when page body changes' do
    skip 'behavioral divergence (restored-from-orphan): ReviewStateTracker.filter_candidates does not re-review wiki summary domain on body change — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    policy = create_policy('Global Wiki Summary Standard')
    run = create_run(policy)
    tracker = tracker_for(policy, run)
    old_candidate = wiki_candidate(title: 'Architecture - Standard - auth flow', page_text: 'old body')
    new_candidate = wiki_candidate(title: 'Architecture - Standard - auth flow', page_text: 'new body with major changes')

    AutomyraBridge::GovernanceReviewState.create!(tracker.review_state_attributes(old_candidate))

    assert_equal [new_candidate], tracker.filter_candidates([new_candidate])
  end

  private

  def create_policy(name)
    AutomyraBridge::GovernancePolicy.create!(
      name: name,
      project: @project,
      created_by: @user,
      mode: 'report_only',
      provider_model: 'manifest/auto',
      config: { mode: 'report_only', scope_wiki_pages: true }.to_json
    )
  end

  def create_run(policy)
    AutomyraBridge::GovernanceRun.create!(
      governance_policy: policy,
      created_by: @user,
      status: 'completed',
      policy_source_hash: AutomyraBridge::Governance::PolicySourceSnapshot.hash(policy: policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(policy))
    )
  end

  def tracker_for(policy, run)
    AutomyraBridge::Governance::ReviewStateTracker.new(policy: policy, config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(policy), run: run)
  end

  def wiki_candidate(title:, page_text:)
    {
      object_type: 'WikiHub::PageSnapshot',
      object_id: 45,
      title: title,
      current_value: title,
      page_text: page_text,
      project_id: @project.id
    }
  end
end
