require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeErrorHubStatusReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_error_status_changed' => 'https://automyra.sbg-server.com/webhooks/redmica-error-status',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_ERROR_STATUS'] = '1'

    AutomyraBridge::ErrorStatusHook.install!
    AutomyraBridge::ErrorHubReviewDispatcher.stubs(:dispatch_update)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_ERROR_STATUS')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  test 'fires webhook when error status changes' do
    error = create_error(author: @user)
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(status: 'resolved')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.error_hub.error_status_changed', event_type
    assert_match(/\Aerror-review-status-#{error.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'does not fire status webhook on non-status changes' do
    error = create_error(author: @user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(title: 'Title only changed')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_ERROR_STATUS is unset' do
    error = create_error(author: @user)
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_ERROR_STATUS')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(status: 'resolved')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_ERROR_STATUS is 0' do
    error = create_error(author: @user)
    clear_enqueued_jobs

    ENV['AUTOMYRA_BRIDGE_ERROR_STATUS'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(status: 'resolved')
    end
  end

  test 'does not fire status webhook when authored by configured bot user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user

    error = create_error(author: admin_user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(status: 'resolved')
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def create_error(author:)
    ErrorHub::Error.create!(
      title: "Status test error #{SecureRandom.hex(4)}",
      system: 'core',
      project: @project,
      author: author,
      error_code: "ERR-STATUS-#{SecureRandom.hex(6).upcase}",
      status: 'active',
      severity: 2,
      description: 'Test description',
      root_cause: 'Root cause',
      solution: 'Solution',
      prevention: 'Prevention',
      tags: 'test,sample'
    )
  end
end
