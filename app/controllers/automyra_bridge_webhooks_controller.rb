require 'zlib'

class AutomyraBridgeWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required

  def incoming
    return render_unauthorized unless valid_webhook_token?

    project = find_project
    return render json: { error: 'project not found' }, status: :not_found unless project

    user = webhook_user
    return render json: { error: 'webhook user not found' }, status: :unprocessable_entity unless user

    unless valid_email_payload?
      return render json: { error: 'subject and body are required' }, status: :unprocessable_entity
    end

    job = AutomyraBridge::JobCreator.create_for_webhook(
      user: user,
      project: project,
      payload: webhook_payload,
      source_id: webhook_source_id
    )

    return render json: { error: 'webhook user is not allowed to use Automyra on this project' }, status: :forbidden unless job

    render json: {
      status: 'queued',
      job_id: job.id,
      correlation_id: job.correlation_id,
      idempotency_key: job.idempotency_key
    }, status: :accepted
  end

  private

  def valid_webhook_token?
    expected = settings['webhook_secret'].to_s
    return false if expected.blank?

    supplied = request.authorization.to_s.sub(/\ABearer\s+/i, '')
    ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
  rescue ArgumentError
    false
  end

  def settings
    Setting.plugin_redmine_automyra_bridge || {}
  end

  def webhook_user
    login = settings['webhook_user_login'].to_s.presence
    user = User.find_by(login: login) if login
    user || User.active.where(admin: true).order(:id).first
  end

  def find_project
    identifier = webhook_payload['project_identifier'].presence || webhook_payload['project_id'].presence
    return nil if identifier.blank?

    Project.find_by(identifier: identifier.to_s) || Project.find_by(id: identifier)
  end

  def webhook_payload
    @webhook_payload ||= begin
      raw = params[:email].presence || params[:webhook].presence || params
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    end.deep_stringify_keys
  end

  def valid_email_payload?
    webhook_payload['subject'].to_s.present? && webhook_payload['body'].to_s.present?
  end

  def webhook_source_id
    provided = webhook_payload['message_id'].presence || webhook_payload['idempotency_key'].presence
    seed = provided || [webhook_payload['from'], webhook_payload['sent_at'], webhook_payload['subject'], webhook_payload['body']].join('|')
    Zlib.crc32(seed.to_s)
  end

  def render_unauthorized
    render json: { error: 'unauthorized' }, status: :unauthorized
  end
end
