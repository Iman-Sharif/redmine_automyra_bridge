require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeHermesWebhookNotifierTest < ActiveSupport::TestCase
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
    refute_nil captured_request
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

    refute_nil captured_request
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

    refute_nil captured_request
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

    refute_nil captured_request
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

    refute_nil captured_request
  end
end
