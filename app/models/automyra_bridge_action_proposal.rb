class AutomyraBridgeActionProposal < ActiveRecord::Base
  self.table_name = 'automyra_bridge_action_proposals'

  STATUSES = %w[pending approved pr_opened rejected executed failed].freeze
ACTION_TYPES = %w[create_task update_task cancel_task complete_task reopen_task assign_task set_task_priority set_task_due_date add_task_comment link_task_issue promote_task search_tasks create_issue update_issue assign_issue set_issue_status set_issue_priority set_issue_due_date link_related_issue search_issues summarize_issue assign_issue_to_requester add_issue_comment read_wiki search_wiki create_wiki_page update_wiki create_wiki_draft summarize_wiki wiki_backlinks wiki_related_pages context_current_object context_current_thread context_linked_objects context_project_search context_memory_search context_expand project_status_summary change_status destructive_action unsupported_action].freeze
  SUPPORTED_ACTION_TYPES = %w[create_task update_task cancel_task complete_task reopen_task assign_task set_task_priority set_task_due_date add_task_comment link_task_issue promote_task search_tasks create_issue update_issue assign_issue set_issue_status set_issue_priority set_issue_due_date link_related_issue search_issues summarize_issue assign_issue_to_requester add_issue_comment read_wiki search_wiki create_wiki_page update_wiki create_wiki_draft summarize_wiki wiki_backlinks wiki_related_pages context_current_object context_current_thread context_linked_objects context_project_search context_memory_search context_expand project_status_summary].freeze

  belongs_to :automyra_bridge_job, class_name: 'AutomyraBridgeJob'
  belongs_to :project
  belongs_to :task, class_name: 'TaskHub::Task', optional: true
  belongs_to :user
  belongs_to :approved_by, class_name: 'User', optional: true

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true, allow_blank: true
  validates :request_payload, presence: true

  after_commit :record_status_run_event, on: :update

  scope :pending, -> { where(status: 'pending') }
  scope :for_task, ->(task) { where(task_id: task.id) }
  scope :visible_on_task, lambda { |task|
    left_outer_joins(:automyra_bridge_job)
      .where('automyra_bridge_action_proposals.task_id = :task_id OR (automyra_bridge_jobs.source_type = :source_type AND automyra_bridge_jobs.source_id IN (:comment_ids))',
             task_id: task.id,
             source_type: 'TaskHub::TaskComment',
             comment_ids: task.comments.select(:id))
  }

  def payload
    JSON.parse(request_payload.to_s.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  STATUSES.each do |proposal_status|
    define_method("#{proposal_status}?") do
      status.to_s == proposal_status
    end
  end

  def target_type
    payload['target_type'] || payload.dig('target', 'type') || task_target_type
  end

  def target_id
    payload['target_id'] || payload.dig('target', 'id') || task_id
  end

  private

  def task_target_type
    return unless task_id.present?

    'TaskHub::Task'
  end

  def record_status_run_event
    return unless previous_changes.key?('status')
    return unless %w[approved rejected].include?(status.to_s)
    return unless defined?(AutomyraBridge::RunEventRecorder)
    return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

    run = AutomyraBridgeRun.find_by(source_type: automyra_bridge_job.source_type, source_id: automyra_bridge_job.source_id)
    return unless run

    AutomyraBridge::RunEventRecorder.record(
      run: run,
      event_type: "action_proposal.#{status}",
      status: status,
      message: "Automyra proposal #{status}: #{action_type.to_s.humanize.downcase}.",
      payload: status_event_payload,
      visible_to_user: true,
      created_by: approved_by,
      sequence: status_event_sequence(status)
    )
  rescue StandardError => e
    Rails.logger.warn("Automyra proposal status run event failed for #{id}: #{e.message}") if defined?(Rails)
  end

  def status_event_payload
    {
      proposal_id: id,
      action_type: action_type,
      target_type: target_type,
      target_id: target_id,
      status: status,
      reason: 'This action requires approval because it would modify Redmica data. An operator with permission can approve or reject it.',
      changed_at: (decided_at || Time.current).utc.iso8601(3)
    }.compact
  end

  def status_event_sequence(suffix)
    Digest::SHA256.hexdigest("action_proposal:#{id}:#{suffix}").to_i(16) % 1_000_000_000
  end
end
