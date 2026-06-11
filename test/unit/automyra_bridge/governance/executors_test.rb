require File.expand_path('../../../test_helper', __dir__)

class AutomyraBridgeGovernanceExecutorsTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :trackers, :issue_statuses, :enumerations

  setup do
    WikiHub::PageLink.delete_all if defined?(WikiHub::PageLink)
    WikiHub::PageSnapshot.delete_all if defined?(WikiHub::PageSnapshot)
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    TaskHub::Task.delete_all if defined?(TaskHub::Task)
    Issue.where("subject LIKE 'Governance executor %'").delete_all

    @user = User.find(1)
    @other_user = User.find(3)
    @project = Project.find(1)
    @project.update!(status: Project::STATUS_ACTIVE)
    grant_permissions!(@user, %i[manage_task_hub_tasks edit_wiki_pages view_wiki_pages edit_issues manage_files])
    @policy = create_policy(@user)
    @run = AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, created_by: @user, status: 'running')
  end

  test 'attachment filename executor applies rename and captures rollback payload' do
    attachment = create_issue_attachment('old_name.pdf')
    action = create_action('update_attachment_filename', 'Attachment', attachment.id, 'attachment_filename', 'old_name.pdf', 'new_name.pdf')

    result = AutomyraBridge::Governance::Executors::AttachmentFilenameExecutor.call(action)

    assert result.applied?
    assert_equal 'new_name.pdf', attachment.reload.filename
    assert_equal 'applied', action.reload.status
    assert_equal 'applied', action.governance_finding.reload.status
    assert_equal({ 'filename' => 'old_name.pdf', 'attachment_id' => attachment.id }, JSON.parse(action.reload.rollback_payload))
  end

  test 'attachment filename executor fails stale object without mutating' do
    attachment = create_issue_attachment('changed_name.pdf')
    action = create_action('update_attachment_filename', 'Attachment', attachment.id, 'attachment_filename', 'old_name.pdf', 'new_name.pdf')

    result = AutomyraBridge::Governance::Executors::AttachmentFilenameExecutor.call(action)

    assert result.failed?
    assert_equal 'changed_name.pdf', attachment.reload.filename
    assert_equal 'Governance target changed since validation.', action.governance_finding.reload.evaluator_error
  end

  test 'attachment filename executor fails permission check' do
    attachment = create_issue_attachment('old_name.pdf')
    outsider = User.generate!(firstname: 'Governance', lastname: 'Outsider', mail: "governance-outsider-#{SecureRandom.hex(4)}@example.com")
    policy = create_policy(outsider)
    run = AutomyraBridge::GovernanceRun.create!(governance_policy: policy, created_by: outsider, status: 'running')
    action = create_action('update_attachment_filename', 'Attachment', attachment.id, 'attachment_filename', 'old_name.pdf', 'new_name.pdf', policy: policy, run: run, created_by: outsider)

    result = AutomyraBridge::Governance::Executors::AttachmentFilenameExecutor.call(action)

    assert result.failed?
    assert_equal 'old_name.pdf', attachment.reload.filename
    assert_equal 'Governance action is not permitted.', action.governance_finding.reload.evaluator_error
  end

  test 'attachment filename executor detects duplicate filename on same record' do
    issue = create_requirement_issue
    create_issue_attachment('existing_name.pdf', container: issue)
    attachment = create_issue_attachment('old_name.pdf', container: issue)
    action = create_action('update_attachment_filename', 'Attachment', attachment.id, 'attachment_filename', 'old_name.pdf', 'existing_name.pdf')

    result = AutomyraBridge::Governance::Executors::AttachmentFilenameExecutor.call(action)

    assert result.failed?
    assert_equal 'old_name.pdf', attachment.reload.filename
    assert_equal 'Attachment filename already exists on this record.', action.governance_finding.reload.evaluator_error
  end

  test 'task title executor applies update and captures rollback payload' do
    task = create_task('Old task title')
    action = create_action('update_task_title', 'TaskHub::Task', task.id, 'task_title', 'Old task title', 'New task title')

    result = AutomyraBridge::Governance::Executors::TaskTitleExecutor.call(action)

    assert result.applied?
    assert_equal 'New task title', task.reload.title
    assert_equal 'applied', action.reload.status
    assert_equal 'applied', action.governance_finding.reload.status
    assert_equal({ 'title' => 'Old task title', 'task_id' => task.id }, JSON.parse(action.rollback_payload))
  end

  test 'task title executor fails stale object without mutating' do
    task = create_task('Changed task title')
    action = create_action('update_task_title', 'TaskHub::Task', task.id, 'task_title', 'Old task title', 'New task title')

    result = AutomyraBridge::Governance::Executors::TaskTitleExecutor.call(action)

    assert result.failed?
    assert_equal 'Changed task title', task.reload.title
    assert_equal 'failed', action.reload.status
    assert_equal 'Governance target changed since validation.', action.governance_finding.reload.evaluator_error
  end

  test 'task title executor fails permission check' do
    task = create_task('Old task title')
    policy = create_policy(@other_user)
    run = AutomyraBridge::GovernanceRun.create!(governance_policy: policy, created_by: @other_user, status: 'running')
    action = create_action('update_task_title', 'TaskHub::Task', task.id, 'task_title', 'Old task title', 'New task title', policy: policy, run: run, created_by: @other_user)

    result = AutomyraBridge::Governance::Executors::TaskTitleExecutor.call(action)

    assert result.failed?
    assert_equal 'Old task title', task.reload.title
    assert_equal 'Governance action is not permitted.', action.governance_finding.reload.evaluator_error
  end

  test 'wiki title executor renames page and captures rollback payload' do
    page = create_wiki_page('Old_wiki_title')
    snapshot = create_snapshot(page, 'Old_wiki_title')
    action = create_action('update_wiki_title', 'WikiHub::PageSnapshot', snapshot.id, 'wiki_title', 'Old_wiki_title', 'New_wiki_title')

    result = AutomyraBridge::Governance::Executors::WikiTitleExecutor.call(action)

    assert result.applied?
    assert_equal 'New_wiki_title', page.reload.title
    assert_equal 'New_wiki_title', snapshot.reload.title
    assert_equal({ 'title' => 'Old_wiki_title', 'wiki_page_id' => page.id }, JSON.parse(action.reload.rollback_payload))
  end

  test 'wiki title executor handles rename collision gracefully' do
    page = create_wiki_page('Old_wiki_title')
    create_wiki_page('Existing_title')
    snapshot = create_snapshot(page, 'Old_wiki_title')
    action = create_action('update_wiki_title', 'WikiHub::PageSnapshot', snapshot.id, 'wiki_title', 'Old_wiki_title', 'Existing_title')

    result = AutomyraBridge::Governance::Executors::WikiTitleExecutor.call(action)

    assert result.failed?
    assert_equal 'Old_wiki_title', page.reload.title
    assert_equal 'Wiki page title already exists.', action.governance_finding.reload.evaluator_error
  end

  test 'task requirement link executor prevents duplicate links' do
    issue = create_requirement_issue
    task = create_task('Requirement task', issue_id: issue.id, project_id: issue.project_id)
    action = create_action('link_task_requirement', 'TaskHub::Task', task.id, 'task_requirement_link', '', "Requirement ##{issue.id}")

    result = AutomyraBridge::Governance::Executors::TaskRequirementLinkExecutor.call(action)

    assert result.skipped?
    assert_equal issue.id, task.reload.issue_id
    assert_equal 'validated', action.reload.status
    assert_equal [task.id], JSON.parse(action.rollback_payload)['existing_relation_ids']
  end

  test 'task requirement link executor applies link and captures reversible rollback payload' do
    issue = create_requirement_issue
    task = create_task('Requirement task without link')
    action = create_action('link_task_requirement', 'TaskHub::Task', task.id, 'task_requirement_link', '', "Requirement ##{issue.id}")

    result = AutomyraBridge::Governance::Executors::TaskRequirementLinkExecutor.call(action)

    assert result.applied?
    assert_equal issue.id, task.reload.issue_id
    assert_equal 'applied', action.reload.status
    rollback = JSON.parse(action.rollback_payload)
    assert_equal task.id, rollback['task_id']
    assert_equal [], rollback['existing_relation_ids']
  end

  test 'wiki requirement link executor creates link once and skips duplicate' do
    issue = create_requirement_issue
    page = create_wiki_page('Requirements_page')
    snapshot = create_snapshot(page, 'Requirements_page')
    action = create_action('link_wiki_requirement', 'WikiHub::PageSnapshot', snapshot.id, 'wiki_requirement_link', '', "Requirement ##{issue.id}")

    result = AutomyraBridge::Governance::Executors::WikiRequirementLinkExecutor.call(action)

    assert result.applied?
    assert_equal 1, WikiHub::PageLink.where(source_page_id: page.id, link_type: 'requirement').count
    assert_equal 'applied', action.reload.status
    rollback = JSON.parse(action.rollback_payload)
    assert_equal page.id, rollback['wiki_page_id']
    assert rollback['created_relation_id'].present?

    duplicate_action = create_action('link_wiki_requirement', 'WikiHub::PageSnapshot', snapshot.id, 'wiki_requirement_link', '', "Requirement ##{issue.id}")
    duplicate = AutomyraBridge::Governance::Executors::WikiRequirementLinkExecutor.call(duplicate_action)
    assert duplicate.skipped?
    assert_equal 1, WikiHub::PageLink.where(source_page_id: page.id, link_type: 'requirement').count
  end

  private

  def create_policy(user)
    AutomyraBridge::GovernancePolicy.create!(name: "Policy #{user.id}", project: @project, created_by: user, mode: 'apply_after_validation', provider_model: 'manifest/auto')
  end

  def create_task(title, attrs = {})
    TaskHub::Task.create!({ title: title, user: @user, author: @user, project: @project, status: 'todo', priority: 2 }.merge(attrs))
  end

  def create_wiki_page(title)
    wiki = @project.wiki || @project.create_wiki
    page = WikiPage.create!(wiki: wiki, title: title)
    page.content = WikiContent.new(page: page, text: 'body', author: @user)
    page.content.save!
    page
  end

  def create_snapshot(page, title)
    snapshot = WikiHub::PageSnapshot.find_or_initialize_by(wiki_page_id: page.id)
    snapshot.update!(project_id: @project.id, title: title, searchable_text: title)
    snapshot
  end

  def create_requirement_issue
    Issue.create!(project: @project, tracker: Tracker.first, status: IssueStatus.where(is_closed: false).first || IssueStatus.first, subject: 'Governance executor requirement', author: @user, priority: IssuePriority.default || IssuePriority.first)
  end

  def create_issue_attachment(filename, container: nil)
    issue = container || create_requirement_issue
    file = Tempfile.new(['governance-attachment', '.txt'])
    file.write('governance attachment test file')
    file.rewind
    Attachment.create!(container: issue, file: Rack::Test::UploadedFile.new(file.path, 'text/plain'), author: @user, filename: filename)
  ensure
    file&.close!
  end

  def create_action(action_type, object_type, object_id, finding_type, current_value, recommended_value, policy: @policy, run: @run, created_by: @user)
    finding = AutomyraBridge::GovernanceFinding.create!(governance_run: run, governance_policy: policy, object_type: object_type, object_id: object_id, finding_type: finding_type, current_value: current_value, recommended_value: recommended_value, confidence: 0.95, rationale: 'Executor test', status: 'valid', created_by: created_by)
    AutomyraBridge::GovernanceAction.create!(governance_run: run, governance_finding: finding, governance_policy: policy, action_type: action_type, object_type: object_type, object_id: object_id, rollback_payload: '{}', idempotency_key: SecureRandom.uuid, status: 'validated', created_by: created_by)
  end

  def grant_permissions!(user, permissions)
    role = Role.generate!(permissions: permissions)
    member = Member.find_or_initialize_by(project: @project, user: user)
    member.roles = [role]
    member.save!
  end
end
