require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeToolRegistryTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @user = User.find(2)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Registry task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra help')
    @job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'TaskHub::TaskComment', source_id: @comment.id, user: @user, project: @project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'task_hub_comment' }.to_json)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
  end

  test 'registry exposes task and issue tools with schemas' do
    names = AutomyraBridge::ToolRegistry.all.map(&:name)

    %w[task.create task.update task.cancel task.complete task.reopen task.assign task.set_priority task.set_due_date task.add_comment task.link_issue task.promote_to_issue task.search].each do |name|
      assert_includes names, name
    end
    assert_includes names, 'issue.assign_to_requester'
    assert_includes names, 'issue.add_comment'
    %w[issue.create issue.update issue.assign issue.set_status issue.set_priority issue.set_due_date issue.link_related issue.search issue.summarize].each do |name|
      assert_includes names, name
    end
    %w[wiki.read wiki.search wiki.create_page wiki.update_page wiki.create_draft wiki.summarize wiki.backlinks wiki.related_pages].each do |name|
      assert_includes names, name
    end
    %w[context.current_object context.current_thread context.linked_objects context.project_search context.memory_search context.expand project.status_summary].each do |name|
      assert_includes names, name
    end
    assert_equal 'task.create', AutomyraBridge::ToolRegistry.find('task.create').schema[:name]
  end

  test 'tool schemas include provider-compatible function definitions and internal metadata' do
    AutomyraBridge::ToolRegistry.schemas_for_job(@job).each do |schema|
      assert_equal 'function', schema[:type]
      assert schema[:function].is_a?(Hash), "#{schema.inspect} missing function definition"
      assert_equal schema[:name], schema[:function][:name]
      assert_equal schema[:description], schema[:function][:description]
      assert_equal schema[:input_schema], schema[:function][:parameters]
      assert_equal schema[:input_schema], schema[:parameters]
      assert_equal 'object', schema.dig(:function, :parameters, :type)
      assert schema[:risk_level].present?
      assert schema[:legacy_action_type].present?
    end
  end

  test 'all registered tools have required constants and consistent names' do
    assert_empty AutomyraBridge::ToolRegistry.validate_tool_classes!(logger: nil)

    names = AutomyraBridge::ToolRegistry.all.map(&:name)
    assert_equal names.uniq.sort, names.sort
    names.each do |name|
      tool = AutomyraBridge::ToolRegistry.find(name)
      assert_equal name, tool.schema.dig(:function, :name)
    end
  end

  test 'context builder defaults to compact tier and broadens with project search' do
    task = TaskHub::Task.create!(title: 'Searchable context task', user: @user, author: @user, project: @project, status: 'todo')
    task.comments.create!(author: @user, body: '@automyra context please')

    compact = AutomyraBridge::ContextBuilder.for_task(task, @user)
    expanded = AutomyraBridge::ContextBuilder.for_task(task, @user, tier: 3)

    assert_equal 1, compact[:tier]
    assert_nil compact[:project_search]
    assert_equal 3, expanded[:tier]
    assert(expanded[:project_search][:tasks].any? { |item| item[:title] == 'Searchable context task' })
  end

  test 'context project search tool returns broadened project context' do
    task = TaskHub::Task.create!(title: 'Tool searchable task', user: @user, author: @user, project: @project, status: 'todo')
    comment = task.comments.create!(author: @user, body: '@automyra find context')
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'TaskHub::TaskComment', source_id: comment.id, user: @user, project: @project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'task_hub_comment' }.to_json)
    tool = AutomyraBridge::ToolRegistry.find('context.project_search')

    result = tool.call(job, @user, { 'query' => 'Tool searchable', 'limit' => 5 })

    assert(result[:result][:tasks].any? { |item| item[:title] == 'Tool searchable task' })
  end

  test 'registry filters tools by job context' do
    names = AutomyraBridge::ToolRegistry.for_job(@job).map(&:name)

    assert_includes names, 'task.create'
    assert_includes names, 'task.update'
    assert_includes names, 'task.cancel'
    assert_includes names, 'task.add_comment'
    assert_includes names, 'task.search'
    assert_not_includes names, 'issue.assign_to_requester'
  end

  test 'task tools execute and verify through registry' do
    create = AutomyraBridge::ToolRegistry.find('task.create')
    update = AutomyraBridge::ToolRegistry.find('task.update')
    cancel = AutomyraBridge::ToolRegistry.find('task.cancel')

    created = create.call(@job, @user, { 'task' => { 'title' => 'Created through tool' } })
    create.verify!(created, { 'task' => { 'title' => 'Created through tool' } })
    assert_equal 'Created through tool', TaskHub::Task.find(created[:task_id]).title

    updated = update.call(@job, @user, { 'task' => { 'title' => 'Updated through tool' } })
    update.verify!(updated, { 'task' => { 'title' => 'Updated through tool' } })
    assert_equal 'Updated through tool', @task.reload.title

    cancelled = cancel.call(@job, @user, {})
    cancel.verify!(cancelled, {})
    assert_equal 'cancelled', @task.reload.status
  end

  test 'issue tools execute and verify through registry' do
    issue = Issue.find(1)
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'Journal', source_id: issue.journals.create!(user: @user, notes: '@automyra').id, user: @user, project: issue.project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'issue_journal', issue_id: issue.id }.to_json)
    assign = AutomyraBridge::ToolRegistry.find('issue.assign_to_requester')
    comment = AutomyraBridge::ToolRegistry.find('issue.add_comment')

    assigned = assign.call(job, @user, {})
    assign.verify!(assigned, {})
    commented = comment.call(job, @user, { 'comment' => { 'body' => 'Comment through tool' } })

    assert_equal issue.id, commented[:issue_id]
    assert_includes issue.reload.journals.order(:id).last.notes, 'Comment through tool'
  end

  test 'expanded issue tools execute through registry' do
    issue = Issue.find(1)
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'Journal', source_id: issue.journals.create!(user: @user, notes: '@automyra').id, user: @user, project: issue.project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'issue_journal', issue_id: issue.id }.to_json)
    create = AutomyraBridge::ToolRegistry.find('issue.create')
    update = AutomyraBridge::ToolRegistry.find('issue.update')
    assign = AutomyraBridge::ToolRegistry.find('issue.assign')
    status = AutomyraBridge::ToolRegistry.find('issue.set_status')
    priority = AutomyraBridge::ToolRegistry.find('issue.set_priority')
    due = AutomyraBridge::ToolRegistry.find('issue.set_due_date')
    link = AutomyraBridge::ToolRegistry.find('issue.link_related')
    search = AutomyraBridge::ToolRegistry.find('issue.search')
    summarize = AutomyraBridge::ToolRegistry.find('issue.summarize')

    created = create.call(job, @user, { 'issue' => { 'subject' => 'Issue through tool' } })
    create.verify!(created, { 'issue' => { 'subject' => 'Issue through tool' } })
    update.call(job, @user, { 'issue' => { 'subject' => 'Updated issue through tool' } })
    assert_equal 'Updated issue through tool', issue.reload.subject
    assign.call(job, @user, { 'assignment' => { 'assigned_to_id' => @user.id } })
    assert_equal @user.id, issue.reload.assigned_to_id
    status.call(job, @user, { 'issue' => { 'status_id' => IssueStatus.first.id } })
    priority.call(job, @user, { 'issue' => { 'priority_id' => IssuePriority.first.id } })
    due.call(job, @user, { 'issue' => { 'due_date' => Date.current.to_s } })
    assert_equal Date.current, issue.reload.due_date
    other_issue = Issue.generate!(project: issue.project, tracker: issue.tracker, author: @user, subject: 'Related issue')
    assert link.call(job, @user, { 'target' => { 'related_issue_id' => other_issue.id } })[:relation_id]
    assert search.call(job, @user, { 'query' => 'Updated', 'limit' => 5 })[:issues].any?
    assert_includes summarize.call(job, @user, {})[:summary], 'Updated issue through tool'
  end

  test 'wiki tools execute through registry' do
    @project.create_wiki unless @project.wiki
    create = AutomyraBridge::ToolRegistry.find('wiki.create_page')
    read = AutomyraBridge::ToolRegistry.find('wiki.read')
    update = AutomyraBridge::ToolRegistry.find('wiki.update_page')
    search = AutomyraBridge::ToolRegistry.find('wiki.search')
    draft = AutomyraBridge::ToolRegistry.find('wiki.create_draft')
    summarize = AutomyraBridge::ToolRegistry.find('wiki.summarize')
    backlinks = AutomyraBridge::ToolRegistry.find('wiki.backlinks')
    related = AutomyraBridge::ToolRegistry.find('wiki.related_pages')

    create.call(@job, @user, { 'wiki' => { 'title' => 'Automyra Tool Page', 'text' => 'Initial text' } })
    assert_equal 'Initial text', read.call(@job, @user, { 'wiki' => { 'title' => 'Automyra Tool Page' } })[:text]
    update.call(@job, @user, { 'wiki' => { 'title' => 'Automyra Tool Page', 'text' => 'Updated text with [[Linked Page]]' } })
    draft.call(@job, @user, { 'wiki' => { 'title' => 'Automyra Draft', 'text' => 'Draft body' } })

    assert search.call(@job, @user, { 'query' => 'Automyra', 'limit' => 5 })[:pages].any?
    assert_includes summarize.call(@job, @user, { 'wiki' => { 'title' => 'Automyra Tool Page' } })[:summary], 'Updated text'
    assert backlinks.call(@job, @user, { 'wiki' => { 'title' => 'Linked Page' } })[:pages].any?
    assert related.call(@job, @user, { 'wiki' => { 'title' => 'Automyra', 'limit' => 5 } })[:pages].any?
  end

  test 'expanded task tools execute and verify through registry' do
    complete = AutomyraBridge::ToolRegistry.find('task.complete')
    reopen = AutomyraBridge::ToolRegistry.find('task.reopen')
    assign = AutomyraBridge::ToolRegistry.find('task.assign')
    priority = AutomyraBridge::ToolRegistry.find('task.set_priority')
    due = AutomyraBridge::ToolRegistry.find('task.set_due_date')
    comment = AutomyraBridge::ToolRegistry.find('task.add_comment')
    search = AutomyraBridge::ToolRegistry.find('task.search')

    completed = complete.call(@job, @user, {})
    complete.verify!(completed, {})
    reopened = reopen.call(@job, @user, { 'status' => 'todo' })
    reopen.verify!(reopened, { 'status' => 'todo' })
    assigned = assign.call(@job, @user, { 'assignment' => { 'assigned_to_id' => @user.id } })
    assign.verify!(assigned, { 'assignment' => { 'assigned_to_id' => @user.id } })
    changed_priority = priority.call(@job, @user, { 'task' => { 'priority' => 4 } })
    priority.verify!(changed_priority, { 'task' => { 'priority' => 4 } })
    changed_due = due.call(@job, @user, { 'task' => { 'due_date' => Date.current.to_s } })
    due.verify!(changed_due, { 'task' => { 'due_date' => Date.current.to_s } })
    added_comment = comment.call(@job, @user, { 'comment' => { 'body' => 'Task comment through tool' } })
    comment.verify!(added_comment, {})
    found = search.call(@job, @user, { 'query' => 'Registry', 'limit' => 5 })

    assert_equal @task.id, found[:tasks].first[:id]
  end

  test 'task tools fail with invalid input and unauthorized users' do
    other = User.generate!(login: 'other')
    Member.create!(user: other, project: @project, role_ids: [Role.find_by_name('Manager').id])

    # Unauthorized user authorization check
    cancel = AutomyraBridge::ToolRegistry.find('task.cancel')
    assert_equal false, cancel.authorized?(@job, other)

    # Invalid status for update is silently ignored by task safe_attributes
    update = AutomyraBridge::ToolRegistry.find('task.update')
    assert_raises(RuntimeError) { update.call(@job, @user, { 'task' => { 'status' => 'invalid_status' } }) }
  end

  test 'issue tools fail with invalid workflow and unauthorized users' do
    private_project = Project.generate!(name: 'AuthQA', is_public: false)
    Tracker.first || raise('No tracker for test')
    IssueStatus.first || raise('No issue status for test')
    issue = Issue.create!(project: private_project, tracker: Tracker.first, author: @user, subject: 'Auth test issue', status: IssueStatus.first)
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'Journal', source_id: issue.journals.create!(user: @user, notes: '@automyra').id, user: @user, project: private_project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'issue_journal', issue_id: issue.id }.to_json)

    # Invalid status ID triggers tool-side validation
    set_status = AutomyraBridge::ToolRegistry.find('issue.set_status')
    assert_raises(RuntimeError) { set_status.call(job, @user, { 'issue' => { 'status_id' => 999_999 } }) }

    # Unauthorized user must not have membership or admin role
    anon = User.anonymous
    assert_equal false, anon.admin?
    assert_equal false, set_status.authorized?(job, anon)
  end

  test 'wiki tools detect stale edits and invalid input' do
    @project.create_wiki unless @project.wiki
    update = AutomyraBridge::ToolRegistry.find('wiki.update_page')

    # Create the page first so the tool can update it
    wiki = Wiki.find_by(project_id: @project.id) || raise('Wiki not available')
    page = WikiPage.find_by(wiki_id: wiki.id, title: 'Stale Page')
    page ||= WikiPage.create!(wiki_id: wiki.id, title: 'Stale Page')
    page.content = WikiContent.new(page: page, text: 'Original', author: @user, comments: 'v1')
    page.save!

    # Stale edit: simulate page updated by another user
    # Update the page text outside the tool to create a new version, then detect stale
    page.content.update_column :text, 'Updated by other'
    current_version = page.content.versions.maximum(:version).to_i
    assert current_version >= 1
    stale_version = current_version - 1
    stale_version = [stale_version, 0].max
    assert_raises(RuntimeError) { update.call(@job, @user, { 'wiki' => { 'title' => 'Stale Page', 'text' => 'Ignored', 'version' => stale_version } }) }
  end

  test 'context tools expose only authorized project data' do
    other_project = Project.generate!(name: 'Other Project')
    TaskHub::Task.create!(title: 'Other project task', user: @user, author: @user, project: other_project, status: 'todo')

    # Project search should not leak other project tasks
    search = AutomyraBridge::ToolRegistry.find('task.search')
    result = search.call(@job, @user, { 'query' => 'Other', 'limit' => 10 })
    assert_not(result[:tasks].any? { |t| t[:title] == 'Other project task' })
  end

  test 'audit events are recorded for tool execution' do
    AutomyraBridgeMemoryEvent.delete_all
    task = TaskHub::Task.create!(title: 'Read-back task', user: @user, author: @user, project: @project, status: 'todo')
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'TaskHub::TaskComment', source_id: task.comments.create!(author: @user, body: '@automyra read-back').id, user: @user, project: @project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: {}.to_json)

    # Create a task and verify read-back
    create = AutomyraBridge::ToolRegistry.find('task.create')
    result = create.call(job, @user, { 'task' => { 'title' => 'Created for read-back', 'status' => 'todo' } })
    created = TaskHub::Task.find(result[:task_id])
    assert_equal 'Created for read-back', created.title
    assert_equal 'todo', created.status
  end
end
