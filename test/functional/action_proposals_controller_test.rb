require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeActionProposalsControllerTest < ActionController::TestCase
  tests AutomyraBridgeActionProposalsController

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    AutomyraBridgeActionProposal.delete_all
    AutomyraBridgeAuditEvent.delete_all
    AutomyraBridgeJob.delete_all
    @user = User.find(2)
    @project = Project.find(1)
    grant_permissions!(@user)
    @job = AutomyraBridgeJob.create!(
      status: 'succeeded',
      source_type: 'TaskHub::TaskComment',
      source_id: 123,
      project: @project,
      user: @user,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: {}.to_json
    )
    @proposal = AutomyraBridgeActionProposal.create!(
      automyra_bridge_job: @job,
      project: @project,
      user: @user,
      action_type: 'create_task',
      status: 'pending',
      idempotency_key: SecureRandom.uuid,
      request_payload: { action_type: 'create_task', task: { title: 'Follow-up task' } }.to_json
    )
  end

  test 'show displays proposal details' do
    login_as('admin')

    get :show, params: { id: @proposal.id }

    assert_response :success
    assert_select 'h2', text: "Automyra proposal ##{@proposal.id}"
    assert_select 'pre', text: /Follow-up task/
  end

  test 'approve returns json success response' do
    login_as('admin')
    @controller.stubs(:authorize_manage!).returns(true)
    AutomyraBridge::ActionProposalExecutor.any_instance.stubs(:approve).returns(true)
    @proposal.update!(status: 'approved')

    post :approve, params: { id: @proposal.id }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal({ 'success' => true }, body)
  end

  test 'approve returns json error response' do
    login_as('admin')
    @controller.stubs(:authorize_manage!).returns(true)
    AutomyraBridge::ActionProposalExecutor.any_instance.stubs(:approve).returns(false)
    @proposal.update!(error_message: 'Nope')

    post :approve, params: { id: @proposal.id }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'Nope', body['error']
  end

  test 'reject returns json success response' do
    login_as('admin')
    @controller.stubs(:authorize_manage!).returns(true)
    AutomyraBridge::ActionProposalExecutor.any_instance.stubs(:reject).returns(true)
    @proposal.update!(status: 'rejected')

    post :reject, params: { id: @proposal.id }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal({ 'success' => true }, body)
  end

  test 'reject returns json error response' do
    login_as('admin')
    @controller.stubs(:authorize_manage!).returns(true)
    AutomyraBridge::ActionProposalExecutor.any_instance.stubs(:reject).returns(false)
    @proposal.update!(error_message: 'Nope')

    post :reject, params: { id: @proposal.id }

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body['success']
    assert_equal 'Nope', body['error']
  end

  private

  def login_as(login)
    user = User.find_by!(login: login)
    @request.session[:user_id] = user.id
    User.current = user
  end

  def grant_permissions!(user)
    EnabledModule.find_or_create_by!(project: @project, name: 'automyra_bridge')
    role = Role.generate!(permissions: [:manage_automyra_bridge])
    member = Member.find_or_initialize_by(project: @project, user: user)
    member.roles = [role]
    member.save!
  end
end
