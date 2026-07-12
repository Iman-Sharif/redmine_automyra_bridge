require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeTaskHubStatusReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_task_status_changed' => 'https://automyra.bundecca.co.uk/webhooks/redmica-task-status',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_TASK_STATUS'] = '1'

    AutomyraBridge::TaskStatusHook.install!
    AutomyraBridge::TaskHubReviewDispatcher.stubs(:dispatch_update)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_TASK_STATUS')
    Thread.current[AutomyraBridge::TaskStatusHook::SKIP_KEY] = nil
  end

  test 'fires webhook when task status changes' do
    task = create_task(title: 'Status change task')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(status: 'in_progress')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.task_hub.task_status_changed', event_type
    assert_match(/\Atask-hub-review-status-#{task.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'does not fire status webhook on non-status changes' do
    task = create_task(title: 'Non-status change task')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(title: 'Title only changed')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_TASK_STATUS is unset' do
    task = create_task(title: 'Flag-off status task')
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_TASK_STATUS')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(status: 'in_progress')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_TASK_STATUS is 0' do
    task = create_task(title: 'Zero flag status task')
    clear_enqueued_jobs

    ENV['AUTOMYRA_BRIDGE_TASK_STATUS'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(status: 'in_progress')
    end
  end

  test 'does not fire status webhook when authored by configured bot user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user

    task = create_task(title: 'Bot-authored status task', author: admin_user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      task.update!(status: 'in_progress')
    end
  end

  private

  def create_task(title:, author: nil)
    TaskHub::Task.create!(
      title: title,
      user: @user,
      author: author || @user,
      project: @project,
      status: 'todo',
      priority: 2
    )
  end
end
