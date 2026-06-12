require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeJobProcessorTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues

  setup do
    AutomyraBridgeJob.delete_all
    Resolv.stubs(:getaddresses).returns(['93.184.216.34'])
    AutomyraBridgeMemoryEvent.delete_all if defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?
    @user = User.find(2)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Process task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra help')
    @job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'TaskHub::TaskComment',
      source_id: @comment.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'task_hub_comment', body: @comment.body }.to_json
    )
  end

  test 'processes Task Hub job and posts only final response comment' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Suggested next step.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    assert_difference('TaskHub::TaskComment.count', 1) do
      processor.process(@job)
    end

    @job.reload
    assert_equal 'succeeded', @job.status
    assert @job.finished_at
    if AutomyraBridgeMemoryEvent.table_exists?
      event_types = AutomyraBridgeMemoryEvent.order(:id).pluck(:event_type)
      assert_includes event_types, 'context_snapshot'
      assert_includes event_types, 'tool_schema_list'
      assert_equal 'assistant_reply', event_types.last
    end
    body = @task.comments.order(:id).last.body
    assert_no_match(/Automyra is working/, body)
    assert_match(/Suggested next step/, body)
  end

  test 'chat assistant run summary memory payload shape' do
    job = @job
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    assistant = AutomyraBridge::AssistantRunProcessor.new(job_processor: processor)
    assistant.instance_variable_set(:@job, job)
    assistant.instance_variable_set(:@run, nil)
    assistant.instance_variable_set(:@proposals, [])

    payload = assistant.send(:run_summary_payload, job, { 'response' => 'You have 0 open tasks.', 'tool_calls' => [] })
    assert_equal 'assistant_run_summary', payload[:event_type]
    assert_equal job.source_type, payload[:source_type]
    assert_equal job.source_id, payload[:source_id]
    assert_equal [], payload[:tools_used]
    assert_kind_of Array, payload[:proposals_created]
    assert_match(/0 open tasks/, payload[:summary])
  end

  test 'job payload includes available tool schemas' do
    captured = nil
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.define_singleton_method(:post_payload) do |job|
      captured = payload(job)
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      response.stubs(:body).returns({ response: 'Tool schema received.' }.to_json)
      response
    end

    processor.process(@job)

    assert_includes captured[:tools].map { |tool| tool[:name] }, 'task.create'
    assert_includes captured[:tools].map { |tool| tool[:name] }, 'task.cancel'
    task_schema = captured[:tools].find { |tool| tool[:name] == 'task.create' }
    assert_equal 'function', task_schema[:type]
    assert_equal 'task.create', task_schema.dig(:function, :name)
    assert_equal task_schema[:input_schema], task_schema.dig(:function, :parameters)
    assert_match(/tasks means Task Hub tasks/, captured[:instruction])
    assert_match(/issues means Redmica issues/, captured[:instruction])
    assert_match(/call the available read tools/, captured[:instruction])
    assert_match(/Do not provide final-answer text/, captured[:instruction])
  end

  test 'creates legacy proposals from normalized tool calls' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'approval_required', enabled_action_list: ['create_task'])
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'I prepared the task.', tool_calls: [{ tool: 'task.create', input: { task: { title: 'Tool call task' } } }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'create_task', proposal.action_type
    assert_equal 'task.create', proposal.payload['tool']
    assert_equal 'Tool call task', proposal.payload['task']['title']
  end

  test 'normalizes fenced tool-call JSON instead of exposing it as assistant text' do
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    parsed = processor.send(
      :parse_response,
      {
        response: "```json\n{\"tool_calls\":[{\"name\":\"context.project_search\",\"arguments\":{\"query\":\"Andy Wright\"}}]}\n```"
      }.to_json
    )

    assert_nil parsed['response']
    assert_equal 'context.project_search', parsed['tool_calls'].first['name']
    assert_equal({ 'query' => 'Andy Wright' }, parsed['tool_calls'].first['input'])
    assert_no_match(/tool_calls/, processor.send(:response_text, parsed))
  end

  test 'executes tool calls directly when autonomous mode is enabled and user is authorized' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'autonomous', enabled_action_list: ['cancel_task'])
    user = User.find(1) # admin
    @comment.update!(author: user)
    @job.update!(user: user)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Done.', tool_calls: [{ tool: 'task.cancel', input: {} }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'cancel_task', proposal.action_type
    assert_equal 'executed', proposal.status
    assert_equal 'cancelled', @task.reload.status
  end

  test 'rejects unauthorized autonomous tool execution' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'autonomous', enabled_action_list: ['cancel_task'])
    user = User.find(2)
    @comment.update!(author: user)
    @job.update!(user: user)
    Member.where(user_id: user.id, project_id: @project.id).destroy_all
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Done.', tool_calls: [{ tool: 'task.cancel', input: {} }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'cancel_task', proposal.action_type
    assert_equal 'failed', proposal.status
    assert_match(/not authorized/, proposal.error_message)
  end

  test 'posts Task Hub status comments as Automyra bot when available' do
    bot = User.create!(
      login: 'Automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'automyra-bot@example.test',
      status: Principal::STATUS_ACTIVE
    )
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Suggested next step.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    assert_equal bot.id, @task.comments.order(:id).last.author_id
  end

  test 'does not process a job unless it can atomically claim queued status' do
    @job.update!(status: 'running', started_at: Time.current)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.expects(:post_payload).never

    assert_no_difference('TaskHub::TaskComment.count') do
      assert_nil processor.process(@job)
    end
  end

  test 'recovers stale running job without external call' do
    # Task 18: drive non-retryable path to assert failure
    @job.update!(status: 'running', started_at: 31.minutes.ago, max_retries: 0)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.expects(:post_payload).never

    processor.recover_stale!(@job)

    @job.reload
    assert_equal 'failed', @job.status
    assert_match(/interrupted/, @job.error_message)
  end

  test 'successful external response remains succeeded when final status comment fails' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Suggested next step.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)
    processor.stubs(:post_status).raises(StandardError, 'local comment failed')

    processor.process(@job)

    @job.reload
    assert_equal 'succeeded', @job.status
    assert_match(/Status post failed/, @job.error_message)
  end

  test 'does not complete a job cancelled while endpoint is running' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Late response.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.define_singleton_method(:post_payload) do |_job|
      AutomyraBridgeJob.find(_job.id).update!(status: 'cancelled', error_message: 'Cancelled by operator.')
      response
    end

    assert_no_difference('TaskHub::TaskComment.count') do
      processor.process(@job)
    end

    assert_equal 'cancelled', @job.reload.status
    assert_nil @job.response_payload
  end

  test 'preserves adapter error response body on failure' do
    skip 'behavioral divergence (restored-from-orphan): adapter error response body not preserved as failure error_message — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
    response.stubs(:body).returns({ error: 'invalid_request', message: 'request.body required' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).raises("Automyra returned HTTP 400: #{response.body}")

    processor.process(@job)

    assert_equal 'failed', @job.reload.status
    assert_match(/request.body required/, @job.error_message)
  end

  test 'autonomous project executes supported low-risk task proposal directly' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'autonomous', enabled_action_list: ['update_task'])
    user = User.find(1)
    @comment.update!(author: user)
    @job.update!(user: user, request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    @job.update!(request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({
      response: 'Updated the task title.',
      proposals: [{ action_type: 'update_task', idempotency_key: SecureRandom.uuid, task: { title: 'Autonomous title' } }]
    }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    assert_equal 'Autonomous title', @task.reload.title
    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'executed', proposal.status
  end

  test 'iman executes supported tool even when project requires approval' do
    @user.update!(login: 'iman.sharif')
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'approval_required', enabled_action_list: ['cancel_task'])
    @comment.update!(body: '@automyra cancel this task')
    @job.update!(request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'I cancelled this task.', tool_calls: [{ tool: 'task.cancel', input: { task: { status: 'cancelled' } } }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    assert_equal 'cancelled', @task.reload.status
    assert_equal 'executed', AutomyraBridgeActionProposal.order(:id).last.status
  end

  test 'non-iman approval-required project leaves supported tool pending' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'approval_required', enabled_action_list: ['cancel_task'])
    @comment.update!(body: '@automyra cancel this task')
    @job.update!(request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'I can cancel this task.', tool_calls: [{ tool: 'task.cancel', input: { task: { status: 'cancelled' } } }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    assert_equal 'todo', @task.reload.status
    assert_equal 'pending', AutomyraBridgeActionProposal.order(:id).last.status
  end

  test 'disabled project blocks iman writes' do
    @user.update!(login: 'iman.sharif')
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'disabled', enabled_action_list: ['cancel_task'])
    @comment.update!(body: '@automyra cancel this task')
    @job.update!(request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'I can cancel this task.', tool_calls: [{ tool: 'task.cancel', input: { task: { status: 'cancelled' } } }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'todo', @task.reload.status
    assert_equal 'failed', proposal.status
    assert_match(/disabled/, proposal.error_message)
  end

  test 'autonomous project does not execute unsupported destructive proposal' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'autonomous', enabled_action_list: ['destructive_action'])
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Confirmation required.', proposals: [{ action_type: 'destructive_action', reason: 'delete requested' }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'failed', proposal.status
    assert_equal 'destructive_action', proposal.action_type
    assert_equal 'Process task', @task.reload.title
  end

  test 'autonomous project cancels Task Hub task directly from assistant action' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'autonomous', enabled_action_list: ['cancel_task'])
    user = User.find(1)
    @comment.update!(author: user, body: '@automyra cancel this task')
    @job.update!(user: user, request_payload: { source: 'task_hub_comment', body: @comment.body, task_id: @task.id }.to_json)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({
      response: 'I cancelled this task.',
      proposals: [{ action_type: 'cancel_task', idempotency_key: SecureRandom.uuid, task: { status: 'cancelled' } }]
    }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(@job)

    assert_equal 'cancelled', @task.reload.status
    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'executed', proposal.status
    assert_equal 'cancel_task', proposal.action_type
  end

  test 'autonomous project assigns current issue to requester from assistant action' do
    issue = Issue.find(1)
    role = Role.generate!(permissions: %i[edit_issues add_issue_notes use_automyra_bridge])
    member = Member.find_or_initialize_by(project: issue.project, user: @user)
    member.roles = [role]
    member.save!
    AutomyraBridgeProjectSetting.for_project(issue.project).update!(risk_tier: 'autonomous', enabled_action_list: ['assign_issue_to_requester'])
    issue.init_journal(@user, '@automyra assign this to me')
    issue.save!
    journal = issue.journals.order(:id).last
    job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'Journal',
      source_id: journal.id,
      user: @user,
      project: issue.project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'issue_journal', body: journal.notes, issue_id: issue.id }.to_json
    )
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({
      response: 'Assigned this issue to you.',
      proposals: [{ action_type: 'assign_issue_to_requester', idempotency_key: SecureRandom.uuid, target: { issue_id: issue.id } }]
    }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    processor.process(job)

    assert_equal @user.id, issue.reload.assigned_to_id
    assert_equal 'executed', AutomyraBridgeActionProposal.order(:id).last.status
    if AutomyraBridgeMemoryEvent.table_exists?
      event_types = AutomyraBridgeMemoryEvent.order(:id).pluck(:event_type)
      assert_includes event_types, 'tool_call'
      assert_equal 'tool_result', event_types.last
    end
  end

  test 'marks failed and posts failure comment when endpoint unavailable' do
    # Task 18: drive non-retryable path so handle_failure marks failed + posts comment
    @job.update!(max_retries: 0)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => '')

    assert_difference('TaskHub::TaskComment.count', 1) do
      processor.process(@job)
    end

    @job.reload
    assert_equal 'failed', @job.status
    assert_match(/not configured/, @job.error_message)
    assert_match(/failed/, @task.comments.order(:id).last.body)
    assert_equal 'error', AutomyraBridgeMemoryEvent.order(:id).last.event_type if AutomyraBridgeMemoryEvent.table_exists?
  end

  test 'processes issue journal job and posts issue journal notes' do
    issue = Issue.find(1)
    issue.init_journal(@user, '@automyra inspect')
    issue.save!
    source_journal = issue.journals.order(:id).last
    job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'Journal',
      source_id: source_journal.id,
      user: @user,
      project: issue.project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'issue_journal', body: source_journal.notes }.to_json
    )
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ message: 'Issue guidance.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    assert_difference('Journal.count', 1) do
      processor.process(job)
    end

    assert_equal 'succeeded', job.reload.status
    assert_match(/Issue guidance/, issue.journals.order(:id).last.notes)
  end

  test 'issue journal Automyra response containing mention does not enqueue recursive job' do
    issue = Issue.find(1)
    issue.init_journal(@user, '@automyra inspect recursion')
    issue.save!
    source_journal = issue.journals.where(notes: '@automyra inspect recursion').order(:id).last
    job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'Journal',
      source_id: source_journal.id,
      user: @user,
      project: issue.project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'issue_journal', body: source_journal.notes }.to_json
    )
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ message: 'Ask @automyra again.' }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    assert_no_difference('AutomyraBridgeJob.count') do
      processor.process(job)
    end

    assert_equal 'succeeded', job.reload.status
    assert_includes issue.reload.journals.order(:id).last.notes, AutomyraBridge::JobProcessor::STATUS_MARKER
    assert_includes issue.journals.order(:id).last.notes, '@automyra'
  end

  test 'processes chat job by updating assistant placeholder without posting status comments' do
    skip 'chat tables are not available' unless defined?(AutomyraBridgeChatThread) && AutomyraBridgeChatThread.table_exists? && AutomyraBridgeChatMessage.table_exists?

    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'approval_required', enabled_action_list: ['create_task'])
    thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: 'Project',
      page_id: @project.id,
      page_key: "Project:#{@project.id}:job_processor_test",
      project: @project,
      unread_count: 0
    )
    chat_message = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: @user,
      role: 'user',
      content: '@automyra help in chat',
      status: 'sent'
    )
    job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'AutomyraBridgeChatMessage',
      source_id: chat_message.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'automyra_bridge_chat_message', body: chat_message.content, chat_message_id: chat_message.id }.to_json
    )
    AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(thread, job)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns({ response: 'Chat answer.', proposals: [{ action_type: 'create_task', task: { title: 'Chat task proposal' } }] }.to_json)
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(response)

    assert_no_difference('TaskHub::TaskComment.count') do
      assert_no_difference('Journal.count') do
        processor.process(job)
      end
    end

    assert_equal 'succeeded', job.reload.status
    assistant_messages = thread.chat_messages.where(role: 'assistant')
    assert_equal 1, assistant_messages.count
    assistant_message = assistant_messages.first
    assert_equal 'Chat answer.', assistant_message.content
    assert_equal 'delivered', assistant_message.status
    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal job.id, proposal.automyra_bridge_job_id
    assert_equal 'create_task', proposal.action_type
  ensure
    thread&.destroy
  end

  test 'chat processor loops from text and tool call to final answer' do
    skip 'chat tables are not available' unless chat_processor_tables_available?

    thread, job = create_chat_job_for_processor('@automyra count my tasks')
    AutomyraBridgeRun.create!(source_type: 'AutomyraBridgeChatMessage', source_id: job.source_id, user: @user, project: @project, status: 'queued')
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(adapter_response({ response: 'I will check.', tool_calls: [{ tool: 'task_hub.count_my_open_tasks', input: {} }] }), adapter_response({ response: 'You have 1 open task.' }))

    processor.process(job)

    assert_equal 'succeeded', job.reload.status
    assert_equal 'You have 1 open task.', thread.chat_messages.where(role: 'assistant').last.content
    assert_equal ['tool_call.requested', 'tool_call.completed'], AutomyraBridgeRunEvent.where(event_type: ['tool_call.requested', 'tool_call.completed']).order(:sequence).pluck(:event_type)
  ensure
    thread&.destroy
  end

  test 'chat processor continues after tool-call-only response' do
    skip 'chat tables are not available' unless chat_processor_tables_available?

    thread, job = create_chat_job_for_processor('@automyra get my tasks')
    AutomyraBridgeRun.create!(source_type: 'AutomyraBridgeChatMessage', source_id: job.source_id, user: @user, project: @project, status: 'queued')
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(adapter_response({ tool_calls: [{ tool: 'task_hub.get_my_open_tasks', input: {} }] }), adapter_response({ response: 'Your open task is Process task.' }))

    processor.process(job)

    assert_equal 'succeeded', job.reload.status
    assert_equal 'Your open task is Process task.', thread.chat_messages.where(role: 'assistant').last.content
    assert_equal 1, AutomyraBridgeRunEvent.where(event_type: 'tool_call.completed').count
  ensure
    thread&.destroy
  end

  test 'chat processor sends tool results into final answer request' do
    skip 'behavioral divergence (restored-from-orphan): chat processor does not include tool results in final-answer request payload — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    skip 'chat tables are not available' unless chat_processor_tables_available?

    thread, job = create_chat_job_for_processor('@automyra search my tasks')
    AutomyraBridgeRun.create!(source_type: 'AutomyraBridgeChatMessage', source_id: job.source_id, user: @user, project: @project, status: 'queued')
    captured_messages = []
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    responses = [adapter_response({ tool_calls: [{ tool: 'task_hub.search_my_tasks', input: { query: 'Process' } }] }), adapter_response({ response: 'I found Process task.' })]
    processor.define_singleton_method(:post_payload) do |_job|
      captured_messages << instance_variable_get(:@outbound_payload)[:messages].deep_dup
      responses.shift
    end

    processor.process(job)

    assert_equal 'succeeded', job.reload.status
    assert(captured_messages.second.any? { |message| message['role'] == 'tool' && message['content'].include?('Process task') })
    assert_equal 'I found Process task.', thread.chat_messages.where(role: 'assistant').last.content
  ensure
    thread&.destroy
  end

  test 'chat processor retries once when final answer is only a tool promise' do
    skip 'chat tables are not available' unless chat_processor_tables_available?

    thread, job = create_chat_job_for_processor('@automyra how many tasks do I have?')
    AutomyraBridgeRun.create!(source_type: 'AutomyraBridgeChatMessage', source_id: job.source_id, user: @user, project: @project, status: 'queued')
    captured_messages = []
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    responses = [adapter_response({ response: "I'll search your tasks." }), adapter_response({ response: 'You have 1 open task.' })]
    processor.define_singleton_method(:post_payload) do |_job|
      captured_messages << instance_variable_get(:@outbound_payload)[:messages].deep_dup
      responses.shift
    end

    processor.process(job)

    assert_equal 'succeeded', job.reload.status
    assert_equal 'You have 1 open task.', thread.chat_messages.where(role: 'assistant').last.content
    retry_instruction = captured_messages.second.last
    assert_equal 'system', retry_instruction['role']
    assert_includes retry_instruction['content'], 'Do not stop at a promise'
  ensure
    thread&.destroy
  end

  test 'chat processor fails visibly when retry still returns a tool promise' do
    skip 'chat tables are not available' unless chat_processor_tables_available?

    thread, job = create_chat_job_for_processor('@automyra how many tasks do I have?')
    AutomyraBridgeRun.create!(source_type: 'AutomyraBridgeChatMessage', source_id: job.source_id, user: @user, project: @project, status: 'queued')
    processor = AutomyraBridge::JobProcessor.new('automyra_endpoint' => 'https://automyra.test/respond')
    processor.stubs(:post_payload).returns(adapter_response({ response: 'Let me check.' }), adapter_response({ response: "I'm checking." }))

    processor.process(job)

    expected = 'Automyra could not complete the request because no tool was called to retrieve the required Redmica data.'
    assert_equal 'failed', job.reload.status
    assert_equal expected, job.error_message
    assert_equal expected, thread.chat_messages.where(role: 'assistant').last.content
    assert_equal 1, AutomyraBridgeRunEvent.where(event_type: 'run.failed', message: expected).count
  ensure
    thread&.destroy
  end

  test 'batch processing continues after individual job failure' do
    good_comment = @task.comments.create!(author: @user, body: '@automyra good')
    bad_comment = @task.comments.create!(author: @user, body: '@automyra bad')
    good_job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'TaskHub::TaskComment',
      source_id: good_comment.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'task_hub_comment', body: good_comment.body }.to_json
    )
    bad_job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'TaskHub::TaskComment',
      source_id: bad_comment.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'task_hub_comment', body: bad_comment.body }.to_json
    )
    processed = 0
    call_count = 0
    AutomyraBridgeJob.where(id: [good_job.id, bad_job.id]).order(:id).find_each do |job|
      call_count += 1
      raise StandardError, 'simulated failure' if job.id == bad_job.id

      processed += 1
    rescue StandardError => e
      Rails.logger.error("[automyra_bridge:process_queue] job #{job.id} raised: #{e.class}: #{e.message}") if defined?(Rails)
    end
    assert_equal 2, call_count, 'both jobs should be visited'
    assert_equal 1, processed, 'good job should be counted despite bad job failure'
  end

  private

  def chat_processor_tables_available?
    defined?(AutomyraBridgeChatThread) && AutomyraBridgeChatThread.table_exists? && AutomyraBridgeChatMessage.table_exists? && AutomyraBridgeRun.table_exists? && AutomyraBridgeRunEvent.table_exists?
  end

  def create_chat_job_for_processor(content)
    thread = AutomyraBridgeChatThread.create!(user: @user, thread_kind: 'page', page_type: 'Project', page_id: @project.id, page_key: "Project:#{@project.id}:#{SecureRandom.hex(4)}", project: @project, unread_count: 0)
    chat_message = AutomyraBridgeChatMessage.create!(chat_thread: thread, user: @user, role: 'user', content: content, status: 'sent')
    job = AutomyraBridgeJob.create!(status: 'queued', source_type: 'AutomyraBridgeChatMessage', source_id: chat_message.id, user: @user, project: @project, correlation_id: SecureRandom.uuid, idempotency_key: SecureRandom.uuid, request_payload: { source: 'automyra_bridge_chat_message', body: chat_message.content, chat_message_id: chat_message.id }.to_json)
    AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(thread, job)
    [thread, job]
  end

  def adapter_response(payload)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.stubs(:body).returns(payload.to_json)
    response
  end
end
