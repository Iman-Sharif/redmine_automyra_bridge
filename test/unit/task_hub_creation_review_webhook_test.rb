require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeTaskHubCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_task_review' => 'https://automyra.sbg-server.com/webhooks/redmica-task-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_TASK_REVIEW'] = '1'

    AutomyraBridge::TaskHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_TASK_REVIEW')
    Thread.current[AutomyraBridge::TaskHubCreationHook::SKIP_KEY] = nil
  end

  # --- 1. Create hook --------------------------------------------------------

  test 'fires redmica.task_hub.task_created when TaskHub::Task is created' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_task(title: 'New review task')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.task_hub.task_created', event_type
    assert_match(/\Atask-hub-review-\d+-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_task(title: 'Bot-authored task', author: admin_user)
    end
  end

  # --- 2. Update hook --------------------------------------------------------

  test 'fires redmica.task_hub.task_updated on watched attribute change' do
    task = create_task(title: 'Initial title')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(title: 'Updated title')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'
    assert_equal 'redmica.task_hub.task_updated', job[:args][0]

    delivery_id = job[:args][2]
    # SecureRandom.hex(8) emits 8 random bytes -> 16 hex characters.
    assert_match(/\Atask-hub-review-update-\d+-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'fires update on notes / due_date / priority / status / assignee / parent change' do
    TaskHub::Task.any_instance.stubs(:tag_list).returns([])

    {
      notes: 'updated notes body',
      due_date: Date.current + 7,
      priority: 4,
      status: 'in_progress',
      assigned_to_id: @user.id
    }.each do |attr, new_value|
      task = create_task(title: "Baseline task #{attr}")
      clear_enqueued_jobs

      assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
        task.update!(attr => new_value)
      end

      job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
      assert_equal 'redmica.task_hub.task_updated', job[:args][0],
                   "expected update event for watched attribute #{attr}"
    end

    parent = create_task(title: 'Parent for linkage')
    child = create_task(title: 'Child for linkage')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      child.update!(parent_task_id: parent.id)
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_equal 'redmica.task_hub.task_updated', job[:args][0]
  end

  test 'does not fire update webhook on metadata-only change' do
    task = create_task(title: 'Baseline for metadata-only test')
    clear_enqueued_jobs

    # Changing `position` is intentionally NOT in the watched list.
    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(position: task.position.to_i + 1)
    end
  end

  # --- 3. Environment flag gating -------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_TASK_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_TASK_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_task(title: 'Flag-off task')
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_TASK_REVIEW is unset' do
    task = create_task(title: 'Baseline for flag-off update test')
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_TASK_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(title: 'After flag off')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_TASK_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_TASK_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_task(title: 'Zero flag task')
    end
  end

  # --- 4. Thread-local skip flag --------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[AutomyraBridge::TaskHubCreationHook::SKIP_KEY] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_task(title: 'Skipped create task')
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    task = create_task(title: 'Baseline for skip update test')
    clear_enqueued_jobs

    Thread.current[AutomyraBridge::TaskHubCreationHook::SKIP_KEY] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(title: 'Should be skipped')
    end
  end

  # --- 5. Payload shape ------------------------------------------------------

  test 'create payload includes all required keys plus event_type' do
    create_task(title: 'Payload task', notes: 'Payload notes', priority: 3, status: 'in_progress')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, _delivery_id = job[:args]
    assert_equal 'redmica.task_hub.task_created', event_type

    assert payload['task_id'].is_a?(Integer)
    assert_equal 'Payload task', payload['subject']
    assert_equal 'Payload notes', payload['notes']
    assert_equal 3, payload['priority']
    assert_equal 'in_progress', payload['status']
    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_login']
    assert_equal @project.id, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']
    assert_equal [], payload['tags']
    assert_equal [], payload['checklist']
    assert payload['url'].include?('/standalone_tasks/') || payload['url'].include?('/issue_tasks/')
    assert payload['timestamp'].is_a?(String)
    assert payload['timestamp'].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
  end

  test 'payload notes are truncated to 2000 characters' do
    long_notes = 'n' * 3000
    create_task(title: 'Truncation task', notes: long_notes)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'
    payload = job[:args][1]

    assert payload['notes'].length <= 2000,
           "notes must be truncated to <= 2000 chars (got #{payload['notes'].length})"
  end

  test 'create delivery id uses task-hub-review-{id}-{hex} format' do
    task = create_task(title: 'Delivery id task')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    delivery_id = job[:args][2]

    assert_match(/\Atask-hub-review-#{task.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'update delivery id uses task-hub-review-update-{id}-{hex} format' do
    task = create_task(title: 'Update delivery id task')
    clear_enqueued_jobs

    task.update!(title: 'Update delivery id task - changed')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'
    delivery_id = job[:args][2]

    # SecureRandom.hex(8) emits 8 random bytes -> 16 hex characters.
    assert_match(/\Atask-hub-review-update-#{task.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 6. Activity log -------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    create_task(title: 'Logged create task')

    log = AutomyraBridgeActivityLog.where(action_type: 'task_created_webhook_dispatched').last
    assert_not_nil log, 'expected a task_created_webhook_dispatched activity log entry'
    assert_equal 'TaskHub::Task', log.target_type
    assert log.target_id.to_s.match?(/\A\d+\z/)
  end

  test 'activity log entry is written on update dispatch' do
    task = create_task(title: 'Logged update baseline')
    clear_enqueued_jobs
    AutomyraBridgeActivityLog.delete_all

    task.update!(title: 'Logged update new title')

    log = AutomyraBridgeActivityLog.where(action_type: 'task_updated_webhook_dispatched').last
    assert_not_nil log, 'expected a task_updated_webhook_dispatched activity log entry'
    assert_equal 'TaskHub::Task', log.target_type
    assert_equal task.id.to_s, log.target_id.to_s
  end

  # --- 7. Direct dispatcher payload -----------------------------------------

  test 'build_payload exposes parent_id from parent_task_id' do
    parent = create_task(title: 'Parent task')
    child = create_task(title: 'Child task', parent_task_id: parent.id)

    payload = AutomyraBridge::TaskHubReviewDispatcher.build_payload(
      child, AutomyraBridge::TaskHubReviewDispatcher::EVENT_CREATED
    )

    assert_equal parent.id, payload[:parent_id]
    assert_equal child.id, payload[:task_id]
  end

  private

  def create_task(title:, notes: nil, priority: 2, status: 'todo', author: nil, parent_task_id: nil)
    TaskHub::Task.create!(
      title: title,
      notes: notes,
      user: @user,
      author: author || @user,
      project: @project,
      status: status,
      priority: priority,
      parent_task_id: parent_task_id
    )
  end
end
