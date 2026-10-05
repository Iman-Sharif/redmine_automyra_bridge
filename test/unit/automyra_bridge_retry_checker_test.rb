require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeRetryCheckerTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues

  STATUS_MARKER = '<!-- automyra-bridge-status -->'.freeze

  setup do
    AutomyraBridgeWebhookDelivery.delete_all
    Journal.delete_all

    @bot_user = User.create!(
      login: "retry-test-bot-#{SecureRandom.hex(4)}",
      firstname: 'Retry',
      lastname: 'Bot',
      mail: "retry-bot-#{SecureRandom.hex(4)}@example.test",
      status: Principal::STATUS_ACTIVE,
      admin: true
    )
    @issue = Issue.first
    @settings = {
      'webhook_user_login' => @bot_user.login,
      'hermes_webhook_retry_interval_minutes' => '30',
      'hermes_webhook_retry_max_retries' => '3',
      'hermes_webhook_retry_timeout_minutes' => '60'
    }
  end

  teardown do
    @bot_user&.destroy
  end

  def create_delivery(overrides = {})
    AutomyraBridgeWebhookDelivery.create!({
      event_type: 'redmica.issue_mention',
      delivery_id: "delivery-#{SecureRandom.hex(8)}",
      payload: { 'source' => 'issue_journal', 'body' => '@automyra help' }.to_json,
      target_type: 'Issue',
      target_id: @issue.id,
      retry_count: 0,
      max_retries: 3,
      next_retry_at: 5.minutes.ago,
      status: 'pending'
    }.merge(overrides))
  end

  def add_bot_journal(notes, created_on: Time.current)
    Journal.create!(
      journalized_type: 'Issue',
      journalized_id: @issue.id,
      user_id: @bot_user.id,
      notes: notes,
      created_on: created_on
    )
  end

  # --- Success detection: bot journal without STATUS_MARKER -> resolved ---

  test 'marks delivery resolved when bot journal exists without status marker' do
    delivery = create_delivery
    journal = add_bot_journal('Here is the answer to your question.')

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'resolved', delivery.status
    assert_equal journal.id, delivery.detected_journal_id
    assert_equal 'bot_user', delivery.detection_method
  end

  # --- Failure detection: bot journal with STATUS_MARKER -> retry ---

  test 'retries delivery when bot journal has status marker and failure text' do
    delivery = create_delivery
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited by provider")

    # Stub the Hermes re-delivery to simulate success
    success_response = Net::HTTPOK.new('1.1', '200', 'OK')
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(success_response)

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'pending', delivery.status
    assert_equal 1, delivery.retry_count
    assert delivery.next_retry_at > Time.current
  end

  test 'success journal takes priority over failure journal' do
    delivery = create_delivery
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited")
    success_journal = add_bot_journal('Here is the actual answer.')

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'resolved', delivery.status
    assert_equal success_journal.id, delivery.detected_journal_id
  end

  # --- Timeout detection: no bot journal after timeout -> retry ---

  test 'retries delivery when no bot journal exists and timeout has passed' do
    delivery = create_delivery(created_at: 2.hours.ago)

    # Stub Hermes re-delivery
    success_response = Net::HTTPOK.new('1.1', '200', 'OK')
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(success_response)

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'pending', delivery.status
    assert_equal 1, delivery.retry_count
  end

  test 'does not retry when no bot journal and timeout not yet exceeded' do
    delivery = create_delivery(created_at: 10.minutes.ago)

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'pending', delivery.status
    assert_equal 0, delivery.retry_count
    # next_retry_at should be pushed forward for the next cycle
    assert delivery.next_retry_at > Time.current
  end

  # --- Exhaustion: retry_count >= max_retries -> exhausted ---

  test 'marks exhausted when failure detected and retry_count >= max_retries' do
    delivery = create_delivery(retry_count: 3, max_retries: 3)
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: timeout exceeded")

    AutomyraBridge::HermesWebhookNotifier.expects(:deliver).never

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'exhausted', delivery.status
    assert delivery.last_error.present?
  end

  test 'marks exhausted when timeout reached and retry_count >= max_retries' do
    delivery = create_delivery(retry_count: 3, max_retries: 3, created_at: 2.hours.ago)

    AutomyraBridge::HermesWebhookNotifier.expects(:deliver).never

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'exhausted', delivery.status
    assert delivery.last_error.present?
  end

  # --- Cancellation logic: cancelled deliveries are not checked ---

  test 'does not check cancelled deliveries' do
    delivery = create_delivery(status: 'cancelled')
    add_bot_journal('Some response.')

    AutomyraBridge::HermesWebhookNotifier.expects(:deliver).never

    checker = AutomyraBridge::RetryChecker.new(@settings)
    count = checker.check_all

    assert_equal 0, count
    delivery.reload
    assert_equal 'cancelled', delivery.status
  end

  test 'does not check resolved deliveries' do
    delivery = create_delivery(status: 'resolved')
    add_bot_journal('Some response.')

    AutomyraBridge::HermesWebhookNotifier.expects(:deliver).never

    checker = AutomyraBridge::RetryChecker.new(@settings)
    count = checker.check_all

    assert_equal 0, count
    delivery.reload
    assert_equal 'resolved', delivery.status
  end

  # --- check_all return value ---

  test 'check_all returns count of checked deliveries' do
    create_delivery(delivery_id: 'count-1')
    create_delivery(delivery_id: 'count-2', created_at: 2.hours.ago)

    # Stub Hermes to avoid real HTTP calls
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    checker = AutomyraBridge::RetryChecker.new(@settings)
    count = checker.check_all

    assert_equal 2, count
  end

  test 'check_all returns 0 when bot_user is nil' do
    create_delivery

    # Create checker with settings that produce no bot user
    User.active.where(admin: true).update_all(status: Principal::STATUS_LOCKED)
    User.where(login: 'Automyra').destroy_all

    checker = AutomyraBridge::RetryChecker.new('webhook_user_login' => 'nonexistent')
    count = checker.check_all

    assert_equal 0, count
  ensure
    User.where(admin: true).update_all(status: Principal::STATUS_ACTIVE)
  end

  # --- Re-delivery failure handling ---

  test 'keeps delivery pending when re-delivery returns non-success' do
    delivery = create_delivery
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited")

    # Stub Hermes to return nil (failure)
    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(nil)

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'pending', delivery.status
    assert_equal 0, delivery.retry_count
    assert delivery.last_error.present?
  end

  test 'keeps delivery pending when re-delivery raises exception' do
    delivery = create_delivery
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited")

    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).raises(StandardError, 'connection refused')

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'pending', delivery.status
    assert_equal 0, delivery.retry_count
    assert delivery.last_error.present?
  end

  # --- Fallback comment replacement on retry ---

  test 'replaces fallback comment with retry placeholder on failure retry' do
    delivery = create_delivery
    failure_journal = add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited")

    AutomyraBridge::HermesWebhookNotifier.stubs(:deliver).returns(
      Net::HTTPOK.new('1.1', '200', 'OK')
    )

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    failure_journal.reload
    assert_equal failure_journal.id, delivery.fallback_journal_id
    assert_match(/retrying/, failure_journal.notes)
  end

  # --- Exhaustion posts comment when no fallback journal ---

  test 'posts exhaustion comment on issue when timeout exhausted with no fallback journal' do
    delivery = create_delivery(retry_count: 3, max_retries: 3, created_at: 2.hours.ago)

    AutomyraBridge::HermesWebhookNotifier.expects(:deliver).never

    initial_journal_count = @issue.journals.where(user_id: @bot_user.id).count

    checker = AutomyraBridge::RetryChecker.new(@settings)
    checker.check_all

    delivery.reload
    assert_equal 'exhausted', delivery.status

    final_journal_count = @issue.journals.where(user_id: @bot_user.id).count
    assert final_journal_count > initial_journal_count, 'should have posted an exhaustion comment'

    last_journal = @issue.journals.where(user_id: @bot_user.id).order(:id).last
    assert_match(/could not complete/, last_journal.notes)
  end

  # --- next_delivery_id used in re-delivery ---

  test 'uses next_delivery_id when re-delivering' do
    delivery = create_delivery(retry_count: 0)
    expected_new_id = delivery.next_delivery_id
    add_bot_journal("#{STATUS_MARKER}\nAutomyra request failed: rate limited")

    captured = {}
    original_deliver = AutomyraBridge::HermesWebhookNotifier.method(:deliver)
    AutomyraBridge::HermesWebhookNotifier.define_singleton_method(:deliver) do |_event_type:, _payload:, delivery_id: nil|
      captured[:delivery_id] = delivery_id
      Net::HTTPOK.new('1.1', '200', 'OK')
    end

    begin
      checker = AutomyraBridge::RetryChecker.new(@settings)
      checker.check_all
    ensure
      AutomyraBridge::HermesWebhookNotifier.define_singleton_method(:deliver, original_deliver)
    end

    assert_equal expected_new_id, captured[:delivery_id]
  end
end
