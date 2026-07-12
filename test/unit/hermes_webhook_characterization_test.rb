# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Characterization tests pinning the CURRENT behavior of the Hermes outbound
# webhook delivery chain. Task 9 of the Automyra Bridge plan; predecessor of
# Task 17 (retries/idempotency) and Task 23 (signature algorithm).
#
# Chain (pinned):
#   Journal#after_create
#     -> AutomyraBridge::IssueStatusHook::InstanceMethods#automyra_auto_close_on_status_change
#       -> AutomyraBridge::AutoCloseDispatcher.dispatch(journal)
#         -> AutomyraBridge::HermesWebhookDeliverJob.perform_later(event_type, payload, delivery_id)
#           -> AutomyraBridge::HermesWebhookNotifier#deliver(event_type:, payload:, delivery_id:)
#
# Pinned baseline (auto-close path):
#   * Event name: "redmica.issue_status_changed" (AutoCloseDispatcher::EVENT_TYPE).
#   * Wire body: `{ "event_type": <event>, "payload": <dispatcher payload> }`.
#     The dispatcher's payload itself ALSO carries an :event_type key, so
#     event_type appears at BOTH the top level AND inside payload — pinned.
#   * Signature header: `X-Hub-Signature-256: sha256=<hex>`,
#     hex = `OpenSSL::HMAC.hexdigest('SHA256', secret, body_bytes)`.
#   * Delivery id format: `auto-close-issue-<issue_id>-journal-<journal_id>`.
#
# Retry/timeout baseline (evolved by Task 17):
#   * HermesWebhookDeliverJob: `retry_on StandardError, wait: :polynomially_longer,
#     attempts: 5` (Rails 7.2 spelling). The retry block logs and SWALLOWS the
#     final error so the primary AutomyraBridgeJob pipeline is never blocked by
#     Hermes fanout.
#   * HermesWebhookNotifier: `read_timeout`/`open_timeout` both pulled from
#     `request_timeout_seconds`, default 15s when unset/zero, clamped to [1, 30].
#   * Per-delivery idempotency store (AutomyraBridgeWebhookDelivery): a delivery
#     id recorded after a successful send is skipped on re-enqueue.
class AutomyraBridgeHermesWebhookCharacterizationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles,
           :enabled_modules, :issues, :issue_statuses, :trackers, :enumerations

  AUTO_CLOSE_EVENT = 'redmica.issue_status_changed'
  CHAR_SECRET = 'characterization-fixed-secret'
  AUTO_CLOSE_URL = 'https://automyra.bundecca.co.uk/webhooks/redmica-auto-close'

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    AutomyraBridgeJob.delete_all

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'auto_close_enabled' => '1',
      'auto_close_trigger_status_name' => 'Resolved',
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_url_auto_close' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET
    )

    @resolved_status = IssueStatus.find_by(name: 'Resolved')
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    Thread.current[:automyra_auto_close_in_progress] = nil
  end

  test 'status change to Resolved enqueues exactly one HermesWebhookDeliverJob with pinned event and payload' do
    issue = Issue.find(1)
    old_status_name = issue.status.name
    issue.init_journal(@user, 'Char: moving to Resolved')
    issue.status = @resolved_status

    before_count = enqueued_jobs.count { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    issue.save!
    after_count = enqueued_jobs.count { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }

    assert_equal 1, after_count - before_count,
                 'exactly one HermesWebhookDeliverJob must be enqueued for a Resolved transition'

    enqueued = enqueued_jobs.reverse.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil enqueued

    event_type, payload, delivery_id = enqueued[:args]

    assert_equal AUTO_CLOSE_EVENT, event_type,
                 'event name pinned to redmica.issue_status_changed'
    assert_match(/\Aauto-close-issue-#{issue.id}-journal-\d+\z/, delivery_id.to_s,
                 'delivery_id format pinned to auto-close-issue-<issue_id>-journal-<journal_id>')

    # Pinning the EXACT key set (not a subset) so adding or removing a payload
    # key trips this test loudly — the whole point of characterization.
    expected_keys = %w[
      event_type
      issue_id
      old_status_id
      new_status_id
      old_status_name
      new_status_name
      changed_by
      project_id
      project_name
      subject
      description
      tracker_name
      url
      timestamp
    ].sort
    # ActiveJob's :test adapter serializes the symbol-keyed payload and injects
    # an `_aj_symbol_keys` bookkeeping marker; that is a transport artifact, not
    # the product payload shape, so it is excluded from the pinned key set.
    actual_keys = payload.keys.map(&:to_s).reject { |k| k.start_with?('_aj_') }.sort
    assert_equal expected_keys, actual_keys,
                 'payload key set drifted from pinned baseline'

    assert_equal AUTO_CLOSE_EVENT, payload['event_type'] || payload[:event_type]
    assert_equal issue.id, payload['issue_id'] || payload[:issue_id]
    assert_equal 'Resolved', payload['new_status_name'] || payload[:new_status_name]
    assert_equal old_status_name, payload['old_status_name'] || payload[:old_status_name]
    assert_equal @user.login, payload['changed_by'] || payload[:changed_by]
    assert_equal 'ecookbook', payload['project_id'] || payload[:project_id]
    assert_equal 'eCookbook', payload['project_name'] || payload[:project_name]
    assert_equal "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue.id}",
                 (payload['url'] || payload[:url]),
                 'url shape pinned to <protocol>://<host>/issues/<id>'

    # description goes through .truncate(2000); pin the cap, not the content.
    desc = payload['description'] || payload[:description]
    assert desc.is_a?(String), 'description always a String (issue.description.to_s)'
    assert desc.length <= 2000, 'description capped at 2000 chars by truncate(2000)'
  end

  test 'notifier produces sha256 HMAC matching precomputed digest for known fixed inputs' do
    fixed_event = AUTO_CLOSE_EVENT
    fixed_payload = { 'issue_id' => 1, 'new_status_name' => 'Resolved' }
    fixed_delivery = 'char-fixed-delivery-001'

    expected_body = { event_type: fixed_event, payload: fixed_payload }.to_json
    expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', CHAR_SECRET, expected_body)}"

    # Magic-string anchor: the literal hex below is the precomputed sha256 HMAC
    # for this exact body+secret. If you need to flip it, the signature
    # algorithm or wire body shape changed — coordinate with Task 17/23.
    assert_equal 'sha256=e3ad944d4211f7660b763fb441f4bff1ea50caf1a199a782426e5b415f82233f',
                 expected_signature,
                 'pinned characterization digest for fixed inputs drifted'

    captured_request = nil
    response = Net::HTTPOK.new('1.1', '202', 'Accepted')
    response.stubs(:body).returns('{"status":"accepted"}')

    http = mock('http')
    http.stubs(:request).with do |req|
      captured_request = req
      true
    end.returns(response)

    AutomyraBridge::UrlValidator.stubs(:validate!).returns(URI.parse(AUTO_CLOSE_URL))
    AutomyraBridge::UrlValidator.stubs(:validate_connected_peer!).returns(true)
    Net::HTTP.stubs(:start).yields(http).returns(response)

    notifier = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_url_auto_close' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET,
      'request_timeout_seconds' => '15'
    )
    notifier.deliver(event_type: fixed_event, payload: fixed_payload, delivery_id: fixed_delivery)

    assert_not_nil captured_request, 'notifier must build a request even when the body is small'
    assert_equal 'application/json', captured_request['Content-Type']
    assert_equal fixed_event, captured_request['X-GitHub-Event']
    assert_equal fixed_delivery, captured_request['X-GitHub-Delivery']
    assert_equal 'Automyra-Bridge-Hermes-Notifier/1.0', captured_request['User-Agent']

    assert_equal expected_body, captured_request.body,
                 'wire body shape `{event_type:, payload:}.to_json` is pinned'
    assert_equal expected_signature, captured_request['X-Hub-Signature-256'],
                 'X-Hub-Signature-256 algorithm + value pinned to sha256 HMAC of the wire body'
  end

  test 'deliver job has no custom retry_on (uses ActiveJob default)' do
    job_class = AutomyraBridge::HermesWebhookDeliverJob

    # After the F4 scope cleanup, the job no longer defines a custom retry_on
    # so it falls through to ActiveJob::Base.default. Verify no custom handler.
    handlers = job_class.rescue_handlers
    refute handlers.any? { |h| h[0] == 'StandardError' || h[0] == StandardError.name },
           'HermesWebhookDeliverJob must NOT have a custom StandardError retry_on after F4 cleanup'

    src_path = File.expand_path(
      '../../app/jobs/automyra_bridge/hermes_webhook_deliver_job.rb', __dir__
    )
    src = File.read(src_path)
    refute_match(/retry_on\s+StandardError/, src,
                 'HermesWebhookDeliverJob source must not contain a custom retry_on for StandardError')
  end

  test 'notifier timeout baseline is pinned: default 15s, clamped to [1, 30]' do
    n = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET
    )
    assert_equal 15, n.send(:timeout), 'default timeout pinned to 15s when unset'

    n_zero = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET,
      'request_timeout_seconds' => '0'
    )
    assert_equal 15, n_zero.send(:timeout), 'zero/blank timeout coerces to default 15s'

    n_too_low = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET,
      'request_timeout_seconds' => '-5'
    )
    assert_equal 1, n_too_low.send(:timeout), 'timeout clamped at lower bound of 1s'

    n_too_high = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET,
      'request_timeout_seconds' => '999'
    )
    assert_equal 30, n_too_high.send(:timeout), 'timeout clamped at upper bound of 30s (API timeout constraint)'

    n_mid = AutomyraBridge::HermesWebhookNotifier.new(
      'hermes_webhook_url' => AUTO_CLOSE_URL,
      'hermes_webhook_secret' => CHAR_SECRET,
      'request_timeout_seconds' => '30'
    )
    assert_equal 30, n_mid.send(:timeout), 'in-range timeout values pass through'
  end

  private

  def enable_automyra_bridge!(project)
    return if project.module_enabled?(:automyra_bridge)

    EnabledModule.create!(project: project, name: 'automyra_bridge')
  end
end
