class AutomyraBridgeController < ApplicationController
  accept_api_auth :improve_task
  skip_before_action :verify_authenticity_token, only: :improve_task

  before_action :require_login
  before_action :find_project
  before_action :authorize

  def improve_task
    result = AutomyraBridge::TaskImprover.new.call(
      user: User.current,
      project: @project,
      task_params: task_params
    )

    if result.success?
      render json: { task: result.suggestions, correlation_id: result.audit_event.correlation_id }
    else
      render json: { error: result.error, correlation_id: result.audit_event&.correlation_id }, status: :bad_gateway
    end
  end

  def assistant_request
    body = assistant_params[:body].to_s.strip
    return redirect_back fallback_location: project_path(@project), alert: 'Automyra request cannot be blank.' if body.blank?

    if assistant_params[:task_id].present? && defined?(TaskHub::Task)
      task = TaskHub::Task.find(assistant_params[:task_id])
      return render_403 unless User.current.admin? || TaskHub::PermissionFilter.new(User.current).can_manage?(User.current, task)

      comment = task.comments.create!(author: User.current, body: mention_body(body))
      AutomyraBridge::JobCreator.create_for_task_comment(comment) || create_task_comment_job(task, comment)
    elsif assistant_params[:issue_id].present?
      issue = Issue.find(assistant_params[:issue_id])
      return render_403 unless User.current.allowed_to?(:add_issue_notes, issue.project)

      issue.init_journal(User.current, mention_body(body))
      issue.save!
      AutomyraBridge::JobCreator.create_for_issue_journal(issue.journals.order(:id).last)
    else
      return render_404
    end

    redirect_back fallback_location: project_path(@project), notice: 'Automyra request queued.'
  end

  private

  def task_params
    params.fetch(:task, ActionController::Parameters.new)
          .permit(:title, :notes, :status, :priority, :due_date, :project_id, :category_id, tags: [])
          .to_h
          .symbolize_keys
  end

  def assistant_params
    params.fetch(:automyra_assistant, ActionController::Parameters.new).permit(:body, :project_id, :task_id, :issue_id)
  end

  def mention_body(body)
    body.match?(/\b@(automyra|redmyra)\b/i) ? body : "@Automyra #{body}"
  end

  def create_task_comment_job(task, comment)
    AutomyraBridge::JobCreator.create_job(
      source_type: 'TaskHub::TaskComment',
      source_id: comment.id,
      user: User.current,
      project: @project,
      payload: {
        action: 'mention_response', source: 'task_hub_comment', comment_id: comment.id, task_id: task.id,
        task_title: task.title, task_notes: task.notes, issue_id: task.issue_id, body: comment.body,
        context_scope: AutomyraBridge::JobCreator.context_scope(User.current, @project, task),
        channel: AutomyraBridge::JobCreator.channel_context('task', task.id, comment.id),
        context: AutomyraBridge::ContextBuilder.for_task(task, User.current)
      }
    )
  end

  def find_project
    value = task_params[:project_id].presence || assistant_params[:project_id]
    return render_404 if value.blank?

    @project = value.to_s.match?(/\A\d+\z/) ? Project.find_by(id: value) : Project.find_by(identifier: value)
    render_404 unless @project
  end

  def api_request?
    request.headers['X-Redmine-API-Key'].present? || params[:key].present?
  end
end
