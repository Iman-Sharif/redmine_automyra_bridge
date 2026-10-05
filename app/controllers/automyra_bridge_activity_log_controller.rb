class AutomyraBridgeActivityLogController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :check_if_login_required, raise: false

  before_action :verify_activity_log_token!

  def create
    @activity_log = AutomyraBridgeActivityLog.new(activity_log_params)

    if @activity_log.save
      render json: {
        id: @activity_log.id,
        action_type: @activity_log.action_type,
        occurred_at: @activity_log.occurred_at
      }, status: :created
    elsif @activity_log.errors[:idempotency_key].include?('has already been taken')
      render json: { error: 'Duplicate idempotency_key' }, status: :conflict
    else
      render json: { errors: @activity_log.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'Duplicate idempotency_key' }, status: :conflict
  end

  private

  def verify_activity_log_token!
    render json: { error: 'Unauthorized' }, status: :unauthorized unless valid_activity_log_token?
  end

  # Fails closed: a blank configured secret rejects every request, matching
  # AutomyraBridgeWebhooksController#valid_webhook_token?.
  def valid_activity_log_token?
    expected = Setting.plugin_redmine_automyra_bridge['activity_log_secret'].to_s
    return false if expected.blank?

    supplied = request.authorization.to_s.sub(/\ABearer\s+/i, '')
    ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
  rescue ArgumentError
    false
  end

  def activity_log_params
    params.permit(
      :action_type,
      :source,
      :session_id,
      :target_type,
      :target_id,
      :project_id,
      :summary,
      :details,
      :idempotency_key,
      :occurred_at
    ).tap do |p|
      if p[:project_id].present?
        project = Project.find_by(identifier: p[:project_id])
        p[:project_id] = project&.id
      end
    end
  end
end
