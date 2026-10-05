require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeContactsHubCreationReviewWebhookTest < ActiveSupport::TestCase
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
      'hermes_webhook_url_contacts_review' => 'https://automyra.bundecca.co.uk/webhooks/redmica-contacts-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_CONTACTS_REVIEW'] = '1'

    # The hook is installed at boot; ensure it is present for unit tests.
    AutomyraBridge::ContactsHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_CONTACTS_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Create hook ---------------------------------------------------------

  test 'fires webhook when contact is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_contact(name: 'Create hook test', author: @user)
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_contact(name: 'Bot-authored contact', author: admin_user)
    end
  end

  # --- 2. Update hook ---------------------------------------------------------

  test 'fires webhook when contact name changes' do
    contact = create_contact(name: 'Original name', author: @user)
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(name: 'Updated name')
    end
  end

  test 'fires webhook when contact job_title changes' do
    contact = create_contact(name: 'Job title test', author: @user, job_title: 'Engineer')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(job_title: 'Senior Engineer')
    end
  end

  test 'fires webhook when contact status changes' do
    contact = create_contact(name: 'Status test', author: @user)
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(status: 'inactive')
    end
  end

  test 'fires webhook when contact visibility changes' do
    contact = create_contact(name: 'Visibility test', author: @user, visibility: 'private')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(visibility: 'project')
    end
  end

  test 'fires webhook when contact organization_id changes' do
    org = ContactsHub::Organization.create!(name: "Org #{SecureRandom.hex(4)}", status: 'active')
    contact = create_contact(name: 'Org test', author: @user)
    assert_nil contact.organization_id
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(organization_id: org.id)
    end
  end

  test 'does not fire update webhook on metadata-only change (nickname)' do
    contact = create_contact(name: 'Metadata-only test', author: @user, nickname: 'foo')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(nickname: 'bar')
    end
  end

  # --- 3. Environment flag gating ---------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_CONTACTS_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_CONTACTS_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_contact(name: 'Flag off create test', author: @user)
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_CONTACTS_REVIEW is unset' do
    contact = create_contact(name: 'Flag off update baseline', author: @user)
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_CONTACTS_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(name: 'Flag off update test')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_CONTACTS_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_CONTACTS_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_contact(name: 'Zero flag create test', author: @user)
    end
  end

  # --- 4. Thread-local skip flag ----------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_contact(name: 'Skip flag create test', author: @user)
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    contact = create_contact(name: 'Skip flag update baseline', author: @user)
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      contact.update!(name: 'Skip flag update test')
    end
  end

  # --- 5. Dispatcher payload shape -------------------------------------------

  test 'payload includes all required keys plus event_type on create' do
    org = ContactsHub::Organization.create!(name: "Acme #{SecureRandom.hex(4)}", status: 'active')
    contact = create_contact(
      name: 'Payload shape test',
      author: @user,
      job_title: 'CTO',
      organization: org,
      status: 'active',
      visibility: 'project',
      source: 'manual',
      nickname: 'Ace'
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.contacts_hub.contact_created', event_type

    assert_equal contact.id, payload['contact_id']
    assert_equal 'Payload shape test', payload['name']
    assert_equal 'CTO', payload['job_title']
    assert_equal org.id, payload['organization_id']
    assert_equal org.name, payload['organization_name']
    assert_equal 'active', payload['status']
    assert_equal 'project', payload['visibility']
    assert_equal @project.id, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']
    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_login']
    assert_nil payload['assigned_to_id'], 'assigned_to_id is nil when unassigned'
    assert_equal 'manual', payload['source']
    assert_equal [], payload['tags']
    assert_equal [], payload['custom_field_names']
    assert payload['url'].include?("/contacts_hub/#{contact.id}"),
           "url must reference the contact id (got #{payload['url'].inspect})"
    assert payload['timestamp']

    assert_match(/\Acontacts-review-#{contact.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'payload event_type is redmica.contacts_hub.contact_updated on update' do
    contact = create_contact(name: 'Update payload test', author: @user)
    clear_enqueued_jobs
    contact.update!(name: 'Updated for payload check')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.contacts_hub.contact_updated', event_type
    assert_match(/\Acontacts-review-update-#{contact.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 6. PII redaction -------------------------------------------------------

  test 'payload excludes PII fields on create' do
    contact = create_contact(
      name: 'PII test',
      author: @user,
      email: 'pii@example.com',
      secondary_email: 'pii2@example.com',
      phone: '555-1234',
      mobile: '555-5678',
      address_line1: '123 Secret St',
      city: 'Secretville',
      country: 'Secretonia',
      birthday: Date.new(1990, 1, 1),
      description: 'Highly sensitive description that must never leak',
      nickname: 'public-nick'
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]

    # PII fields must be absent
    assert_not payload.key?('email'), 'payload must not include email'
    assert_not payload.key?('secondary_email'), 'payload must not include secondary_email'
    assert_not payload.key?('phone'), 'payload must not include phone'
    assert_not payload.key?('mobile'), 'payload must not include mobile'
    assert_not payload.key?('address_line1'), 'payload must not include address_line1'
    assert_not payload.key?('address_line2'), 'payload must not include address_line2'
    assert_not payload.key?('city'), 'payload must not include city'
    assert_not payload.key?('region'), 'payload must not include region'
    assert_not payload.key?('postal_code'), 'payload must not include postal_code'
    assert_not payload.key?('country'), 'payload must not include country'
    assert_not payload.key?('birthday'), 'payload must not include birthday'
    assert_not payload.key?('description'), 'payload must not include description'
    assert_not payload.key?('notes'), 'payload must not include notes (related model)'

    # Sanity: payload does not contain any of the secret values, even as substrings
    serialized = payload.to_s
    assert_not_includes serialized, 'pii@example.com',
                        'payload must not contain the contact email anywhere'
    assert_not_includes serialized, '555-1234',
                        'payload must not contain the contact phone anywhere'
    assert_not_includes serialized, '123 Secret St',
                        'payload must not contain the contact address anywhere'
    assert_not_includes serialized, '1990-01-01',
                        'payload must not contain the contact birthday anywhere'
    assert_not_includes serialized, 'Highly sensitive description',
                        'payload must not contain the contact description anywhere'

    # Non-PII fields ARE present
    assert_equal 'public-nick', contact.nickname
    assert_equal 'PII test', payload['name']
  end

  test 'payload excludes PII fields on update as well' do
    contact = create_contact(
      name: 'PII update test',
      author: @user,
      email: 'before@example.com'
    )
    clear_enqueued_jobs

    contact.update!(
      name: 'PII update test changed',
      email: 'after@example.com',
      phone: '555-9999'
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]

    assert_not payload.key?('email')
    assert_not payload.key?('phone')

    serialized = payload.to_s
    assert_not_includes serialized, 'after@example.com'
    assert_not_includes serialized, '555-9999'
    assert_not_includes serialized, 'before@example.com'
  end

  # --- 7. Update delivery ID format ------------------------------------------

  test 'update delivery id uses contacts-review-update-{id}-{hex} format' do
    contact = create_contact(name: 'Delivery id test', author: @user)
    clear_enqueued_jobs

    contact.update!(name: 'Trigger update delivery id')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    _event_type, _payload, delivery_id = job[:args]
    # SecureRandom.hex(8) emits 8 random bytes -> 16 hex characters.
    assert_match(/\Acontacts-review-update-#{contact.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 8. Activity log --------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    contact = create_contact(name: 'Activity log create test', author: @user)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'contact_created_webhook_dispatched', log.action_type
    assert_equal 'ContactsHub::Contact', log.target_type
    assert_equal contact.id, log.target_id.to_i
    assert_equal @project.id, log.project_id
  end

  test 'activity log entry is written on update dispatch' do
    contact = create_contact(name: 'Activity log update baseline', author: @user)
    clear_enqueued_jobs
    AutomyraBridgeActivityLog.delete_all
    contact.update!(name: 'Activity log update trigger')

    log = AutomyraBridgeActivityLog.last
    assert_equal 'contact_updated_webhook_dispatched', log.action_type
    assert_equal 'ContactsHub::Contact', log.target_type
    assert_equal contact.id, log.target_id.to_i
  end

  # --- 9. Error rescue --------------------------------------------------------

  test 'dispatcher rescues errors on create without raising' do
    contact = create_contact(name: 'Boom create test', author: @user)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::ContactsHubReviewDispatcher.dispatch_create(contact)
    end
  end

  test 'dispatcher rescues errors on update without raising' do
    contact = create_contact(name: 'Boom update test', author: @user)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::ContactsHubReviewDispatcher.dispatch_update(contact)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  # Build and save a valid ContactsHub::Contact. Required columns on
  # `contacts_hub_contacts` for a valid create: name, status, visibility,
  # project_id, author_id. All PII fields default to nil.
  def create_contact(name:, author:, status: 'active', visibility: 'private', project: @project,
                     job_title: nil, organization: nil, source: nil, nickname: nil,
                     email: nil, secondary_email: nil, phone: nil, mobile: nil,
                     address_line1: nil, address_line2: nil, city: nil, region: nil,
                     postal_code: nil, country: nil, birthday: nil, description: nil)
    ContactsHub::Contact.create!(
      name: name,
      author: author,
      project: project,
      status: status,
      visibility: visibility,
      job_title: job_title,
      organization: organization,
      source: source,
      nickname: nickname,
      email: email,
      secondary_email: secondary_email,
      phone: phone,
      mobile: mobile,
      address_line1: address_line1,
      address_line2: address_line2,
      city: city,
      region: region,
      postal_code: postal_code,
      country: country,
      birthday: birthday,
      description: description
    )
  end
end
