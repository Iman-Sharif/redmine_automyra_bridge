class AutomyraBridgeActivityLogController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required

  before_action :verify_activity_log_token!

  def create
    @activity_log = AutomyraBridgeActivityLog.new(activity_log_params)

    if @activity_log.save
      render json: {
        id: @activity_log.id,
        action_type: @activity_log.action_type,
        occurred_at: @activity_log.occurred_at
      }, status: :created
    else
      if @activity_log.errors[:idempotency_key].include?('has already been taken')
        render json: { error: 'Duplicate idempotency_key' }, status: :conflict
      else
        render json: { errors: @activity_log.errors.full_messages }, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'Duplicate idempotency_key' }, status: :conflict
  end

  private

  def verify_activity_log_token!
    expected = Setting.plugin_redmine_automyra_bridge['activity_log_secret'].to_s
    supplied = request.headers['Authorization'].to_s

    if expected.blank? || supplied != "Bearer #{expected}"
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
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
