require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeWikiCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :wikis, :wiki_pages, :wiki_contents

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_wiki_review' => 'https://automyra.bundecca.co.uk/webhooks/redmica-wiki-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_WIKI_REVIEW'] = '1'

    # The hook is installed at boot; ensure it is present for unit tests.
    AutomyraBridge::WikiCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_WIKI_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Create hook ---------------------------------------------------------

  test 'fires webhook when wiki content is created by regular user' do
    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "TestPage_#{SecureRandom.hex(4)}")

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      WikiContent.create!(page: new_page, text: 'Initial wiki text', author: @user)
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "BotPage_#{SecureRandom.hex(4)}")

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      WikiContent.create!(page: new_page, text: 'Bot-authored wiki text', author: admin_user)
    end
  end

  # --- 2. Update hook ---------------------------------------------------------

  test 'fires webhook when wiki content text changes' do
    content = WikiContent.find(1)
    content.author = @user

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      content.update!(text: 'Updated wiki text body')
    end
  end

  test 'does not fire update webhook on metadata-only change' do
    content = WikiContent.find(1)
    content.author = @user
    content.comments = 'First save to establish baseline'
    content.update!(text: 'Baseline text for metadata-only test')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      content.update!(comments: 'This is only a comment change')
    end
  end

  # --- 3. Environment flag gating ---------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_WIKI_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_WIKI_REVIEW')

    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "FlagOffPage_#{SecureRandom.hex(4)}")

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      WikiContent.create!(page: new_page, text: 'Flag off create test', author: @user)
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_WIKI_REVIEW is unset' do
    content = WikiContent.find(1)
    content.author = @user
    content.update!(text: 'Baseline for flag-off update test')
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_WIKI_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      content.update!(text: 'Flag off update test body')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_WIKI_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_WIKI_REVIEW'] = '0'

    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "ZeroFlagPage_#{SecureRandom.hex(4)}")

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      WikiContent.create!(page: new_page, text: 'Zero flag create test', author: @user)
    end
  end

  # --- 4. Thread-local skip flag ---------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "SkipPage_#{SecureRandom.hex(4)}")

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      WikiContent.create!(page: new_page, text: 'Skip flag create test', author: @user)
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    content = WikiContent.find(1)
    content.author = @user
    content.update!(text: 'Baseline for skip update test')
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      content.update!(text: 'Skip flag update test body')
    end
  end

  # --- 5. Dispatcher payload shape -------------------------------------------

  test 'payload includes all required AC8 domain keys plus event_type' do
    content = build_wiki_content_with_regular_author(text: 'Payload test body')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.wiki_created', event_type

    assert_equal content.page_id, payload['wiki_page_id']
    assert_equal content.page.title, payload['wiki_page_title']
    assert_equal content.version, payload['wiki_content_version']
    assert_equal 'Payload test body', payload['text_preview']
    assert_equal @project.identifier, payload['project_id']
    assert_equal @project.name, payload['project_name']
    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_name']
    assert payload['created_at']
    assert payload['url'].include?(content.page.title)
    assert payload['timestamp']

    assert_equal "wiki-creation-#{content.page_id}-v#{content.version}", delivery_id
  end

  # --- 6. Text preview truncation -------------------------------------------

  test 'text preview is truncated to 2000 characters' do
    long_text = 'a' * 3000
    build_wiki_content_with_regular_author(text: long_text)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    payload = job[:args][1]
    assert payload['text_preview'].length <= 2000,
           "text_preview must be truncated to <= 2000 chars (got #{payload['text_preview'].length})"
  end

  # --- 7. Update delivery ID format ------------------------------------------

  test 'update delivery id uses wiki-update-{page_id}-v{version} format' do
    content = WikiContent.find(1)
    content.author = @user
    content.update!(text: 'Delivery ID update test')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.wiki_updated', event_type
    assert_equal "wiki-update-#{content.page_id}-v#{content.version}", delivery_id
  end

  # --- 8. Activity log --------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    content = WikiContent.find(1).tap { |c| c.author = @user }
    AutomyraBridge::WikiReviewDispatcher.dispatch_create(content)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'wiki_created_webhook_dispatched', log.action_type
    assert_equal 'WikiPage', log.target_type
    assert_equal content.page_id, log.target_id.to_i
  end

  test 'activity log entry is written on update dispatch' do
    content = WikiContent.find(1).tap { |c| c.author = @user }
    AutomyraBridge::WikiReviewDispatcher.dispatch_update(content)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'wiki_updated_webhook_dispatched', log.action_type
    assert_equal 'WikiPage', log.target_type
    assert_equal content.page_id, log.target_id.to_i
  end

  # --- 9. Error rescue --------------------------------------------------------

  test 'dispatcher rescues errors on create without raising' do
    content = WikiContent.find(1).tap { |c| c.author = @user }
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::WikiReviewDispatcher.dispatch_create(content)
    end
  end

  test 'dispatcher rescues errors on update without raising' do
    content = WikiContent.find(1).tap { |c| c.author = @user }
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::WikiReviewDispatcher.dispatch_update(content)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def build_wiki_content_with_regular_author(text:)
    page = WikiPage.find(1)
    new_page = WikiPage.create!(wiki: page.wiki, title: "PayloadPage_#{SecureRandom.hex(4)}")
    WikiContent.create!(page: new_page, text: text, author: @user)
  end
end
