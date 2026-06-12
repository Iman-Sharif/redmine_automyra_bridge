require File.expand_path('../test_helper', __dir__)
require File.expand_path('../support/tool_snapshot', __dir__)

class ToolSnapshotTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses, :projects, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @user = User.find(2)
    @project = Project.find(1)

    @task = TaskHub::Task.create!(title: 'Snapshot task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra help')
    @task_job = AutomyraBridgeJob.create!(
      status: 'queued', source_type: 'TaskHub::TaskComment', source_id: @comment.id,
      user: @user, project: @project, correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid, request_payload: { source: 'task_hub_comment' }.to_json
    )

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

  def pair_inputs(priority_value: 4, comment_body: 'Snapshot comment')
    fixed_date = '2026-06-12'
    [
      ['task.assign',       tool('task.assign'),       @task_job,  @user, { 'assignment' => { 'assigned_to_id' => @user.id } }],
      ['issue.assign',      tool('issue.assign'),      @issue_job, @user, { 'assignment' => { 'assigned_to_id' => @user.id } }],
      ['task.set_due_date', tool('task.set_due_date'), @task_job,  @user, { 'task' => { 'due_date' => fixed_date } }],
      ['issue.set_due_date', tool('issue.set_due_date'), @issue_job, @user, { 'issue' => { 'due_date' => fixed_date } }],
      ['task.set_priority', tool('task.set_priority'), @task_job, @user, { 'task' => { 'priority' => priority_value } }],
      ['issue.set_priority', tool('issue.set_priority'), @issue_job, @user, { 'issue' => { 'priority_id' => IssuePriority.first.id } }],
      ['task.add_comment',  tool('task.add_comment'),  @task_job,  @user, { 'comment' => { 'body' => comment_body } }],
      ['issue.add_comment', tool('issue.add_comment'), @issue_job, @user, { 'comment' => { 'body' => comment_body } }],
      ['task.update',       tool('task.update'),       @task_job,  @user, { 'task' => { 'title' => 'Updated snapshot task' } }],
      ['issue.update',      tool('issue.update'),      @issue_job, @user, { 'issue' => { 'subject' => 'Updated snapshot issue' } }],
      ['task.create',       tool('task.create'),       @task_job,  @user, { 'task' => { 'title' => 'Created snapshot task' } }],
      ['issue.create',      tool('issue.create'),      @task_job,  @user, { 'issue' => { 'subject' => 'Created snapshot issue' } }]
    ]
  end

  test 'capture twice on unchanged code yields byte-identical normalized JSON' do
    first = ToolSnapshot.normalize(ToolSnapshot.capture(pair_inputs))
    second = ToolSnapshot.normalize(ToolSnapshot.capture(pair_inputs))

    assert_equal first, second, 'two captures of unchanged code must be byte-identical'

    File.write('/tmp/task-11-snap1.json', first)
    File.write('/tmp/task-11-snap2.json', second)
    assert_equal first, File.read('/tmp/task-11-snap1.json')
    assert_includes first, '<ID>', 'snapshot must normalize hash IDs to <ID>'
  end

  test 'mutating an input produces a non-empty diff (sensitivity)' do
    baseline = ToolSnapshot.normalize(ToolSnapshot.capture(pair_inputs))
    mutated = ToolSnapshot.normalize(ToolSnapshot.capture(pair_inputs(priority_value: 1, comment_body: 'DIFFERENT body')))

    assert_not_equal baseline, mutated, 'a changed input must change the normalized snapshot'
    File.write('/tmp/task-11-baseline.json', baseline)
    File.write('/tmp/task-11-mutated.json', mutated)
  end

  test 'normalize scrubs ids timestamps and uuids but keeps stable scalars' do
    raw = {
      'task_id' => 12_345,
      'id' => 999,
      'created_at' => Time.now.utc.iso8601,
      'updated_on' => '2026-06-12T10:00:00Z',
      'correlation_id' => SecureRandom.uuid,
      'due_date' => '2026-06-12',
      'priority' => 4,
      'comment' => 'kept text'
    }
    json = ToolSnapshot.normalize(raw)
    parsed = JSON.parse(json)

    assert_equal '<ID>', parsed['task_id']
    assert_equal '<ID>', parsed['id']
    assert_equal '<ID>', parsed['correlation_id']
    assert_equal '<TS>', parsed['created_at']
    assert_equal '<TS>', parsed['updated_on']
    assert_equal '2026-06-12', parsed['due_date']
    assert_equal 4, parsed['priority']
    assert_equal 'kept text', parsed['comment']
    assert_equal parsed.keys, parsed.keys.sort
  end
end
