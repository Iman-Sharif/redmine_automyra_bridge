require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeFinalAnswerGuardTest < ActiveSupport::TestCase
  test 'detects promise without tool call phrases case insensitively' do
    [
      "I'll search Redmica now.",
      'let me check that for you.',
      "I'LL LOOK THAT UP.",
      'One moment while I inspect it.',
      "I'll find out.",
      'Let me see what is assigned to you.',
      "I'm checking your tasks.",
      'Searching...'
    ].each do |text|
      result = AutomyraBridge::FinalAnswerGuard.call(response_text: text, tool_calls_present: false, has_tool_results: false)

      assert_equal true, result[:incomplete], "Expected #{text.inspect} to be incomplete"
      assert_equal 'detected_promise_without_tool_call', result[:reason]
      assert_equal 'high', result[:confidence]
    end
  end

  test 'does not flag promises when tool calls or tool results exist' do
    assert_equal false, AutomyraBridge::FinalAnswerGuard.call(response_text: "I'll search", tool_calls_present: true, has_tool_results: false)[:incomplete]
    assert_equal false, AutomyraBridge::FinalAnswerGuard.call(response_text: "I'll search", tool_calls_present: false, has_tool_results: true)[:incomplete]
  end
end
