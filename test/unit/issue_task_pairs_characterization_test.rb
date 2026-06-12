require File.expand_path('../test_helper', __dir__)

# CHARACTERIZATION TEST — Task 7
#
# Pins the CURRENT return shape and failure behavior of the 6 near-identical
# issue_*/task_* tool pairs (12 tools total) so a later mixin-extraction
# refactor (Task 15) can prove zero behavior change.
#
# Each tool gets >= 1 success assertion (exact return hash) and >= 1 failure
# assertion (exact raised class + message). Behavior is PINNED AS-IS, even
# where the two halves of a pair diverge (e.g. issue.set_priority returns
# :priority_id while task.set_priority returns :priority; issue.add_comment
# returns the body string while task.add_comment returns a comment_id).
#
# Persistence is exercised inside Rails transactional fixtures (each test runs
# in a transaction that rolls back), so no row survives the run. The companion
# evidence file task-7-no-db-pollution.txt captures Issue.count /
# TaskHub::Task.count before and after to prove this.
class IssueTaskPairsCharacterizationTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses, :projects, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @user = User.find(2)
    @project = Project.find(1)

    # Task-sourced job: source_task(job) resolves via the TaskHub::TaskComment.
    @task = TaskHub::Task.create!(title: 'Char task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra help')
    @task_job = AutomyraBridgeJob.create!(
      status: 'queued', source_type: 'TaskHub::TaskComment', source_id: @comment.id,
      user: @user, project: @project, correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid, request_payload: { source: 'task_hub_comment' }.to_json
    )

    # Issue-sourced job: source_issue(job) resolves via payload['issue_id'].
    @issue = Issue.find(1)
    @issue_job = AutomyraBridgeJob.create!(
      status: 'queued', source_type: 'Journal',
      source_id: @issue.journals.create!(user: @user, notes: '@automyra').id,
      user: @user, project: @issue.project, correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'issue_journal', issue_id: @issue.id }.to_json
    )
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
  end

  def tool(name)
    AutomyraBridge::ToolRegistry.find(name)
  end

  # --- Pair 1: assign -------------------------------------------------------

  test 'task.assign success returns task_id and assigned_to_id' do
    result = tool('task.assign').call(@task_job, @user, { 'assignment' => { 'assigned_to_id' => @user.id } })
    assert_equal({ task_id: @task.id, assigned_to_id: @user.id }, result)
  end

  test 'task.assign failure with unknown user raises Assigned user is not available' do
    err = assert_raises(RuntimeError) do
      tool('task.assign').call(@task_job, @user, { 'assignment' => { 'assigned_to_id' => 99_999_999 } })
    end
    assert_equal 'Assigned user is not available.', err.message
  end

  test 'issue.assign success returns issue_id and assigned_to_id' do
    result = tool('issue.assign').call(@issue_job, @user, { 'assignment' => { 'assigned_to_id' => @user.id } })
    assert_equal({ issue_id: @issue.id, assigned_to_id: @user.id }, result)
  end

  test 'issue.assign failure with unknown user raises Assigned user is not available' do
    err = assert_raises(RuntimeError) do
      tool('issue.assign').call(@issue_job, @user, { 'assignment' => { 'assigned_to_id' => 99_999_999 } })
    end
    assert_equal 'Assigned user is not available.', err.message
  end

  # --- Pair 2: set_due_date -------------------------------------------------

  test 'task.set_due_date success returns task_id and stringified due_date' do
    date = Date.current.to_s
    result = tool('task.set_due_date').call(@task_job, @user, { 'task' => { 'due_date' => date } })
    assert_equal({ task_id: @task.id, due_date: date }, result)
  end

  test 'task.set_due_date failure without a source task raises Task is no longer available' do
    # CHARACTERIZATION: current behavior, may be buggy -- pinned for Task 15 refactor.
    # An issue-sourced job has no source_task, so the tool aborts before touching params.
    err = assert_raises(RuntimeError) do
      tool('task.set_due_date').call(@issue_job, @user, { 'task' => { 'due_date' => Date.current.to_s } })
    end
    assert_equal 'Task is no longer available.', err.message
  end

  test 'issue.set_due_date success returns issue_id and stringified due_date' do
    date = Date.current.to_s
    result = tool('issue.set_due_date').call(@issue_job, @user, { 'issue' => { 'due_date' => date } })
    assert_equal({ issue_id: @issue.id, due_date: date }, result)
  end

  test 'issue.set_due_date failure without a source issue raises Issue is no longer available' do
    # CHARACTERIZATION: current behavior, may be buggy -- pinned for Task 15 refactor.
    # A task-sourced job has no source_issue, so the tool aborts.
    err = assert_raises(RuntimeError) do
      tool('issue.set_due_date').call(@task_job, @user, { 'issue' => { 'due_date' => Date.current.to_s } })
    end
    assert_equal 'Issue is no longer available.', err.message
  end

  # --- Pair 3: set_priority -------------------------------------------------

  test 'task.set_priority success returns task_id and priority (not priority_id)' do
    # CHARACTERIZATION: task.set_priority returns :priority, diverging from
    # issue.set_priority which returns :priority_id -- pinned for Task 15 refactor.
    result = tool('task.set_priority').call(@task_job, @user, { 'task' => { 'priority' => 4 } })
    assert_equal({ task_id: @task.id, priority: 4 }, result)
  end

  test 'task.set_priority failure without a source task raises Task is no longer available' do
    err = assert_raises(RuntimeError) do
      tool('task.set_priority').call(@issue_job, @user, { 'task' => { 'priority' => 4 } })
    end
    assert_equal 'Task is no longer available.', err.message
  end

  test 'issue.set_priority success returns issue_id and priority_id (not priority)' do
    # CHARACTERIZATION: issue.set_priority returns :priority_id, diverging from
    # task.set_priority which returns :priority -- pinned for Task 15 refactor.
    priority = IssuePriority.first
    result = tool('issue.set_priority').call(@issue_job, @user, { 'issue' => { 'priority_id' => priority.id } })
    assert_equal({ issue_id: @issue.id, priority_id: priority.id }, result)
  end

  test 'issue.set_priority failure with unknown priority raises Issue priority is not available' do
    err = assert_raises(RuntimeError) do
      tool('issue.set_priority').call(@issue_job, @user, { 'issue' => { 'priority_id' => 99_999_999 } })
    end
    assert_equal 'Issue priority is not available.', err.message
  end

  # --- Pair 4: add_comment --------------------------------------------------

  test 'task.add_comment success returns task_id and comment_id' do
    # CHARACTERIZATION: task.add_comment returns a :comment_id, diverging from
    # issue.add_comment which returns the raw :comment body string -- pinned for Task 15.
    result = tool('task.add_comment').call(@task_job, @user, { 'comment' => { 'body' => 'Pinned comment' } })
    assert_equal %i[comment_id task_id], result.keys.sort
    assert_equal @task.id, result[:task_id]
    assert_equal TaskHub::TaskComment.find(result[:comment_id]).id, result[:comment_id]
    assert_equal 'Pinned comment', TaskHub::TaskComment.find(result[:comment_id]).body
  end

  test 'task.add_comment failure with blank body raises Comment body is blank' do
    err = assert_raises(RuntimeError) do
      tool('task.add_comment').call(@task_job, @user, { 'comment' => { 'body' => '   ' } })
    end
    assert_equal 'Comment body is blank.', err.message
  end

  test 'issue.add_comment success returns issue_id and comment body string' do
    # CHARACTERIZATION: issue.add_comment returns the body under :comment (a String),
    # NOT a journal/comment id -- pinned for Task 15 refactor.
    result = tool('issue.add_comment').call(@issue_job, @user, { 'comment' => { 'body' => 'Pinned journal' } })
    assert_equal({ issue_id: @issue.id, comment: 'Pinned journal' }, result)
  end

  test 'issue.add_comment failure with blank body raises Comment body is blank' do
    err = assert_raises(RuntimeError) do
      tool('issue.add_comment').call(@issue_job, @user, { 'comment' => { 'body' => '   ' } })
    end
    assert_equal 'Comment body is blank.', err.message
  end

  # --- Pair 5: update -------------------------------------------------------

  test 'task.update success returns task_id only' do
    result = tool('task.update').call(@task_job, @user, { 'task' => { 'title' => 'Updated char task' } })
    assert_equal({ task_id: @task.id }, result)
    assert_equal 'Updated char task', @task.reload.title
  end

  test 'task.update failure without a source task raises Task is no longer available' do
    err = assert_raises(RuntimeError) do
      tool('task.update').call(@issue_job, @user, { 'task' => { 'title' => 'Nope' } })
    end
    assert_equal 'Task is no longer available.', err.message
  end

  test 'issue.update success returns issue_id only' do
    result = tool('issue.update').call(@issue_job, @user, { 'issue' => { 'subject' => 'Updated char issue' } })
    assert_equal({ issue_id: @issue.id }, result)
    assert_equal 'Updated char issue', @issue.reload.subject
  end

  test 'issue.update failure with no fields raises No issue fields supplied' do
    err = assert_raises(RuntimeError) do
      tool('issue.update').call(@issue_job, @user, { 'issue' => {} })
    end
    assert_equal 'No issue fields supplied.', err.message
  end

  # --- Pair 6: create -------------------------------------------------------

  test 'task.create success returns task_id only' do
    result = tool('task.create').call(@task_job, @user, { 'task' => { 'title' => 'Created char task' } })
    assert_equal [:task_id], result.keys
    assert_equal 'Created char task', TaskHub::Task.find(result[:task_id]).title
  end

  test 'task.create failure with blank title raises RuntimeError' do
    # CHARACTERIZATION: task.create re-raises the model error string as a
    # RuntimeError -- pinned for Task 15 refactor.
    assert_raises(RuntimeError) do
      tool('task.create').call(@task_job, @user, { 'task' => {} })
    end
  end

  test 'issue.create success returns issue_id only' do
    result = tool('issue.create').call(@task_job, @user, { 'issue' => { 'subject' => 'Created char issue' } })
    assert_equal [:issue_id], result.keys
    assert_equal 'Created char issue', Issue.find(result[:issue_id]).subject
  end

  test 'issue.create failure with blank subject raises ActiveRecord::RecordInvalid' do
    # CHARACTERIZATION: issue.create calls Issue#save! directly, so an invalid
    # issue surfaces as ActiveRecord::RecordInvalid (NOT a RuntimeError like
    # task.create) -- pinned for Task 15 refactor.
    assert_raises(ActiveRecord::RecordInvalid) do
      tool('issue.create').call(@task_job, @user, { 'issue' => {} })
    end
  end
end
