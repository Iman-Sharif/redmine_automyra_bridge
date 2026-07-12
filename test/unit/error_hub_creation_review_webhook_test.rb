require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeErrorHubCreationReviewWebhookTest < ActiveSupport::TestCase
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
      'hermes_webhook_url_error_review' => 'https://automyra.bundecca.co.uk/webhooks/redmica-error-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_ERROR_REVIEW'] = '1'

    # The hook is installed at boot; ensure it is present for unit tests.
    AutomyraBridge::ErrorHubCreationHook.install!
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_ERROR_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  # --- 1. Create hook ---------------------------------------------------------

  test 'fires webhook when error is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      build_valid_error(title: 'Create hook test', error_code: unique_error_code)
    end
  end

  test 'does not fire create webhook when author matches configured Automyra user' do
    admin_user = User.find_by(login: 'admin')
    assert_not_nil admin_user, 'expected admin fixture user to exist'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      build_valid_error(title: 'Bot-authored error', author: admin_user, error_code: unique_error_code)
    end
  end

  # --- 2. Update hook ---------------------------------------------------------

  test 'fires webhook when error title changes' do
    error = build_valid_error(title: 'Original title', error_code: unique_error_code)

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(title: 'Updated title')
    end
  end

  test 'fires webhook when error description changes' do
    error = build_valid_error(title: 'Desc test', error_code: unique_error_code)

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(description: 'Updated description')
    end
  end

  test 'fires webhook when error status changes' do
    error = build_valid_error(title: 'Status test', error_code: unique_error_code)

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(status: 'resolved')
    end
  end

  test 'fires webhook when error root_cause changes' do
    error = build_valid_error(title: 'Root cause test', error_code: unique_error_code)

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(root_cause: 'Discovered the actual root cause')
    end
  end

  test 'does not fire update webhook on metadata-only change' do
    error = build_valid_error(title: 'Baseline metadata-only test', error_code: unique_error_code)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(module_path: 'app/models/foo.rb#bar')
    end
  end

  # --- 3. Environment flag gating ---------------------------------------------

  test 'does not fire create webhook when AUTOMYRA_BRIDGE_ERROR_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_ERROR_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      build_valid_error(title: 'Flag off create test', error_code: unique_error_code)
    end
  end

  test 'does not fire update webhook when AUTOMYRA_BRIDGE_ERROR_REVIEW is unset' do
    error = build_valid_error(title: 'Baseline for flag-off update test', error_code: unique_error_code)
    clear_enqueued_jobs

    ENV.delete('AUTOMYRA_BRIDGE_ERROR_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(title: 'Flag off update test')
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_ERROR_REVIEW is 0' do
    ENV['AUTOMYRA_BRIDGE_ERROR_REVIEW'] = '0'

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      build_valid_error(title: 'Zero flag create test', error_code: unique_error_code)
    end
  end

  # --- 4. Thread-local skip flag ---------------------------------------------

  test 'does not fire create webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      build_valid_error(title: 'Skip flag create test', error_code: unique_error_code)
    end
  end

  test 'does not fire update webhook when thread-local skip flag is set' do
    error = build_valid_error(title: 'Baseline for skip update test', error_code: unique_error_code)
    clear_enqueued_jobs

    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      error.update!(title: 'Skip flag update test body')
    end
  end

  # --- 5. Dispatcher payload shape -------------------------------------------

  test 'payload includes all required keys plus event_type on create' do
    error = build_valid_error(title: 'Payload shape test', error_code: unique_error_code)

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job, 'expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload, delivery_id = job[:args]
    assert_equal 'redmica.error_hub.error_created', event_type

    assert_equal error.id, payload['error_id']
    assert_equal 'Payload shape test', payload['title']
    assert_equal error.description, payload['description']
    assert_equal error.error_code, payload['error_code']
    assert_equal error.severity, payload['severity']
    assert_equal error.status, payload['status']
    assert_equal error.root_cause, payload['root_cause']
    assert_equal error.solution, payload['solution']
    assert_equal error.prevention, payload['prevention']
    assert payload.key?('category'), 'payload must always include category (may be nil)'
    assert_equal error.tags, payload['tags']
    assert_equal @project.identifier, payload['project_id']
    assert_equal @project.identifier, payload['project_identifier']
    assert_equal @project.name, payload['project_name']
    assert_equal @user.id, payload['author_id']
    assert_equal @user.login, payload['author_login']
    assert payload['url'].include?(error.id.to_s),
           "url must reference the error id (got #{payload['url'].inspect})"
    assert payload['timestamp']

    assert_match(/\Aerror-review-#{error.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  test 'payload event_type is redmica.error_hub.error_updated on update' do
    error = build_valid_error(title: 'Update payload test', error_code: unique_error_code)
    clear_enqueued_jobs
    error.update!(title: 'Updated for payload check')

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job

    event_type, _payload, delivery_id = job[:args]
    assert_equal 'redmica.error_hub.error_updated', event_type
    assert_match(/\Aerror-review-update-#{error.id}-[0-9a-f]{16}\z/, delivery_id)
  end

  # --- 6. Text field truncation -----------------------------------------------

  test 'long text fields are truncated to 2000 characters' do
    long_text = 'a' * 3000
    build_valid_error(
      title: 'Truncation test',
      description: long_text,
      root_cause: long_text,
      solution: long_text,
      prevention: long_text,
      error_code: unique_error_code
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]

    %w[description root_cause solution prevention].each do |key|
      assert payload[key].length <= 2000,
             "#{key} must be truncated to <= 2000 chars (got #{payload[key].length})"
    end
  end

  # --- 7. Activity log --------------------------------------------------------

  test 'activity log entry is written on create dispatch' do
    error = build_valid_error(title: 'Activity log create test', error_code: unique_error_code)

    log = AutomyraBridgeActivityLog.last
    assert_equal 'error_created_webhook_dispatched', log.action_type
    assert_equal 'ErrorHub::Error', log.target_type
    assert_equal error.id, log.target_id.to_i
  end

  test 'activity log entry is written on update dispatch' do
    error = build_valid_error(title: 'Activity log update test', error_code: unique_error_code)
    clear_enqueued_jobs
    AutomyraBridgeActivityLog.delete_all
    error.update!(title: 'Activity log update trigger')

    log = AutomyraBridgeActivityLog.last
    assert_equal 'error_updated_webhook_dispatched', log.action_type
    assert_equal 'ErrorHub::Error', log.target_type
    assert_equal error.id, log.target_id.to_i
  end

  # --- 8. Error rescue --------------------------------------------------------

  test 'dispatcher rescues errors on create without raising' do
    error = build_valid_error(title: 'Boom create test', error_code: unique_error_code)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::ErrorHubReviewDispatcher.dispatch_create(error)
    end
  end

  test 'dispatcher rescues errors on update without raising' do
    error = build_valid_error(title: 'Boom update test', error_code: unique_error_code)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::ErrorHubReviewDispatcher.dispatch_update(error)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end

  # Build and save a valid ErrorHub::Error. Required columns on
  # error_hub_errors: title, system, project_id, author_id, error_code, status.
  def build_valid_error(title:, error_code:, author: @user,
                        description: 'Test description body',
                        root_cause: 'Original root cause',
                        solution: 'Original solution',
                        prevention: 'Original prevention')
    ErrorHub::Error.create!(
      title: title,
      system: 'core',
      project: @project,
      author: author,
      error_code: error_code,
      status: 'active',
      severity: 2,
      description: description,
      root_cause: root_cause,
      solution: solution,
      prevention: prevention,
      tags: 'test,sample'
    )
  end

  def unique_error_code
    "ERR-TEST-#{SecureRandom.hex(6).upcase}"
  end
end
