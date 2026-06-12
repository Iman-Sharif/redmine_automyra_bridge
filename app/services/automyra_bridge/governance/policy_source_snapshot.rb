require 'digest'

module AutomyraBridge
  module Governance
    class PolicySourceSnapshot
      def self.hash(policy:, config: nil)
        new(policy: policy, config: config).hash
      end

      def initialize(policy:, config: nil)
        @policy = policy
        @config = (config || PolicyLoader.normalize_policy_config(policy)).deep_stringify_keys
      end

      def hash
        Digest::SHA256.hexdigest(stable_json(@config))
      end

      private

      def stable_json(value)
        case value
        when Hash
          ordered = value.keys.map(&:to_s).sort.index_with do |key|
            JSON.parse(stable_json(value[key]))
          end
          JSON.generate(ordered)
        when Array
          JSON.generate(value.map { |item| JSON.parse(stable_json(item)) })
        else
          JSON.generate(value)
        end
      end
    end
  end
end
