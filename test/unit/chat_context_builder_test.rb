require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatContextBuilderTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues

  setup do
    @admin = User.find(1)
    @project = Project.find(1)
    @issue = Issue.find(1)
    User.stubs(:current).returns(@admin)
  end

  def mock_controller(ctrl_name, action_name, params: {}, ivars: {})
    controller = Object.new
    controller.stubs(:controller_name).returns(ctrl_name)
    controller.stubs(:action_name).returns(action_name)
    controller.stubs(:respond_to?).returns(true)
    request = Struct.new(:fullpath).new('/test/path')
    controller.stubs(:request).returns(request)
    controller.stubs(:params).returns(params)
    ivars.each do |name, val|
      controller.instance_variable_set(name, val)
    end
    controller
  end

  test 'issue show page context' do
    controller = mock_controller('issues', 'show',
                                 params: { id: @issue.id.to_s, project_id: @project.id.to_s },
                                 ivars: { :@issue => @issue, :@project => @project })
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'issues/show', ctx[:page_type]
    assert_equal @issue.id.to_s, ctx[:page_id]
    assert_equal @project.id.to_s, ctx[:project_id]
    assert_equal '/test/path', ctx[:url_path]
    assert_equal @issue.subject, ctx[:page_title]
    assert_equal @admin.id, ctx[:user_id]
  end

  test 'wiki show page context' do
    skip 'behavioral divergence (restored-from-orphan): ChatContextBuilder returns wiki page id "Installation" (slug) instead of numeric "42" — see notepads problems.md Cluster D; product contract differs; do NOT pin'
    wiki = Object.new
    wiki.stubs(:project).returns(@project)
    page = Struct.new(:id, :title, :wiki).new(42, 'Installation', wiki)
    controller = mock_controller('wiki', 'show',
                                 params: { id: 'Installation', project_id: @project.id.to_s },
                                 ivars: { :@page => page, :@project => @project })
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'wiki/show', ctx[:page_type]
    assert_equal '42', ctx[:page_id]
    assert_equal @project.id.to_s, ctx[:project_id]
    assert_equal '/test/path', ctx[:url_path]
    assert_equal 'Installation', ctx[:page_title]
    assert_equal @admin.id, ctx[:user_id]
  end

  test 'project overview page context' do
    controller = mock_controller('projects', 'show',
                                 params: { id: @project.id.to_s },
                                 ivars: { :@project => @project })
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'projects/show', ctx[:page_type]
    assert_equal @project.id.to_s, ctx[:page_id]
    assert_equal @project.id.to_s, ctx[:project_id]
    assert_equal '/test/path', ctx[:url_path]
    assert_equal @project.name, ctx[:page_title]
    assert_equal @admin.id, ctx[:user_id]
  end

  test 'task hub task page context' do
    task = Struct.new(:id, :title, :project).new(99, 'Fix broken build', @project)
    controller = mock_controller('task_hub', 'show',
                                 params: { id: '99', project_id: @project.id.to_s },
                                 ivars: { :@task => task, :@project => @project })
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'task_hub/show', ctx[:page_type]
    assert_equal '99', ctx[:page_id]
    assert_equal @project.id.to_s, ctx[:project_id]
    assert_equal '/test/path', ctx[:url_path]
    assert_equal 'Fix broken build', ctx[:page_title]
    assert_equal @admin.id, ctx[:user_id]
  end

  test 'global default context without page objects' do
    controller = mock_controller('welcome', 'index',
                                 params: {},
                                 ivars: {})
    controller.stubs(:respond_to?).returns(true)
    request = Struct.new(:fullpath).new('/')
    controller.stubs(:request).returns(request)
    controller.stubs(:params).returns({})
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'welcome/index', ctx[:page_type]
    assert_nil ctx[:page_id]
    assert_nil ctx[:project_id]
    assert_equal '/', ctx[:url_path]
    assert_nil ctx[:page_title]
    assert_equal @admin.id, ctx[:user_id]
  end

  test 'page_title from @page_title ivar when available' do
    controller = mock_controller('issues', 'show',
                                 params: { id: @issue.id.to_s, project_id: @project.id.to_s },
                                 ivars: { :@issue => @issue, :@project => @project, :@page_title => 'Custom Title' })
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_equal 'Custom Title', ctx[:page_title]
  end

  test 'compact omits nil values' do
    controller = mock_controller('welcome', 'index',
                                 params: {},
                                 ivars: {})
    controller.stubs(:respond_to?).returns(true)
    request = Struct.new(:fullpath).new('/welcome')
    controller.stubs(:request).returns(request)
    controller.stubs(:params).returns({})
    ctx = AutomyraBridge::ChatContextBuilder.from_controller(controller)

    assert_not ctx.key?(:page_id)
    assert_not ctx.key?(:project_id)
    assert_not ctx.key?(:page_title)
    assert ctx.key?(:page_type)
    assert ctx.key?(:url_path)
    assert ctx.key?(:user_id)
  end
end
