class AutomyraBridgeOperatorController < ApplicationController
  before_action :require_login
  before_action :find_project
  before_action :authorize_manage!
  before_action :find_job, only: %i[retry_job cancel_job]

  def index
    @project_setting = AutomyraBridgeProjectSetting.for_project(@project)
    @status_filter = params[:status].to_s
    @audit_query = params[:q].to_s.strip
    @proposal_status_filter = params[:proposal_status].to_s
    @proposal_action_filter = params[:proposal_action].to_s
    @pending_proposals = proposal_scope.where(status: 'pending').order(created_at: :desc).limit(50)
    @failed_proposals = proposal_scope.where(status: 'failed').order(updated_at: :desc).limit(50)
    @failed_jobs = AutomyraBridgeJob.where(project: @project, status: 'failed').order(updated_at: :desc).limit(50)
    @audit_events = audit_scope.order(created_at: :desc).limit(50)
    @queue_depth = AutomyraBridgeJob.where(project: @project, status: 'queued').count
    @running_jobs_count = AutomyraBridgeJob.where(project: @project, status: 'running').count
    @recent_failed_jobs_count = AutomyraBridgeJob.where(project: @project, status: 'failed').where('updated_at >= ?', 24.hours.ago).count
    @active_bridge_jobs_count = AutomyraBridgeJob.where(project: @project, status: %w[queued pending running retrying]).count
    @active_runs_count = defined?(AutomyraBridgeRun) ? AutomyraBridgeRun.where(project: @project, status: %w[queued running retrying]).count : 0
    @unprocessed_run_events_count = defined?(AutomyraBridgeRunEvent) ? AutomyraBridgeRunEvent.joins(:run).where(automyra_bridge_runs: { project_id: @project.id }).where(visible_to_user: true).count : 0
    @failed_runs_24h_count = defined?(AutomyraBridgeRun) ? AutomyraBridgeRun.where(project: @project, status: 'failed').where('updated_at >= ?', 24.hours.ago).count : 0
    email_bridge_jobs = AutomyraBridgeJob.where(project: @project, source_type: 'WebhookIncoming')
    @email_bridge_last_processed_job = email_bridge_jobs.where(status: 'succeeded').order(updated_at: :desc).first
    @email_bridge_last_failed_job = email_bridge_jobs.where(status: 'failed').order(updated_at: :desc).first
    @email_bridge_queue_depth = email_bridge_jobs.where(status: %w[queued pending]).count
    @email_bridge_failures_24h_count = email_bridge_jobs.where(status: 'failed').where('updated_at >= ?', 24.hours.ago).count
    @registered_tools = AutomyraBridge::ToolRegistry.all
    @tool_risk_counts = @registered_tools.group_by(&:risk_level).transform_values(&:count)
    @last_worker_job = AutomyraBridgeJob.where(project: @project).order(updated_at: :desc).first
    @adapter_health = adapter_health
    @diagnostics = diagnostics_payload
  end

  def diagnostics
    render json: diagnostics_payload
  end

  def retry_job
    unless @job.status == 'failed'
      redirect_to operator_path, flash: { error: 'Only failed Automyra jobs can be retried.' }
      return
    end

    @job.update!(status: 'queued', retry_count: @job.retry_count.to_i + 1, error_message: nil, started_at: nil, finished_at: nil)
    audit!('job.retry_requested', 'queued', operator_correlation('retry', @job), operator_idempotency('retry', @job))
    redirect_to operator_path, notice: 'Automyra job queued for retry.'
  end

  def cancel_job
    unless %w[queued running failed].include?(@job.status)
      redirect_to operator_path, flash: { error: 'This Automyra job cannot be cancelled.' }
      return
    end

    @job.update!(status: 'cancelled', error_message: 'Cancelled by operator.', finished_at: Time.current)
    audit!('job.cancelled', 'cancelled', operator_correlation('cancel', @job), operator_idempotency('cancel', @job))
    redirect_to operator_path, notice: 'Automyra job cancelled.'
  end

  def update_settings
    setting = AutomyraBridgeProjectSetting.for_project(@project)
    setting.enabled_action_list = Array(params.dig(:automyra_bridge_project_setting, :enabled_actions))
    setting.risk_tier = params.dig(:automyra_bridge_project_setting, :risk_tier).to_s
    setting.enable_sse = ActiveModel::Type::Boolean.new.cast(params.dig(:automyra_bridge_project_setting, :enable_sse)) if setting.respond_to?(:enable_sse=)
    if setting.save
      audit!('settings.updated', 'succeeded', SecureRandom.uuid, SecureRandom.uuid)
      redirect_to operator_path, notice: 'Automyra project settings updated.'
    else
      redirect_to operator_path, flash: { error: setting.errors.full_messages.to_sentence }
    end
  end

  private

  def find_project
    @project = if params[:project_id].present?
                 Project.find(params[:project_id])
               elsif User.current&.admin?
                 Project.first
               else
                 Project.visible.find { |project| User.current.allowed_to?(:manage_automyra_bridge, project) }
               end
    render_404 unless @project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_manage!
    return if User.current.admin? || User.current.allowed_to?(:manage_automyra_bridge, @project)

    render_403
  end

  def find_job
    @job = AutomyraBridgeJob.where(project: @project).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def audit_scope
    scope = AutomyraBridgeAuditEvent.where(project: @project)
    scope = scope.where(status: @status_filter) if @status_filter.present?
    if @audit_query.present?
      pattern = "%#{@audit_query}%"
      scope = scope.where('action LIKE ? OR status LIKE ? OR correlation_id LIKE ? OR error_message LIKE ?', pattern, pattern, pattern, pattern)
    end
    scope
  end

  def proposal_scope
    scope = AutomyraBridgeActionProposal.where(project: @project)
    scope = scope.where(status: @proposal_status_filter) if @proposal_status_filter.present?
    scope = scope.where(action_type: @proposal_action_filter) if @proposal_action_filter.present?
    scope
  end

  def adapter_health
    endpoint = Setting.plugin_redmine_automyra_bridge['automyra_endpoint'].to_s
    ready_uri = AutomyraBridge::UrlValidator.validate!(endpoint.sub(%r{/improve\z}, '/ready'))
    response = Net::HTTP.start(ready_uri.host, ready_uri.port, use_ssl: ready_uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
      AutomyraBridge::UrlValidator.validate_connected_peer!(http, ready_uri.host, Setting.plugin_redmine_automyra_bridge)
      http.get(ready_uri.request_uri)
    end
    { status: response.code.to_i, body: response.body.to_s.truncate(160) }
  rescue StandardError => e
    { status: 'unreachable', body: e.message.truncate(160) }
  end

  def diagnostics_payload
    tool_health = AutomyraBridge::ToolRegistry.health_check(user: User.current, project: @project)
    queue_depth = AutomyraBridgeJob.where(project: @project, status: %w[queued pending retrying]).count
    email_bridge_jobs = AutomyraBridgeJob.where(project: @project, source_type: 'WebhookIncoming')
    email_bridge_last_processed_job = email_bridge_jobs.where(status: 'succeeded').order(updated_at: :desc).first
    email_bridge_last_failed_job = email_bridge_jobs.where(status: 'failed').order(updated_at: :desc).first
    last_successful_run = defined?(AutomyraBridgeRun) ? AutomyraBridgeRun.where(project: @project, status: 'completed').order(updated_at: :desc).first : nil
    last_failed_run = defined?(AutomyraBridgeRun) ? AutomyraBridgeRun.where(project: @project, status: 'failed').order(updated_at: :desc).first : nil
    provider_reachable = endpoint_reachable?(Setting.plugin_redmine_automyra_bridge['automyra_endpoint'])
    memory_reachable = endpoint_reachable?(Setting.plugin_redmine_automyra_bridge['memory_endpoint'])
    health_status = if !provider_reachable || queue_depth > 100 || tool_health[:healthy].zero?
                      'critical'
                    elsif !memory_reachable || tool_health[:healthy] < tool_health[:total]
                      'degraded'
                    else
                      'ok'
                    end

    {
      status: health_status,
      provider_reachable: provider_reachable,
      memory_reachable: memory_reachable,
      queue_depth: queue_depth,
      email_bridge: {
        last_processed_at: email_bridge_last_processed_job&.updated_at&.utc&.iso8601,
        last_error: email_bridge_last_failed_job&.error_message,
        queue_depth: email_bridge_jobs.where(status: %w[queued pending]).count,
        failures_24h_count: email_bridge_jobs.where(status: 'failed').where('updated_at >= ?', 24.hours.ago).count
      },
      last_successful_run_at: last_successful_run&.updated_at&.utc&.iso8601,
      last_failed_run_at: last_failed_run&.updated_at&.utc&.iso8601,
      tool_registry_status: tool_health.slice(:total, :healthy),
      tool_registry_checks: tool_health[:checks]
    }
  end

  def endpoint_reachable?(endpoint)
    return false if endpoint.to_s.blank?

    uri = AutomyraBridge::UrlValidator.validate!(endpoint, Setting.plugin_redmine_automyra_bridge)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
      AutomyraBridge::UrlValidator.validate_connected_peer!(http, uri.host, Setting.plugin_redmine_automyra_bridge)
      response = http.head(uri.request_uri)
      response = http.get(uri.request_uri) if response.is_a?(Net::HTTPMethodNotAllowed)
      response.code.to_i < 500
    end
  rescue StandardError
    false
  end

  def operator_path
    automyra_bridge_operator_path(@project)
  end

  def audit!(action, status, correlation_id, idempotency_key)
    AutomyraBridgeAuditEvent.create!(
      user: User.current,
      project: @project,
      action: action,
      status: status,
      correlation_id: correlation_id,
      idempotency_key: idempotency_key
    )
  end

  def operator_correlation(action, job)
    "#{job.correlation_id}:operator:#{action}:#{SecureRandom.hex(8)}"
  end

  def operator_idempotency(action, job)
    "#{job.idempotency_key}:operator:#{action}:#{SecureRandom.hex(8)}"
  end
end
