module AutomyraBridge
  module Governance
    module Collectors
      class RequirementCollector < BaseCollector
        def self.call(**kwargs)
          new(**kwargs).call
        end

        def call
          return [] unless project || policy&.global?

          project_ids = policy&.global? ? active_project_ids : [project.id]
          scope = Issue.joins(:project).where(project_id: project_ids, projects: { status: Project::STATUS_ACTIVE })
          scope = scope.where(tracker_id: tracker_ids) if tracker_ids.any?
          scope = scope.where(status_id: status_ids) if status_ids.any?
          scope = filter_by_custom_field(scope)
          scope.order(:id).limit(limit).map { |issue| candidate(issue) }
        end

        private

        def tracker_ids
          ids = Array(config['requirement_tracker_ids']).map(&:to_i).reject(&:zero?)
          names = Array(config['requirement_tracker_names']).map(&:to_s).reject(&:blank?)
          ids.concat(Tracker.where(name: names).pluck(:id)) if names.any?
          ids.uniq
        end

        def status_ids
          ids = Array(config['requirement_status_ids']).map(&:to_i).reject(&:zero?)
          names = Array(config['requirement_status_names']).map(&:to_s).reject(&:blank?)
          ids.concat(IssueStatus.where(name: names).pluck(:id)) if names.any?
          ids.uniq
        end

        def custom_field_id
          configured = config['requirement_custom_field_id'].to_i
          return configured if configured.positive? || config['requirement_custom_field_name'].blank?

          IssueCustomField.find_by(name: config['requirement_custom_field_name'].to_s)&.id.to_i
        end

        def filter_by_custom_field(scope)
          return scope unless custom_field_id.positive?

          values = Array(config['requirement_custom_field_values']).map(&:to_s).reject(&:blank?)
          filtered = scope.joins(:custom_values).where(custom_values: { custom_field_id: custom_field_id })
          values.any? ? filtered.where(custom_values: { value: values }) : filtered
        end

        def candidate(issue)
          {
            object_type: 'Issue',
            object_id: issue.id,
            subject: issue.subject,
            tracker: issue.tracker&.name,
            status: issue.status&.name,
            project_id: issue.project_id,
            current_value: issue.subject
          }
        end
      end
    end
  end
end
