module AutomyraBridge
  module FinalAnswerGuard
    INCOMPLETE_INTENT_PHRASES = [
      "I'll search",
      'Let me check',
      "I'll look that up",
      'One moment',
      "I'll find out",
      'Let me see',
      "I'm checking",
      'Searching...'
    ].freeze

    module_function

    def call(response_text:, tool_calls_present:, has_tool_results:)
      incomplete = incomplete?(response_text, tool_calls_present, has_tool_results)

      {
        incomplete: incomplete,
        reason: incomplete ? 'detected_promise_without_tool_call' : 'no_data',
        confidence: 'high'
      }
    end

    def incomplete?(response_text, tool_calls_present, has_tool_results)
      return false if tool_calls_present || has_tool_results

      text = response_text.to_s
      INCOMPLETE_INTENT_PHRASES.any? { |phrase| text.match?(/#{Regexp.escape(phrase)}/i) }
    end
  end
end
