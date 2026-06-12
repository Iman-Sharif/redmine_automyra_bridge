# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatControllerTest < ActionController::TestCase
  tests AutomyraBridgeChatController

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    AutomyraBridgeChatThread.delete_all
    AutomyraBridgeChatMessage.delete_all
    Attachment.delete_all
  end

  # ------------------------------------------------------------------
  # Authentication
  # ------------------------------------------------------------------

  test 'requires login for send_message' do
    post :send_message
    assert_response 302
  end

  test 'requires login for history' do
    get :history
    assert_response 302
  end

  test 'requires login for poll' do
    get :poll
    assert_response 302
  end

  test 'requires login for toggle_thread' do
    post :toggle_thread
    assert_response 302
  end

  test 'requires login for mark_read' do
    post :mark_read
    assert_response 302
  end

  test 'requires login for upload_attachment' do
    post :upload_attachment
    assert_response 302
  end

  # ------------------------------------------------------------------
  # Permission checks
  # ------------------------------------------------------------------

  test 'forbids user without Automyra bridge chat permission' do
    login_as('jsmith')
    project = Project.find_by!(identifier: 'ecookbook')
    enable_automyra_bridge!(project)

    get :history
    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'Access denied', body['error']
  end

  test 'forbids user when page belongs to project without Automyra bridge chat permission' do
    login_as('jsmith')
    allowed_project = Project.find_by!(identifier: 'ecookbook')
    forbidden_project = Project.find_by!(identifier: 'onlinestore')
    enable_automyra_bridge!(allowed_project)
    enable_automyra_bridge!(forbidden_project)
    grant_automyra_bridge_permission!(User.current, allowed_project)
    issue = Issue.create!(project: forbidden_project, tracker: find_tracker, author: User.current, subject: 'Forbidden issue')

    get :history, params: { thread_kind: 'page', page_type: 'issue', page_id: issue.id, project_id: allowed_project.id }

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'Access denied', body['error']
  end

  test 'forbids thread_id access when thread project is not permitted' do
    login_as('jsmith')
    allowed_project = Project.find_by!(identifier: 'ecookbook')
    forbidden_project = Project.find_by!(identifier: 'onlinestore')
    enable_automyra_bridge!(allowed_project)
    enable_automyra_bridge!(forbidden_project)
    grant_automyra_bridge_permission!(User.current, allowed_project)
    thread = AutomyraBridgeChatThread.create!(
      user: User.current,
      project: forbidden_project,
      thread_kind: 'global',
      page_type: 'global',
      page_id: 0,
      page_key: 'global',
      status: 'active'
    )

    get :history, params: { thread_id: thread.id }

    assert_response :forbidden
  end

  test 'rejects unknown thread kind' do
    login_as('admin')

    get :history, params: { thread_kind: 'other' }

    assert_response :bad_request
  end

  test 'rejects unsupported page type' do
    login_as('admin')

    get :history, params: { thread_kind: 'page', page_type: 'Project', page_id: 1 }

    assert_response :bad_request
  end

  test 'allows admin without explicit project permission' do
    login_as('admin')

    get :history
    assert_response :success
  end

  # ------------------------------------------------------------------
  # send_message
  # ------------------------------------------------------------------

  test 'send_message returns no_content' do
    login_as('admin')

    post :send_message, params: { body: 'hello' }

    assert_response :no_content
  end

  # ------------------------------------------------------------------
  # history
  # ------------------------------------------------------------------

  test 'history returns empty messages array' do
    login_as('admin')

    get :history

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body['messages']
  end

  # ------------------------------------------------------------------
  # poll
  # ------------------------------------------------------------------

  test 'poll returns empty messages and zero unread when no thread exists' do
    login_as('admin')

    get :poll, params: { thread_kind: 'page', page_type: 'issue', page_id: 1 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body['messages']
    assert_equal 0, body['unread_count']
  end

  test 'poll returns new messages for existing thread' do
    login_as('admin')
    user = User.current
    thread = AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )
    msg = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: user,
      role: 'assistant',
      content: 'Hi there',
      status: 'delivered'
    )

    get :poll, params: { thread_kind: 'page', page_type: 'issue', page_id: 1, last_message_id: 0 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body['messages'].length
    assert_equal msg.id, body['messages'].first['id']
    assert_equal 'assistant', body['messages'].first['role']
    assert_equal 'Hi there', body['messages'].first['content']
    assert_equal 'delivered', body['messages'].first['status']
    assert_equal false, body['messages'].first['has_proposal']
  end

  test 'poll passes last_seen_update_at to service and returns cursor metadata' do
    login_as('admin')
    requested_update_cursor = '2025-01-01T10:05:00.000Z'
    service_result = {
      new_messages: [],
      unread_count: 0,
      has_updates: false,
      thread_status: 'active',
      last_message_id: 42,
      last_seen_update_at: '2025-01-01T10:10:00.000Z',
      server_time: '2025-01-01T10:11:00.000Z'
    }
    captured_args = nil
    AutomyraBridgeChatThread.create!(
      user: User.current,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )

    AutomyraBridge::ChatPollService.stub(:poll, ->(*args, **kwargs) { captured_args = [args, kwargs]; service_result }) do
      get :poll, params: {
        thread_kind: 'page',
        page_type: 'issue',
        page_id: 1,
        last_message_id: '7',
        last_seen_update_at: requested_update_cursor
      }
    end

    assert_response :success
    assert_equal '7', captured_args.last[:since_message_id]
    assert_equal requested_update_cursor, captured_args.last[:since_updated_at]
    body = JSON.parse(response.body)
    assert_equal 42, body['last_message_id']
    assert_equal '2025-01-01T10:10:00.000Z', body['last_seen_update_at']
    assert_equal '2025-01-01T10:11:00.000Z', body['server_time']
  end

  test 'poll returns cursor metadata when no thread exists' do
    login_as('admin')

    get :poll, params: { thread_kind: 'page', page_type: 'issue', page_id: 999, last_seen_update_at: 'not-a-time' }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body['messages']
    assert_equal 0, body['last_message_id']
    assert body['last_seen_update_at'].present?
    assert body['server_time'].present?
  end

  test 'poll returns archived cursor metadata for archived thread' do
    login_as('admin')
    thread = AutomyraBridgeChatThread.create!(
      user: User.current,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'archived',
      unread_count: 3
    )
    AutomyraBridgeChatMessage.create!(chat_thread: thread, user: User.current, role: 'assistant', content: 'Hidden', status: 'pending')

    get :poll, params: { thread_kind: 'page', page_type: 'issue', page_id: 1, last_message_id: 0 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body['messages']
    assert_equal 0, body['unread_count']
    assert_equal 'archived', body['thread_status']
    assert_equal 0, body['last_message_id']
  end

  test 'poll rejects unknown thread kind' do
    login_as('admin')

    get :poll, params: { thread_kind: 'other' }

    assert_response :bad_request
  end

  test 'poll rejects unsupported page type' do
    login_as('admin')

    get :poll, params: { thread_kind: 'page', page_type: 'Project', page_id: 1 }

    assert_response :bad_request
  end

  # ------------------------------------------------------------------
  # toggle_thread
  # ------------------------------------------------------------------

  test 'toggle_thread creates page thread and returns it with messages' do
    login_as('admin')

    post :toggle_thread, params: { thread_kind: 'page', page_type: 'issue', page_id: 1 }

    assert_response :success
    body = JSON.parse(response.body)
    assert body['thread_id'].present?
    assert_equal 'page', body['thread_kind']
    assert_equal [], body['messages']
    assert_equal 0, body['unread_count']

    thread = AutomyraBridgeChatThread.find(body['thread_id'])
    assert_equal 'page', thread.thread_kind
    assert_equal 'issue', thread.page_type
    assert_equal 1, thread.page_id
  end

  test 'toggle_thread creates global thread' do
    login_as('admin')

    post :toggle_thread, params: { thread_kind: 'global' }

    assert_response :success
    body = JSON.parse(response.body)
    assert body['thread_id'].present?
    assert_equal 'global', body['thread_kind']
    assert_equal [], body['messages']

    thread = AutomyraBridgeChatThread.find(body['thread_id'])
    assert_equal 'global', thread.thread_kind
    assert_equal 'global', thread.page_key
  end

  test 'toggle_thread returns existing thread with messages' do
    login_as('admin')
    user = User.current
    thread = AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )
    msg = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: user,
      role: 'user',
      content: 'Hello',
      status: 'sent'
    )

    post :toggle_thread, params: { thread_kind: 'page', page_type: 'issue', page_id: 1 }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal thread.id, body['thread_id']
    assert_equal 1, body['messages'].length
    assert_equal msg.id, body['messages'].first['id']
    assert_equal 'Hello', body['messages'].first['content']
  end

  # ------------------------------------------------------------------
  # mark_read
  # ------------------------------------------------------------------

  test 'mark_read clears unread count on existing thread' do
    login_as('admin')
    user = User.current
    thread = AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active',
      unread_count: 3
    )

    post :mark_read, params: { thread_id: thread.id }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 0, thread.reload.unread_count
  end

  test 'mark_read requires thread_id' do
    login_as('admin')

    post :mark_read, params: { thread_kind: 'page', page_type: 'issue', page_id: 999 }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'thread_id is required', body['error']
  end

  # ------------------------------------------------------------------
  # upload_attachment
  # ------------------------------------------------------------------

  test 'upload_attachment creates attachment on message' do
    login_as('admin')
    user = User.current
    thread = AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: user,
      role: 'user',
      content: 'See attached',
      status: 'sent'
    )
    tmpfile = Tempfile.new(['test_upload', '.txt'])
    tmpfile.write('test content')
    tmpfile.rewind

    post :upload_attachment, params: {
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      message_id: message.id,
      file: Rack::Test::UploadedFile.new(tmpfile.path, 'text/plain')
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert body['id'].present?
    assert_equal 'test_upload.txt', body['filename']
    assert_equal 'text/plain', body['content_type']
    assert body['url'].present?
    assert body['filesize'].present?

    attachment = Attachment.find(body['id'])
    assert_equal message, attachment.container
    assert_equal user, attachment.author
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  test 'upload_attachment returns not_found when thread missing' do
    login_as('admin')

    tmpfile = Tempfile.new(['test_upload', '.txt'])
    tmpfile.write('test content')
    tmpfile.rewind

    post :upload_attachment, params: {
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 999,
      message_id: 1,
      file: Rack::Test::UploadedFile.new(tmpfile.path, 'text/plain')
    }

    assert_response :not_found
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  test 'upload_attachment returns not_found when message missing' do
    login_as('admin')
    user = User.current
    AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )
    tmpfile = Tempfile.new(['test_upload', '.txt'])
    tmpfile.write('test content')
    tmpfile.rewind

    post :upload_attachment, params: {
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      message_id: 999,
      file: Rack::Test::UploadedFile.new(tmpfile.path, 'text/plain')
    }

    assert_response :not_found
  ensure
    tmpfile&.close
    tmpfile&.unlink
  end

  test 'upload_attachment returns bad_request when no file provided' do
    login_as('admin')
    user = User.current
    thread = AutomyraBridgeChatThread.create!(
      user: user,
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      page_key: 'issue:1',
      status: 'active'
    )
    message = AutomyraBridgeChatMessage.create!(
      chat_thread: thread,
      user: user,
      role: 'user',
      content: 'See attached',
      status: 'sent'
    )

    post :upload_attachment, params: {
      thread_kind: 'page',
      page_type: 'issue',
      page_id: 1,
      message_id: message.id
    }

    assert_response :bad_request
    body = JSON.parse(response.body)
    assert_equal 'No file provided', body['error']
  end

  private

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end

  def grant_automyra_bridge_permission!(user, project)
    # Scope to the target project only: jsmith shares core roles across
    # ecookbook/onlinestore, so a global role mutation would leak the
    # permission and mask the forbidden-project authorization behavior.
    role = Role.generate!(permissions: [:use_automyra_bridge])
    member = Member.find_by(user_id: user.id, project_id: project.id)
    if member
      member.roles << role
      member.save!
    else
      Member.create!(project: project, user: user, roles: [role])
    end
  end

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
  end

  def find_tracker
    Tracker.first || Tracker.create!(name: 'Bug', default_status: IssueStatus.first)
  end
end
