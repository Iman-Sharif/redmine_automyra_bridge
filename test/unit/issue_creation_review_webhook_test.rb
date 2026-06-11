require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeIssueCreationReviewWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues, :issue_statuses, :trackers, :enumerations

  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_user_login' => 'automyra',
      'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
      'hermes_webhook_url_creation_review' => 'https://automyra.sbg-server.com/webhooks/redmica-creation-review',
      'hermes_webhook_secret' => 'test-secret'
    )

    ENV['AUTOMYRA_BRIDGE_CREATION_REVIEW'] = '1'
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_CREATION_REVIEW')
    Thread.current[:automyra_bridge_skip_webhook] = nil
  end

  test 'fires webhook when issue is created by regular user' do
    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      Issue.create!(
        project: @project,
        tracker: Tracker.find(1),
        subject: 'Test creation review',
        author: @user,
        status: IssueStatus.find(1)
      )
    end
  end

  test 'does not fire webhook when AUTOMYRA_BRIDGE_CREATION_REVIEW is unset' do
    ENV.delete('AUTOMYRA_BRIDGE_CREATION_REVIEW')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      Issue.create!(
        project: @project,
        tracker: Tracker.find(1),
        subject: 'Flag off test',
        author: @user,
        status: IssueStatus.find(1)
      )
    end
  end

  test 'fires webhook for bot-authored issue (bot issues are reviewed too)' do
    bot_user = User.create!(
      login: 'automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'bot@example.com',
      password: SecureRandom.hex,
      language: 'en'
    )

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      Issue.create!(
        project: @project,
        tracker: Tracker.find(1),
        subject: 'Bot test',
        author: bot_user,
        status: IssueStatus.find(1)
      )
    end
  end

  test 'does not fire webhook when thread-local skip flag is set' do
    Thread.current[:automyra_bridge_skip_webhook] = true

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      Issue.create!(
        project: @project,
        tracker: Tracker.find(1),
        subject: 'Skip flag test',
        author: @user,
        status: IssueStatus.find(1)
      )
    end
  end

  test 'payload includes all required keys' do
    issue = Issue.create!(
      project: @project,
      tracker: Tracker.find(1),
      subject: 'Payload test',
      description: 'This is a test description',
      author: @user,
      status: IssueStatus.find(1)
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    assert_equal 'redmica.issue_created', job[:args][0]
    payload = job[:args][1]
    assert_equal issue.id, payload['issue_id']
    assert_equal 'Payload test', payload['subject']
    assert_equal 'This is a test description', payload['description']
    assert payload['url'].include?(issue.id.to_s)
    assert_equal "issue-creation-#{issue.id}", job[:args][2]
  end

  test 'description is truncated to 2000 characters' do
    long_description = 'a' * 3000

    issue = Issue.create!(
      project: @project,
      tracker: Tracker.find(1),
      subject: 'Truncation test',
      description: long_description,
      author: @user,
      status: IssueStatus.find(1)
    )

    job = enqueued_jobs.find { |j| j[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil job
    payload = job[:args][1]
    assert payload['description'].length <= 2000
  end

  test 'activity log entry is written on dispatch' do
    issue = Issue.find(1)

    assert_difference('AutomyraBridgeActivityLog.count', 1) do
      AutomyraBridge::CreationReviewDispatcher.dispatch(issue)
    end

    log = AutomyraBridgeActivityLog.last
    assert_equal 'issue_creation_review_webhook_dispatched', log.action_type
    assert_equal 'Issue', log.target_type
    assert_equal issue.id, log.target_id.to_i
  end

  test 'dispatcher rescues errors gracefully' do
    issue = Issue.find(1)
    AutomyraBridge::HermesWebhookDeliverJob.stubs(:perform_later).raises(RuntimeError, 'boom')

    assert_nothing_raised do
      AutomyraBridge::CreationReviewDispatcher.dispatch(issue)
    end
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: :automyra_bridge) unless EnabledModule.exists?(project: project, name: :automyra_bridge)
  end
end
