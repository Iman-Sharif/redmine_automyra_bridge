require 'yaml'

module AutomyraBridge
  module Governance
    class WikiPolicyParser
      KEYS = %w[title_rules frequency_hours max_changes_per_run confidence_threshold mode exclusions provider_model].freeze

      def self.parse(text)
        new(text).parse
      end

      def initialize(text)
        @text = text.to_s
      end

      def parse
        yaml_config.presence || heading_config
      end

      private

      def yaml_config
        @text.scan(/```ya?ml\s*(.*?)```/mi).each do |match|
          data = safe_yaml(match.first)
          config = data['automyra_governance'] if data.is_a?(Hash)
          return normalize(config) if config.is_a?(Hash)
        end
        {}
      end

      def safe_yaml(raw)
        YAML.safe_load(raw.to_s, permitted_classes: [], aliases: false)
      rescue Psych::SyntaxError, Psych::DisallowedClass, StandardError
        nil
      end

      def heading_config
        sections = parse_sections
        config = {}
        config['title_rules'] = sections['title standard'] if sections['title standard'].present?
        config.merge!(parse_key_values(sections['frequency'])) if sections['frequency'].present?
        normalize(config)
      end

      def parse_sections
        sections = {}
        current = nil
        @text.each_line do |line|
          if (match = line.match(/^##\s+(.+?)\s*$/))
            current = match[1].to_s.strip.downcase
            sections[current] = +' '
          elsif current
            sections[current] << line
          end
        end
        sections.transform_values(&:strip)
      end

      def parse_key_values(text)
        config = {}
        text.to_s.each_line do |line|
          key, value = line.split(':', 2).map { |part| part.to_s.strip }
          next unless key.present? && value.present?

          normalized_key = key.downcase.tr(' ', '_')
          config[normalized_key] = value if KEYS.include?(normalized_key)
        end
        config
      end

      def normalize(config)
        return {} unless config.is_a?(Hash)

        config.deep_stringify_keys.slice(*KEYS).tap do |hash|
          integerize!(hash, 'frequency_hours')
          integerize!(hash, 'max_changes_per_run')
          floatize!(hash, 'confidence_threshold')
        end
      end

      def integerize!(hash, key)
        hash[key] = hash[key].to_i if hash.key?(key) && hash[key].present?
      end

      def floatize!(hash, key)
        hash[key] = hash[key].to_f if hash.key?(key) && hash[key].present?
      end
    end
  end
end
