require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeFaqHubStatusReviewWebhookTest < ActiveSupport::TestCase
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
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_faq_status_changed' => 'https://automyra.bundecca.co.uk/webhooks/redmica-faq-status',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_FAQ_STATUS'] = '1'

    AutomyraBridge::FaqStatusHook.install!
    AutomyraBridge::FaqHubReviewDispatcher.stubs(:dispatch_update)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_FAQ_STATUS')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  test 'fires webhook when FAQ status changes' do
    faq = create_faq(author: @user)
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(status: 'review')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.faq_hub.faq_status_changed', event_type
    assert_match(/\Afaq-review-status-#{faq.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'does not fire status webhook on non-status changes' do
    faq = create_faq(author: @user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(title: 'Title only changed')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_FAQ_STATUS is unset' do
    faq = create_faq(author: @user)
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_FAQ_STATUS')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(status: 'review')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_FAQ_STATUS is 0' do
    faq = create_faq(author: @user)
    clear_enqueued_jobs

    ENV['AUTOMYRA_BRIDGE_FAQ_STATUS'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(status: 'review')
    end
  end

  test 'does not fire status webhook when authored by configured bot user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user

    faq = create_faq(author: admin_user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(status: 'review')
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def create_faq(author:, title: nil)
    FaqHub::Faq.create!(
      project: @project,
      author: author,
      title: title || "FAQ status #{SecureRandom.hex(4)}",
      short_answer: 'short',
      answer: 'answer body',
      audience: 'end_user',
      system: 'core',
      tags: 'tag1',
      status: 'active'
    )
  end
end
