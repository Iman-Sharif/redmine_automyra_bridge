require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeIssueStatusHookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues, :issue_statuses, :trackers, :enumerations

  setup do
    AutomyraBridgeJob.delete_all
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find(2)
    @project = Project.find(1)
    enable_automyra_bridge!(@project)

    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'auto_close_enabled' => '1',
      'auto_close_trigger_status_name' => 'Resolved',
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_auto_close' => 'https://automyra.bundecca.co.uk/webhooks/redmica-auto-close',
      'hermes_webhook_secret' => 'test-secret'
    )

    @resolved_status = IssueStatus.find_by(name: 'Resolved')
    @closed_status = IssueStatus.find_by(name: 'Closed')
    @assigned_status = IssueStatus.find_by(name: 'Assigned')
    @new_status = IssueStatus.find_by(name: 'New')
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
  end

  test 'fires webhook when status changes to Resolved via API by regular user' do
    issue = Issue.find(1)
    issue.init_journal(@user, 'Moving to Resolved')
    issue.status = @resolved_status

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'fires webhook when status changes to Resolved by Automyra bot' do
    automyra_user = User.create!(
      login: 'Automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'automyra@example.com',
      password: SecureRandom.hex,
      language: 'en'
    )

    issue = Issue.find(1)
    issue.init_journal(automyra_user, 'Moving to Resolved')
    issue.status = @resolved_status

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'does not fire webhook when status changes to non-Resolved' do
    issue = Issue.find(1)
    issue.init_journal(@user, 'Moving to Assigned')
    issue.status = @assigned_status

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'does not fire webhook when status does not change' do
    issue = Issue.find(1)
    issue.init_journal(@user, 'Just updating description')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'does not fire webhook when auto_close is disabled' do
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'auto_close_enabled' => '0'
    )

    issue = Issue.find(1)
    issue.init_journal(@user, 'Moving to Resolved')
    issue.status = @resolved_status

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'does not fire webhook when journal contains auto-close-result marker' do
    issue = Issue.find(1)
    issue.init_journal(@user, "<!-- automyra-auto-close-result -->\nDeep review completed.")
    issue.status = @resolved_status

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  end

  test 'respects thread-local skip flag' do
    Thread.current[:automyra_auto_close_in_progress] = true

    issue = Issue.find(1)
    issue.init_journal(@user, 'Moving to Resolved')
    issue.status = @resolved_status

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.save!
    end
  ensure
    Thread.current[:automyra_auto_close_in_progress] = nil
  end

  test 'webhook payload includes correct old and new status names' do
    issue = Issue.find(1)
    old_status_name = issue.status.name
    issue.init_journal(@user, 'Moving to Resolved')
    issue.status = @resolved_status
    issue.save!

    enqueued = enqueued_jobs.find { |entry| entry[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil enqueued, 'Expected a HermesWebhookDeliverJob to be enqueued'

    event_type, payload = enqueued[:args]
    assert_equal 'redmica.issue_status_changed', event_type
    assert_equal issue.id, payload['issue_id']
    assert_equal @resolved_status.name, payload['new_status_name']
    assert_equal old_status_name, payload['old_status_name']
    assert_equal @user.login, payload['changed_by']
    assert_equal 'ecookbook', payload['project_id']
    assert_equal 'eCookbook', payload['project_name']
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
  end
end
