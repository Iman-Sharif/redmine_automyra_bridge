require File.expand_path('../test_helper', __dir__)
require File.expand_path('../../app/services/automyra_bridge/chat_job_creator', __dir__)

class AutomyraBridgeChatJobCreatorTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    skip 'chat tables are not available' unless chat_tables_available?

    AutomyraBridgeAuditEvent.where(action: 'chat_job_created').delete_all if defined?(AutomyraBridgeAuditEvent)
    AutomyraBridgeChatMessage.delete_all if defined?(AutomyraBridgeChatMessage)
    AutomyraBridgeChatThread.delete_all if defined?(AutomyraBridgeChatThread)
    AutomyraBridgeJob.delete_all

    @user = User.find(2)
    @project = Project.find(1)
    grant_automyra_bridge_permission!(@user, @project)
    @thread = create_thread(@user, @project)
    @message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'user',
      content: 'Help me understand this page',
      status: 'sent'
    )
    @context = {
      page_type: 'issues/show',
      page_id: '1',
      project_id: @project.id.to_s,
      url_path: '/issues/1',
      page_title: 'Issue page',
      user_id: @user.id
    }
  end

  test 'creates job with chat message source type and source id' do
    job = nil

    assert_difference('AutomyraBridgeJob.count', 1) do
      job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)
    end

    assert_equal 'queued', job.status
    assert_equal 'AutomyraBridgeChatMessage', job.source_type
    assert_equal @message.id, job.source_id
    assert_equal @user, job.user
    assert_equal @project, job.project
    assert_equal 'chat_request', job.payload['action']
    assert_equal @message.id, job.payload['chat_message_id']
    assert_equal @thread.id, job.payload['chat_thread_id']
    assert_equal @message.content, job.payload['body']
    assert_equal @context[:page_type], job.payload['context']['page_type']
    assert_equal 'redmica', job.payload['channel']['channel']
    assert_equal 'chat', job.payload['channel']['source_type']
    assert_equal @thread.id, job.payload['channel']['source_id']
    assert_equal @message.id, job.payload['channel']['message_id']
    assert_equal "redmica-chat-#{@thread.id}", job.payload['channel']['thread_id']
    assert_equal @project.id, job.payload['context_scope']['project_id']
    assert_equal 'AutomyraBridgeChatMessage', job.payload['context_scope']['source_type']
    assert_equal true, job.payload['context_scope']['view_issues']
  end

  test 'creates assistant placeholder message' do
    job = nil

    assert_difference('AutomyraBridgeChatMessage.assistant_messages.count', 1) do
      job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)
    end

    placeholder = AutomyraBridgeChatMessage.assistant_messages.order(:id).last
    assert_equal @thread, placeholder.chat_thread
    assert_equal @thread.user, placeholder.user
    assert_equal 'pending', placeholder.status
    assert_equal '', placeholder.content
    assert_equal job, placeholder.job
  end

  test 'returns nil if user missing permission' do
    other_user = User.find(3)
    thread = create_thread(other_user, @project, page_key: 'Issue:permission-test')
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: other_user,
      role: 'user',
      content: 'No permission',
      status: 'sent'
    )

    assert_no_difference('AutomyraBridgeJob.count') do
      assert_nil AutomyraBridge::ChatJobCreator.create_job_from_message(message, thread, @context)
    end
  end

  test 'returns nil if project missing' do
    thread = create_thread(@user, nil, page_key: 'global-missing-project')
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: @user,
      role: 'user',
      content: 'No project',
      status: 'sent'
    )

    assert_no_difference('AutomyraBridgeJob.count') do
      assert_nil AutomyraBridge::ChatJobCreator.create_job_from_message(message, thread, {})
    end
  end

  test 'uses source type and source id idempotency to prevent duplicate jobs' do
    first_job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)

    assert_no_difference('AutomyraBridgeJob.count') do
      assert_no_difference('AutomyraBridgeChatMessage.assistant_messages.count') do
        second_job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)
        assert_equal first_job.id, second_job.id
      end
    end
  end

  test 'pre-populates slash command tool for open tasks' do
    @message.update!(content: '/Tasks Open')

    job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)

    assert_equal ['task_hub.get_my_open_tasks'], job.payload['tools']
    assert_equal 'tasks', job.payload['slash_command']['command']
    assert_equal ['Open'], job.payload['slash_command']['args']
    assert_includes job.payload['instruction_hint'], 'task_hub.get_my_open_tasks'
  end

  test 'pre-populates slash command tool for my issues' do
    @message.update!(content: '/issues mine')

    job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)

    assert_equal ['issues.get_my_open_issues'], job.payload['tools']
  end

  test 'pre-populates slash command tool for summarize' do
    @message.update!(content: '/summarize')

    job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)

    assert_equal ['context.current_page'], job.payload['tools']
  end

  test 'unknown slash command falls back to normal chat payload' do
    @message.update!(content: '/unknown command')

    job = AutomyraBridge::ChatJobCreator.create_job_from_message(@message, @thread, @context)

    assert_nil job.payload['tools']
    assert_nil job.payload['slash_command']
  end

  private

  def chat_tables_available?
    defined?(AutomyraBridgeChatThread) &&
      defined?(AutomyraBridgeChatMessage) &&
      AutomyraBridgeChatThread.table_exists? &&
      AutomyraBridgeChatMessage.table_exists?
  end

  def create_thread(user, project, page_key: nil)
    AutomyraBridgeChatThread.create!(
      user: user,
      project: project,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: SecureRandom.random_number(100_000),
      page_key: page_key || "Issue:#{SecureRandom.uuid}",
      status: 'active',
      unread_count: 0
    )
  end

  def grant_automyra_bridge_permission!(user, project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
    role = Role.generate!(permissions: %i[use_automyra_bridge view_issues])
    member = Member.find_or_initialize_by(project: project, user: user)
    member.roles = [role]
    member.save!
  end
end
