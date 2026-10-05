require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeWebhookDeliveryModelTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues

  setup do
    AutomyraBridgeWebhookDelivery.delete_all
    @project = Project.first
    @issue = Issue.first
  end

  def valid_attributes(overrides = {})
    {
      event_type: 'redmica.issue_mention',
      delivery_id: "delivery-#{SecureRandom.hex(8)}",
      payload: { 'source' => 'issue_journal', 'body' => '@automyra help' }.to_json,
      target_type: 'Issue',
      target_id: @issue.id,
      project_id: @project.id,
      retry_count: 0,
      max_retries: 3,
      next_retry_at: Time.current,
      status: 'pending'
    }.merge(overrides)
  end

  # --- Validations ---

  test 'is valid with all required attributes' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes)
    assert delivery.valid?, delivery.errors.full_messages.join(', ')
  end

  test 'requires event_type' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(event_type: nil))
    assert_not delivery.valid?
    assert_includes delivery.errors[:event_type], 'cannot be blank'
  end

  test 'requires delivery_id' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(delivery_id: nil))
    assert_not delivery.valid?
    assert_includes delivery.errors[:delivery_id], 'cannot be blank'
  end

  test 'requires payload' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(payload: nil))
    assert_not delivery.valid?
    assert_includes delivery.errors[:payload], 'cannot be blank'
  end

  test 'requires next_retry_at' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(next_retry_at: nil))
    assert_not delivery.valid?
    assert_includes delivery.errors[:next_retry_at], 'cannot be blank'
  end

  test 'validates delivery_id uniqueness' do
    AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'unique-delivery-1'))
    duplicate = AutomyraBridgeWebhookDelivery.new(valid_attributes(delivery_id: 'unique-delivery-1'))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:delivery_id], 'has already been taken'
  end

  test 'validates status inclusion' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(status: 'invalid'))
    assert_not delivery.valid?
    assert_includes delivery.errors[:status], 'is not included in the list'
  end

  test 'accepts all valid statuses' do
    AutomyraBridgeWebhookDelivery::STATUSES.each do |status|
      delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(status: status))
      assert delivery.valid?, "#{status} should be valid"
    end
  end

  test 'validates retry_count numericality' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(retry_count: -1))
    assert_not delivery.valid?
    assert_includes delivery.errors[:retry_count], 'must be greater than or equal to 0'
  end

  test 'validates max_retries numericality' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(max_retries: -1))
    assert_not delivery.valid?
    assert_includes delivery.errors[:max_retries], 'must be greater than or equal to 0'
  end

  # --- Scopes ---

  test 'pending scope returns only pending deliveries' do
    pending = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'p-1', status: 'pending'))
    resolved = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'p-2', status: 'resolved'))

    assert_includes AutomyraBridgeWebhookDelivery.pending.to_a, pending
    assert_not_includes AutomyraBridgeWebhookDelivery.pending.to_a, resolved
  end

  test 'ready_to_check scope returns pending deliveries whose next_retry_at has passed' do
    ready = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'r-1', next_retry_at: 10.minutes.ago))
    not_ready = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'r-2', next_retry_at: 10.minutes.from_now))
    resolved = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'r-3', status: 'resolved', next_retry_at: 10.minutes.ago))

    results = AutomyraBridgeWebhookDelivery.ready_to_check.to_a
    assert_includes results, ready
    assert_not_includes results, not_ready
    assert_not_includes results, resolved
  end

  test 'for_target scope filters by target_type and target_id' do
    d1 = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 't-1', target_type: 'Issue', target_id: @issue.id))
    d2 = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 't-2', target_type: 'Issue', target_id: 999_999))
    d3 = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 't-3', target_type: 'TaskHub::Task', target_id: @issue.id))

    results = AutomyraBridgeWebhookDelivery.for_target('Issue', @issue.id).to_a
    assert_includes results, d1
    assert_not_includes results, d2
    assert_not_includes results, d3
  end

  test 'recent scope orders by created_at descending' do
    old = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'o-1'))
    newer = AutomyraBridgeWebhookDelivery.create!(valid_attributes(delivery_id: 'o-2'))

    old.update_columns(created_at: 2.hours.ago)
    newer.update_columns(created_at: 1.hour.ago)

    results = AutomyraBridgeWebhookDelivery.recent.to_a
    assert_equal newer, results.first
    assert_equal old, results.last
  end

  # --- Instance methods ---

  test 'payload_hash returns parsed JSON' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(payload: { 'key' => 'value', 'num' => 42 }.to_json))
    assert_equal({ 'key' => 'value', 'num' => 42 }, delivery.payload_hash)
  end

  test 'payload_hash returns empty hash for blank payload' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(payload: ''))
    assert_equal({}, delivery.payload_hash)
  end

  test 'payload_hash returns empty hash on JSON parse error' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(payload: 'not valid json'))
    assert_equal({}, delivery.payload_hash)
  end

  test 'retryable? returns true when retry_count < max_retries' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(retry_count: 1, max_retries: 3))
    assert delivery.retryable?
  end

  test 'retryable? returns false when retry_count >= max_retries' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(retry_count: 3, max_retries: 3))
    assert_not delivery.retryable?
  end

  test 'increment_retry! increments retry_count and sets next_retry_at' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(retry_count: 0, max_retries: 3, status: 'retrying'))

    delivery.increment_retry!(30)

    delivery.reload
    assert_equal 1, delivery.retry_count
    assert delivery.next_retry_at > Time.current
    assert_equal 'pending', delivery.status
  end

  test 'mark_resolved! sets status resolved with journal info' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(status: 'pending'))

    delivery.mark_resolved!(42, 'bot_user')

    delivery.reload
    assert_equal 'resolved', delivery.status
    assert_equal 42, delivery.detected_journal_id
    assert_equal 'bot_user', delivery.detection_method
  end

  test 'mark_exhausted! sets status exhausted with optional error' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(status: 'pending'))

    delivery.mark_exhausted!('Failed after 4 attempts')

    delivery.reload
    assert_equal 'exhausted', delivery.status
    assert_equal 'Failed after 4 attempts', delivery.last_error
  end

  test 'mark_exhausted! works without error message' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(status: 'pending', last_error: 'previous'))

    delivery.mark_exhausted!

    delivery.reload
    assert_equal 'exhausted', delivery.status
    assert_nil delivery.last_error
  end

  test 'mark_cancelled! sets status cancelled' do
    delivery = AutomyraBridgeWebhookDelivery.create!(valid_attributes(status: 'pending'))

    delivery.mark_cancelled!

    delivery.reload
    assert_equal 'cancelled', delivery.status
  end

  test 'next_delivery_id appends retry suffix with incremented count' do
    delivery = AutomyraBridgeWebhookDelivery.new(valid_attributes(delivery_id: 'abc-123', retry_count: 0))
    assert_equal 'abc-123-retry-1', delivery.next_delivery_id

    delivery.retry_count = 2
    assert_equal 'abc-123-retry-3', delivery.next_delivery_id
  end
end
