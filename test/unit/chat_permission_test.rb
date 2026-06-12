require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatPermissionTest < ActiveSupport::TestCase
  fixtures :users, :projects, :members, :member_roles, :roles

  setup do
    @admin = User.find(1)
    @member = User.find(2)
    @non_member = User.find(3)
    @project_a = projects(:projects_001)
    @project_b = projects(:projects_002)
  end

  test 'logged-in admin is allowed' do
    assert_equal true, @admin.admin?
    assert_equal true, @admin.logged?
    assert AutomyraBridge::ChatPermission.allowed?(@admin)
  end

  test 'global chat ignores blanket global permission and requires a visible permitted project' do
    @member.stubs(:allowed_to_globally?).with(:use_automyra_bridge).returns(true)
    Project.stubs(:all).returns([@project_a])
    @project_a.stubs(:visible?).returns(true)
    @member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_a).returns(false)

    assert_not AutomyraBridge::ChatPermission.allowed?(@member)
  end

  test 'global chat is allowed with permission on at least one visible project' do
    Project.stubs(:all).returns([@project_a])
    @project_a.stubs(:visible?).returns(true)
    @member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_a).returns(true)

    assert AutomyraBridge::ChatPermission.allowed?(@member)
  end

  test 'user with permission on project A cannot access chat for project B issue' do
    AutomyraBridge::ChatProjectResolver.stubs(:from_page).with('Issue', 2).returns(@project_b)
    @project_b.stubs(:visible?).returns(true)
    @member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_b).returns(false)

    assert_not AutomyraBridge::ChatPermission.allowed?(@member, page_type: 'Issue', page_id: 2)
  end

  test 'user can access own thread only if resolved project is visible and permitted' do
    thread = stub(user_id: @member.id, page_type: 'Issue', page_id: 1, project: nil)
    AutomyraBridge::ChatProjectResolver.stubs(:from_page).with('Issue', 1).returns(@project_a)
    @project_a.stubs(:visible?).returns(true)
    @member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_a).returns(true)

    assert AutomyraBridge::ChatPermission.allowed?(@member, thread: thread)
  end

  test 'user cannot access own thread when resolved project is hidden' do
    thread = stub(user_id: @member.id, page_type: 'Issue', page_id: 1, project: nil)
    AutomyraBridge::ChatProjectResolver.stubs(:from_page).with('Issue', 1).returns(@project_a)
    @project_a.stubs(:visible?).returns(false)
    @member.stubs(:member_of?).with(@project_a).returns(false)
    @member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_a).returns(true)

    assert_not AutomyraBridge::ChatPermission.allowed?(@member, thread: thread)
  end

  test 'user cannot access another users thread even when project is permitted' do
    thread = stub(user_id: @non_member.id, page_type: 'Issue', page_id: 1, project: @project_a)

    assert_not AutomyraBridge::ChatPermission.allowed?(@member, thread: thread)
  end

  test 'anonymous user is denied' do
    anon = User.anonymous
    assert_equal false, anon.logged?
    assert_not AutomyraBridge::ChatPermission.allowed?(anon)
  end

  test 'user without any permission is denied' do
    Project.stubs(:all).returns([@project_a])
    @project_a.stubs(:visible?).returns(true)
    @non_member.stubs(:allowed_to?).with(:use_automyra_bridge, @project_a).returns(false)

    assert_not AutomyraBridge::ChatPermission.allowed?(@non_member)
  end

  test 'nil user is denied' do
    assert_not AutomyraBridge::ChatPermission.allowed?(nil)
  end
end
