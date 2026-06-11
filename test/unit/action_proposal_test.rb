require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeActionProposalTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    AutomyraBridgeActionProposal.delete_all if defined?(AutomyraBridgeActionProposal)
    AutomyraBridgeJob.delete_all
    @user = User.find(2)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Proposal task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra propose')
    @job = AutomyraBridgeJob.create!(
      status: 'succeeded',
      source_type: 'TaskHub::TaskComment',
      source_id: @comment.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'task_hub_comment', body: @comment.body }.to_json
    )
  end

  test 'creates pending update proposal from Automyra response without changing task' do
    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'update_task', 'task' => { 'title' => 'Automyra title', 'notes' => 'Automyra notes' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'pending', proposal.status
    assert_equal 'update_task', proposal.action_type
    assert_equal @task.id, proposal.task_id
    assert_equal 'Proposal task', @task.reload.title
  end

  test 'proposal creation is idempotent for repeated Automyra response' do
    response = {
      'proposals' => [
        { 'action_type' => 'update_task', 'idempotency_key' => 'proposal-repeat-key', 'task' => { 'title' => 'Automyra title' } }
      ]
    }

    assert_difference('AutomyraBridgeActionProposal.count', 1) do
      2.times { AutomyraBridge::ActionProposalCreator.create_from_response(@job, response) }
    end

    assert_equal 'proposal-repeat-key', AutomyraBridgeActionProposal.order(:id).last.idempotency_key
  end

  test 'supported issue proposals are persisted for approval' do
    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'create_issue', 'idempotency_key' => 'unsupported-create-issue', 'issue' => { 'subject' => 'No silent write' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'pending', proposal.status
    assert_equal 'create_issue', proposal.action_type
    assert_equal @task.id, proposal.task_id
    assert_nil proposal.error_message
  end

  test 'create task proposals remain visible on source task' do
    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'create_task', 'task' => { 'title' => 'Visible create proposal' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'pending', proposal.status
    assert_equal @task.id, proposal.task_id
    assert_includes AutomyraBridgeActionProposal.pending.visible_on_task(@task), proposal
  end

  test 'project settings can disable supported write proposals' do
    setting = AutomyraBridgeProjectSetting.for_project(@project)
    setting.enabled_action_list = ['create_task']
    setting.save!

    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'update_task', 'task' => { 'title' => 'Disabled update' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'failed', proposal.status
    assert_equal 'Automyra action is disabled for this project.', proposal.error_message
    assert_equal 'Proposal task', @task.reload.title
  end

  test 'malformed supported proposal is stored as failed for operator visibility' do
    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'create_task', 'idempotency_key' => 'malformed-create-task', 'task' => { 'notes' => 'Missing title' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'failed', proposal.status
    assert_equal 'create_task', proposal.action_type
    assert_equal 'Malformed Automyra write proposal.', proposal.error_message
  end

  test 'read only risk tier disables supported write proposals' do
    setting = AutomyraBridgeProjectSetting.for_project(@project)
    setting.enabled_action_list = ['update_task']
    setting.risk_tier = 'read_only'
    setting.save!

    AutomyraBridge::ActionProposalCreator.create_from_response(@job, {
      'proposals' => [
        { 'action_type' => 'update_task', 'task' => { 'title' => 'Read only update' } }
      ]
    })

    proposal = AutomyraBridgeActionProposal.order(:id).last
    assert_equal 'failed', proposal.status
    assert_equal 'Automyra action is disabled for this project.', proposal.error_message
  end

  test 'approving update proposal changes task after human approval' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('update_task', @task, { 'task' => { 'title' => 'Approved title' } })

    assert AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)

    assert_equal 'executed', proposal.reload.status
    assert_equal 'Approved title', @task.reload.title
    assert_equal 'Automyra proposal approved: update task.', @task.comments.order(:id).last.body
  end

  test 'approval fails when read back verification fails' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('update_task', @task, { 'task' => { 'title' => 'Verified title' } })
    TaskHub::Task.any_instance.stubs(:update).returns(true)

    assert_not AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)

    assert_equal 'failed', proposal.reload.status
    assert_match(/verification failed/, proposal.error_message)
    assert_equal 'Proposal task', @task.reload.title
  end

  test 'rejecting proposal does not change task' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('update_task', @task, { 'task' => { 'title' => 'Rejected title' } })

    assert AutomyraBridge::ActionProposalExecutor.new.reject(proposal, @user)

    assert_equal 'rejected', proposal.reload.status
    assert_equal 'Proposal task', @task.reload.title
    assert_equal 'Automyra proposal rejected: update task.', @task.comments.order(:id).last.body
  end

  test 'approving create proposal creates Task Hub task' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('create_task', nil, { 'task' => { 'title' => 'Created by proposal', 'notes' => 'Created notes' } })

    assert_difference('TaskHub::Task.count', 1) do
      assert AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)
    end

    task = TaskHub::Task.order(:id).last
    assert_equal 'Created by proposal', task.title
    assert_equal @project.id, task.project_id
    assert_equal 'executed', proposal.reload.status
    assert_equal 'Automyra proposal approved: create task.', @task.comments.order(:id).last.body
  end

  test 'approval rolls back task changes when decision comment fails' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('update_task', @task, { 'task' => { 'title' => 'Rolled back title' } })
    TaskHub::TaskComment.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(TaskHub::TaskComment.new))

    assert_no_difference('@task.comments.count') do
      assert_not AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)
    end

    assert_equal 'failed', proposal.reload.status
    assert_equal 'Proposal task', @task.reload.title
  end

  test 'rejection rolls back proposal state when decision comment fails' do
    grant_task_hub_permissions!(@user)
    proposal = create_proposal('update_task', @task, { 'task' => { 'title' => 'Rejected rollback title' } })
    TaskHub::TaskComment.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(TaskHub::TaskComment.new))

    assert_no_difference('@task.comments.count') do
      assert_raises(ActiveRecord::RecordInvalid) do
        AutomyraBridge::ActionProposalExecutor.new.reject(proposal, @user)
      end
    end

    assert_equal 'pending', proposal.reload.status
    assert_nil proposal.decided_at
  end

  private

  def create_proposal(action_type, task, payload)
    AutomyraBridgeActionProposal.create!(
      automyra_bridge_job: @job,
      project: @project,
      task: task,
      user: @user,
      action_type: action_type,
      status: 'pending',
      request_payload: payload.merge('action_type' => action_type).to_json
    )
  end

  def grant_task_hub_permissions!(user)
    EnabledModule.find_or_create_by!(project: @project, name: 'task_hub')
    role = Role.generate!(permissions: [:view_task_hub_tasks, :manage_task_hub_tasks])
    Member.create!(project: @project, user: user, roles: [role]) unless user.member_of?(@project)
    user.memberships.where(project: @project).each { |member| member.roles = [role]; member.save! }
  end
end
