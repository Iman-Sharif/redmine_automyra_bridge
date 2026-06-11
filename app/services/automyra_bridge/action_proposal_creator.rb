module AutomyraBridge
  class ActionProposalCreator
    def self.create_from_response(job, parsed)
      new(job, parsed).create
    end

    def initialize(job, parsed)
      @job = job
      @parsed = parsed || {}
    end

    def create
      created = []
      proposals.each do |proposal|
        action_type = proposal['action_type'].to_s
        action_type = 'unsupported_action' unless AutomyraBridgeActionProposal::ACTION_TYPES.include?(action_type)
        enabled = read_action?(action_type) || project_setting.action_enabled?(action_type)
        valid = valid_proposal?(action_type, proposal)

        task = proposal_task(action_type, proposal)
        next if task_required?(action_type) && task.blank?

        record = AutomyraBridgeActionProposal.find_or_create_by!(idempotency_key: idempotency_key(action_type, proposal)) do |record|
          record.automyra_bridge_job = @job
          record.project = @job.project
          record.task = task
          record.user = @job.user
          record.action_type = action_type
          record.status = proposal_status(action_type, enabled, valid)
          record.request_payload = proposal.to_json
          record.error_message = proposal_error(action_type, enabled, valid)
        end
        created << record
        record_chat_proposal_created(record) if record.persisted? && record.status == 'pending'
        record_run_proposal_created(record) if record.persisted? && record.status == 'pending'
      end
      created
    end

    private

      def proposals
        legacy = Array(@parsed['proposals'].presence || @parsed['actions']).select { |item| item.is_a?(Hash) }
        tool_proposals = Array(@parsed['tool_calls']).filter_map { |item| tool_call_to_proposal(item) }
        legacy + tool_proposals
      end

    def tool_call_to_proposal(item)
      return unless item.is_a?(Hash)

      tool = AutomyraBridge::ToolRegistry.find(item['tool'] || item['name'])
      return unless tool

      input = item['input'].is_a?(Hash) ? item['input'] : item['arguments'].is_a?(Hash) ? item['arguments'] : {}
      input.merge(
        'action_type' => tool.legacy_action_type,
        'tool' => tool.name,
        'idempotency_key' => item['idempotency_key']
      ).compact
    end

    def proposal_task(action_type, proposal)
      task_from_proposal(proposal) if %w[create_task update_task cancel_task complete_task reopen_task assign_task set_task_priority set_task_due_date add_task_comment link_task_issue promote_task search_tasks unsupported_action create_issue update_issue assign_issue set_issue_status set_issue_priority set_issue_due_date link_related_issue search_issues summarize_issue read_wiki search_wiki create_wiki_page update_wiki create_wiki_draft summarize_wiki wiki_backlinks wiki_related_pages change_status destructive_action assign_issue_to_requester add_issue_comment].include?(action_type)
    end

    def source_task
      return @source_task if defined?(@source_task)
      @source_task = nil
      return @source_task unless @job.source_type == 'TaskHub::TaskComment'

      comment = TaskHub::TaskComment.find_by(id: @job.source_id)
      @source_task = comment&.task
    end

    def task_from_proposal(proposal)
      task_id = proposal['task_id'].presence || proposal.dig('target', 'task_id').presence || proposal.dig('task', 'id').presence
      task = TaskHub::Task.visible_to(@job.user).find_by(id: task_id) if task_id.present? && defined?(TaskHub::Task)
      return task if task && (@job.user.admin? || @job.user.allowed_to?(:manage_task_hub_tasks, task.project))

      source_task
    end

    def idempotency_key(action_type, proposal)
      proposal['idempotency_key'].presence || Digest::SHA256.hexdigest([
        @job.idempotency_key,
        action_type,
        proposal.to_json
      ].join(':'))
    end

    def project_setting
      @project_setting ||= AutomyraBridgeProjectSetting.for_project(@job.project)
    end

    def valid_proposal?(action_type, proposal)
      return true unless AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES.include?(action_type)

      return issue_from_proposal(proposal).present? if action_type == 'assign_issue_to_requester'
      return proposal.dig('comment', 'body').to_s.strip.present? && issue_from_proposal(proposal).present? if action_type == 'add_issue_comment'
      return proposal.dig('issue', 'subject').present? if action_type == 'create_issue'
      return issue_from_proposal(proposal).present? && proposal['issue'].is_a?(Hash) if action_type == 'update_issue'
      return issue_from_proposal(proposal).present? && proposal.dig('assignment', 'assigned_to_id').present? if action_type == 'assign_issue'
      return issue_from_proposal(proposal).present? && proposal.dig('issue', 'status_id').present? if action_type == 'set_issue_status'
      return issue_from_proposal(proposal).present? && proposal.dig('issue', 'priority_id').present? if action_type == 'set_issue_priority'
      return issue_from_proposal(proposal).present? && proposal.dig('issue', 'due_date').present? if action_type == 'set_issue_due_date'
      return issue_from_proposal(proposal).present? && proposal.dig('target', 'related_issue_id').present? if action_type == 'link_related_issue'
      return true if %w[search_issues summarize_issue].include?(action_type)
      return proposal.dig('wiki', 'title').present? if %w[read_wiki create_wiki_page update_wiki create_wiki_draft summarize_wiki wiki_backlinks wiki_related_pages].include?(action_type)
      return true if action_type == 'search_wiki'
      return true if action_type.start_with?('context_') || action_type == 'project_status_summary'
      task = task_from_proposal(proposal)
      return task.present? if %w[cancel_task complete_task reopen_task search_tasks].include?(action_type)
      return task.present? && proposal.dig('assignment', 'assigned_to_id').present? if action_type == 'assign_task'
      return task.present? && proposal.dig('task', 'priority').present? if action_type == 'set_task_priority'
      return task.present? && proposal.dig('task', 'due_date').present? if action_type == 'set_task_due_date'
      return task.present? && proposal.dig('comment', 'body').to_s.strip.present? if action_type == 'add_task_comment'
      return task.present? && proposal.dig('target', 'issue_id').present? if action_type == 'link_task_issue'
      return task.present? if action_type == 'promote_task'

      task = proposal['task']
      return false unless task.is_a?(Hash)
      return task['title'].to_s.strip.present? if action_type == 'create_task'

      task.slice('title', 'notes', 'status', 'priority', 'due_date', 'category_id', 'tags').values.any?(&:present?)
    end

    def task_required?(action_type)
      %w[update_task cancel_task complete_task reopen_task assign_task set_task_priority set_task_due_date add_task_comment link_task_issue promote_task].include?(action_type)
    end

    def read_action?(action_type)
      AutomyraBridge::ToolRegistry.find_by_legacy_action(action_type)&.risk_level == 'read'
    end

    def issue_from_proposal(proposal)
      issue_id = proposal.dig('target', 'issue_id').presence || proposal['issue_id'].presence || @job.payload['issue_id'].presence
      Issue.find_by(id: issue_id)
    end

    def proposal_status(action_type, enabled, valid)
      AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES.include?(action_type) && enabled && valid ? 'pending' : 'failed'
    end

    def proposal_error(action_type, enabled, valid)
      return 'Unsupported Automyra write proposal.' unless AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES.include?(action_type)
      return 'Malformed Automyra write proposal.' unless valid
      return 'Automyra action is disabled for this project.' unless enabled
      return nil if AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES.include?(action_type)
    end

    def record_chat_proposal_created(record)
      AuditRecorder.record(
        'chat_proposal_created',
        record.user,
        project_id: record.project_id,
        correlation_id: record.automyra_bridge_job&.correlation_id,
        proposal_id: record.id,
        job_id: record.automyra_bridge_job_id,
        action_type: record.action_type,
        status: record.status
      )
    rescue StandardError
    end

    def record_run_proposal_created(record)
      run = run_for(record.automyra_bridge_job)
      return unless run

      AutomyraBridge::RunEventRecorder.record(
        run: run,
        event_type: 'action_proposal.created',
        status: record.status,
        message: 'This action can modify Redmica data and requires operator approval.',
        payload: {
          proposal_id: record.id,
          action_type: record.action_type,
          risk_level: proposal_risk_level(record),
          reason: proposal_approval_reason(record),
          status: 'pending'
        },
        visible_to_user: true,
        created_by: record.user,
        sequence: proposal_event_sequence(record, 'created')
      )
    rescue StandardError => e
      Rails.logger.warn("Automyra proposal run event failed for #{record&.id}: #{e.message}") if defined?(Rails)
    end

    def run_for(job)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists? && job

      AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    end

    def proposal_event_sequence(record, suffix)
      Digest::SHA256.hexdigest("action_proposal:#{record.id}:#{suffix}").to_i(16) % 1_000_000_000
    end

    def proposal_risk_level(record)
      AutomyraBridge::ToolRegistry.find_by_legacy_action(record.action_type)&.risk_level.presence || 'write'
    end

    def proposal_approval_reason(record)
      risk_level = proposal_risk_level(record)
      return 'This read-only action is being shown for review before Automyra continues.' if risk_level == 'read'

      'This action can modify Redmica data and requires operator approval.'
    end
  end
end
