require 'digest'

module AutomyraBridge
  module Governance
    class FakeProvider
      attr_reader :calls

      def initialize(responses = {})
        @responses = responses.stringify_keys
        @calls = []
      end

      def call(prompt:, model:, metadata: {})
        prompt_hash = Digest::SHA256.hexdigest(prompt.to_s)
        batch_id = metadata[:batch_id] || metadata['batch_id']
        @calls << { prompt: prompt, model: model, metadata: metadata, prompt_hash: prompt_hash }
        response = @responses[prompt_hash] || @responses[batch_id.to_s] || @responses['default']
        response.is_a?(String) ? response : response.to_json
      end
    end
  end
end
