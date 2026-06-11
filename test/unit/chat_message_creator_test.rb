require File.expand_path('../test_helper', __dir__)

class ChatMessageCreatorTest < ActiveSupport::TestCase
  fixtures :users, :projects

  def setup
    @user = users(:users_001)
    @project = projects(:projects_001)
    @other_user = users(:users_002)
    @thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 1,
      page_key: 'Issue:1',
      project: @project,
      unread_count: 0
    )
    @job = AutomyraBridgeJob.create!(
      user: @user,
      project: @project,
      status: 'queued',
      source_type: 'AutomyraBridgeChatMessage',
      source_id: 0,
      request_payload: '{}',
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid
    )
  end

  def teardown
    AutomyraBridgeAuditEvent.where('action LIKE ?', 'chat%').destroy_all
    AutomyraBridgeChatMessage.where(chat_thread_id: @thread.id).destroy_all
    @thread.destroy
    @job.destroy if @job.persisted?
  end

  def test_create_user_message_creates_message_with_correct_attributes
    message = AutomyraBridge::ChatMessageCreator.create_user_message!(@user, @thread, 'Hello!')

    assert_not_nil message
    assert_equal @thread.id, message.chat_thread_id
    assert_equal @user.id, message.user_id
    assert_equal 'user', message.role
    assert_equal 'Hello!', message.content
    assert_equal 'sent', message.status
  end

  def test_create_user_message_does_not_increment_unread_for_user
    @thread.update!(unread_count: 0)
    AutomyraBridge::ChatMessageCreator.create_user_message!(@user, @thread, 'Hello!')
    @thread.reload

    assert_equal 0, @thread.unread_count
  end

  def test_create_user_message_records_audit_event
    message = AutomyraBridge::ChatMessageCreator.create_user_message!(@user, @thread, 'Hello!')

    event = AutomyraBridgeAuditEvent.find_by(action: 'chat_message_sent')
    assert_not_nil event
    assert_equal @user, event.user
    assert_equal @project.id, event.project_id
    details = JSON.parse(event.details)
    assert_equal message.id, details['message_id']
    assert_equal @thread.id, details['thread_id']
    assert_equal 'user', details['role']
  end

  def test_create_assistant_placeholder_creates_message_with_pending_status
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)

    assert_not_nil message
    assert_equal @thread.id, message.chat_thread_id
    assert_equal @user.id, message.user_id
    assert_equal 'assistant', message.role
    assert_equal '', message.content
    assert_equal 'pending', message.status
  end

  def test_create_assistant_placeholder_links_to_job
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)

    assert_equal @job.id, message.job_id
  end

  def test_create_assistant_placeholder_increments_unread_count
    @thread.update!(unread_count: 0)
    AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)
    @thread.reload

    assert_equal 1, @thread.unread_count
  end

  def test_update_assistant_message_updates_content_and_status
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)
    proposal = create_proposal

    updated = AutomyraBridge::ChatMessageCreator.update_assistant_message!(
      message, 'Here is the answer', proposal.id
    )

    assert_equal 'Here is the answer', updated.content
    assert_equal 'delivered', updated.status
  end

  def test_update_assistant_message_links_proposal
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)
    proposal = create_proposal

    updated = AutomyraBridge::ChatMessageCreator.update_assistant_message!(
      message, 'Here is the answer', proposal.id
    )

    assert_equal proposal.id, updated.proposal_id
  end

  def test_update_assistant_message_increments_unread_on_delivery
    @thread.update!(unread_count: 0)
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)
    proposal = create_proposal

    AutomyraBridge::ChatMessageCreator.update_assistant_message!(
      message, 'Here is the answer', proposal.id
    )
    @thread.reload

    assert_equal 1, @thread.unread_count
  end

  def test_update_assistant_message_records_audit_event
    message = AutomyraBridge::ChatMessageCreator.create_assistant_placeholder!(@thread, @job)
    proposal = create_proposal

    AutomyraBridge::ChatMessageCreator.update_assistant_message!(
      message, 'Here is the answer', proposal.id
    )

    event = AutomyraBridgeAuditEvent.find_by(action: 'chat_message_sent')
    assert_not_nil event
    assert_equal @user, event.user
    assert_equal @project.id, event.project_id
    details = JSON.parse(event.details)
    assert_equal message.id, details['message_id']
    assert_equal @thread.id, details['thread_id']
    assert_equal 'assistant', details['role']
    assert_equal proposal.id, details['proposal_id']
  end

  def test_update_assistant_message_returns_original_if_not_pending
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: 'assistant',
      content: 'Already delivered',
      status: 'delivered'
    )
    proposal = create_proposal

    result = AutomyraBridge::ChatMessageCreator.update_assistant_message!(
      message, 'New content', proposal.id
    )

    assert_equal 'Already delivered', result.reload.content
    assert_equal 'delivered', result.status
  end

  def test_create_system_message_creates_message_with_correct_attributes
    message = AutomyraBridge::ChatMessageCreator.create_system_message!(@thread, 'System error occurred')

    assert_not_nil message
    assert_equal @thread.id, message.chat_thread_id
    assert_equal @user.id, message.user_id
    assert_equal 'system', message.role
    assert_equal 'System error occurred', message.content
    assert_equal 'delivered', message.status
  end

  def test_create_system_message_increments_unread_count
    @thread.update!(unread_count: 0)
    AutomyraBridge::ChatMessageCreator.create_system_message!(@thread, 'System error')
    @thread.reload

    assert_equal 1, @thread.unread_count
  end

  def test_create_assistant_reply_creates_new_delivered_message
    proposal = create_proposal

    message = AutomyraBridge::ChatMessageCreator.create_assistant_reply!(
      @thread, 'Direct reply', proposal.id
    )

    assert_not_nil message
    assert_equal @thread.id, message.chat_thread_id
    assert_equal @user.id, message.user_id
    assert_equal 'assistant', message.role
    assert_equal 'Direct reply', message.content
    assert_equal 'delivered', message.status
  end

  def test_create_assistant_reply_links_proposal
    proposal = create_proposal

    message = AutomyraBridge::ChatMessageCreator.create_assistant_reply!(
      @thread, 'Direct reply', proposal.id
    )

    assert_equal proposal.id, message.proposal_id
  end

  def test_create_assistant_reply_increments_unread_count
    @thread.update!(unread_count: 0)
    proposal = create_proposal

    AutomyraBridge::ChatMessageCreator.create_assistant_reply!(
      @thread, 'Direct reply', proposal.id
    )
    @thread.reload

    assert_equal 1, @thread.unread_count
  end

  def test_create_assistant_reply_records_audit_event
    proposal = create_proposal

    message = AutomyraBridge::ChatMessageCreator.create_assistant_reply!(
      @thread, 'Direct reply', proposal.id
    )

    event = AutomyraBridgeAuditEvent.find_by(action: 'chat_message_sent')
    assert_not_nil event
    assert_equal @user, event.user
    assert_equal @project.id, event.project_id
    details = JSON.parse(event.details)
    assert_equal message.id, details['message_id']
    assert_equal @thread.id, details['thread_id']
    assert_equal 'assistant', details['role']
    assert_equal proposal.id, details['proposal_id']
  end

  private

  def create_proposal
    AutomyraBridgeActionProposal.create!(
      automyra_bridge_job: @job,
      project: @project,
      user: @user,
      action_type: 'create_issue',
      status: 'pending',
      request_payload: '{}'
    )
  end
end
