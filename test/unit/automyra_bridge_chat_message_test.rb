require_relative '../test_helper'

class AutomyraBridgeChatMessageTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @chat_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      title: 'Test Thread'
    )
    @message = AutomyraBridgeChatMessage.new(
      chat_thread: @chat_thread,
      user: @user,
      role: 'user',
      content: 'Test message',
      status: 'pending'
    )
  end

  def teardown
    @message.destroy if @message&.persisted?
    @chat_thread.destroy if @chat_thread&.persisted?
  end

  # Validations

  def test_valid_message
    assert @message.valid?
  end

  def test_requires_chat_thread_id
    @message.chat_thread_id = nil
    assert_not @message.valid?
    assert_includes @message.errors[:chat_thread_id], "can't be blank"
  end

  def test_requires_user_id
    @message.user_id = nil
    assert_not @message.valid?
    assert_includes @message.errors[:user_id], "can't be blank"
  end

  def test_requires_role
    @message.role = nil
    assert_not @message.valid?
    assert_includes @message.errors[:role], "can't be blank"
  end

  def test_requires_content
    @message.content = nil
    assert_not @message.valid?
    assert_includes @message.errors[:content], "can't be blank"
  end

  def test_valid_role_inclusion
    valid_roles = %w[user assistant system]
    valid_roles.each do |role|
      @message.role = role
      assert @message.valid?, "Role '#{role}' should be valid"
    end
  end

  def test_invalid_role_inclusion
    @message.role = 'invalid_role'
    assert_not @message.valid?
    assert_includes @message.errors[:role], 'is not included in the list'
  end

  def test_valid_status_inclusion
    valid_statuses = %w[pending sent delivered failed]
    valid_statuses.each do |status|
      @message.status = status
      assert @message.valid?, "Status '#{status}' should be valid"
    end
  end

  def test_invalid_status_inclusion
    @message.status = 'invalid_status'
    assert_not @message.valid?
    assert_includes @message.errors[:status], 'is not included in the list'
  end

  # Status transitions

  def test_mark_sent
    @message.save!
    @message.mark_sent!
    assert_equal 'sent', @message.status
  end

  def test_mark_delivered
    @message.save!
    @message.mark_delivered!
    assert_equal 'delivered', @message.status
  end

  def test_mark_failed
    @message.save!
    @message.mark_failed!('Something went wrong')
    assert_equal 'failed', @message.status
    assert_equal 'Error: Something went wrong', @message.content
  end

  # has_proposal?

  def test_has_proposal_returns_false_when_nil
    @message.proposal_id = nil
    assert_not @message.has_proposal?
  end

  def test_has_proposal_returns_true_when_set
    proposal = AutomyraBridgeActionProposal.create!(
      user: @user,
      chat_thread: @chat_thread,
      action_type: 'create_issue',
      status: 'pending',
      content: 'Test proposal'
    )
    @message.proposal = proposal
    assert @message.has_proposal?
    proposal.destroy
  end

  # Associations

  def test_belongs_to_chat_thread
    @message.save!
    assert_equal @chat_thread, @message.chat_thread
  end

  def test_belongs_to_user
    assert_equal @user, @message.user
  end

  def test_optional_job_association
    @message.save!
    @message.job = nil
    assert_nil @message.job
    assert @message.valid?
  end

  def test_optional_proposal_association
    @message.save!
    @message.proposal = nil
    assert_nil @message.proposal
    assert @message.valid?
  end

  # Scopes

  def test_by_thread_scope
    other_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      title: 'Other Thread'
    )
    @message.save!

    other_message = AutomyraBridgeChatMessage.create!(
      chat_thread: other_thread,
      user: @user,
      role: 'user',
      content: 'Other message',
      status: 'pending'
    )

    thread_messages = AutomyraBridgeChatMessage.by_thread(@chat_thread.id)
    assert_includes thread_messages, @message
    assert_not_includes thread_messages, other_message

    other_message.destroy
    other_thread.destroy
  end

  def test_user_messages_scope
    @message.role = 'user'
    @message.save!

    assistant_message = AutomyraBridgeChatMessage.create!(
      chat_thread: @chat_thread,
      user: @user,
      role: 'assistant',
      content: 'Assistant response',
      status: 'pending'
    )

    user_messages = AutomyraBridgeChatMessage.user_messages
    assert_includes user_messages, @message
    assert_not_includes user_messages, assistant_message

    assistant_message.destroy
  end

  def test_assistant_messages_scope
    @message.role = 'assistant'
    @message.save!

    user_message = AutomyraBridgeChatMessage.create!(
      chat_thread: @chat_thread,
      user: @user,
      role: 'user',
      content: 'User message',
      status: 'pending'
    )

    assistant_messages = AutomyraBridgeChatMessage.assistant_messages
    assert_includes assistant_messages, @message
    assert_not_includes assistant_messages, user_message

    user_message.destroy
  end

  def test_pending_scope
    @message.status = 'pending'
    @message.save!

    sent_message = AutomyraBridgeChatMessage.create!(
      chat_thread: @chat_thread,
      user: @user,
      role: 'assistant',
      content: 'Sent message',
      status: 'sent'
    )

    pending_messages = AutomyraBridgeChatMessage.pending
    assert_includes pending_messages, @message
    assert_not_includes pending_messages, sent_message

    sent_message.destroy
  end

  def test_failed_scope
    @message.status = 'failed'
    @message.save!

    pending_message = AutomyraBridgeChatMessage.create!(
      chat_thread: @chat_thread,
      user: @user,
      role: 'assistant',
      content: 'Pending message',
      status: 'pending'
    )

    failed_messages = AutomyraBridgeChatMessage.failed
    assert_includes failed_messages, @message
    assert_not_includes failed_messages, pending_message

    pending_message.destroy
  end
end