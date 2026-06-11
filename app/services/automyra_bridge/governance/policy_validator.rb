module AutomyraBridge
  module Governance
    class PolicyValidator
      Result = Struct.new(:valid?, :errors, keyword_init: true)

      SCOPE_KEYS = %w[scope_wiki_pages scope_tasks scope_attachments scope_requirement_links scope_wiki_requirement_links scope_task_requirement_links].freeze

      def self.call(policy:, config: nil)
        new(policy: policy, config: config).call
      end

      def initialize(policy:, config: nil)
        @policy = policy
        @config = (config || PolicyLoader.normalize_policy_config(policy)).deep_stringify_keys
        @errors = []
      end

      def call
        validate_mode
        validate_provider_model
        validate_scopes
        validate_limits
        validate_requirement_link_schema
        Result.new(valid?: @errors.empty?, errors: @errors)
      end

      private

      def validate_mode
        return if AutomyraBridge::GovernancePolicy::MODES.include?(@config['mode'].to_s)

        @errors << 'mode is not included in the list'
      end

      def validate_provider_model
        @errors << 'provider_model cannot be blank' if @config['provider_model'].blank?
      end

      def validate_scopes
        return if SCOPE_KEYS.any? { |key| truthy?(@config[key]) }

        @errors << 'at least one governance scope must be enabled'
      end

      def validate_limits
        validate_minimum('max_changes_per_run', 0)
        validate_range('confidence_threshold', 0.0, 1.0)
        validate_minimum('frequency_hours', 1)
      end

      def validate_requirement_link_schema
        return unless truthy?(@config['scope_requirement_links']) || truthy?(@config['scope_wiki_requirement_links']) || truthy?(@config['scope_task_requirement_links'])
        return if Array(@config['requirement_tracker_ids']).any? || Array(@config['requirement_tracker_names']).any? || @config['requirement_custom_field_id'].present? || @config['requirement_custom_field_name'].present?

        @errors << 'requirement linking requires requirement_tracker_ids, requirement_tracker_names, requirement_custom_field_id, or requirement_custom_field_name'
      end

      def validate_minimum(key, minimum)
        return if @config[key].blank? || @config[key].to_i >= minimum

        @errors << "#{key} must be greater than or equal to #{minimum}"
      end

      def validate_range(key, min, max)
        return if @config[key].blank?

        value = @config[key].to_f
        return if value >= min && value <= max

        @errors << "#{key} must be between #{min.to_i} and #{max.to_i}"
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.downcase)
      end
    end
  end
end
