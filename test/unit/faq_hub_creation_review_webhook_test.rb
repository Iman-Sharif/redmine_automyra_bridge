require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeFaqHubCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'admin',
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_faq_review' => 'https://automyra.bundecca.co.uk/webhooks/redmica-faq-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_FAQ_REVIEW'] = '1'

    # The hook is installed at boot; ensure it is present for unit tests.
    AutomyraBridge::FaqHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_FAQ_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Create hook --------------------------------------------------------

  test 'fires webhook when FAQ is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_faq(author: @user)
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_faq(author: admin_user, suffix: 'bot')
    end
  end

  # --- 2. Update hook --------------------------------------------------------

  test 'fires webhook when FAQ title changes' do
    faq = create_faq(author: @user, suffix: 'upd-title')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(title: 'Updated title')
    end
  end

  test 'fires webhook when FAQ answer body changes' do
    faq = create_faq(author: @user, suffix: 'upd-answer', answer: 'Original answer body')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(answer: 'Updated answer body content')
    end
  end

  test 'fires webhook when FAQ status changes' do
    faq = create_faq(author: @user, suffix: 'upd-status')
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(status: 'review')
    end
  end

  test 'does not fire update webhook on metadata-only change (tags)' do
    faq = create_faq(author: @user, suffix: 'meta-only', tags: 'alpha,beta')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(tags: 'alpha,beta,gamma')
    end
  end

  test 'does not fire update webhook on metadata-only change (priority)' do
    faq = create_faq(author: @user, suffix: 'meta-prio')
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(priority: 4)
    end
  end

  # --- 3. Environment flag gating --------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_FAQ_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_FAQ_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_faq(author: @user, suffix: 'flagoff-create')
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_FAQ_REVIEW is unset' do
    faq = create_faq(author: @user, suffix: 'flagoff-update')
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_FAQ_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(title: 'Title changed under flag-off')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_FAQ_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_FAQ_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_faq(author: @user, suffix: 'zero-flag')
    end
  end

  # --- 4. Thread-local skip flag ---------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_faq(author: @user, suffix: 'skip-create')
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    faq = create_faq(author: @user, suffix: 'skip-update')
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      faq.update!(title: 'Skip-flagged update')
    end
  end

  # --- 5. Dispatcher payload shape -------------------------------------------

  test 'payload includes all required keys on create' do
    faq = create_faq(
      author: @user,
      suffix: 'payload',
      title: 'Payload test FAQ',
      short_answer: 'short answer',
      answer: 'full answer body',
      audience: 'end_user',
      system: 'core',
      tags: 'one,two,three'
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.faq_hub.faq_created', event_type

    assert_equal faq.id, payload['faq_id']
    assert_equal 'Payload test FAQ', payload['title']
    assert_equal 'short answer', payload['short_answer']
    assert_equal 'full answer body', payload['answer_preview']
    assert_equal 'end_user', payload['audience']
    assert_equal 'active', payload['status']
    assert_equal 'core', payload['system']
    assert_equal 'one,two,three', payload['tags']

    assert_equal @project.id, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']

    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_login']

    assert payload['url'].include?("/projects/#{@project.identifier}/faq_hub/#{faq.id}")
    assert payload['timestamp']

    # Create delivery id format: faq-review-{id}-{hex16}
    # SecureRandom.hex(8) emits 8 random bytes -> 16 hex characters.
    assert_match(/\Afaq-review-#{faq.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 6. Answer preview truncation -----------------------------------------

  test 'answer preview is truncated to 2000 characters' do
    long_answer = 'b' * 3000
    create_faq(author: @user, suffix: 'long', answer: long_answer)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    payload = job[:args][1]
    assert payload['answer_preview'].length <= 2000,
           "answer_preview must be truncated to <= 2000 chars (got #{payload['answer_preview'].length})"
  end

  # --- 7. Update delivery ID format ------------------------------------------

  test 'update delivery id uses faq-review-update-{id}-{hex8} format' do
    faq = create_faq(author: @user, suffix: 'deliv')
    clear_enqueued_jobs

    faq.update!(title: 'Update delivery id test')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.faq_hub.faq_updated', event_type
    assert_match(/\Afaq-review-update-#{faq.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 8. Activity log -------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    faq = create_faq(author: @user, suffix: 'log-create')
    AutomyraBridge::FaqHubReviewDispatcher.dispatch_create(faq)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'faq_created_webhook_dispatched', log.action_type
    assert_equal 'FaqHub::Faq', log.target_type
    assert_equal faq.id, log.target_id.to_i
  end

  test 'activity log entry is written on update dispatch' do
    faq = create_faq(author: @user, suffix: 'log-update')
    AutomyraBridge::FaqHubReviewDispatcher.dispatch_update(faq)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'faq_updated_webhook_dispatched', log.action_type
    assert_equal 'FaqHub::Faq', log.target_type
    assert_equal faq.id, log.target_id.to_i
  end

  # --- 9. Error rescue -------------------------------------------------------

  test 'dispatcher rescues errors on create without raising' do
    faq = create_faq(author: @user, suffix: 'rescue-create')
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::FaqHubReviewDispatcher.dispatch_create(faq)
    end
  end

  test 'dispatcher rescues errors on update without raising' do
    faq = create_faq(author: @user, suffix: 'rescue-update')
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::FaqHubReviewDispatcher.dispatch_update(faq)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def create_faq(author:, suffix: SecureRandom.hex(4), title: nil, short_answer: 'short', answer: 'answer body',
                 audience: 'end_user', system: 'core', tags: 'tag1')
    FaqHub::Faq.create!(
      project: @project,
      author: author,
      title: title || "FAQ #{suffix} #{SecureRandom.hex(4)}",
      short_answer: short_answer,
      answer: answer,
      audience: audience,
      system: system,
      tags: tags,
      status: 'active'
    )
  end
end
