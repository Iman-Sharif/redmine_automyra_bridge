require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceModelsTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues, :trackers, :issue_statuses, :enumerations

  setup do
    AutomyraBridge::GovernanceReviewState.delete_all if defined?(AutomyraBridge::GovernanceReviewState)
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all

    @user = User.find(2)
    @project = Project.find(1)
    @policy = AutomyraBridge::GovernancePolicy.create!(
      name: 'Governance defaults',
      project: @project,
      created_by: @user,
      config: { style: 'concise' }.to_json,
      mode: 'report_only',
      provider_model: 'manifest/auto'
    )
    @run = AutomyraBridge::GovernanceRun.create!(
      governance_policy: @policy,
      created_by: @user,
      policy_source_hash: 'policy-hash'
    )
    @finding = AutomyraBridge::GovernanceFinding.create!(
      governance_run: @run,
      governance_policy: @policy,
      created_by: @user,
      object_type: 'WikiPage',
      object_id: 123,
      finding_type: 'wiki_title',
      current_value: 'Old title',
      recommended_value: 'New title',
      confidence: 0.875,
      rationale: 'Matches governance policy.'
    )
  end

  test 'policy validates required fields and mode inclusion' do
    policy = AutomyraBridge::GovernancePolicy.new(project: @project, mode: 'unsafe')

    assert_not policy.valid?
    assert policy.errors[:name].present?
    assert_includes policy.errors[:mode], 'is not included in the list'

    assert @policy.report_only?
    assert_includes AutomyraBridge::GovernancePolicy.enabled, @policy
  end

  test 'global policy does not require a project' do
    policy = AutomyraBridge::GovernancePolicy.new(
      name: 'Global governance defaults',
      scope_type: 'global',
      mode: 'report_only',
      provider_model: 'manifest/auto'
    )

    assert policy.valid?
    assert policy.global?
  end

  test 'project policy still requires a project' do
    policy = AutomyraBridge::GovernancePolicy.new(
      name: 'Project governance defaults',
      scope_type: 'project',
      mode: 'report_only',
      provider_model: 'manifest/auto'
    )

    assert_not policy.valid?
    assert policy.errors[:project].present?
  end

  test 'global requirement collector scans active projects' do
    global_policy = AutomyraBridge::GovernancePolicy.create!(
      name: 'Global requirements',
      scope_type: 'global',
      created_by: User.find(1),
      mode: 'report_only',
      provider_model: 'manifest/auto',
      config: { requirement_tracker_ids: [Tracker.first.id] }.to_json
    )

    candidates = AutomyraBridge::Governance::Collectors::RequirementCollector.call(policy: global_policy, limit: 20)

    assert candidates.any?
    assert candidates.all? { |candidate| candidate[:project_id].present? }
  end

  test 'run validates status and supports status transitions' do
    @run.mark_running!

    assert @run.reload.running?
    assert_not_nil @run.started_at
    assert_nil @run.finished_at

    @run.mark_completed!(findings_count: 1, actions_count: 1, applied_count: 1)

    assert @run.reload.completed?
    assert_equal 1, @run.findings_count
    assert_not_nil @run.finished_at

    @run.status = 'unknown'
    assert_not @run.valid?
  end

  test 'finding validates type and supports status transitions' do
    @finding.mark_valid!

    assert @finding.reload.valid_status?
    assert_includes AutomyraBridge::GovernanceFinding.valid, @finding

    @finding.mark_applied!
    assert @finding.reload.applied?

    @finding.finding_type = 'unknown'
    assert_not @finding.valid?
  end

  test 'attachment filename findings are valid and build review actions only' do
    @finding.update!(object_type: 'Attachment', object_id: 456, finding_type: 'attachment_filename', current_value: 'Bad File Name.pdf', recommended_value: 'bad-file-name.pdf', status: 'valid')

    actions = AutomyraBridge::Governance::ActionBuilder.call(run: @run, policy: @policy, findings: [@finding], created_by: @user)

    assert_equal 1, actions.size
    assert_equal 'review_attachment_filename', actions.first.action_type
    assert_equal 'validated', actions.first.status
    assert_equal({ 'filename' => 'Bad File Name.pdf', 'attachment_id' => 456 }, JSON.parse(actions.first.rollback_payload))
  end

  test 'review state tracks fingerprint by policy object and domain' do
    state = AutomyraBridge::GovernanceReviewState.create!(
      governance_policy: @policy,
      governance_run: @run,
      object_type: 'WikiHub::PageSnapshot',
      object_id: 456,
      review_domain: 'wiki_summary',
      content_fingerprint: 'abc123',
      policy_source_hash: 'policy-hash',
      last_reviewed_at: Time.current
    )

    assert state.valid?
    assert_equal @policy, state.governance_policy
    assert_equal @run, state.governance_run
  end

  test 'wiki governance quality findings are valid and build review actions only' do
    expected = {
      'wiki_summary' => 'review_wiki_summary',
      'wiki_metadata' => 'review_wiki_metadata',
      'wiki_heading_structure' => 'review_wiki_heading_structure'
    }

    expected.each do |finding_type, action_type|
      finding = @run.governance_findings.create!(
        governance_policy: @policy,
        object_type: 'WikiHub::PageSnapshot',
        object_id: 456,
        finding_type: finding_type,
        current_value: 'Current content',
        recommended_value: 'Recommended content',
        confidence: 0.9,
        rationale: 'Matches policy.',
        status: 'valid',
        created_by: @user
      )

      actions = AutomyraBridge::Governance::ActionBuilder.call(run: @run, policy: @policy, findings: [finding], created_by: @user)

      assert_equal action_type, actions.first.action_type
      assert_equal 'validated', actions.first.status
      assert_equal({ 'content' => 'Current content' }, JSON.parse(actions.first.rollback_payload))
    end
  end

  test 'action validates duplicate idempotency key and supports status transitions' do
    action = create_action('governance-action-repeat')

    assert action.pending?
    action.mark_validated!
    assert action.reload.validated?
    action.mark_applied!
    assert action.reload.applied?
    assert_not_nil action.applied_at
    action.mark_rolled_back!
    assert action.reload.rolled_back?
    assert_not_nil action.rolled_back_at

    duplicate = build_action('governance-action-repeat')
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:idempotency_key], 'has already been taken'
  end

  test 'associations connect policy runs findings and actions' do
    action = create_action('governance-action-association')

    assert_includes @policy.governance_runs, @run
    assert_includes @run.governance_findings, @finding
    assert_includes @finding.governance_actions, action
    assert_equal @policy, action.governance_policy
  end

  test 'policy validator requires requirement selection schema for requirement linking scopes' do
    @policy.update!(config: { scope_wiki_requirement_links: true }.to_json)

    result = AutomyraBridge::Governance::PolicyValidator.call(policy: @policy)
    assert_not result.valid?
    assert result.errors.any? { |error| error.include?('requirement linking requires') }

    result = AutomyraBridge::Governance::PolicyValidator.call(
      policy: @policy,
      config: AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(@policy).merge('requirement_tracker_names' => ['Requirement'])
    )
    assert result.valid?
  end

  private

  def create_action(idempotency_key)
    build_action(idempotency_key).tap(&:save!)
  end

  def build_action(idempotency_key)
    AutomyraBridge::GovernanceAction.new(
      governance_run: @run,
      governance_finding: @finding,
      governance_policy: @policy,
      created_by: @user,
      action_type: 'update_wiki_title',
      object_type: 'WikiPage',
      object_id: 123,
      rollback_payload: { title: 'Old title' }.to_json,
      idempotency_key: idempotency_key
    )
  end
end
