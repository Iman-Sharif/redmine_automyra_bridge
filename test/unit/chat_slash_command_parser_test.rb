require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeChatSlashCommandParserTest < ActiveSupport::TestCase
  test 'parses leading slash command with normalized command and args' do
    parsed = AutomyraBridge::ChatSlashCommandParser.parse('/Tasks Open')

    assert_equal 'tasks', parsed[:command]
    assert_equal ['Open'], parsed[:args]
    assert_equal '/Tasks Open', parsed[:raw]
  end

  test 'ignores normal chat content' do
    assert_nil AutomyraBridge::ChatSlashCommandParser.parse('please /help me')
  end
end
