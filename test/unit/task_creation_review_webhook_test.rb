require File.expand_path('../test_helper', __dir__)

# TDD RED PHASE — Redmica issue #439
#
# These tests target `AutomyraBridge::TaskCreationReviewDispatcher`, a not-yet-
# implemented dispatcher that should mirror `AutomyraBridge::CreationReviewDispatcher`
# (which is bound to `Issue`) but operate on `TaskHub::Task` instead. They are
# intentionally written BEFORE the dispatcher exists so they FAIL with a missing
# constant error (`NameError: uninitialized constant
# AutomyraBridge::TaskCreationReviewDispatcher`). The structural template is
# `issue_creation_review_webhook_test.rb` — fixtures, setup/teardown, env flag
# handling, and assertion style are aligned 1:1 with the issue dispatcher.
#
# Required constants and references to fail in the red phase:
#   * AutomyraBridge::TaskCreationReviewDispatcher  ← does NOT exist yet
#   * AutomyraBridge::HermesWebhookDeliverJob       ← already exists
#   * TaskHub::Task                                 ← already exists
#   * AutomyraBridgeActivityLog                     ← already exists
class AutomyraBridgeTaskCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues,
           :issue_statuses, :trackers, :enumerations

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'automyra',
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_creation_review' => 'https://automyra.sbg-server.com/webhooks/redmica-creation-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    # The dispatcher must be gated by the same env flag as the issue creation
    # reviewer (see config/additional_environment.rb comment for issue #423).
    ENV['AUTOMYRA_BRIDGE_CREATION_REVIEW'] = '1'
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_CREATION_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Dispatch contract ---------------------------------------------------

  test 'dispatch enqueues HermesWebhookDeliverJob for a valid TaskHub::Task' do
    task = build_valid_task(title: 'Dispatch test')

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end
  end

  test 'dispatch returns early when record is not a TaskHub::Task' do
    issue = Issue.find(1)

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(issue)
    end
  end

  test 'dispatch returns early when record is a non-Task non-Issue object' do
    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(:not_a_task)
    end

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(nil)
    end
  end

  # --- 2. Environment flag gating --------------------------------------------

  test 'dispatch does not enqueue when AUTOMYRA_BRIDGE_CREATION_REVIEW is unset' do
    # The dispatcher MUST honor the same env flag as the issue-side reviewer.
    # In a working environment, the env flag is read inside the hook; here we
    # also assert that `dispatch` itself short-circuits when called without it
    # set, so the dispatcher remains a no-op unless the operator opts in.
    ENV.delete('AUTOMYRA_BRIDGE_CREATION_REVIEW')

    task = build_valid_task(title: 'Flag off test')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end
  end

  test 'dispatch does not enqueue when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true
    task = build_valid_task(title: 'Skip flag test')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end
  end

  # --- 3. Error rescue contract ---------------------------------------------

  test 'dispatcher rescues errors gracefully' do
    task = build_valid_task(title: 'Boom test')
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end
  end

  # --- 4. Payload shape -------------------------------------------------------

  test 'payload includes all required keys' do
    task = build_valid_task(title: 'Payload test', notes: 'Initial notes')

    AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]

    assert_equal 'redmica.task_created', event_type
    assert_equal task.id, payload['task_id']
    assert_equal 'Payload test', payload['title']
    assert_equal 'Initial notes', payload['notes']
    assert_equal 'todo', payload['status']
    assert_equal @project.identifier, payload['project_id']
    assert_equal @project.name, payload['project_name']
    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_name']
    assert payload['url'].include?(task.id.to_s)
    assert_equal "task-creation-#{task.id}", delivery_id
    assert payload.key?('issue_id'), 'payload must always include issue_id (may be nil)'
    assert payload.key?('created_at'), 'payload must include created_at'
    assert payload.key?('timestamp'),  'payload must include timestamp'
  end

  test 'notes field is truncated to 2000 characters' do
    long_notes = 'a' * 3000
    task = build_valid_task(title: 'Truncation test', notes: long_notes)

    AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]
    assert payload['notes'].length <= 2000, "notes must be truncated to <= 2000 chars (got #{payload['notes'].length})"
  end

  # --- 5. Activity log --------------------------------------------------------

  test 'activity log entry is written on dispatch' do
    task = build_valid_task(title: 'Activity log test')

    assert_difference('AutomyraBridgeActivityLog.count', 1) do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end

    log = AutomyraBridgeActivityLog.last
    assert_equal 'task_creation_review_webhook_dispatched', log.action_type
    assert_equal 'TaskHub::Task', log.target_type
    assert_equal task.id, log.target_id.to_i
  end

  # --- 6. Standalone vs issue-linked task -----------------------------------

  test 'standalone task has nil issue_id in payload' do
    # A standalone task has no project AND no issue. Build it directly so the
    # assertion is independent of the issue_creation_hook's project gating.
    task = TaskHub::Task.create!(
      user: @user,
      title: 'Standalone task',
      notes: 'no project, no issue',
      status: 'todo',
      priority: 2
    )

    AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]
    assert_nil task.issue_id, 'precondition: task must be standalone'
    assert payload.key?('issue_id'), 'standalone tasks must still emit the issue_id key (nil value)'
    assert_nil payload['issue_id']
    assert_nil payload['project_id'], 'standalone tasks must emit nil project_id'
  end

  test 'issue-linked task includes issue_id in payload' do
    issue = Issue.find(1)
    task = build_valid_task(title: 'Issue-linked task', issue: issue)

    AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]
    assert_equal issue.id, payload['issue_id']
  end

  # --- 7. Direct dispatcher (no hook required) -------------------------------

  test 'dispatcher can be invoked directly on a fixture task' do
    # exercise the dispatcher API without going through TaskHub::Task.create!
    # — uses the existing todo_task fixture loaded via task_hub_tasks.yml.
    task = TaskHub::Task.find_by(title: 'Todo task') || build_valid_task(title: 'Fixture fallback')

    assert_nothing_raised do
      AutomyraBridge::TaskCreationReviewDispatcher.dispatch(task)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  # Build a valid TaskHub::Task that the dispatcher will accept. The task
  # creation hook in production also wraps this with project gating; here
  # we just construct a task the dispatcher can serialize.
  def build_valid_task(title:, notes: 'test notes', issue: nil)
    attrs = {
      user: @user,
      author: @user,
      title: title,
      notes: notes,
      status: 'todo',
      priority: 2,
      project: @project
    }
    attrs[:issue] = issue if issue
    TaskHub::Task.create!(attrs)
  end
end
