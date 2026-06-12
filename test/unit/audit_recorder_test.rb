require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeAuditRecorderTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    @user = User.find(1)
    @project = Project.find(1)
  end

  test 'records event with all required fields' do
    event = AutomyraBridge::AuditRecorder.record('test_action', @user, project_id: @project.id)

    assert_not_nil event
    assert_equal 'test_action', event.action
    assert_equal @user, event.user
    assert_equal @project.id, event.project_id
    assert_not_nil event.correlation_id
    assert_not_nil event.idempotency_key
    assert_equal 'success', event.status
  end

  test 'generates default correlation_id and idempotency_key' do
    event = AutomyraBridge::AuditRecorder.record('generate_test', @user)

    assert_not_nil event
    assert_match UUID_REGEX, event.correlation_id
    assert_match(/\Aaudit-generate_test-#{@user.id}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, event.idempotency_key)
  end

  test 'accepts custom correlation_id and idempotency_key' do
    custom_correlation = 'custom-correlation-123'
    custom_idempotency = 'custom-idempotency-key'

    event = AutomyraBridge::AuditRecorder.record(
      'custom_test',
      @user,
      correlation_id: custom_correlation,
      idempotency_key: custom_idempotency
    )

    assert_not_nil event
    assert_equal custom_correlation, event.correlation_id
    assert_equal custom_idempotency, event.idempotency_key
  end

  test 'handles RecordInvalid gracefully' do
    # Mock create! to raise RecordInvalid
    AutomyraBridgeAuditEvent.stubs(:create!).raises(ActiveRecord::RecordInvalid.new(@user))

    result = AutomyraBridge::AuditRecorder.record('failing_action', @user)

    assert_nil result
    AutomyraBridgeAuditEvent.unstub(:create!)
  end

  test 'status defaults to success' do
    event = AutomyraBridge::AuditRecorder.record('status_test', @user)

    assert_not_nil event
    assert_equal 'success', event.status
  end

  test 'accepts custom status' do
    event = AutomyraBridge::AuditRecorder.record(
      'custom_status_test',
      @user,
      status: 'failed'
    )

    assert_not_nil event
    assert_equal 'failed', event.status
  end

  test 'serializes extra details to JSON' do
    extra_details = { foo: 'bar', count: 42 }

    event = AutomyraBridge::AuditRecorder.record(
      'details_test',
      @user,
      project_id: @project.id,
      **extra_details
    )

    assert_not_nil event
    details = JSON.parse(event.request_payload)
    assert_equal 'bar', details['foo']
    assert_equal 42, details['count']
  end

  UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
end
