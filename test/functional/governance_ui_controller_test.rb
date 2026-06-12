require File.expand_path('../test_helper', __dir__)
require 'stringio'

class AutomyraBridgeGovernanceUiControllerTest < ActionController::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  tests AutomyraBridge::Governance::PoliciesController

  setup do
    AutomyraBridge::GovernanceAction.delete_all
    AutomyraBridge::GovernanceFinding.delete_all
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    AutomyraBridgeProjectSetting.delete_all if defined?(AutomyraBridgeProjectSetting)
    @project = Project.find(1)
    @user = User.find(2)
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    grant_permissions!(@user)
    login_as('jsmith')
    @policy = AutomyraBridge::GovernancePolicy.create!(
      project: @project,
      created_by: @user,
      name: 'Title standardisation',
      mode: 'report_only',
      provider_model: 'manifest/auto',
      max_changes_per_run: 5,
      config: '{"rules":["Use clear English titles"]}'
    )
  end

  test 'policy index requires governance permission' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    Role.delete_all

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test 'policy index and detail render native governance data' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    run = AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, status: 'completed', findings_count: 1, actions_count: 1, applied_count: 1, provider_model_used: 'manifest/auto', error_message: 'full troubleshooting details', policy_source_hash: 'policy123', prompt_hash: 'prompt123', response_hash: 'response123')
    finding = AutomyraBridge::GovernanceFinding.create!(governance_run: run, governance_policy: @policy, object_type: 'WikiHub::PageProfile', object_id: 10, finding_type: 'wiki_title', status: 'valid', recommended_value: 'Better title')
    AutomyraBridge::GovernanceAction.create!(governance_run: run, governance_finding: finding, governance_policy: @policy, action_type: 'update_wiki_title', object_type: 'WikiHub::PageProfile', object_id: 10, status: 'proposed', idempotency_key: SecureRandom.uuid)

    get :index, params: { project_id: @project.id }
    assert_response :success
    assert_select 'h2', text: 'Automyra governance policies'
    assert_select 'input[type=submit][value=?]', 'Run all now'
    assert_select 'form.button-to[action=?] input[type=submit][value=?]', edit_automyra_bridge_governance_policy_path(@policy), 'Edit'
    assert_match(/Title standardisation/, @response.body)
    assert_select 'span.automyra-governance-health-success', text: 'Successful'

    get :show, params: { id: @policy.id }
    assert_response :success
    assert_select 'h3', text: 'Run now'
    assert_select 'span.badge', text: 'valid'
    assert_select 'a', text: 'Approval queue'
    assert_select 'button.automyra-copy-run-details[data-copy-text*=?]', 'Run URL:'
    assert_match(/full troubleshooting details/, @response.body)
    assert_match(/policy123/, @response.body)
  end

  test 'finding detail links to supported object records' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    issue = Issue.find(1)
    run = AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, status: 'completed', provider_model_used: 'manifest/auto')
    issue_finding = AutomyraBridge::GovernanceFinding.create!(
      governance_run: run,
      governance_policy: @policy,
      object_type: 'Issue',
      object_id: issue.id,
      finding_type: 'task_requirement_link',
      status: 'valid',
      recommended_value: 'Link the requirement.'
    )

    attachment = Attachment.create!(
      container: @project,
      author: @user,
      filename: 'Bad File Name.pdf',
      disk_filename: 'bad_file_name.pdf',
      filesize: 12,
      content_type: 'application/pdf',
      digest: 'abc123',
      disk_directory: 'test',
      downloads: 0,
      created_on: Time.current,
      description: 'governance attachment'
    )
    attachment_finding = AutomyraBridge::GovernanceFinding.create!(
      governance_run: run,
      governance_policy: @policy,
      object_type: 'Attachment',
      object_id: attachment.id,
      finding_type: 'attachment_filename',
      status: 'valid',
      recommended_value: 'good-file-name.pdf'
    )

    get :show, params: { id: issue_finding.id }
    assert_response :success
    assert_select 'th', text: 'Object'
    assert_select "a[href='#{issue_path(issue)}']", text: 'Issue #1'

    get :show, params: { id: attachment_finding.id }
    assert_response :success
    assert_select "a[href='#{attachment_path(attachment)}']", text: "Attachment ##{attachment.id}"
  end

  test 'policy index shows red failed health for last failed run' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, status: 'completed')
    AutomyraBridge::GovernanceRun.create!(governance_policy: @policy, status: 'failed', error_message: 'provider failed')

    get :index, params: { project_id: @project.id }

    assert_response :success
    assert_select 'span.automyra-governance-health-failed', text: 'Failed'
    assert_select 'span.automyra-governance-health-success', count: 0
  end

  test 'global policy index works without project and can create global policy' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    assert_difference('AutomyraBridge::GovernancePolicy.where(scope_type: "global").count') do
      post :create, params: { automyra_bridge_governance_policy: { name: 'Global title standard', scope_type: 'global', mode: 'report_only', provider_model: 'manifest/auto' } }
    end

    policy = AutomyraBridge::GovernancePolicy.order(:id).last
    assert_nil policy.project_id
    assert_redirected_to automyra_bridge_governance_policy_path(policy)

    get :index
    assert_response :success
    assert_match(/Global title standard/, @response.body)
    assert_match(/Global/, @response.body)
  end

  test 'validation errors are shown on create' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    assert_no_difference('AutomyraBridge::GovernancePolicy.count') do
      post :create, params: { project_id: @project.id, automyra_bridge_governance_policy: { name: '', mode: 'invalid', provider_model: '' } }
    end

    assert_response :success
    assert_select '#errorExplanation'
  end

  test 'run now enqueues governance job with mode and guardrail' do
    assert_enqueued_with(job: AutomyraBridge::GovernanceRunJob, args: [@policy.id, 'propose']) do
      post :run_now, params: { id: @policy.id, mode: 'propose', max_changes_per_run: '7' }
    end

    assert_redirected_to automyra_bridge_governance_policy_path(@policy)
    assert_equal 7, @policy.reload.max_changes_per_run
  end

  test 'run all now enqueues enabled policies in current scope' do
    disabled_policy = AutomyraBridge::GovernancePolicy.create!(
      project: @project,
      created_by: @user,
      name: 'Disabled standardisation',
      mode: 'report_only',
      provider_model: 'manifest/auto',
      enabled: false,
      max_changes_per_run: 5
    )

    assert_difference('enqueued_jobs.size', 1) do
      post :run_all_now, params: { project_id: @project.id }
    end

    assert_enqueued_with(job: AutomyraBridge::GovernanceRunJob, args: [@policy.id, @policy.mode])
    assert_redirected_to automyra_bridge_governance_policies_path(project_id: @project.id)
    assert_equal false, disabled_policy.reload.enabled?
  end

  test 'read only project mode blocks policy changes and apply runs' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'read_only')

    patch :update, params: { id: @policy.id, automyra_bridge_governance_policy: { name: 'Blocked change', mode: 'report_only', provider_model: 'manifest/auto' } }
    assert_response :forbidden
    assert_equal 'Title standardisation', @policy.reload.name

    assert_no_enqueued_jobs do
      post :run_now, params: { id: @policy.id, mode: 'apply_after_validation', max_changes_per_run: '2' }
    end
    assert_redirected_to automyra_bridge_governance_policy_path(@policy)
  end

  test 'toggle_enabled pauses an enabled policy' do
    assert @policy.enabled?

    post :toggle_enabled, params: { id: @policy.id }

    assert_redirected_to automyra_bridge_governance_policies_path(project_id: @project.id)
    assert_equal false, @policy.reload.enabled?
    assert_match(/has been paused/, flash[:notice])
  end

  test 'toggle_enabled resumes a disabled policy' do
    @policy.update!(enabled: false)

    post :toggle_enabled, params: { id: @policy.id }

    assert_redirected_to automyra_bridge_governance_policies_path(project_id: @project.id)
    assert_equal true, @policy.reload.enabled?
    assert_match(/has been enabled/, flash[:notice])
  end

  test 'toggle_enabled is blocked in read only project mode' do
    AutomyraBridgeProjectSetting.for_project(@project).update!(risk_tier: 'read_only')

    post :toggle_enabled, params: { id: @policy.id }

    assert_redirected_to automyra_bridge_governance_policies_path(project_id: @project.id)
    assert_match(/read-only.*Governance policies cannot be changed/, flash[:error])
    assert_equal true, @policy.reload.enabled?
  end

  test 'edit page renders delete button for policy' do
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    skip 'environment drift: redmica view_customizes table missing in test DB (separate plugin, not automyra) — view rendering raises PG::UndefinedTable — see notepads problems.md Cluster D / env drift; do NOT pin'
    get :edit, params: { id: @policy.id }

    assert_response :success
    assert_select "form.button_to[action='#{automyra_bridge_governance_policy_path(@policy)}'] input[name='_method'][value='delete']", 1
    assert_select "form.button_to input[type=submit][value='Delete']", 1
  end

  private

  def teardown
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    super
  end

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
