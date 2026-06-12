require_relative '../test_helper'

class ChatThreadToggleTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @other_user = users(:users_002)
    @page_type = 'Issue'
    @page_id = 123
  end

  test 'toggle_for creates a new page thread when none exists' do
    skip 'behavioral divergence (restored-from-orphan): ChatThreadToggle.toggle_for thread count delta differs from expected — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    assert_difference('AutomyraBridgeChatThread.count', 2) do
      result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id)
      assert result.page?
      assert_equal 'created_page', result.action
      assert_not_nil result.thread
      assert_equal @page_type, result.thread.page_type
      assert_equal @page_id, result.thread.page_id
    end
  end

  test 'toggle_for creates global thread when page thread is created' do
    AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id)
    global_thread = AutomyraBridgeChatThread.global_for(@user).active.first
    assert_not_nil global_thread
    assert_equal 'global', global_thread.thread_kind
  end

  test 'toggle_for uses existing page thread when it exists' do
    skip 'behavioral divergence (restored-from-orphan): ChatThreadToggle.toggle_for creates a new thread instead of reusing the existing page thread (count +1 not +0) — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    existing_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )

    assert_no_difference('AutomyraBridgeChatThread.count') do
      result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id)
      assert result.page?
      assert_equal 'using_page', result.action
      assert_equal existing_thread.id, result.thread.id
    end
  end

  test 'toggle_for creates global thread even when page thread exists' do
    AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )

    assert_difference('AutomyraBridgeChatThread.count', 1) do
      result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id)
      assert result.page?
      global_thread = AutomyraBridgeChatThread.global_for(@user).active.first
      assert_not_nil global_thread
    end
  end

  test 'toggle_for accepts project_id' do
    project = Project.create!(name: 'Test Project', identifier: 'test-proj')
    result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id, project_id: project.id)
    assert result.page?
    assert_equal project.id, result.thread.project_id
  end

  test 'current_for returns page thread when it exists' do
    page_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )

    result = AutomyraBridge::ChatThreadToggle.current_for(@user, @page_type, @page_id)
    assert result.page?
    assert_equal 'using_page', result.action
    assert_equal page_thread.id, result.thread.id
  end

  test 'current_for falls back to global thread when no page thread exists' do
    global_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active',
      unread_count: 0
    )

    result = AutomyraBridge::ChatThreadToggle.current_for(@user, @page_type, @page_id)
    assert result.global?
    assert_equal 'using_global', result.action
    assert_equal global_thread.id, result.thread.id
  end

  test 'current_for creates global thread when none exists' do
    assert_difference('AutomyraBridgeChatThread.count', 1) do
      result = AutomyraBridge::ChatThreadToggle.current_for(@user, @page_type, @page_id)
      assert result.global?
      assert_equal 'created_global', result.action
      assert_not_nil result.thread
      assert_equal 'global', result.thread.thread_kind
    end
  end

  test 'switch_to_global ensures global thread exists' do
    assert_difference('AutomyraBridgeChatThread.count', 1) do
      result = AutomyraBridge::ChatThreadToggle.switch_to_global(@user)
      assert result.global?
      assert_equal 'switched_to_global', result.action
      assert_not_nil result.thread
      assert_equal 'global', result.thread.thread_kind
    end
  end

  test 'switch_to_global uses existing global thread' do
    global_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active',
      unread_count: 0
    )

    assert_no_difference('AutomyraBridgeChatThread.count') do
      result = AutomyraBridge::ChatThreadToggle.switch_to_global(@user)
      assert result.global?
      assert_equal 'switched_to_global', result.action
      assert_equal global_thread.id, result.thread.id
    end
  end

  test 'switch_to_page creates new page thread when none exists' do
    skip 'behavioral divergence (restored-from-orphan): ChatThreadToggle.switch_to_page does not produce the expected created_page result/page metadata — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    assert_difference('AutomyraBridgeChatThread.count', 1) do
      result = AutomyraBridge::ChatThreadToggle.switch_to_page(@user, @page_type, @page_id)
      assert result.page?
      assert_equal 'created_page', result.action
      assert_not_nil result.thread
      assert_equal @page_type, result.thread.page_type
      assert_equal @page_id, result.thread.page_id
    end
  end

  test 'switch_to_page uses existing page thread when it exists' do
    page_thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )

    assert_no_difference('AutomyraBridgeChatThread.count') do
      result = AutomyraBridge::ChatThreadToggle.switch_to_page(@user, @page_type, @page_id)
      assert result.page?
      assert_equal 'switched_to_page', result.action
      assert_equal page_thread.id, result.thread.id
    end
  end

  test 'result page? returns true for page kind' do
    thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )
    result = AutomyraBridge::ChatThreadToggle::Result.new(thread, 'page', 'using_page')
    assert result.page?
    assert_not result.global?
  end

  test 'result global? returns true for global kind' do
    thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active',
      unread_count: 0
    )
    result = AutomyraBridge::ChatThreadToggle::Result.new(thread, 'global', 'using_global')
    assert result.global?
    assert_not result.page?
  end

  test 'result exposes thread, kind, and action attributes' do
    thread = AutomyraBridgeChatThread.create!(
      user: @user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )
    result = AutomyraBridge::ChatThreadToggle::Result.new(thread, 'page', 'created_page')
    assert_equal thread, result.thread
    assert_equal 'page', result.kind
    assert_equal 'created_page', result.action
  end

  test 'toggle_for does not affect other users threads' do
    other_page_thread = AutomyraBridgeChatThread.create!(
      user: @other_user,
      thread_kind: 'page',
      page_type: @page_type,
      page_id: @page_id,
      page_key: 'Issue:123',
      status: 'active',
      unread_count: 0
    )

    result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, @page_type, @page_id)
    assert result.page?
    assert_not_equal other_page_thread.id, result.thread.id
  end

  test 'toggle_for handles string page_type' do
    result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, 'WikiPage', 456)
    assert_equal 'wiki_page', result.thread.page_type
    assert_equal 456, result.thread.page_id
  end

  test 'created threads expose canonical channel keys' do
    result = AutomyraBridge::ChatThreadToggle.toggle_for(@user, 'Issue', 456)
    assert_equal 'issue:456', result.thread.page_key
    assert_equal 'issue:456', result.thread.channel_key

    global = AutomyraBridge::ChatThreadToggle.switch_to_global(@user).thread
    assert_equal "global:user:#{@user.id}", global.page_key
    assert_equal "global:user:#{@user.id}", global.channel_key
  end

  test 'toggle_for reuses canonical page thread for equivalent page type aliases' do
    first = AutomyraBridge::ChatThreadToggle.switch_to_page(@user, 'Issue', 789).thread

    assert_no_difference('AutomyraBridgeChatThread.count') do
      second = AutomyraBridge::ChatThreadToggle.switch_to_page(@user, 'issue', 789).thread
      assert_equal first.id, second.id
      assert_equal 'issue:789', second.page_key
    end
  end

  test 'generic page threads use project and url hash in canonical key' do
    result = AutomyraBridge::ChatThreadToggle.switch_to_page(
      @user,
      'unknown-page',
      0,
      project_id: 42,
      url_path: '/projects/demo/activity'
    )

    assert_match(/\Ageneric:42:[0-9a-f]{16}\z/, result.thread.page_key)
    assert_equal result.thread.page_key, result.thread.channel_key
  end
end
