require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceModeExecutorTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    AutomyraBridgeActionProposal.delete_all if defined?(AutomyraBridgeActionProposal)
    AutomyraBridgeJob.delete_all
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    TaskHub::Task.delete_all if defined?(TaskHub::Task)

    @user = User.find(1)
    @project = Project.find(1)
    grant_permissions!(@user, %i[manage_task_hub_tasks edit_wiki_pages view_wiki_pages edit_issues manage_files])
    @task = TaskHub::Task.create!(title: 'Old task title', user: @user, author: @user, project: @project, status: 'todo', priority: 2)
  end

  test 'apply after validation applies attachment filename changes' do
    policy = create_policy('apply_after_validation', max_changes_per_run: 1)
    run = create_run(policy)
    attachment = create_issue_attachment('old_name.pdf')

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [attachment_filename_finding(attachment)])

    assert_equal 1, result.actions.size
    assert_equal 1, result.applied_count
    assert_equal 'new_name.pdf', attachment.reload.filename
    assert_equal 'update_attachment_filename', result.actions.first.reload.action_type
    assert_equal({ 'filename' => 'old_name.pdf', 'attachment_id' => attachment.id }, JSON.parse(result.actions.first.rollback_payload))
  end

  test 'report only mode creates valid findings only' do
    policy = create_policy('report_only')
    run = create_run(policy)

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [task_title_finding])

    assert_equal 1, result.findings.size
    assert_empty result.actions
    assert_empty result.proposals
    assert_equal 1, run.reload.findings_count
    assert_equal 0, run.actions_count
    assert_equal 'valid', AutomyraBridge::GovernanceFinding.last.status
  end

  test 'propose mode creates findings actions and action proposals' do
    policy = create_policy('propose')
    run = create_run(policy)

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [task_title_finding])

    assert_equal 1, result.findings.size
    assert_equal 1, result.actions.size
    assert_equal 1, result.proposals.size
    assert_equal 'proposed', result.actions.first.reload.status
    proposal = result.proposals.first
    assert_equal 'update_task', proposal.action_type
    assert_equal @task.id, proposal.task_id
    assert_equal result.actions.first.id, proposal.payload.dig('governance', 'governance_action_id')
    assert_equal 1, run.reload.actions_count
  end

  test 'apply after validation creates and marks actions applied up to limit' do
    policy = create_policy('apply_after_validation', max_changes_per_run: 1)
    run = create_run(policy)

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [task_title_finding, wiki_title_finding])

    assert_equal 2, result.actions.size
    assert_equal 1, result.applied_count
    assert_equal 1, result.actions.count { |action| action.reload.applied? }
    assert_equal 'New task title', @task.reload.title
    assert_equal 1, AutomyraBridge::GovernanceFinding.applied.count
    assert_equal 1, run.reload.applied_count
    assert_equal 2, run.actions_count
    assert_equal 0, AutomyraBridgeActionProposal.count
  end

  test 'apply after validation validates review-only metadata actions without applying' do
    policy = create_policy('apply_after_validation', max_changes_per_run: 1)
    run = create_run(policy)

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [wiki_metadata_finding])

    assert_equal 1, result.actions.size
    assert_equal 0, result.applied_count
    assert_equal 'validated', result.actions.first.reload.status
    assert_equal 'valid', result.findings.first.reload.status
    assert_equal 1, run.reload.actions_count
  end

  test 'action builder stores rollback payload and deterministic idempotency key' do
    policy = create_policy('propose')
    run = create_run(policy)
    finding = AutomyraBridge::Governance::FindingPersistor.call(run: run, findings: [task_title_finding]).first

    action = AutomyraBridge::Governance::ActionBuilder.call(run: run, findings: [finding]).first
    expected_key = AutomyraBridge::Governance::ActionBuilder.idempotency_key(
      policy: policy,
      object_type: 'TaskHub::Task',
      object_id: @task.id,
      action_type: 'update_task_title',
      current_value: 'Old task title',
      recommended_value: 'New task title'
    )

    assert_equal expected_key, action.idempotency_key
    assert_equal({ 'title' => 'Old task title' }, JSON.parse(action.rollback_payload))
  end

  test 'duplicate runs do not create duplicate actions or proposals' do
    policy = create_policy('propose')
    first_run = create_run(policy)
    second_run = create_run(policy)

    assert_difference('AutomyraBridge::GovernanceAction.count', 1) do
      AutomyraBridge::Governance::ModeExecutor.call(run: first_run, findings: [task_title_finding])
      AutomyraBridge::Governance::ModeExecutor.call(run: second_run, findings: [task_title_finding])
    end
    assert_equal 1, AutomyraBridgeActionProposal.count
  end

  test 'invalid evaluator findings persist as invalid and do not build actions' do
    policy = create_policy('propose')
    run = create_run(policy)
    invalid = task_title_finding.merge('status' => 'invalid', 'evaluator_error' => 'failed validation')

    result = AutomyraBridge::Governance::ModeExecutor.call(run: run, findings: [invalid])

    assert_equal 'invalid', result.findings.first.reload.status
    assert_empty result.actions
    assert_equal 0, run.reload.actions_count
  end

  private

  def create_policy(mode, attrs = {})
    AutomyraBridge::GovernancePolicy.create!({
      name: "#{mode} policy",
      project: @project,
      created_by: @user,
      mode: mode,
      provider_model: 'manifest/auto',
      config: { mode: mode }.to_json
    }.merge(attrs))
  end

  def create_run(policy)
    AutomyraBridge::GovernanceRun.create!(governance_policy: policy, created_by: @user, status: 'running')
  end

  def task_title_finding
    {
      'object_type' => 'TaskHub::Task',
      'object_id' => @task.id,
      'finding_type' => 'task_title',
      'current_value' => 'Old task title',
      'recommended_value' => 'New task title',
      'confidence' => 0.95,
      'rationale' => 'Task title should use sentence case.'
    }
  end

  def wiki_title_finding
    {
      'object_type' => 'WikiHub::PageSnapshot',
      'object_id' => 99_001,
      'finding_type' => 'wiki_title',
      'current_value' => 'OLD WIKI TITLE',
      'recommended_value' => 'Old wiki title',
      'confidence' => 0.91,
      'rationale' => 'Wiki title should use sentence case.'
    }
  end

  def wiki_metadata_finding
    {
      'object_type' => 'WikiHub::PageSnapshot',
      'object_id' => 99_002,
      'finding_type' => 'wiki_metadata',
      'current_value' => 'OLD WIKI TITLE',
      'recommended_value' => { category: 'Architecture', tags: %w[automyra memory] }.to_json,
      'confidence' => 0.91,
      'rationale' => 'Wiki metadata should describe the page.'
    }
  end

  def attachment_filename_finding(attachment)
    {
      'object_type' => 'Attachment',
      'object_id' => attachment.id,
      'finding_type' => 'attachment_filename',
      'current_value' => 'old_name.pdf',
      'recommended_value' => 'new_name.pdf',
      'confidence' => 0.95,
      'rationale' => 'Attachment filename should follow the standard.'
    }
  end

  def create_issue_attachment(filename)
    issue = Issue.create!(project: @project, tracker: Tracker.first, status: IssueStatus.where(is_closed: false).first || IssueStatus.first, subject: 'Governance mode executor attachment', author: @user, priority: IssuePriority.default || IssuePriority.first)
    file = Tempfile.new(['governance-attachment', '.txt'])
    file.write('governance attachment test file')
    file.rewind
    Attachment.create!(container: issue, file: Rack::Test::UploadedFile.new(file.path, 'text/plain'), author: @user, filename: filename)
  ensure
    file&.close!
  end

  def grant_permissions!(user, permissions)
    role = Role.generate!(permissions: permissions)
    member = Member.find_or_initialize_by(project: @project, user: user)
    member.roles = [role]
    member.save!
  end
end
