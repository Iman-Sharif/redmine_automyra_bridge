require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeJobCreatorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules, :issues

  setup do
    AutomyraBridgeJob.delete_all
    AutomyraBridgeMemoryEvent.delete_all if defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?
    @user = User.find(2)
    @project = Project.find(1)
    grant_automyra_bridge_permission!(@user, @project)
    @task = TaskHub::Task.create!(title: 'Mention task', user: @user, author: @user, project: @project, status: 'todo')
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ENV['AUTOMYRA_BRIDGE_HANDLE_MENTIONS'] = '1'
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter if @old_queue_adapter
    ENV.delete('AUTOMYRA_BRIDGE_HANDLE_MENTIONS')
  end

  test 'fires webhook for Task Hub comment mention without bridge job' do
    comment = @task.comments.create!(author: @user, body: 'Please help @automyra')

    assert_no_difference('AutomyraBridgeJob.count') do
      result = AutomyraBridge::JobCreator.create_for_task_comment(comment)
      assert result, 'Expected create_for_task_comment to return truthy when webhook is fired'
    end

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::JobCreator.create_for_task_comment(comment)
    end
  end

  test 'ignores Task Hub comments without mention' do
    comment = @task.comments.create!(author: @user, body: 'No request here')

    assert_no_difference('AutomyraBridgeJob.count') do
      assert_nil AutomyraBridge::JobCreator.create_for_task_comment(comment)
    end
  end

  test 'fires webhook for Redmyra alias mention without bridge job' do
    comment = @task.comments.create!(author: @user, body: '@Redmyra please help')

    assert_no_difference('AutomyraBridgeJob.count') do
      result = AutomyraBridge::JobCreator.create_for_task_comment(comment)
      assert result, 'Expected create_for_task_comment to return truthy when webhook is fired'
    end
  end

  test 'ignores Task Hub comment mention without bridge permission' do
    other_user = User.find(3)
    comment = @task.comments.create!(author: other_user, body: '@automyra help')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      assert_no_difference('AutomyraBridgeJob.count') do
        assert_nil AutomyraBridge::JobCreator.create_for_task_comment(comment)
      end
    end
  end

  test 'fires webhook for issue journal mention without bridge job' do
    issue = Issue.find(1)
    grant_automyra_bridge_permission!(@user, issue.project)
    AutomyraBridgeJob.delete_all

    assert_no_difference('AutomyraBridgeJob.count') do
      issue.init_journal(@user, '@automyra review this issue')
      issue.save!
    end

    journal = issue.journals.where(notes: '@automyra review this issue').order(:id).last

    assert_no_difference('AutomyraBridgeJob.count') do
      result = AutomyraBridge::JobCreator.create_for_issue_journal(journal)
      assert result, 'Expected create_for_issue_journal to return truthy when webhook is fired'
    end
  end

  test 'issue journal hook enqueues webhook without creating bridge job' do
    issue = Issue.find(1)
    grant_automyra_bridge_permission!(@user, issue.project)
    AutomyraBridgeJob.delete_all
    AutomyraBridge::JobProcessor.any_instance.expects(:process).never

    assert_no_difference('AutomyraBridgeJob.count') do
      issue.init_journal(@user, '@automyra queue only')
      issue.save!
    end

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      issue.init_journal(@user, '@automyra queue only')
      issue.save!
    end
  end

  test 'status journals do not create Automyra jobs' do
    issue = Issue.find(1)
    grant_automyra_bridge_permission!(@user, issue.project)

    assert_no_difference('AutomyraBridgeJob.count') do
      issue.init_journal(@user, "#{AutomyraBridge::JobProcessor::STATUS_MARKER}\nAutomyra response abc:\n\nPlease ask @automyra again")
      issue.save!
    end
  end

  test 'enqueues Hermes webhook for Task Hub comment mention with correlation_id' do
    comment = @task.comments.create!(author: @user, body: 'Please help @automyra')

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::JobCreator.create_for_task_comment(comment)
    end

    enqueued = enqueued_jobs.find { |entry| entry[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    event_type, payload, delivery_id = enqueued[:args]
    assert_equal 'redmica.task_comment_mention', event_type
    assert_equal "task-comment-#{comment.id}", delivery_id
    assert payload['correlation_id'].present?
    assert payload['idempotency_key'].present?
    assert_equal 'task_hub_comment', payload['source']
  end

  test 'enqueues Hermes webhook for issue journal mention with correlation_id' do
    issue = Issue.find(1)
    grant_automyra_bridge_permission!(@user, issue.project)
    AutomyraBridgeJob.delete_all
    issue.init_journal(@user, '@automyra please review')
    issue.save!
    journal = issue.journals.where(notes: '@automyra please review').order(:id).last
    AutomyraBridgeJob.delete_all
    clear_enqueued_jobs

    assert_enqueued_with(job: AutomyraBridge::HermesWebhookDeliverJob) do
      AutomyraBridge::JobCreator.create_for_issue_journal(journal)
    end

    enqueued = enqueued_jobs.find { |entry| entry[:job] == AutomyraBridge::HermesWebhookDeliverJob }
    event_type, payload, delivery_id = enqueued[:args]
    assert_equal 'redmica.issue_mention', event_type
    assert_equal "issue-journal-#{journal.id}", delivery_id
    assert payload['correlation_id'].present?
    assert payload['idempotency_key'].present?
    assert_equal 'issue_journal', payload['source']
  end

  test 'does not enqueue Hermes webhook when job creation is blocked by permission' do
    other_user = User.find(3)
    comment = @task.comments.create!(author: other_user, body: '@automyra help')

    assert_no_enqueued_jobs(only: AutomyraBridge::HermesWebhookDeliverJob) do
      assert_nil AutomyraBridge::JobCreator.create_for_task_comment(comment)
    end
  end

  test 'falls through to bridge job when handle_mentions is disabled' do
    ENV.delete('AUTOMYRA_BRIDGE_HANDLE_MENTIONS')
    comment = @task.comments.create!(author: @user, body: 'Please help @automyra')

    assert_difference('AutomyraBridgeJob.count', 1) do
      job = AutomyraBridge::JobCreator.create_for_task_comment(comment)
      assert_equal 'queued', job.status
      assert_equal 'TaskHub::TaskComment', job.source_type
    end
  end

  test 'falls through to bridge job for journal when handle_mentions is disabled' do
    ENV.delete('AUTOMYRA_BRIDGE_HANDLE_MENTIONS')
    issue = Issue.find(1)
    grant_automyra_bridge_permission!(@user, issue.project)
    AutomyraBridgeJob.delete_all
    issue.init_journal(@user, '@automyra review this issue')
    issue.save!
    journal = issue.journals.where(notes: '@automyra review this issue').order(:id).last

    assert_difference('AutomyraBridgeJob.count', 1) do
      job = AutomyraBridge::JobCreator.create_for_issue_journal(journal)
      assert_equal 'queued', job.status
      assert_equal 'Journal', job.source_type
    end
  end

  private

  def grant_automyra_bridge_permission!(user, project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
    role = Role.generate!(permissions: [:use_automyra_bridge, :view_task_hub_tasks, :view_issues])
    member = Member.find_or_initialize_by(project: project, user: user)
    member.roles = [role]
    member.save!
  end
end
