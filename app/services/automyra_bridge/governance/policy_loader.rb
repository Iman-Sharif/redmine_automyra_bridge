module AutomyraBridge
  module Governance
    class PolicyLoader
      LoadedPolicy = Struct.new(:policy, :config, keyword_init: true)

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(project: nil, policy_id: nil, due: false, now: Time.current)
        @project = project
        @policy_id = policy_id
        @due = due
        @now = now
      end

      def call
        scope.map { |policy| LoadedPolicy.new(policy: policy, config: normalize_config(policy)) }
      end

      private

      def scope
        policies = AutomyraBridge::GovernancePolicy.enabled
        policies = policies.where(project_id: @project.id) if @project
        policies = policies.where(id: @policy_id) if @policy_id
        policies = policies.order(:id)
        return policies.to_a.select { |policy| due?(policy) } if @due

        policies
      end

      def due?(policy)
        return true if policy.last_run_at.blank? || policy.frequency_hours.blank?

        policy.last_run_at <= @now - policy.frequency_hours.to_i.hours
      end

      def normalize_config(policy)
        self.class.normalize_policy_config(policy)
      end

      def self.normalize_policy_config(policy)
        parsed = parse_json(policy.config)
        wiki_config = parsed_wiki_config(policy)
        base_config(policy).merge(parsed).merge(wiki_config).deep_stringify_keys
      end

      def self.parse_json(raw)
        return {} if raw.blank?

        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end

      def self.base_config(policy)
        {
          mode: policy.mode,
          provider_model: policy.provider_model,
          max_changes_per_run: policy.max_changes_per_run,
          confidence_threshold: policy.confidence_threshold&.to_f,
          frequency_hours: policy.frequency_hours,
          exclusions: policy.exclusions,
          scope_wiki_pages: policy.scope_wiki_pages,
          scope_tasks: policy.scope_tasks,
          scope_requirement_links: policy.scope_requirement_links,
          scope_wiki_requirement_links: policy.scope_wiki_requirement_links,
          scope_task_requirement_links: policy.scope_task_requirement_links,
          scope_attachments: policy.respond_to?(:scope_attachments) ? policy.scope_attachments : nil
        }.compact
      end

      def self.parsed_wiki_config(policy)
        return {} if policy.policy_page_id.blank?

        raw_text = WikiPolicyLoader.call(page_profile_id: policy.policy_page_id)
        WikiPolicyParser.parse(raw_text).merge(
          'standard_wiki_page' => WikiPolicyLoader.context(page_profile_id: policy.policy_page_id)
        )
      rescue StandardError => e
        Rails.logger.warn("Automyra wiki policy load failed for policy #{policy&.policy_page_id}: #{e.class}: #{e.message}") if defined?(Rails)
        {}
      end
    end
  end
end
