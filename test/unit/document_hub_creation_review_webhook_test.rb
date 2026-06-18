require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeDocumentHubCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :enumerations

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @admin = User.find_by(login: 'admin')
    @user = User.find_by(login: 'jsmith')
    @project = Project.first
    enable_automyra_bridge!(@project)
    enable_document_hub!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_document_review' => 'https://automyra.sbg-server.com/webhooks/redmica-document-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_DOCUMENT_REVIEW'] = '1'

    AutomyraBridge::DocumentHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_DOCUMENT_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Document create hook ------------------------------------------------

  test 'fires webhook when Document is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_document(author: @user)
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      User.current = @admin
      create_document(author: @admin)
      User.current = @user
    end
  end

  # --- 2. Document update hook ------------------------------------------------

  test 'fires webhook when Document title changes' do
    document = create_document(author: @user, title: 'Original title')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      document.update!(title: 'Updated title')
    end
  end

  test 'fires webhook when Document description changes' do
    document = create_document(author: @user, title: 'Description test')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      document.update!(description: 'Updated description')
    end
  end

  test 'does not fire update webhook when no meaningful field changes' do
    document = create_document(author: @user, title: 'No-op test')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      document.touch
    end
  end

  # --- 3. Attachment attached to Document hook --------------------------------

  test 'fires document_created webhook when Attachment is attached to Document' do
    document = create_document(author: @user, title: 'Attachment host')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_attachment(container: document, author: @user)
    end
  end

  test 'does not fire webhook when Attachment is attached to Project' do
    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_attachment(container: @project, author: @user)
    end
  end

  # --- 4. Environment flag gating ----------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_DOCUMENT_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_DOCUMENT_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_document(author: @user, title: 'Flag off create')
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_DOCUMENT_REVIEW is unset' do
    document = create_document(author: @user, title: 'Flag off update baseline')
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_DOCUMENT_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      document.update!(title: 'Flag off update')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_DOCUMENT_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_DOCUMENT_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_document(author: @user, title: 'Zero flag')
    end
  end

  # --- 5. Thread-local skip flag ----------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_document(author: @user, title: 'Skip flag create')
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    document = create_document(author: @user, title: 'Skip flag update baseline')
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      document.update!(title: 'Skip flag update')
    end
  end

  test 'does not fire attachment webhook when thread-local skip flag is set' do
    document = create_document(author: @user, title: 'Skip flag attachment host')
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_attachment(container: document, author: @user)
    end
  end

  # --- 6. Dispatcher payload shape --------------------------------------------

  test 'payload includes all required keys on document create' do
    document = create_document(
      author: @user,
      title: 'Payload test document',
      description: 'Payload description body'
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.document_hub.document_created', event_type

    assert_equal document.id, payload['document_id']
    assert_equal 'Payload test document', payload['title']
    assert_equal 'Payload description body', payload['description']
    assert_equal document.project_id, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']

    assert payload.key?('item_id')
    assert payload.key?('attachment_id')
    assert payload.key?('filename')
    assert payload.key?('content_type')
    assert payload.key?('filesize')
    assert payload.key?('digest')
    assert payload.key?('category_id')
    assert payload.key?('category_name')
    assert payload.key?('container_type')
    assert payload.key?('version_id')
    assert payload.key?('tags')
    assert payload.key?('url')
    assert payload.key?('timestamp')
    assert payload.key?('event_type')

    assert_match(/\Adocument-review-#{document.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'payload includes attachment_id and container_type on attachment create' do
    document = create_document(author: @user, title: 'Attachment payload host')
    clear_enqueued_jobs

    attachment = create_attachment(container: document, author: @user)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, _delivery_id = job[:args]
    assert_equal 'redmica.document_hub.document_created', event_type

    assert_equal attachment.id, payload['attachment_id']
    assert_equal document.id, payload['document_id']
    assert_equal 'Document', payload['container_type']
    assert_equal 'attachment-payload.txt', payload['filename']
    assert_equal 'text/plain', payload['content_type']
    assert_equal 12, payload['filesize']
    assert_equal 'deadbeef', payload['digest']

    assert payload['url'].include?('/attachments/download/')
  end

  # --- 7. Missing snapshot fallback -------------------------------------------

  test 'dispatcher builds payload from native Document when DocumentHub::Item is missing' do
    document = create_document(author: @user, title: 'Fallback document', description: 'Fallback body')

    payload = AutomyraBridge::DocumentHubReviewDispatcher.build_payload(document, nil, 'redmica.document_hub.document_created')

    assert_equal document.id, payload[:document_id]
    assert_equal 'Fallback document', payload[:title]
    assert_equal 'Fallback body', payload[:description]
    assert_equal @project.id, payload[:project_id]
    assert_equal @project.identifier, payload[:project_identifier]
    assert_equal @project.name, payload[:project_name]
    assert_nil payload[:item_id]
  end

  test 'dispatcher builds payload from native Attachment when DocumentHub::Item is missing' do
    document = create_document(author: @user, title: 'Fallback attachment host')
    attachment = create_attachment(container: document, author: @user, skip_clear: true)

    payload = AutomyraBridge::DocumentHubReviewDispatcher.build_payload(document, nil, 'redmica.document_hub.document_created', attachment: attachment)

    assert_equal attachment.id, payload[:attachment_id]
    assert_equal document.id, payload[:document_id]
    assert_equal 'Document', payload[:container_type]
    assert_equal 'attachment-payload.txt', payload[:filename]
    assert_equal 'text/plain', payload[:content_type]
    assert_equal 12, payload[:filesize]
    assert_equal 'deadbeef', payload[:digest]
    assert_nil payload[:item_id]
  end

  # --- 8. Long text truncation -------------------------------------------------

  test 'long description is truncated to 2000 characters' do
    long_description = 'd' * 3000
    create_document(author: @user, title: 'Truncation document', description: long_description)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    payload = job[:args][1]
    assert payload['description'].length <= 2000,
           "description must be truncated to <= 2000 chars (got #{payload['description'].length})"
  end

  # --- 9. Update delivery ID format ------------------------------------------

  test 'update delivery id uses document-review-update-{id}-{hex} format' do
    document = create_document(author: @user, title: 'Update delivery id document')
    clear_enqueued_jobs

    document.update!(title: 'Update delivery id document - changed')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.document_hub.document_updated', event_type
    assert_match(/\Adocument-review-update-#{document.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 10. Activity log -------------------------------------------------------

  test 'activity log entry is written on document create dispatch' do
    document = create_document(author: @user, title: 'Activity log create document')

    log = AutomyraBridgeActivityLog.where(action_type: 'document_created_webhook_dispatched').last
    assert_not_nil log, 'expected a document_created_webhook_dispatched activity log entry'
    assert_equal 'Document', log.target_type
    assert_equal document.id, log.target_id.to_i
  end

  test 'activity log entry is written on document update dispatch' do
    document = create_document(author: @user, title: 'Activity log update baseline')
    clear_enqueued_jobs
    AutomyraBridgeActivityLog.delete_all

    document.update!(title: 'Activity log update document')

    log = AutomyraBridgeActivityLog.where(action_type: 'document_updated_webhook_dispatched').last
    assert_not_nil log, 'expected a document_updated_webhook_dispatched activity log entry'
    assert_equal 'Document', log.target_type
    assert_equal document.id, log.target_id.to_i
  end

  test 'activity log entry is written on attachment create dispatch' do
    document = create_document(author: @user, title: 'Activity log attachment host')
    clear_enqueued_jobs
    AutomyraBridgeActivityLog.delete_all

    attachment = create_attachment(container: document, author: @user)

    log = AutomyraBridgeActivityLog.where(action_type: 'document_created_webhook_dispatched').last
    assert_not_nil log, 'expected activity log entry for attachment-created document event'
    assert_equal 'Attachment', log.target_type
    assert_equal attachment.id, log.target_id.to_i
  end

  # --- 11. Error rescue -------------------------------------------------------

  test 'dispatcher rescues errors on document create without raising' do
    document = create_document(author: @user, title: 'Boom document create')
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::DocumentHubReviewDispatcher.dispatch_create(document)
    end
  end

  test 'dispatcher rescues errors on document update without raising' do
    document = create_document(author: @user, title: 'Boom document update')
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::DocumentHubReviewDispatcher.dispatch_update(document)
    end
  end

  test 'dispatcher rescues errors on attachment create without raising' do
    document = create_document(author: @user, title: 'Boom attachment host')
    attachment = create_attachment(container: document, author: @user, skip_clear: true)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::DocumentHubReviewDispatcher.dispatch_attachment_create(attachment)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def enable_document_hub!(project)
    EnabledModule.create!(project: project, name: :document_hub) unless EnabledModule.exists?(project: project, name: :document_hub)
    EnabledModule.create!(project: project, name: :documents) unless EnabledModule.exists?(project: project, name: :documents)
  end

  def create_document(author: nil, title: 'Test document', description: 'Test description')
    User.current = author if author

    Document.create!(
      project: @project,
      category: DocumentCategory.first || DocumentCategory.create!(name: 'Test category'),
      title: title,
      description: description
    )
  end

  def create_attachment(container:, author:, skip_clear: false)
    clear_enqueued_jobs unless skip_clear

    Attachment.create!(
      container: container,
      filename: 'attachment-payload.txt',
      filesize: 12,
      content_type: 'text/plain',
      digest: 'deadbeef',
      author: author,
      description: 'Attachment payload'
    )
  end
end
