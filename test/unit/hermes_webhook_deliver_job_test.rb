require File.expand_path('../test_helper', __dir__)

class HermesWebhookDeliverJobTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues

  setup do
    AutomyraBridgeWebhookDelivery.delete_all
    Journal.delete_all

    @issue = Issue.first
    @event_type = 'redmica.issue_created'
    @payload = { 'issue_id' => @issue.id, 'project_id' => @issue.project_id }.to_json
    @delivery_id = "test-delivery-#{SecureRandom.hex(8)}"

    # Ensure settings required by the notifier are present
    Setting.plugin_redmine_automyra_bridge ||= {}
    @original_settings = Setting.plugin_redmine_automyra_bridge.dup
    Setting.plugin_redmine_automyra_bridge = @original_settings.merge(
      'hermes_webhook_url' => 'http://127.0.0.1:8644/webhooks/test',
      'hermes_webhook_secret' => 'test-secret-key',
      'webhook_user_login' => 'automyra-bot'
    )
  end

  teardown do
    Setting.plugin_redmine_automyra_bridge = @original_settings
    AutomyraBridgeWebhookDelivery.delete_all
    Journal.delete_all
  end

  # --- Layer 1: Delivery record creation before HTTP POST ---

  test 'creates delivery record before HTTP POST so failed deliveries are tracked' do
    # Stub the notifier to simulate HTTP failure
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).raises(StandardError, 'Connection refused')

    job = AutomyraBridge::HermesWebhookDeliverJob.new(@event_type, @payload, @delivery_id)

    # perform_now with retry_on tries to enqueue the retry, which raises
    # NotImplementedError in the test adapter.  Rescue it — the delivery
    # record must already exist at this point (created before the HTTP POST).
    begin
      job.perform_now
    rescue NotImplementedError
      # retry_on tries to enqueue a retry job; the inline test adapter can't enqueue
    end

    # The delivery record MUST exist even though the HTTP POST failed
    delivery = AutomyraBridgeWebhookDelivery.find_by(delivery_id: @delivery_id)
    assert delivery, 'delivery record should be created before HTTP POST, even on failure'
    assert_equal 'pending', delivery.status
    assert_equal @event_type, delivery.event_type
    assert_equal @delivery_id, delivery.delivery_id
  end

  test 'does not create duplicate delivery record on retry (idempotency guard)' do
    # Pre-create the delivery record (simulating a previous attempt)
    AutomyraBridgeWebhookDelivery.create!(
      delivery_id: @delivery_id,
      event_type: @event_type,
      payload: @payload,
      target_type: 'Issue',
      target_id: @issue.id,
      project_id: @issue.project_id,
      retry_count: 0,
      max_retries: 3,
      next_retry_at: 5.minutes.ago,
      status: 'pending'
    )

    # Stub notifier to succeed
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    job = AutomyraBridge::HermesWebhookDeliverJob.new(@event_type, @payload, @delivery_id)
    job.perform_now

    # Should still have exactly 1 record
    count = AutomyraBridgeWebhookDelivery.where(delivery_id: @delivery_id).count
    assert_equal 1, count, 'idempotency guard should prevent duplicate delivery records'
  end

  test 'delivery record captures target info from payload' do
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    job = AutomyraBridge::HermesWebhookDeliverJob.new(@event_type, @payload, @delivery_id)
    job.perform_now

    delivery = AutomyraBridgeWebhookDelivery.find_by(delivery_id: @delivery_id)
    assert delivery
    assert_equal 'Issue', delivery.target_type
    assert_equal @issue.id, delivery.target_id
    assert_equal @issue.project_id, delivery.project_id
  end

  # --- Layer 1: Successful delivery still creates pending record for RetryChecker ---

  test 'successful HTTP delivery creates pending record for RetryChecker monitoring' do
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    job = AutomyraBridge::HermesWebhookDeliverJob.new(@event_type, @payload, @delivery_id)
    job.perform_now

    delivery = AutomyraBridgeWebhookDelivery.find_by(delivery_id: @delivery_id)
    assert delivery, 'delivery record should be created on success too'
    assert_equal 'pending', delivery.status, 'status should be pending so RetryChecker can verify Hermes processing'
  end

  # --- Layer 2: RetryChecker picks up deliveries created by failed HTTP ---

  test 'RetryChecker retries delivery that was created on HTTP failure' do
    # Simulate what happens after ActiveJob exhausts its retries:
    # delivery record exists as pending with an error, next_retry_at in the past
    delivery = AutomyraBridgeWebhookDelivery.create!(
      delivery_id: @delivery_id,
      event_type: @event_type,
      payload: @payload,
      target_type: 'Issue',
      target_id: @issue.id,
      project_id: @issue.project_id,
      retry_count: 0,
      max_retries: 3,
      next_retry_at: 5.minutes.ago,
      status: 'pending',
      last_error: 'Connection refused',
      created_at: 2.hours.ago
    )

    # Stub the re-delivery to succeed
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    bot_user = User.create!(
      login: "deliver-test-bot-#{SecureRandom.hex(4)}",
      firstname: 'Deliver',
      lastname: 'Bot',
      mail: "deliver-bot-#{SecureRandom.hex(4)}@example.test",
      status: Principal::STATUS_ACTIVE,
      admin: true
    )

    begin
      settings = {
        'webhook_user_login' => bot_user.login,
        'hermes_webhook_retry_interval_minutes' => '30',
        'hermes_webhook_retry_max_retries' => '3',
        'hermes_webhook_retry_timeout_minutes' => '60'
      }

      checker = AutomyraBridge::RetryChecker.new(settings)
      checker.check_all

      delivery.reload
      # After retry, the delivery should still be pending (waiting for bot response)
      # but retry_count should be incremented and next_retry_at pushed forward
      assert_equal 'pending', delivery.status
      assert_equal 1, delivery.retry_count
      assert delivery.next_retry_at > Time.current
    ensure
      bot_user&.destroy
    end
  end

  # --- extract_target handles all event types ---

  test 'extract_target handles document_id from payload' do
    document_payload = { 'document_id' => 42, 'project_id' => 1 }.to_json
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    delivery_id = "doc-test-#{SecureRandom.hex(8)}"
    job = AutomyraBridge::HermesWebhookDeliverJob.new('redmica.document_review', document_payload, delivery_id)
    job.perform_now

    delivery = AutomyraBridgeWebhookDelivery.find_by(delivery_id: delivery_id)
    assert delivery
    assert_equal 'DocumentHub::Document', delivery.target_type
    assert_equal 42, delivery.target_id
  end

  test 'extract_target handles repository_id from payload' do
    repo_payload = { 'repository_id' => 7, 'project_id' => 1 }.to_json
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    delivery_id = "repo-test-#{SecureRandom.hex(8)}"
    job = AutomyraBridge::HermesWebhookDeliverJob.new('redmica.repo_review', repo_payload, delivery_id)
    job.perform_now

    delivery = AutomyraBridgeWebhookDelivery.find_by(delivery_id: delivery_id)
    assert delivery
    assert_equal 'RepoHub::Repository', delivery.target_type
    assert_equal 7, delivery.target_id
  end
end