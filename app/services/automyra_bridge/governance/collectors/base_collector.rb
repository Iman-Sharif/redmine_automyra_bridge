module AutomyraBridge
  module Governance
    module Collectors
      class BaseCollector
        DEFAULT_LIMIT = 100

        def initialize(policy: nil, project: nil, exclusions: nil, limit: nil)
          @policy = policy
          @project = project || policy&.project
          @config = policy ? AutomyraBridge::Governance::PolicyLoader.normalize_policy_config(policy) : {}
          @exclusions = Array(exclusions || @config['exclusions']).flat_map { |entry| entry.to_s.split(/[,\n]/) }.map(&:strip).reject(&:blank?)
          @limit = (limit || @config['batch_size'] || @config['max_changes_per_run'] || DEFAULT_LIMIT).to_i
          @limit = DEFAULT_LIMIT if @limit <= 0
        end

        private

        attr_reader :policy, :project, :config, :exclusions, :limit

        def active_project_ids
          ids = governable_active_project_ids
          configured_ids = Array(config['project_ids']).map(&:to_i).reject(&:zero?)
          configured_identifiers = Array(config['project_identifiers']).map(&:to_s).reject(&:blank?)
          ids &= configured_ids if configured_ids.any?
          ids &= Project.where(identifier: configured_identifiers).pluck(:id) if configured_identifiers.any?
          ids
        end

        def governable_active_project_ids
          user = policy&.created_by || User.current
          scope = Project.where(status: Project::STATUS_ACTIVE)
          return scope.pluck(:id) if user&.admin?

          scope.select { |project| user&.allowed_to?(:manage_automyra_bridge, project) }.map(&:id)
        end

        def active_project_scope(relation, table_name)
          project_ids = policy&.global? ? active_project_ids : [project&.id].compact
          relation.joins(:project).where(projects: { status: Project::STATUS_ACTIVE })
                  .where(table_name => { project_id: project_ids })
        end

        def excluded?(value)
          exclusions.any? do |pattern|
            File.fnmatch?(pattern, value.to_s, File::FNM_CASEFOLD) || value.to_s.casecmp?(pattern)
          end
        end
      end
    end
  end
end
