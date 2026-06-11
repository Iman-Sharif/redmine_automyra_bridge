require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeTaskImproverTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    Resolv.stubs(:getaddresses).returns(['93.184.216.34'])
  end

  test 'returns configured error without endpoint' do
    result = AutomyraBridge::TaskImprover.new(
      'automyra_endpoint' => '',
      'request_timeout_seconds' => '15'
    ).call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert_not result.success?
    assert_equal 'Automyra endpoint is not configured.', result.error
    assert_equal 'failed', result.audit_event.status
  end

  test 'normalizes task suggestions from Automyra response' do
    service = AutomyraBridge::TaskImprover.new('automyra_endpoint' => 'https://automyra.test/improve')
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ task: { title: 'Improved', body: 'Better notes', tags: 'alpha, beta, alpha' } }.to_json)
    service.stubs(:post_payload).returns(response)

    result = service.call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert result.success?
    assert_equal 'Improved', result.suggestions[:title]
    assert_equal 'Better notes', result.suggestions[:notes]
    assert_equal %w[alpha beta], result.suggestions[:tags]
    assert_equal 'succeeded', result.audit_event.status
  end

  test 'rejects invalid endpoint URL without making outbound request' do
    service = AutomyraBridge::TaskImprover.new('automyra_endpoint' => 'file:///etc/passwd')
    service.expects(:post_payload).never

    result = service.call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert_not result.success?
    assert_equal 'Automyra endpoint must be an HTTP or HTTPS URL.', result.error
    assert_equal 'failed', result.audit_event.status
  end

  test 'drops blank suggestion values' do
    service = AutomyraBridge::TaskImprover.new('automyra_endpoint' => 'https://automyra.test/improve')
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ task: { title: '', body: '' } }.to_json)
    service.stubs(:post_payload).returns(response)

    result = service.call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert result.success?
    assert_empty result.suggestions
  end

  test 'records request metadata for Automyra calls' do
    service = AutomyraBridge::TaskImprover.new(
      'automyra_endpoint' => 'https://automyra.test/improve',
      'automyra_token' => 'secret-token',
      'request_timeout_seconds' => '5'
    )
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ task: { title: 'Improved' } }.to_json)
    captured = nil
    service.stubs(:post_payload).with do |user, task_params, project, audit_event|
      captured = [user, task_params, project, audit_event]
      true
    end.returns(response)

    result = service.call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert result.success?
    assert_equal 'Draft', captured[1][:title]
    assert captured[3].correlation_id.present?
  end

  test 'preserves adapter error body in result error' do
    service = AutomyraBridge::TaskImprover.new('automyra_endpoint' => 'https://automyra.test/improve')
    service.stubs(:post_payload).raises('Automyra returned HTTP 400: {"error":"invalid_request","message":"task.title required"}')

    result = service.call(user: User.find(2), project: Project.find(1), task_params: { title: 'Draft' })

    assert_not result.success?
    assert_match /task.title required/, result.error
  end
end
