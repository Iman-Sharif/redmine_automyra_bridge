require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeMemorySyncTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    skip 'memory events table is not available' unless defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

    AutomyraBridgeMemoryEvent.delete_all
    @user = User.find(2)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Memory sync task', user: @user, author: @user, project: @project, status: 'todo')
    @event = AutomyraBridgeMemoryEvent.create!(
      container_type: @task.class.name,
      container_id: @task.id,
      user: @user,
      role: 'user',
      event_type: 'user_mention',
      content: 'unique-redmica-memory-sync-event',
      payload: { channel: 'redmica' }.to_json,
      correlation_id: SecureRandom.uuid
    )
    Resolv.stubs(:getaddresses).returns(['93.184.216.34'])
  end

  test 'skips sync when memory endpoint is not configured' do
    AutomyraBridge::MemorySync.new({}).sync_event(@event)

    assert_equal 'skipped', @event.reload.sync_status
  end

  test 'syncs memory event through OpenAI-compatible chat endpoint' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ id: 'chatcmpl-test', choices: [{ message: { content: { ok: true, result: { details: { id: 'memory-123' } } }.to_json } }] }.to_json)
    Net::HTTP.stubs(:start).returns(response)

    AutomyraBridge::MemorySync.new(
      'memory_endpoint' => 'https://memory.test/v1/chat/completions',
      'memory_token' => 'secret',
      'memory_model' => 'manifest/auto'
    ).sync_event(@event)

    assert_equal 'synced', @event.reload.sync_status
    assert_equal 'memory-123', @event.external_memory_id
  end

  test 'marks sync failed when external memory call fails' do
    Net::HTTP.stubs(:start).raises(StandardError, 'memory unavailable')

    AutomyraBridge::MemorySync.new(
      'memory_endpoint' => 'https://memory.test/v1/chat/completions',
      'memory_token' => 'secret'
    ).sync_event(@event)

    assert_equal 'failed', @event.reload.sync_status
    assert_match(/memory unavailable/, @event.sync_error)
  end

  test 'recalls memory through OpenAI-compatible chat endpoint' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ id: 'chatcmpl-recall', choices: [{ message: { content: { results: [{ text: 'unique-redmica-memory-sync-event' }] }.to_json } }] }.to_json)
    Net::HTTP.stubs(:start).returns(response)

    result = AutomyraBridge::MemorySync.new(
      'memory_endpoint' => 'https://memory.test/v1/chat/completions',
      'memory_token' => 'secret'
    ).recall('unique-redmica-memory-sync-event')

    assert_equal 'unique-redmica-memory-sync-event', result['results'].first['text']
  end
end
