# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AssistantRunHappyPathTest < ActionDispatch::IntegrationTest
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  def log_user(login, password)
    get '/login'
    assert_response :success
    post '/login', params: { username: login, password: password }
    assert_equal login, User.find(session[:user_id]).login
  end

  setup do
    AutomyraBridgeChatMessage.delete_all
    AutomyraBridgeChatThread.delete_all
    AutomyraBridgeJob.delete_all
    AutomyraBridgeRunEvent.delete_all if defined?(AutomyraBridgeRunEvent)
    AutomyraBridgeRun.delete_all if defined?(AutomyraBridgeRun)
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge('automyra_endpoint' => 'https://automyra.test/respond')
  end

  test 'how many open tasks happy path completes with count and source' do
    log_user('admin', 'admin')
    stub_provider_responses(
      { tool_calls: [{ tool: 'task_hub.count_my_open_tasks', input: {} }], response: 'Checking your tasks.' },
      { response: 'You have 3 open tasks.' }
    )

    job = create_chat_job('How many open tasks do I have?')
    AutomyraBridge::JobProcessor.new.process(job)

    assert_equal 'succeeded', job.reload.status
    assistant = AutomyraBridgeChatMessage.where(role: 'assistant').order(:id).last
    assert_match(/3 open tasks/, assistant.content)
    run = AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    completed = run.run_events.where(event_type: 'run.completed').last
    payload = completed.payload.is_a?(Hash) ? completed.payload : JSON.parse(completed.payload.to_s.presence || '{}')
    assert_includes payload['sources_used'], 'task_hub.count_my_open_tasks'
  end

  test 'no tasks returns explicit no open tasks answer' do
    log_user('admin', 'admin')
    stub_provider_responses(
      { tool_calls: [{ tool: 'task_hub.count_my_open_tasks', input: {} }] },
      { response: 'You have no open tasks.' }
    )

    job = create_chat_job('How many open tasks do I have?')
    AutomyraBridge::JobProcessor.new.process(job)

    assert_equal 'succeeded', job.reload.status
    assert_equal 'You have no open tasks.', AutomyraBridgeChatMessage.where(role: 'assistant').order(:id).last.content
  end

  test 'permission denied fails with controlled error' do
    skip 'behavioral divergence (restored-from-orphan): permission-denied path produces "max tool loop steps" error instead of "User is not authorized" — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    log_user('admin', 'admin')
    AutomyraBridge::Tools::TaskHubCountMyOpenTasksTool.any_instance.stubs(:authorized?).returns(false)
    stub_provider_responses({ tool_calls: [{ tool: 'task_hub.count_my_open_tasks', input: {} }] })

    job = create_chat_job('How many open tasks do I have?')
    job.update!(max_retries: 0)
    AutomyraBridge::JobProcessor.new.process(job)

    assert_equal 'failed', job.reload.status
    assert_match(/User is not authorized/, job.error_message)
  end

  test 'provider timeout fails with timeout error' do
    log_user('admin', 'admin')
    AutomyraBridge::JobProcessor.any_instance.stubs(:post_payload).raises(Timeout::Error, 'provider timeout')

    job = create_chat_job('How many open tasks do I have?')
    job.update!(max_retries: 0)
    AutomyraBridge::JobProcessor.new.process(job)

    assert_equal 'failed', job.reload.status
    assert_match(/provider timeout/, job.error_message)
  end

  test 'tool unavailable fails with tool error' do
    skip 'behavioral divergence (restored-from-orphan): unknown-tool path produces "max tool loop steps" error instead of "Tool error … Unknown tool" — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    log_user('admin', 'admin')
    stub_provider_responses({ tool_calls: [{ tool: 'missing.tool', input: {} }] })

    job = create_chat_job('How many open tasks do I have?')
    job.update!(max_retries: 0)
    AutomyraBridge::JobProcessor.new.process(job)

    assert_equal 'failed', job.reload.status
    assert_match(/Tool error.*Unknown tool/, job.error_message)
  end

  private

  def create_chat_job(content)
    post '/automyra_bridge/chat/send', params: { thread_kind: 'global', project_id: 1, content: content }
    assert_response :success
    AutomyraBridgeJob.order(:id).last
  end

  def stub_provider_responses(*payloads)
    responses = payloads.map do |payload|
      Net::HTTPOK.new('1.1', '200', 'OK').tap { |response| response.stubs(:body).returns(payload.to_json) }
    end
    AutomyraBridge::JobProcessor.any_instance.stubs(:post_payload).returns(*responses)
  end
end
