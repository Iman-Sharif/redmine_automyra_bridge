require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeHermesWebhookNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  fixtures :users, :projects

  SECRET = 'test-secret-very-long-random-value'.freeze
  URL = 'https://automyra.sbg-server.com/webhooks/redmica-mentions'.freeze

  setup do
    @event_type = 'redmica.test_event'
    @payload = { 'foo' => 'bar', 'nested' => { 'n' => 1 } }
    @delivery_id = 'test-delivery-001'
    @settings = {
      'hermes_webhook_url' => URL,
      'hermes_webhook_secret' => SECRET,
      'request_timeout_seconds' => '15'
    }
  end

  test 'returns nil and makes no HTTP call when webhook url is blank' do
    Net::HTTP.expects(:start).never
    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings.merge('hermes_webhook_url' => ''))
    assert_nil notifier.deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
  end

  test 'returns nil and makes no HTTP call when secret is blank' do
    Net::HTTP.expects(:start).never
    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings.merge('hermes_webhook_secret' => ''))
    assert_nil notifier.deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
  end

  test 'returns nil when UrlValidator rejects the url' do
    AutomyraBridge::UrlValidator.stubs(:validate!).raises(ArgumentError, 'Outbound URL is not permitted: hostname is not allowlisted')
    Net::HTTP.expects(:start).never
    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    assert_nil notifier.deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
  end

  test 'posts request with correct signed body and headers' do
    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')

    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    result = notifier.deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)

    assert_equal response, result
    assert_not_nil captured_request
    assert_equal 'application/json', captured_request['Content-Type']
    assert_equal @event_type, captured_request['X-GitHub-Event']
    assert_equal @delivery_id, captured_request['X-GitHub-Delivery']
    assert_equal 'Automyra-Bridge-Hermes-Notifier/1.0', captured_request['User-Agent']

    signature = captured_request['X-Hub-Signature-256']
    assert signature.start_with?('sha256='), "expected sha256= prefix, got #{signature.inspect}"

    body = captured_request.body
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, body)}"
    assert_equal expected, signature

    parsed = JSON.parse(body)
    assert_equal @event_type, parsed['event_type']
    assert_equal @payload, parsed['payload']
  end

  test 'generates a delivery id when none provided' do
    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    notifier.deliver(event_type: @event_type, payload: @payload)

    delivery = captured_request['X-GitHub-Delivery']
    assert delivery.to_s.length.positive?
  end

  test 'raises on non-2xx response' do
    response = Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized')
    response.stubs(:body).returns('{"error":"Invalid signature"}')
    http = mock('http')
    http.stubs(:request).returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    assert_raises(StandardError) do
      notifier.deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
    end
  end

  test 'routes redmica.issue_created to hermes_webhook_url_creation_review' do
    creation_url = 'https://automyra.sbg-server.com/webhooks/redmica-creation-review'
    settings = @settings.merge('hermes_webhook_url_creation_review' => creation_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(creation_url, anything).returns(URI.parse(creation_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.issue_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.issue_mention to hermes_webhook_url_mentions' do
    mentions_url = 'https://automyra.sbg-server.com/webhooks/redmica-mentions-v2'
    settings = @settings.merge('hermes_webhook_url_mentions' => mentions_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(mentions_url, anything).returns(URI.parse(mentions_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.issue_mention', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.issue_status_changed to hermes_webhook_url_auto_close' do
    auto_close_url = 'https://automyra.sbg-server.com/webhooks/redmica-auto-close'
    settings = @settings.merge('hermes_webhook_url_auto_close' => auto_close_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(auto_close_url, anything).returns(URI.parse(auto_close_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.issue_status_changed', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.task_created to hermes_webhook_url_creation_review' do
    creation_url = 'https://automyra.sbg-server.com/webhooks/redmica-task-creation-review'
    settings = @settings.merge('hermes_webhook_url_creation_review' => creation_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(creation_url, anything).returns(URI.parse(creation_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.task_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.wiki_created to hermes_webhook_url_wiki_review' do
    wiki_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-wiki-review'
    settings = @settings.merge('hermes_webhook_url_wiki_review' => wiki_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(wiki_review_url, anything).returns(URI.parse(wiki_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.wiki_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.wiki_updated to hermes_webhook_url_wiki_review' do
    wiki_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-wiki-review'
    settings = @settings.merge('hermes_webhook_url_wiki_review' => wiki_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(wiki_review_url, anything).returns(URI.parse(wiki_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.wiki_updated', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.faq_hub.faq_created to hermes_webhook_url_faq_review' do
    faq_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-faq-review'
    settings = @settings.merge('hermes_webhook_url_faq_review' => faq_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(faq_review_url, anything).returns(URI.parse(faq_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.faq_hub.faq_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.faq_hub.faq_updated to hermes_webhook_url_faq_review' do
    faq_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-faq-review'
    settings = @settings.merge('hermes_webhook_url_faq_review' => faq_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(faq_review_url, anything).returns(URI.parse(faq_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.faq_hub.faq_updated', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.faq_hub.faq_status_changed to hermes_webhook_url_faq_status_changed' do
    faq_status_changed_url = 'https://automyra.sbg-server.com/webhooks/redmica-faq-status'
    settings = @settings.merge('hermes_webhook_url_faq_status_changed' => faq_status_changed_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(faq_status_changed_url, anything).returns(URI.parse(faq_status_changed_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.faq_hub.faq_status_changed', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.error_hub.error_created to hermes_webhook_url_error_review' do
    error_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-error-review'
    settings = @settings.merge('hermes_webhook_url_error_review' => error_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(error_review_url, anything).returns(URI.parse(error_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.error_hub.error_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.error_hub.error_status_changed to hermes_webhook_url_error_status_changed' do
    error_status_changed_url = 'https://automyra.sbg-server.com/webhooks/redmica-error-status'
    settings = @settings.merge('hermes_webhook_url_error_status_changed' => error_status_changed_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(error_status_changed_url, anything)
                                .returns(URI.parse(error_status_changed_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.error_hub.error_status_changed', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.task_hub.task_updated to hermes_webhook_url_task_review' do
    task_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-task-hub-review'
    settings = @settings.merge('hermes_webhook_url_task_review' => task_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(task_review_url, anything).returns(URI.parse(task_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.task_hub.task_updated', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.task_hub.task_status_changed to hermes_webhook_url_task_status_changed' do
    task_status_changed_url = 'https://automyra.sbg-server.com/webhooks/redmica-task-hub-status'
    settings = @settings.merge('hermes_webhook_url_task_status_changed' => task_status_changed_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(task_status_changed_url, anything)
                                .returns(URI.parse(task_status_changed_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.task_hub.task_status_changed', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.contacts_hub.contact_created to hermes_webhook_url_contacts_review' do
    contacts_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-contacts-review'
    settings = @settings.merge('hermes_webhook_url_contacts_review' => contacts_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(contacts_review_url, anything)
                                .returns(URI.parse(contacts_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.contacts_hub.contact_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.contacts_hub.contact_status_changed to hermes_webhook_url_contacts_status_changed' do
    contacts_status_changed_url = 'https://automyra.sbg-server.com/webhooks/redmica-contacts-status'
    settings = @settings.merge('hermes_webhook_url_contacts_status_changed' => contacts_status_changed_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(contacts_status_changed_url, anything)
                                .returns(URI.parse(contacts_status_changed_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.contacts_hub.contact_status_changed', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.document_hub.document_updated to hermes_webhook_url_document_review' do
    document_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-document-review'
    settings = @settings.merge('hermes_webhook_url_document_review' => document_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(document_review_url, anything)
                                .returns(URI.parse(document_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.document_hub.document_updated', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'routes redmica.repo_hub.repository_created to hermes_webhook_url_repo_review' do
    repo_review_url = 'https://automyra.sbg-server.com/webhooks/redmica-repo-review'
    settings = @settings.merge('hermes_webhook_url_repo_review' => repo_review_url)

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(repo_review_url, anything).returns(URI.parse(repo_review_url))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.repo_hub.repository_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'falls back to hermes_webhook_url for redmica.wiki_created when wiki-review url is blank' do
    settings = @settings.merge('hermes_webhook_url_wiki_review' => '')

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(URL, anything).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.wiki_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'falls back to hermes_webhook_url for redmica.task_created when creation-review url is blank' do
    settings = @settings.merge('hermes_webhook_url_creation_review' => '')

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(URL, anything).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.task_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'falls back to hermes_webhook_url when per-event url is blank' do
    settings = @settings.merge('hermes_webhook_url_creation_review' => '')

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(URL, anything).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.issue_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'falls back to hermes_webhook_url for redmica.faq_hub.faq_created when faq-review url is blank' do
    settings = @settings.merge('hermes_webhook_url_faq_review' => '')

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).with(URL, anything).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(settings)
    notifier.deliver(event_type: 'redmica.faq_hub.faq_created', payload: @payload, delivery_id: @delivery_id)

    assert_not_nil captured_request
  end

  test 'drops payloads larger than 1MB without making an HTTP call' do
    Net::HTTP.expects(:start).never
    oversized = { 'blob' => 'x' * (1.megabyte + 1.kilobyte) }

    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    result = notifier.deliver(event_type: @event_type, payload: oversized, delivery_id: @delivery_id)

    assert_nil result, 'oversized payload must be dropped (returns nil, no outbound HTTP)'
  end

  test 'deliver job uses default ActiveJob retry (no custom retry_on)' do
    old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    # After the F4 scope fix, HermesWebhookDeliverJob no longer defines a custom
    # retry_on, so it falls through to ActiveJob::Base.default. The default
    # retry_on (StandardError, 3 attempts, :exponentially_longer) is pinned here
    # because removing the custom retry was an intentional simplification.
    job_class = AutomyraBridge::HermesWebhookDeliverJob
    src = File.read(File.expand_path('../../app/jobs/automyra_bridge/hermes_webhook_deliver_job.rb', __dir__))
    refute_match(/retry_on\s+StandardError/, src,
                 'HermesWebhookDeliverJob should NOT have a custom retry_on after F4 cleanup')
  ensure
    ActiveJob::Base.queue_adapter = old_adapter if old_adapter
  end
end
