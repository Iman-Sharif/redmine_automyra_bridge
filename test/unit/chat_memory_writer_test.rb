require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatMemoryWriterTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    skip 'memory events table is not available' unless defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

    AutomyraBridgeMemoryEvent.delete_all
    AutomyraBridgeChatThread.delete_all if defined?(AutomyraBridgeChatThread)
    AutomyraBridgeChatMessage.delete_all if defined?(AutomyraBridgeChatMessage)
    AutomyraBridgeJob.delete_all if defined?(AutomyraBridgeJob)

    @user = User.find(2)
    @project = Project.find(1)
    @thread = AutomyraBridgeChatThread.create!(
      user: @user,
      project: @project,
      thread_kind: 'global',
      page_key: 'global',
      status: 'active'
    )
  end

  test 'writes memory event for user message' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Hello Automyra',
      status: 'sent'
    )

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    assert_equal 'chat_message', memory.event_type
    assert_equal 'user', memory.role
    assert_equal 'AutomyraBridgeChatThread', memory.container_type
    assert_equal @thread.id, memory.container_id
    assert_equal 'Hello Automyra', memory.content
    assert_nil memory.correlation_id
  end

  test 'writes memory event for assistant message' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'assistant',
      content: 'Hello! How can I help?',
      status: 'sent'
    )

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    assert_equal 'chat_reply', memory.event_type
    assert_equal 'assistant', memory.role
    assert_equal 'Hello! How can I help?', memory.content
  end

  test 'writes memory event for system message' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'system',
      content: 'System initialized',
      status: 'sent'
    )

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    assert_equal 'chat_system', memory.event_type
    assert_equal 'system', memory.role
    assert_equal 'System initialized', memory.content
  end

  test 'includes correlation_id from linked job' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Message with job',
      status: 'sent'
    )

    job = AutomyraBridgeJob.create!(
      user: @user,
      project: @project,
      status: 'queued',
      correlation_id: 'test-correlation-123',
      idempotency_key: SecureRandom.uuid,
      request_payload: {}.to_json,
      source_type: 'AutomyraBridgeChatMessage',
      source_id: message.id
    )
    message.update!(job: job)

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    assert_equal 'test-correlation-123', memory.correlation_id
  end

  test 'handles nil correlation_id when no job linked' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Message without job',
      status: 'sent'
    )

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    assert_nil memory.correlation_id
  end

  test 'does not write memory event for unknown role' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Valid message',
      status: 'sent'
    )

    # Temporarily set an invalid role
    message.role = 'invalid_role'

    assert_no_difference('AutomyraBridgeMemoryEvent.count') do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end
  end

  test 'does not write when memory events table does not exist' do
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Test message',
      status: 'sent'
    )

    AutomyraBridgeMemoryEvent.stubs(:table_exists?).returns(false)

    assert_no_difference('AutomyraBridgeMemoryEvent.count') do
      AutomyraBridge::ChatMemoryWriter.write_message(message, @thread)
    end
  end

  test 'writes compact assistant run summary payload shape' do
    seed_message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'What did we decide about issue 42?',
      status: 'sent'
    )

    job = AutomyraBridgeJob.create!(
      user: @user,
      project: @project,
      status: 'succeeded',
      correlation_id: 'run-summary-correlation',
      idempotency_key: SecureRandom.uuid,
      request_payload: { body: 'What did we decide about issue 42?' }.to_json,
      source_type: 'AutomyraBridgeChatMessage',
      source_id: seed_message.id
    )

    run = defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists? ? AutomyraBridgeRun.create!(user: @user, project: @project, source_type: 'AutomyraBridgeChatMessage', source_id: 123, status: 'completed') : nil
    final_answer = 'A' * 700

    assert_difference('AutomyraBridgeMemoryEvent.count', 1) do
      AutomyraBridge::ChatMemoryWriter.write_run_summary(
        job: job,
        thread: @thread,
        run: run,
        final_answer: final_answer,
        tool_calls: %w[issue_search issue_search context_current_page],
        timeline: [{ type: 'started' }, { type: 'tool_call', name: 'issue_search' }, { type: 'completed' }],
        page_context: { page_type: 'issue', page_id: '42' },
        user_query: 'What did we decide about issue 42?'
      )
    end

    memory = AutomyraBridgeMemoryEvent.order(:id).last
    payload = memory.payload_hash
    assert_equal 'assistant_run_summary', memory.event_type
    assert_equal 'system', memory.role
    assert_equal run&.id, payload['run_id']
    assert_equal @thread.id, payload['thread_id']
    assert_equal @user.id, payload['user_id']
    assert_equal 'issue', payload['page_type']
    assert_equal '42', payload['page_id']
    assert_equal 200, payload['final_answer'].length
    assert_equal 'What did we decide about issue 42?', payload['user_query']
    assert_equal %w[issue_search context_current_page], payload['tool_calls']
    assert_equal(%w[started tool_call completed], payload['timeline'].map { |event| event['type'] })
    assert_includes memory.content, "Run ID: #{run&.id || 'unknown'}"
    assert_includes memory.content, 'Query: What did we decide about issue 42?'
    assert_includes memory.content, 'Answer: '
    assert_includes memory.content, 'Tools used: issue_search, context_current_page'
    assert_includes memory.content, 'Page context: issue:42'
  end
end
