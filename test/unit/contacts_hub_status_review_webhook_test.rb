require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeContactsHubStatusReviewWebhookTest < ActiveSupport::TestCase
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
      'hermes_webhook_url_contacts_status_changed' => 'https://automyra.bundecca.co.uk/webhooks/redmica-contacts-status',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_CONTACTS_STATUS'] = '1'

    AutomyraBridge::ContactsStatusHook.install!
    AutomyraBridge::ContactsHubReviewDispatcher.stubs(:dispatch_update)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_CONTACTS_STATUS')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  test 'fires webhook when contact status changes' do
    contact = create_contact(name: 'Status change contact', author: @user)
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(status: 'inactive')
    end

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.contacts_hub.contact_status_changed', event_type
    assert_match(/\Acontacts-review-status-#{contact.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'does not fire status webhook on non-status changes' do
    contact = create_contact(name: 'Non-status change contact', author: @user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(name: 'Name only changed')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_CONTACTS_STATUS is unset' do
    contact = create_contact(name: 'Flag-off status contact', author: @user)
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_CONTACTS_STATUS')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(status: 'inactive')
    end
  end

  test 'does not fire status webhook when AUTOMYRA_BRIDGE_CONTACTS_STATUS is 0' do
    contact = create_contact(name: 'Zero flag status contact', author: @user)
    clear_enqueued_jobs

    ENV['AUTOMYRA_BRIDGE_CONTACTS_STATUS'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(status: 'inactive')
    end
  end

  test 'does not fire status webhook when authored by configured bot user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user

    contact = create_contact(name: 'Bot-authored status contact', author: admin_user)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(status: 'inactive')
    end
  end

  test 'payload redacts PII fields in status payload' do
    contact = create_contact(
      name: 'PII status contact',
      author: @user,
      email: 'pii-status@example.com',
      phone: '555-STATUS',
      city: 'Statusville'
    )
    clear_enqueued_jobs

    contact.update!(status: 'inactive')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    _event_type, payload, _delivery_id = job[:args]
    assert_equal '[REDACTED]', payload['email']
    assert_equal '[REDACTED]', payload['phone']
    assert_equal '[REDACTED]', payload['city']

    serialized = payload.to_s
    assert_not_includes serialized, 'pii-status@example.com'
    assert_not_includes serialized, '555-STATUS'
    assert_not_includes serialized, 'Statusville'
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def create_contact(name:, author:, email: nil, phone: nil, city: nil)
    ContactsHub::Contact.create!(
      name: name,
      author: author,
      project: @project,
      status: 'active',
      visibility: 'private',
      email: email,
      phone: phone,
      city: city
    )
  end
end
