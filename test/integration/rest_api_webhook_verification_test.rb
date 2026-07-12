# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeRestApiWebhookVerificationTest < Redmine::ApiTest::Base
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues, :issue_statuses,
           :trackers, :enumerations

  setup do
    AutomyraBridgeJob.delete_all
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    @user = User.find_by!(login: 'jsmith')
    @issue = Issue.find(6)
    @resolved_status = IssueStatus.find_by!(name: 'Resolved')

    enable_automyra_bridge!(@issue.project)
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'auto_close_enabled' => '1',
      'auto_close_trigger_status_name' => 'Resolved',
      'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
      'hermes_webhook_url_auto_close' => 'https://automyra.bundecca.co.uk/webhooks/redmica-auto-close',
      'hermes_webhook_secret' => 'test-secret'
    )
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
  end

  test 'PUT /issues/:id.json with API key enqueues auto-close webhook when status resolves' do
    assert_difference('Journal.count') do
      assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
        put(
          "/issues/#{@issue.id}.json",
          params: { issue: { status_id: @resolved_status.id, notes: 'Moving to Resolved via API' } },
          headers: credentials(@user.api_key, 'X')
        )
      end
    end

    assert_response :no_content
    assert_equal @resolved_status.id, @issue.reload.status_id
    enqueued = enqueued_jobs.find { |entry| entry[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    assert_not_nil enqueued, 'Expected a HermesWebhookDeliverJob to be enqueued'
    assert_equal 'redmica.issue_status_changed', enqueued[:args][0]
  end

  private

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
  end
end
