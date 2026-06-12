require File.expand_path('../test_helper', __dir__)

class ChatThreadChannelResolverTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
  end

  test 'builds global user key' do
    assert_equal "global:user:#{@user.id}", AutomyraBridge::ChatThreadChannelResolver.channel_key(user: @user, thread_kind: 'global')
  end

  test 'builds project key from project id' do
    assert_equal 'project:5', AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'project', page_id: 5)
  end

  test 'builds issue key' do
    assert_equal 'issue:123', AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'Issue', page_id: 123)
  end

  test 'builds wiki page key' do
    assert_equal 'wiki_page:77', AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'WikiPage', page_id: 77)
  end

  test 'builds task hub task key' do
    assert_equal 'task_hub_task:9', AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'TaskHub::Task', page_id: 9)
  end

  test 'builds generic key with stable url hash' do
    first = AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'activity', page_id: 0, project_id: 42, url_path: '/projects/demo/activity')
    second = AutomyraBridge::ChatThreadChannelResolver.channel_key(page_type: 'generic', page_id: 0, project_id: 42, url_path: '/projects/demo/activity')

    assert_equal first, second
    assert_match(/\Ageneric:42:[0-9a-f]{16}\z/, first)
  end
end
