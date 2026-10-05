require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeMentionDetectorTest < ActiveSupport::TestCase
  test 'detects @automyra mention' do
    assert AutomyraBridge::MentionDetector.mentioned?('Please help @automyra')
    assert_equal :automyra, AutomyraBridge::MentionDetector.mention_target('Please help @automyra')
  end

  test 'detects @redmyra mention' do
    assert AutomyraBridge::MentionDetector.mentioned?('@Redmyra review this')
    assert_equal :automyra, AutomyraBridge::MentionDetector.mention_target('@Redmyra review this')
  end

  test 'detects @mrt mention with default pattern' do
    assert AutomyraBridge::MentionDetector.mentioned?('Hey @mrt can you check this')
    assert_equal :mr_t, AutomyraBridge::MentionDetector.mention_target('Hey @mrt can you check this')
  end

  test 'detects @mrt at start of text' do
    assert AutomyraBridge::MentionDetector.mentioned?('@mrt please review')
    assert_equal :mr_t, AutomyraBridge::MentionDetector.mention_target('@mrt please review')
  end

  test 'does not match @mrt as substring of longer word' do
    assert_not AutomyraBridge::MentionDetector.mentioned?('Hey @mrtx check this')
    assert_nil AutomyraBridge::MentionDetector.mention_target('Hey @mrtx check this')
  end

  test 'case insensitive Mr T detection' do
    assert AutomyraBridge::MentionDetector.mentioned?('Hey @MRT check this')
    assert_equal :mr_t, AutomyraBridge::MentionDetector.mention_target('Hey @MRT check this')
    assert AutomyraBridge::MentionDetector.mentioned?('Hey @Mrt check this')
  end

  test 'returns nil for text without any mention' do
    assert_not AutomyraBridge::MentionDetector.mentioned?('No mention here')
    assert_nil AutomyraBridge::MentionDetector.mention_target('No mention here')
  end

  test 'returns nil for nil text' do
    assert_not AutomyraBridge::MentionDetector.mentioned?(nil)
    assert_nil AutomyraBridge::MentionDetector.mention_target(nil)
  end

  test 'automyra mention takes precedence over mr_t' do
    assert_equal :automyra, AutomyraBridge::MentionDetector.mention_target('@automyra and @mrt')
  end

  test 'respects custom mr_t_mention_pattern setting' do
    original = Setting.plugin_redmine_automyra_bridge
    Setting.plugin_redmine_automyra_bridge = (original.to_h || {}).merge('mr_t_mention_pattern' => 'boss')

    assert AutomyraBridge::MentionDetector.mentioned?('Hey @boss check this')
    assert_equal :mr_t, AutomyraBridge::MentionDetector.mention_target('Hey @boss check this')
    assert_not AutomyraBridge::MentionDetector.mentioned?('Hey @mrt check this')
  ensure
    Setting.plugin_redmine_automyra_bridge = original
  end

  test 'falls back to default pattern when setting is blank' do
    original = Setting.plugin_redmine_automyra_bridge
    Setting.plugin_redmine_automyra_bridge = (original.to_h || {}).merge('mr_t_mention_pattern' => '')

    assert AutomyraBridge::MentionDetector.mentioned?('Hey @mrt check this')
  ensure
    Setting.plugin_redmine_automyra_bridge = original
  end
end
