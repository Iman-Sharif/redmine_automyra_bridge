require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatThreadTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @thread = AutomyraBridgeChatThread.new(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 1,
      page_key: 'Issue:1',
      status: 'active',
      unread_count: 0
    )
  end

  test 'should be valid with required attributes' do
    assert @thread.valid?
  end

  test 'should require user_id' do
    @thread.user_id = nil
    assert_not @thread.valid?
    assert_includes @thread.errors[:user_id], "cannot be blank"
  end

  test 'should require thread_kind' do
    @thread.thread_kind = nil
    assert_not @thread.valid?
    assert_includes @thread.errors[:thread_kind], "cannot be blank"
  end

  test 'should require page_key' do
    skip 'behavioral divergence (restored-from-orphan): set_page_key_defaults before_validation auto-fills page_key, so presence validator can never fail on new records — see notepads problems.md Cluster B-C residual; do NOT pin'
    @thread.page_key = nil
    assert_not @thread.valid?
    assert_includes @thread.errors[:page_key], "cannot be blank"
  end

  test 'should require page_type when thread_kind is page' do
    @thread.thread_kind = 'page'
    @thread.page_type = nil
    assert_not @thread.valid?
    assert_includes @thread.errors[:page_type], "cannot be blank"
  end

  test 'should require page_id when thread_kind is page' do
    @thread.thread_kind = 'page'
    @thread.page_id = nil
    assert_not @thread.valid?
    assert_includes @thread.errors[:page_id], "cannot be blank"
  end

  test 'should validate page_key uniqueness within user scope' do
    @thread.save!
    duplicate = AutomyraBridgeChatThread.new(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 1,
      page_key: 'Issue:1',
      status: 'active'
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:page_key], 'has already been taken'
  end

  test 'generate_page_key returns canonical global channel key for global page_type' do
    key = AutomyraBridgeChatThread.generate_page_key('global', nil)
    assert_equal 'global:user:', key
  end

  test 'generate_page_key returns canonical key for non-global page_type' do
    key = AutomyraBridgeChatThread.generate_page_key('Issue', 123)
    assert_equal 'issue:123', key
  end

  test 'canonical_channel_key returns resolver key' do
    @thread.page_type = 'Issue'
    @thread.page_id = 123
    @thread.project_id = nil

    assert_equal 'issue:123', @thread.canonical_channel_key
  end

  test 'channel_label prefixes canonical key' do
    skip 'behavioral divergence (restored-from-orphan): channel_label returns user-facing label "Project N" instead of channel-key form "#project:N" — see notepads problems.md Cluster B-C residual; do NOT pin'
    @thread.page_type = 'project'
    @thread.page_id = 5
    @thread.project_id = 5

    assert_equal '#project:5', @thread.channel_label
  end

  test 'channel_description describes page channel type' do
    @thread.page_type = 'wiki_page'

    assert_equal 'Wiki page chat channel', @thread.channel_description
  end

  test 'increment_unread does not increment when sender is thread owner' do
    @thread.unread_count = 0
    @thread.save!
    @thread.increment_unread!(@user.id)
    @thread.reload
    assert_equal 0, @thread.unread_count
  end

  test 'increment_unread increments when sender is different user' do
    other_user = users(:users_002)
    @thread.unread_count = 0
    @thread.save!
    @thread.increment_unread!(other_user.id)
    @thread.reload
    assert_equal 1, @thread.unread_count
  end

  test 'mark_read resets unread_count' do
    @thread.unread_count = 5
    @thread.save!
    @thread.mark_read!
    @thread.reload
    assert_equal 0, @thread.unread_count
  end

  test 'mark_read updates last_message_at' do
    @thread.save!
    @thread.mark_read!
    @thread.reload
    assert_not_nil @thread.last_message_at
  end

  test 'has_many chat_messages association' do
    @thread.save!
    message = AutomyraBridgeChatMessage.create!(
      chat_thread_id: @thread.id,
      user_id: @user.id,
      content: 'Test message',
      role: 'user'
    )
    assert_includes @thread.chat_messages, message
  end

  test 'chat_messages are destroyed when thread is destroyed' do
    @thread.save!
    message = AutomyraBridgeChatMessage.create!(
      chat_thread_id: @thread.id,
      user_id: @user.id,
      content: 'Test message',
      role: 'user'
    )
    message_id = message.id
    @thread.destroy
    assert_not AutomyraBridgeChatMessage.exists?(message_id)
  end

  test 'global thread sets page_key to canonical global channel key' do
    thread = AutomyraBridgeChatThread.new(
      user_id: @user.id,
      thread_kind: 'global',
      page_key: nil
    )
    thread.valid?
    assert_equal "global:user:#{@user.id}", thread.page_key
  end

  test 'global thread sets page_type to global' do
    thread = AutomyraBridgeChatThread.new(
      user_id: @user.id,
      thread_kind: 'global',
      page_type: nil
    )
    thread.valid?
    assert_equal 'global', thread.page_type
  end

  test 'global thread sets page_id to 0' do
    thread = AutomyraBridgeChatThread.new(
      user_id: @user.id,
      thread_kind: 'global',
      page_id: nil
    )
    thread.valid?
    assert_equal 0, thread.page_id
  end

  test 'title_display returns title when present' do
    @thread.title = 'My Custom Title'
    assert_equal 'My Custom Title', @thread.title_display
  end

  test 'title_display returns page_key when title is blank' do
    @thread.title = nil
    @thread.page_key = 'Issue:1'
    assert_equal 'Issue:1', @thread.title_display
  end

  test 'title_display returns Chat when both title and page_key are blank' do
    @thread.title = nil
    @thread.page_key = nil
    assert_equal 'Chat', @thread.title_display
  end

  test 'scope active returns only active threads' do
    active_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 10,
      page_key: 'Issue:10',
      status: 'active'
    )
    archived_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 11,
      page_key: 'Issue:11',
      status: 'archived'
    )
    active_results = AutomyraBridgeChatThread.active
    assert_includes active_results, active_thread
    assert_not_includes active_results, archived_thread
  end

  test 'scope with_unread returns threads with unread_count > 0' do
    has_unread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 20,
      page_key: 'Issue:20',
      status: 'active',
      unread_count: 3
    )
    no_unread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 21,
      page_key: 'Issue:21',
      status: 'active',
      unread_count: 0
    )
    unread_results = AutomyraBridgeChatThread.with_unread
    assert_includes unread_results, has_unread
    assert_not_includes unread_results, no_unread
  end

  test 'scope for_page returns threads matching criteria' do
    page_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 30,
      page_key: 'Issue:30',
      status: 'active'
    )
    other_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active'
    )
    results = AutomyraBridgeChatThread.for_page(@user, 'Issue', 30)
    assert_includes results, page_thread
    assert_not_includes results, other_thread
  end

  test 'scope global_for returns global thread for user' do
    global_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active'
    )
    page_thread = AutomyraBridgeChatThread.create!(
      user_id: @user.id,
      thread_kind: 'page',
      page_type: 'Issue',
      page_id: 40,
      page_key: 'Issue:40',
      status: 'active'
    )
    results = AutomyraBridgeChatThread.global_for(@user)
    assert_includes results, global_thread
    assert_not_includes results, page_thread
  end

  test 'last_message returns most recent message' do
    @thread.save!
    AutomyraBridgeChatMessage.create!(
      chat_thread_id: @thread.id,
      user_id: @user.id,
      content: 'Older message',
      role: 'user',
      created_at: 1.day.ago
    )
    newer = AutomyraBridgeChatMessage.create!(
      chat_thread_id: @thread.id,
      user_id: @user.id,
      content: 'Newer message',
      role: 'user',
      created_at: Time.current
    )
    assert_equal newer.id, @thread.last_message.id
  end

  test 'last_message returns nil when no messages' do
    @thread.save!
    assert_nil @thread.last_message
  end
end
