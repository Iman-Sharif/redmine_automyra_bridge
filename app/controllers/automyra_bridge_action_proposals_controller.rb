class AutomyraBridgeActionProposalsController < ApplicationController
  accept_api_auth :index, :create, :status, :approve, :reject
  skip_before_action :verify_authenticity_token, only: %i[create status approve reject], if: :api_request?

  before_action :require_login
  before_action :find_proposal, except: %i[index create]
  before_action :find_project, only: %i[index]
  before_action :authorize_manage!, except: %i[index create]
  before_action :authorize_project_manage!, only: %i[index]

  def index
    scope = AutomyraBridgeActionProposal.where(project: @project)
    scope = scope.where(status: params[:status].to_s) if params[:status].present?
    scope = scope.where("request_payload LIKE ?", "%\"source\":\"#{sanitize_sql_like(params[:source].to_s)}\"%") if params[:source].present?

    render json: { proposals: scope.order(updated_at: :desc).limit(100).map { |proposal| proposal_json(proposal) } }
  end

  def create
    find_create_project!
    return if performed?

    authorize_project_manage!
    return if performed?

    proposal = upsert_sisyphus_proposal!

    log_sisyphus_proposal_activity(proposal)

    render json: { id: proposal.id, proposal_id: proposal.id, status: proposal.status }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue StandardError => e
    Rails.logger.warn("Sisyphus proposal create failed: #{e.class}: #{e.message}") if defined?(Rails)
    render json: { error: e.message }, status: :internal_server_error
  end

  def show
  end

  def status
    if request.post? && params[:status].to_s == 'implemented'
      @proposal.update!(status: 'executed', executed_at: Time.current)
    elsif request.post? && params[:status].to_s == 'pr_opened'
      payload = @proposal.payload.merge('pr_url' => params[:pr_url].to_s.presence).compact
      @proposal.update!(status: 'pr_opened', request_payload: payload.to_json)
    elsif request.post? && params[:status].to_s == 'failed'
      payload = @proposal.payload.merge('failure_reason' => params[:error].to_s.presence).compact
      @proposal.update!(status: 'failed', error_message: params[:error].to_s.presence, request_payload: payload.to_json)
    end

    render json: proposal_json(@proposal)
  end

  def approve
    if sisyphus_proposal?(@proposal)
      @proposal.update!(status: 'approved', approved_by: User.current, decided_at: Time.current)
      return render json: { success: true }
    end

    if AutomyraBridge::ActionProposalExecutor.new.approve(@proposal, User.current)
      render json: { success: true }
    else
      render json: { success: false, error: @proposal.error_message.presence || 'Automyra proposal could not be approved.' }, status: :unprocessable_entity
    end
  end

  def reject
    if AutomyraBridge::ActionProposalExecutor.new.reject(@proposal, User.current)
      render json: { success: true }
    else
      render json: { success: false, error: @proposal.error_message.presence || 'Automyra proposal could not be rejected.' }, status: :unprocessable_entity
    end
  end

  private

  def find_project
    project_id = recursive_param(params.to_unsafe_h, 'project_id').presence || raw_json_payload['project_id'].presence
    project_id = 'redmine-dta' if project_id.blank? && action_name == 'create'
    @project = Project.find_by(identifier: project_id.to_s) || Project.find_by(id: project_id)
    render_404 unless @project
  end

  def find_create_project!
    payload = proposal_params
    project_id = payload[:project_id].presence || payload['project_id'].presence || 'redmine-dta'
    @project = Project.find_by(identifier: project_id.to_s) || Project.find_by(id: project_id)
    render_404 unless @project
  end

  def find_proposal
    @proposal = AutomyraBridgeActionProposal.find(params[:id])
  end

  def authorize_manage!
    return if User.current.admin? || User.current.allowed_to?(:manage_automyra_bridge, @proposal.project)

    render_403
  end

  def authorize_project_manage!
    return if User.current.admin? || User.current.allowed_to?(:manage_automyra_bridge, @project)

    render_403
  end

  def upsert_sisyphus_proposal!
    payload = proposal_params.to_h.deep_stringify_keys
    idempotency_key = payload['idempotency_key'].presence || sisyphus_idempotency_key(payload)
    job = sisyphus_job!(payload, idempotency_key)

    AutomyraBridgeActionProposal.find_or_create_by!(idempotency_key: idempotency_key) do |record|
      record.automyra_bridge_job = job
      record.project = @project
      record.user = User.current
      record.action_type = 'project_status_summary'
      record.status = 'pending'
      record.request_payload = payload.merge('idempotency_key' => idempotency_key).to_json
    end
  end

  def sisyphus_job!(payload, idempotency_key)
    job = AutomyraBridgeJob.find_by(idempotency_key: "#{idempotency_key}:job")
    return job if job

    AutomyraBridgeJob.create!(idempotency_key: "#{idempotency_key}:job") do |job|
      job.project = @project
      job.user = User.current
      job.status = 'succeeded'
      job.source_type = 'SisyphusLoop'
      job.source_id = Digest::SHA256.hexdigest(idempotency_key.to_s)[0, 8].to_i(16) % 2_000_000_000
      job.correlation_id = "sisyphus-loop:#{idempotency_key}"
      job.request_payload = payload.to_json
      job.response_payload = { source: 'sisyphus-loop' }.to_json
      job.started_at = Time.current if job.respond_to?(:started_at=)
      job.finished_at = Time.current if job.respond_to?(:finished_at=)
    end
  end

  def proposal_params
    raw_payload = raw_json_payload
    return ActionController::Parameters.new(raw_payload).permit(:project_id, :title, :description, :recommendation, :category, :severity, :source, :plugin, :idempotency_key, affected_files: []) if raw_payload.present?

    permitted = params.permit(:project_id, :title, :description, :recommendation, :category, :severity, :source, :plugin, :idempotency_key, affected_files: [])
    return permitted if permitted[:project_id].present?

    recursive_payload = %w[project_id title description recommendation category severity source plugin idempotency_key affected_files].each_with_object({}) do |key, memo|
      value = recursive_param(params.to_unsafe_h, key)
      memo[key] = value if value.present?
    end
    if recursive_payload['project_id'].present? || action_name == 'create'
      recursive_payload['project_id'] ||= @project&.identifier
      return ActionController::Parameters.new(recursive_payload).permit(:project_id, :title, :description, :recommendation, :category, :severity, :source, :plugin, :idempotency_key, affected_files: [])
    end

    params.require(:automyra_bridge_action_proposal).permit(:project_id, :title, :description, :recommendation, :category, :severity, :source, :plugin, :idempotency_key, affected_files: [])
  end

  def raw_json_payload
    return @raw_json_payload if defined?(@raw_json_payload)

    @raw_json_payload = JSON.parse(request.raw_post.to_s.presence || '{}')
  rescue JSON::ParserError
    @raw_json_payload = {}
  end

  def recursive_param(value, key)
    case value
    when Hash
      return value[key] if value[key].present?
      return value[key.to_sym] if value[key.to_sym].present?

      value.values.each do |nested|
        found = recursive_param(nested, key)
        return found if found.present?
      end
    when Array
      value.each do |nested|
        found = recursive_param(nested, key)
        return found if found.present?
      end
    end

    nil
  end

  def sisyphus_idempotency_key(payload)
    Digest::SHA256.hexdigest([
      'sisyphus-loop',
      @project.id,
      payload['plugin'],
      payload['category'],
      payload['title'],
      Array(payload['affected_files']).join(',')
    ].join(':'))
  end

  def proposal_json(proposal)
    payload = proposal.payload

    {
      id: proposal.id,
      proposal_id: proposal.id,
      status: proposal.status,
      title: payload['title'],
      description: payload['description'],
      recommendation: payload['recommendation'],
      plugin: payload['plugin'],
      affected_files: Array(payload['affected_files']),
      source: payload['source'],
      pr_url: payload['pr_url'],
      issue_url: automyra_bridge_proposal_path(proposal)
    }
  end

  def sisyphus_proposal?(proposal)
    proposal.payload['source'].to_s == 'sisyphus-loop'
  end

  def log_sisyphus_proposal_activity(proposal)
    return unless proposal

    summary = proposal.payload['title'].presence ||
              proposal.payload['summary'].presence ||
              proposal.action_type.to_s.humanize
    AutomyraBridge::ActivityLogger.log!(
      action_type: 'sisyphus_proposal',
      source: 'sisyphus_loop',
      summary: "Proposal created: #{summary.to_s.truncate(100)}",
      target_type: proposal.target_type,
      target_id: proposal.target_id,
      project_id: proposal.project_id,
      user_id: proposal.user_id
    )
  rescue StandardError => e
    Rails.logger.warn("Sisyphus proposal activity log failed: #{e.class}: #{e.message}") if defined?(Rails)
  end

  def sanitize_sql_like(value)
    ActiveRecord::Base.sanitize_sql_like(value)
  end

  def redirect_path
    @proposal.task ? task_hub_standalone_path(@proposal.task) : task_hub_standalone_index_path
  end
end
