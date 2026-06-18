require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeRepoHubCreationReviewWebhookTest < ActiveSupport::TestCase
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
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_repo_review' => 'https://automyra.sbg-server.com/webhooks/redmica-repo-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_REPO_REVIEW'] = '1'

    User.current = @user
    AutomyraBridge::RepoHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_REPO_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
    User.current = nil
  end

  # --- 1. Create hook --------------------------------------------------------

  test 'fires webhook when repository is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      create_repository
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    User.current = admin_user

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_repository(identifier: "bot_repo_#{SecureRandom.hex(4)}")
    end
  ensure
    User.current = nil
  end

  # --- 2. Update hook --------------------------------------------------------

  test 'fires webhook when repository is_default changes' do
    repository = create_repository
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      repository.update!(is_default: true)
    end
  end

  test 'fires webhook when repository url changes' do
    repository = create_repository
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      repository.update!(url: 'https://new.example.com/repo.git')
    end
  end

  test 'does not fire update webhook on metadata-only change' do
    repository = create_repository
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      repository.update!(extra_info: { 'foo' => 'bar' })
    end
  end

  # --- 3. Environment flag gating --------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_REPO_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_REPO_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_repository(identifier: "flagoff_create_#{SecureRandom.hex(4)}")
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_REPO_REVIEW is unset' do
    repository = create_repository
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_REPO_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      repository.update!(is_default: true)
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_REPO_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_REPO_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_repository(identifier: "zero_flag_#{SecureRandom.hex(4)}")
    end
  end

  # --- 4. Thread-local skip flag ---------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      create_repository(identifier: "skip_create_#{SecureRandom.hex(4)}")
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    repository = create_repository
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      repository.update!(is_default: true)
    end
  end

  # --- 5. Dispatcher payload shape -------------------------------------------

  test 'payload includes all required keys on create' do
    repository = create_repository(
      url: 'https://user:secret@example.com/repo.git',
      root_url: 'https://user:secret@example.com/',
      identifier: "payload_#{SecureRandom.hex(4)}"
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.repo_hub.repository_created', event_type

    assert_equal repository.id, payload['repository_id']
    assert_equal repository.class.name.split('::').last, payload['scm_type']
    assert_equal repository.identifier, payload['identifier']
    assert payload['url'].include?('https://example.com/repo.git')
    assert payload['url'].exclude?('user:secret')
    assert payload['url'].exclude?('user:')
    assert payload['root_url'].include?('https://example.com/')
    assert payload['root_url'].exclude?('user:secret')

    assert_equal repository.is_default, payload['is_default']

    assert_equal @project.id, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']

    assert payload['created_on']
    assert payload['timestamp']
    assert payload.key?('snapshot_metadata')
    assert payload.key?('updated_at')

    assert_match(/\Arepo-review-#{repository.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 6. URL credential sanitization ----------------------------------------

  test 'url and root_url are stripped of userinfo' do
    create_repository(
      url: 'https://deploy:token@gitlab.example.com/project/repo.git',
      root_url: 'https://deploy:token@gitlab.example.com/project/',
      identifier: "sanitize_#{SecureRandom.hex(4)}"
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    payload = job[:args][1]
    assert_equal 'https://gitlab.example.com/project/repo.git', payload['url']
    assert_equal 'https://gitlab.example.com/project/', payload['root_url']
  end

  # --- 7. Update delivery ID format ------------------------------------------

  test 'update delivery id uses repo-review-update-{id}-{hex8} format' do
    repository = create_repository(identifier: "deliv_#{SecureRandom.hex(4)}")
    clear_enqueued_jobs

    repository.update!(url: 'https://changed.example.com/repo.git')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.repo_hub.repository_updated', event_type
    assert_match(/\Arepo-review-update-#{repository.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 8. Activity log -------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    repository = create_repository(identifier: "log_create_#{SecureRandom.hex(4)}")
    AutomyraBridge::RepoHubReviewDispatcher.dispatch_create(repository)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'repository_created_webhook_dispatched', log.action_type
    assert_equal 'Repository', log.target_type
    assert_equal repository.id, log.target_id.to_i
  end

  test 'activity log entry is written on update dispatch' do
    repository = create_repository(identifier: "log_update_#{SecureRandom.hex(4)}")
    AutomyraBridge::RepoHubReviewDispatcher.dispatch_update(repository)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'repository_updated_webhook_dispatched', log.action_type
    assert_equal 'Repository', log.target_type
    assert_equal repository.id, log.target_id.to_i
  end

  # --- 9. Error rescue --------------------------------------------------------

  test 'dispatcher rescues errors on create without raising' do
    repository = create_repository(identifier: "rescue_create_#{SecureRandom.hex(4)}")
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::RepoHubReviewDispatcher.dispatch_create(repository)
    end
  end

  test 'dispatcher rescues errors on update without raising' do
    repository = create_repository(identifier: "rescue_update_#{SecureRandom.hex(4)}")
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::RepoHubReviewDispatcher.dispatch_update(repository)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  def create_repository(url: 'https://example.com/repo.git',
                        root_url: 'https://example.com/',
                        identifier: "test_repo_#{SecureRandom.hex(4)}",
                        is_default: false)
    Repository::Git.create!(
      project: @project,
      url: url,
      root_url: root_url,
      identifier: identifier,
      is_default: is_default
    )
  end
end
