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

  test 'records a delivery on success and skips a second send with the same delivery id' do
    http = mock('http')
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')
    http.stubs(:request).returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).returns(URI.parse(URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)

    # First delivery: one HTTP round-trip, recorded as delivered.
    Net::HTTP.expects(:start).once.yields(http).returns(response)
    first = AutomyraBridge::HermesWebhookNotifier.new(@settings)
                                                 .deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
    assert_equal response, first
    assert AutomyraBridgeWebhookDelivery.already_delivered?(@delivery_id),
           'successful delivery must be recorded for idempotency'

    # Second delivery with the SAME delivery id: skipped, no HTTP call at all.
    Net::HTTP.expects(:start).never
    second = AutomyraBridge::HermesWebhookNotifier.new(@settings)
                                                  .deliver(event_type: @event_type, payload: @payload, delivery_id: @delivery_id)
    assert_nil second, 'duplicate delivery id must be skipped (idempotent no-op)'
    assert_equal 1, AutomyraBridgeWebhookDelivery.where(idempotency_key: @delivery_id).count,
                 'a delivery id must be recorded exactly once'
  end

  test 'does not record a delivery when the send fails so retries still proceed' do
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
    assert_not AutomyraBridgeWebhookDelivery.already_delivered?(@delivery_id),
               'a failed send must NOT be recorded, so a retry can re-attempt'
  end

  test 'drops payloads larger than 1MB without making an HTTP call' do
    Net::HTTP.expects(:start).never
    oversized = { 'blob' => 'x' * (1.megabyte + 1.kilobyte) }

    notifier = AutomyraBridge::HermesWebhookNotifier.new(@settings)
    result = notifier.deliver(event_type: @event_type, payload: oversized, delivery_id: @delivery_id)

    assert_nil result, 'oversized payload must be dropped (returns nil, no outbound HTTP)'
    assert_not AutomyraBridgeWebhookDelivery.already_delivered?(@delivery_id),
               'a dropped oversized payload must not be recorded as delivered'
  end

  test 'deliver job retries a failing endpoint a bounded number of times then gives up without raising' do
    old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    attempts = 0
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).with do |**_kwargs|
      attempts += 1
      true
    end.raises(StandardError, 'simulated endpoint failure')

    assert_nothing_raised do
      perform_enqueued_jobs do
        AutomyraBridge::HermesWebhookDeliverJob.perform_later(
          'redmica.issue_status_changed', @payload, @delivery_id
        )
      end
    end

    assert_equal 5, attempts,
                 'retry_on attempts: 5 must bound total executions to 5 (no infinite loop)'
  ensure
    ActiveJob::Base.queue_adapter = old_adapter if old_adapter
  end
end
