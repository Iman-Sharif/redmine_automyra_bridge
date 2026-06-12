module AutomyraBridge
  class ActionProposalExecutor
    ALLOWED_ATTRIBUTES = %w[title notes status due_date assigned_to_id priority tags category_id].freeze

    def approve(proposal, user, skip_permission: false, silent: false)
      return forbidden(proposal) unless skip_permission || tool_authorized?(proposal, user)

      AutomyraBridgeActionProposal.transaction do
        proposal.lock!
        return false unless proposal.status == 'pending'

        proposal.update!(status: 'approved', approved_by: user, decided_at: Time.current)
        record_proposal_decision_event(proposal, user, 'approved')
        execute(proposal, user, silent: silent)
      end
    rescue StandardError => e
      proposal.update!(status: 'failed', error_message: e.message)
      Rails.logger.warn("Automyra proposal #{proposal.id} failed: #{e.class}: #{e.message}") if defined?(Rails)
      false
    end

    def reject(proposal, user)
      return forbidden(proposal) unless tool_authorized?(proposal, user)

      AutomyraBridgeActionProposal.transaction do
        proposal.lock!
        return false unless proposal.status == 'pending'

        proposal.update!(status: 'rejected', approved_by: user, decided_at: Time.current)
        record_proposal_decision_event(proposal, user, 'rejected')
        post_decision_comment(proposal, user, 'rejected')
        record_chat_proposal_audit(proposal, user, 'chat_proposal_rejected')
        true
      end
    end

    private

    def execute(proposal, user, silent: false)
      raise 'Unsupported Automyra write proposal.' unless AutomyraBridgeActionProposal::SUPPORTED_ACTION_TYPES.include?(proposal.action_type)

      tool = AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)
      raise 'Unsupported Automyra write proposal.' unless tool

      result = tool.call(proposal_job(proposal), user, proposal.payload)
      tool.verify!(result, proposal.payload)
      proposal.update!(status: 'executed', result_payload: result.to_json, executed_at: Time.current)
      record_proposal_decision_event(proposal, user, 'executed')
      post_decision_comment(proposal, user, 'approved') unless silent
      record_chat_proposal_audit(proposal, user, 'chat_proposal_approved')
      write_approved_proposal_memory(proposal, user)
      record_proposal_activity_log(proposal)
      true
    end

    def attributes(proposal)
      proposal.payload.fetch('task', proposal.payload).slice(*ALLOWED_ATTRIBUTES).compact
    end

    def tool_authorized?(proposal, user)
      return true if user.admin?

      tool = AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)
      return false unless tool

      tool.authorized?(proposal_job(proposal), user)
    end

    def forbidden(proposal)
      proposal.update!(status: 'failed', error_message: 'User is not allowed to approve this proposal.')
      false
    end

    def proposal_job(proposal)
      job = proposal.automyra_bridge_job
      return job unless proposal.task && job.source_type == 'TaskHub::TaskComment'

      job
    end

    def post_decision_comment(proposal, user, decision)
      task = proposal.task || source_task(proposal)
      return unless task

      task.comments.create!(author: user, body: decision_body(proposal, decision))
    end

    def source_task(proposal)
      return unless proposal.automyra_bridge_job.source_type == 'TaskHub::TaskComment'

      TaskHub::TaskComment.find_by(id: proposal.automyra_bridge_job.source_id)&.task
    end

    def decision_body(proposal, decision)
      action = proposal.action_type.humanize.downcase
      "Automyra proposal #{decision}: #{action}."
    end

    def record_chat_proposal_audit(proposal, user, event_type)
      return unless proposal.automyra_bridge_job

      job = proposal.automyra_bridge_job
      AuditRecorder.record(
        event_type,
        user,
        project_id: proposal.project_id,
        correlation_id: job.correlation_id,
        proposal_id: proposal.id,
        job_id: job.id,
        action_type: proposal.action_type,
        decision: proposal_decision_for(event_type)
      )
    rescue StandardError
    end

    def record_proposal_activity_log(proposal)
      AutomyraBridge::ActivityLogger.log!(
        action_type: 'proposal_executed',
        source: 'bridge_executor',
        summary: "Executed proposal: #{proposal_activity_summary(proposal)}",
        session_id: proposal.automyra_bridge_job&.correlation_id,
        target_type: proposal.target_type,
        target_id: proposal.target_id,
        project_id: proposal.project_id,
        user_id: proposal.user_id,
        details: { proposal_id: proposal.id, action_type: proposal.action_type }
      )
    rescue StandardError => e
      Rails.logger.warn("Automyra proposal activity log failed for #{proposal&.id}: #{e.message}") if defined?(Rails)
    end

    def proposal_activity_summary(proposal)
      summary = proposal.payload['summary'].presence ||
                proposal.payload['title'].presence ||
                proposal.action_type.to_s.humanize
      summary.to_s.truncate(100)
    end

    def proposal_decision_for(event_type)
      event_type.to_s.delete_prefix('chat_proposal_').presence || event_type
    end

    def write_approved_proposal_memory(proposal, user)
      job = proposal.automyra_bridge_job
      return unless job

      container = memory_container(job)
      return unless container

      AutomyraBridge::MemoryWriter.write(
        container: container,
        user: user,
        role: 'action',
        event_type: 'action_executed',
        content: "Approved proposal executed: #{proposal.action_type}.",
        payload: {
          proposal_id: proposal.id,
          action_type: proposal.action_type,
          status: proposal.status,
          result: proposal.result_payload
        },
        correlation_id: job.correlation_id,
        journal_id: job.source_type == 'Journal' ? job.source_id : nil,
        **memory_references(job)
      )
    rescue StandardError => e
      Rails.logger.warn("Automyra proposal memory write failed for #{proposal&.id}: #{e.message}") if defined?(Rails)
    end

    def memory_container(job)
      case job.source_type
      when 'AutomyraBridgeChatMessage'
        AutomyraBridgeChatMessage.find_by(id: job.source_id)&.chat_thread
      when 'TaskHub::TaskComment'
        TaskHub::TaskComment.find_by(id: job.source_id)&.task
      when 'Journal'
        Journal.find_by(id: job.source_id)&.journalized
      end
    end

    def memory_references(job)
      return { job_id: job.id } unless job.source_type == 'AutomyraBridgeChatMessage'

      thread = memory_container(job)
      run = run_for(job)
      {
        chat_thread_id: thread&.id,
        chat_message_id: job.source_id,
        run_id: run&.id,
        snapshot_reference: thread&.page_key.presence || thread&.title_display,
        job_id: job.id
      }
    end

    def run_for(job)
      return unless defined?(AutomyraBridgeRun) && AutomyraBridgeRun.table_exists?

      AutomyraBridgeRun.find_by(source_type: job.source_type, source_id: job.source_id)
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridgeRun lookup failed for job #{job&.id}: #{e.message}") if defined?(Rails)
      nil
    end

    def record_proposal_decision_event(proposal, user, decision)
      run = run_for(proposal.automyra_bridge_job)
      return unless run

      changed_at = (proposal.decided_at || Time.current).utc.iso8601(3)
      payload = {
        proposal_id: proposal.id,
        action_type: proposal.action_type,
        risk_level: proposal_risk_level(proposal),
        reason: proposal_approval_reason(proposal),
        status: decision,
        result: proposal_result_payload(proposal),
        changed_at: changed_at
      }

      AutomyraBridge::RunEventRecorder.record(
        run: run,
        event_type: 'proposal.status_changed',
        status: decision,
        message: proposal_decision_message(proposal, decision),
        payload: payload,
        visible_to_user: true,
        created_by: user,
        sequence: proposal_event_sequence(proposal, decision)
      )

      AutomyraBridge::RunEventRecorder.record(
        run: run,
        event_type: "action_proposal.#{decision}",
        status: decision,
        message: proposal_decision_message(proposal, decision),
        payload: payload,
        visible_to_user: true,
        created_by: user,
        sequence: proposal_event_sequence(proposal, "proposal_#{decision}")
      )
    rescue StandardError => e
      Rails.logger.warn("Automyra proposal decision run event failed for #{proposal&.id}: #{e.message}") if defined?(Rails)
    end

    def proposal_event_sequence(proposal, suffix)
      Digest::SHA256.hexdigest("action_proposal:#{proposal.id}:#{suffix}").to_i(16) % 1_000_000_000
    end

    def proposal_decision_message(proposal, decision)
      "Automyra proposal #{decision}: #{proposal.action_type.humanize.downcase}."
    end

    def proposal_risk_level(proposal)
      AutomyraBridge::ToolRegistry.find_by_legacy_action(proposal.action_type)&.risk_level.presence || 'write'
    end

    def proposal_approval_reason(proposal)
      risk_level = proposal_risk_level(proposal)
      return 'This read-only action is being shown for review before Automyra continues.' if risk_level == 'read'

      'This action can modify Redmica data and requires operator approval.'
    end

    def proposal_result_payload(proposal)
      JSON.parse(proposal.result_payload.to_s.presence || '{}')
    rescue JSON::ParserError
      proposal.result_payload
    end
  end
end
