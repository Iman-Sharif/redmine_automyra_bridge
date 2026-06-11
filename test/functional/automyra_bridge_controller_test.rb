require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeControllerTest < ActionController::TestCase
  tests AutomyraBridgeController

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  test 'requires login' do
    post :improve_task, params: { task: { title: 'Draft' } }

    assert_response 302
  end

  test 'returns Automyra suggestions for authorized user' do
    login_as('admin')
    enable_automyra_bridge!(Project.find_by!(identifier: 'ecookbook'))
    result = AutomyraBridge::TaskImprover::Result.new(
      success?: true,
      suggestions: { title: 'Improved task', notes: 'Improved notes', tags: ['standard'] },
      audit_event: stub(correlation_id: 'abc-123')
    )
    AutomyraBridge::TaskImprover.any_instance.stubs(:call).returns(result)

    post :improve_task, params: { task: { title: 'Draft', project_id: 'ecookbook' } }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 'Improved task', body.dig('task', 'title')
    assert_equal 'abc-123', body['correlation_id']
  end

  test 'forbids user without Automyra bridge permission' do
    login_as('jsmith')
    project = Project.find_by!(identifier: 'ecookbook')
    enable_automyra_bridge!(project)

    post :improve_task, params: { task: { title: 'Draft', project_id: project.identifier } }

    assert_response :forbidden
  end

  test 'forbids user when Automyra bridge module is disabled' do
    login_as('jsmith')
    project = Project.find_by!(identifier: 'ecookbook')
    grant_automyra_bridge_permission!(User.find_by!(login: 'jsmith'), project)
    project.enabled_modules.where(name: 'automyra_bridge').delete_all

    post :improve_task, params: { task: { title: 'Draft', project_id: project.identifier } }

    assert_response :forbidden
  end

  test 'accepts Redmine API key for authorized user' do
    previous_rest_api_enabled = Setting.rest_api_enabled?
    Setting.rest_api_enabled = '1'
    user = User.find_by!(login: 'jsmith')
    project = Project.find_by!(identifier: 'ecookbook')
    enable_automyra_bridge!(project)
    grant_automyra_bridge_permission!(user, project)
    token = Token.create!(user: user, action: 'api')
    result = AutomyraBridge::TaskImprover::Result.new(
      success?: true,
      suggestions: { title: 'API improved' },
      audit_event: stub(correlation_id: 'api-123')
    )
    AutomyraBridge::TaskImprover.any_instance.stubs(:call).returns(result)

    @request.env['HTTP_X_REDMINE_API_KEY'] = token.value
    post :improve_task, params: { task: { title: 'Draft', project_id: project.identifier }, format: 'json' }

    assert_response :success
    assert_equal 'API improved', JSON.parse(response.body).dig('task', 'title')
  ensure
    Setting.rest_api_enabled = previous_rest_api_enabled ? '1' : '0'
  end

  test 'assistant request creates Task Hub comment and queued job' do
    login_as('admin')
    AutomyraBridgeJob.delete_all
    project = Project.find_by!(identifier: 'ecookbook')
    enable_automyra_bridge!(project)
    task = TaskHub::Task.create!(title: 'Assistant panel task', user: User.current, author: User.current, project: project, status: 'todo')

    post :assistant_request, params: { automyra_assistant: { project_id: project.id, task_id: task.id, body: 'cancel this task' } }

    assert_redirected_to project_path(project)
    assert task.comments.reload.any?, "expected assistant request to create a comment, response=#{response.status}, flash=#{flash.to_hash.inspect}"
    assert_match /@Automyra cancel this task/, task.comments.order(:id).last.body
    assert AutomyraBridge::MentionDetector.mentioned?(task.comments.order(:id).last.body)
  end

  private

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end

  def grant_automyra_bridge_permission!(user, project)
    role = Role.generate!(permissions: [:use_automyra_bridge])
    Member.create!(project: project, user: user, roles: [role]) unless user.member_of?(project)

    user.memberships.includes(:roles).each do |membership|
      membership.roles.each do |member_role|
        permissions = member_role.permissions.map(&:to_sym)
        member_role.update!(permissions: (permissions | [:use_automyra_bridge]).map(&:to_s))
      end
    end
  end

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
  end
end
