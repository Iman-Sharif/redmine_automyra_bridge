module AutomyraBridge
  module GovernanceHelper
    def governance_object_link(record)
      object = governance_link_target(record)
      label = governance_object_label(record)

      return label unless object

      case object
      when Attachment
        link_to(label, attachment_path(object))
      when Issue
        link_to(label, issue_path(object))
      when TaskHub::Task
        link_to(label, task_hub_standalone_path(object))
      when WikiHub::PageSnapshot
        link_to(label, project_wiki_page_path(object.project.identifier, object.title))
      else
        label
      end
    end

    def governance_run_copy_text(run)
      [
        "Run ##{run.id}",
        "Policy: #{run.governance_policy.name}",
        "Status: #{run.status}",
        "Reason: #{run.error_message.presence || '—'}",
        "Findings: #{run.findings_count}",
        "Actions: #{run.actions_count}",
        "Applied: #{run.applied_count}",
        "Provider: #{run.provider_model_used.presence || '—'}",
        "Created: #{format_time(run.created_at)}",
        "Policy source hash: #{run.policy_source_hash.presence || '—'}",
        "Prompt hash: #{run.prompt_hash.presence || '—'}",
        "Response hash: #{run.response_hash.presence || '—'}",
        "Run URL: #{automyra_bridge_governance_run_url(run, { project_id: run.governance_policy.project_id }.compact)}"
      ].join("\n")
    end

    private

    def governance_link_target(record)
      case record.object_type.to_s
      when 'Attachment'
        Attachment.find_by(id: record.object_id)
      when 'Issue'
        Issue.visible.find_by(id: record.object_id)
      when 'TaskHub::Task'
        defined?(TaskHub::Task) ? TaskHub::Task.find_by(id: record.object_id) : nil
      when 'WikiHub::PageSnapshot'
        defined?(WikiHub::PageSnapshot) ? WikiHub::PageSnapshot.find_by(id: record.object_id) : nil
      else
        nil
      end
    end

    def governance_object_label(record)
      "#{governance_object_type_name(record.object_type)} ##{record.object_id}"
    end

    def governance_object_type_name(object_type)
      object_type.to_s.gsub('WikiHub::PageSnapshot', 'Wiki page').gsub('TaskHub::Task', 'Task').gsub('Attachment', 'Attachment')
    end
  end
end
