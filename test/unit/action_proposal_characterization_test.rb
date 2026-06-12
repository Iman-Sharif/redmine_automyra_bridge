require File.expand_path('../test_helper', __dir__)

# Characterization tests pinning CURRENT behavior of the Automyra Bridge WRITE/
# proposal path: ActionProposalExecutor#approve (execute) and
# ActionProposalCreator#create. Includes the two audit-recording silent-swallow
# rescue sites. These tests assert what the code DOES today, not what is desired.
class AutomyraBridgeActionProposalCharacterizationTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses, :projects, :members, :member_roles, :roles,
           :trackers, :projects_trackers, :issue_statuses, :enumerations,
           :issues, :issue_categories

  setup do
    @user = User.find(1) # admin: short-circuits tool authorization on the write path
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Char task', user: @user, author: @user, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @user, body: '@automyra characterization')
    @job = AutomyraBridgeJob.create!(
      status: 'queued',
      source_type: 'TaskHub::TaskComment',
      source_id: @comment.id,
      user: @user,
      project: @project,
      correlation_id: SecureRandom.uuid,
      idempotency_key: SecureRandom.uuid,
      request_payload: { source: 'task_hub_comment' }.to_json
    )
    # Pin the project setting so the creator yields a 'pending' proposal and reaches
    # the swallow site (record_chat_proposal_created fires only when status == 'pending').
    setting = AutomyraBridgeProjectSetting.for_project(@project)
    setting.update!(risk_tier: 'approval_required', enabled_action_list: AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES)
  end

  def build_pending_proposal(title)
    AutomyraBridgeActionProposal.create!(
      automyra_bridge_job: @job,
      project: @project,
      user: @user,
      action_type: 'create_task',
      status: 'pending',
      request_payload: { 'task' => { 'title' => title } }.to_json,
      idempotency_key: SecureRandom.uuid
    )
  end

  # --- Executor: happy path -------------------------------------------------

  test 'executor approve executes a pending proposal and records audit' do
    proposal = build_pending_proposal('Created via executor')
    before = AutomyraBridgeAuditEvent.count

    result = AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)

    assert_equal true, result, 'approve returns true on success'
    assert_equal 'executed', proposal.reload.status
    assert TaskHub::Task.exists?(title: 'Created via executor'), 'tool side-effect (task) created'
    assert_operator AutomyraBridgeAuditEvent.count, :>=, before + 1,
                    'audit event normally recorded on the happy path'
  end

  # --- Executor: swallow site (action_proposal_executor.rb ~line 111) -------

  test 'executor swallows audit recorder failure and still executes proposal' do
    proposal = build_pending_proposal('Created via executor')
    # CHARACTERIZATION: audit-recording failure is silently swallowed — pinned for Task 13/16; not desired behavior.
    AutomyraBridge::AuditRecorder.stubs(:record).raises(StandardError, 'audit boom')

    result = AutomyraBridge::ActionProposalExecutor.new.approve(proposal, @user)

    assert_equal true, result, 'no exception propagates; approve still returns true'
    assert_equal 'executed', proposal.reload.status, 'proposal still executed despite audit failure'
    assert TaskHub::Task.exists?(title: 'Created via executor'), 'main side-effect still happened'
  end

  # --- Creator: happy path --------------------------------------------------

  test 'creator builds a pending proposal and records audit' do
    parsed = { 'proposals' => [{ 'action_type' => 'create_task', 'task' => { 'title' => 'Created via creator' } }] }
    before = AutomyraBridgeAuditEvent.count

    created = AutomyraBridge::ActionProposalCreator.create_from_response(@job, parsed)

    assert_equal 1, created.size
    assert created.first.persisted?
    assert_equal 'pending', created.first.status
    assert_operator AutomyraBridgeAuditEvent.count, :>=, before + 1,
                    'audit event normally recorded on the happy path'
  end

  # --- Creator: swallow site (action_proposal_creator.rb ~line 162) ---------

  test 'creator swallows audit recorder failure and still creates proposal' do
    parsed = { 'proposals' => [{ 'action_type' => 'create_task', 'task' => { 'title' => 'Created via creator swallow' } }] }
    # CHARACTERIZATION: audit-recording failure is silently swallowed — pinned for Task 13/16; not desired behavior.
    AutomyraBridge::AuditRecorder.stubs(:record).raises(StandardError, 'audit boom')

    created = AutomyraBridge::ActionProposalCreator.create_from_response(@job, parsed)

    assert_equal 1, created.size, 'no exception propagates; create still returns the record'
    assert created.first.persisted?, 'proposal still persisted despite audit failure'
    assert_equal 'pending', created.first.status, 'main side-effect (pending proposal) still happened'
  end
end
