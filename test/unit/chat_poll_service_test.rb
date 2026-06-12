require_relative '../test_helper'

class AutomyraBridge::ChatPollServiceTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 1,
      page_key: 'Issue:1',
      status: 'active',
      unread_count: 0
    )
  end

  def teardown
    @thread.chat_messages.destroy_all if @thread.persisted?
    @thread.destroy if @thread.persisted?
  end

  # --- nil / archived thread ---

  def test_nil_thread_returns_empty_result
    result = AutomyraBridge::ChatPollService.poll(nil, since_message_id: 0)
    assert_equal false, result[:has_updates]
    assert_empty result[:new_messages]
    assert_equal 0, result[:unread_count]
    assert_equal 'archived', result[:thread_status]
  end

  def test_archived_thread_returns_empty_result
    @thread.update!(status: 'archived')
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: 0)
    assert_equal false, result[:has_updates]
    assert_empty result[:new_messages]
    assert_equal 0, result[:unread_count]
    assert_equal 'archived', result[:thread_status]
  end

  # --- first poll (no since_message_id) ---

  def test_first_poll_returns_all_messages
    msg1 = create_message(content: 'Hello')
    msg2 = create_message(content: 'World')
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: nil)

    assert_equal true, result[:has_updates]
    assert_equal 2, result[:new_messages].length
    assert_equal msg1.id, result[:new_messages][0][:id]
    assert_equal 'Hello', result[:new_messages][0][:content]
    assert_equal msg2.id, result[:new_messages][1][:id]
    assert_equal 'World', result[:new_messages][1][:content]
    assert_equal 'active', result[:thread_status]
  end

  # --- no updates ---

  def test_poll_with_no_new_messages
    msg = create_message(content: 'Only message')
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: msg.id)

    assert_equal false, result[:has_updates]
    assert_empty result[:new_messages]
    assert_equal 'active', result[:thread_status]
  end

  # --- new messages detected ---

  def test_poll_detects_new_messages_since_id
    older = create_message(content: 'Older')
    newer = create_message(content: 'Newer')
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: older.id)

    assert_equal true, result[:has_updates]
    assert_equal 1, result[:new_messages].length
    assert_equal newer.id, result[:new_messages][0][:id]
    assert_equal 'Newer', result[:new_messages][0][:content]
    assert_equal 'active', result[:thread_status]
  end

  def test_poll_returns_updated_pending_message_when_id_is_not_newer_than_cursor
    original_time = Time.zone.parse('2025-01-01 10:00:00 UTC')
    cursor_time = Time.zone.parse('2025-01-01 10:05:00 UTC')
    updated_time = Time.zone.parse('2025-01-01 10:10:00 UTC')
    pending = create_message(content: 'Thinking...', role: 'assistant', status: 'pending')
    newer = create_message(content: 'Later message', role: 'user', status: 'sent')

    pending.update_columns(created_at: original_time, updated_at: updated_time)
    newer.update_columns(created_at: cursor_time, updated_at: cursor_time)

    result = AutomyraBridge::ChatPollService.poll(
      @thread,
      since_message_id: newer.id,
      since_updated_at: cursor_time.iso8601(3)
    )

    assert_equal true, result[:has_updates]
    assert_equal [pending.id], result[:new_messages].map { |message| message[:id] }
    assert_equal 'pending', result[:new_messages].first[:status]
    assert_equal updated_time.utc.iso8601(3), result[:new_messages].first[:updated_at]
  end

  def test_poll_since_updated_at_path_returns_updated_message_without_since_message_id
    cursor_time = Time.zone.parse('2025-01-01 11:00:00 UTC')
    older = create_message(content: 'Already seen', role: 'assistant', status: 'pending')
    updated = create_message(content: 'Updated pending bubble', role: 'assistant', status: 'pending')

    older.update_columns(created_at: cursor_time - 10.minutes, updated_at: cursor_time - 5.minutes)
    updated.update_columns(created_at: cursor_time - 9.minutes, updated_at: cursor_time + 1.minute)

    result = AutomyraBridge::ChatPollService.poll(@thread, since_updated_at: cursor_time.iso8601(3))

    assert_equal true, result[:has_updates]
    assert_equal [updated.id], result[:new_messages].map { |message| message[:id] }
    assert_equal 'Updated pending bubble', result[:new_messages].first[:content]
  end

  def test_poll_deduplicates_message_matching_id_and_updated_at_cursors
    cursor_time = Time.zone.parse('2025-01-01 12:00:00 UTC')
    old_message = create_message(content: 'Old')
    overlapping = create_message(content: 'New and updated', role: 'assistant', status: 'pending')

    old_message.update_columns(created_at: cursor_time - 10.minutes, updated_at: cursor_time - 10.minutes)
    overlapping.update_columns(created_at: cursor_time + 1.minute, updated_at: cursor_time + 2.minutes)

    result = AutomyraBridge::ChatPollService.poll(
      @thread,
      since_message_id: old_message.id,
      since_updated_at: cursor_time.iso8601(3)
    )

    assert_equal [overlapping.id], result[:new_messages].map { |message| message[:id] }
  end

  def test_poll_with_since_updated_at_returns_empty_when_no_messages_changed
    cursor_time = Time.zone.parse('2025-01-01 13:00:00 UTC')
    message = create_message(content: 'Unchanged')
    message.update_columns(created_at: cursor_time - 10.minutes, updated_at: cursor_time - 5.minutes)

    result = AutomyraBridge::ChatPollService.poll(@thread, since_updated_at: cursor_time.iso8601(3))

    assert_equal false, result[:has_updates]
    assert_empty result[:new_messages]
    assert_equal message.id, result[:last_message_id]
    assert_equal message.updated_at.utc.iso8601(3), result[:last_seen_update_at]
  end

  def test_poll_ignores_invalid_since_updated_at_for_backwards_compatibility
    older = create_message(content: 'Older')
    newer = create_message(content: 'Newer')

    result = AutomyraBridge::ChatPollService.poll(
      @thread,
      since_message_id: older.id,
      since_updated_at: 'not-a-time'
    )

    assert_equal [newer.id], result[:new_messages].map { |message| message[:id] }
  end

  # --- empty thread ---

  def test_empty_thread_returns_no_updates
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: nil)
    assert_equal false, result[:has_updates]
    assert_empty result[:new_messages]
    assert_equal 'active', result[:thread_status]
  end

  # --- message hash shape ---

  def test_message_hash_contains_required_fields
    proposal = AutomyraBridgeActionProposal.create!(
      user: @user,
      chat_thread: @thread,
      action_type: 'create_issue',
      status: 'pending',
      content: 'Test proposal'
    )
    msg = create_message(
      content: 'Test',
      role: 'assistant',
      status: 'delivered',
      proposal: proposal
    )
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: nil)
    hash = result[:new_messages].first

    assert_equal msg.id, hash[:id]
    assert_equal 'assistant', hash[:role]
    assert_equal 'Test', hash[:content]
    assert_equal 'delivered', hash[:status]
    assert hash[:created_at].present?
    assert_equal proposal.id, hash[:proposal_id]

    proposal.destroy
  end

  # --- unread count ---

  def test_unread_count_reflected_in_result
    @thread.update!(unread_count: 3)
    result = AutomyraBridge::ChatPollService.poll(@thread, since_message_id: nil)
    assert_equal 3, result[:unread_count]
  end

  private

  def create_message(content:, role: 'user', status: 'pending', proposal: nil)
    AutomyraBridgeChatMessage.create!(
      chat_thread: @thread,
      user: @user,
      role: role,
      content: content,
      status: status,
      proposal: proposal
    )
  end
end
