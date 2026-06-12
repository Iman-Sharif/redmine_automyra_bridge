require File.expand_path('../test_helper', __dir__)

# Task 10: Characterization tests pinning the CURRENT return-on-error of the 16
# swallowing rescue sites. We stub each rescued operation to raise StandardError
# and assert the value the rescue currently returns. PIN current behavior even if
# buggy. Do NOT add error handling. Task 14 decides keep/surface.
class SwallowSitesCharacterizationTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  # --- 1. recover_stale_jobs.rb:37 -> nil --------------------------------------
  test 'recover_stale_jobs safe_mark_failed! swallows and returns nil' do
    job = mock('job')
    job.stubs(:update_columns).raises(StandardError, 'boom')
    job.stubs(:id).returns(42)
    svc = AutomyraBridge::RecoverStaleJobs.new
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil svc.send(:safe_mark_failed!, job, 'msg')
  end

  # --- 2. view_hooks.rb:79 -> nil ----------------------------------------------
  test 'view_hooks automyra_page_title swallows and returns nil' do
    controller = mock('controller')
    controller.stubs(:view_context).raises(StandardError, 'boom')
    hooks = AutomyraBridge::ViewHooks.send(:allocate)
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil hooks.send(:automyra_page_title, controller)
  end

  # --- 3. policy_loader.rb:81 -> {} --------------------------------------------
  test 'policy_loader parsed_wiki_config swallows and returns empty hash' do
    policy = mock('policy')
    policy.stubs(:policy_page_id).returns(1)
    AutomyraBridge::Governance::WikiPolicyLoader.stubs(:call).raises(StandardError, 'boom')
    # CHARACTERIZATION: current swallow -> {}; Task 14 decides keep/surface.
    assert_equal({}, AutomyraBridge::Governance::PolicyLoader.parsed_wiki_config(policy))
  end

  # --- 4. memory_reader.rb:21 -> false -----------------------------------------
  test 'memory_reader configured? swallows and returns false' do
    AutomyraBridge::MemoryReader.stubs(:lancedb_configuration).raises(StandardError, 'boom')
    # CHARACTERIZATION: current swallow -> false; Task 14 decides keep/surface.
    assert_equal false, AutomyraBridge::MemoryReader.configured?({})
  end

  # --- 5. assistant_run_processor.rb:266 -> [] ---------------------------------
  test 'assistant_run_processor recall_memory_events swallows and returns empty array' do
    thread = mock('thread')
    thread.stubs(:channel_key).returns('chan')
    thread.stubs(:page_key).returns('pk')
    thread.stubs(:id).returns(1)
    proc = AutomyraBridge::AssistantRunProcessor.allocate
    proc.stubs(:chat_thread_for).returns(thread)
    AutomyraBridge::MemoryReader.stubs(:configured?).returns(true)
    AutomyraBridge::MemoryReader.stubs(:recall).raises(StandardError, 'boom')
    # CHARACTERIZATION: current swallow -> []; Task 14 decides keep/surface.
    assert_equal [], proc.send(:recall_memory_events, mock('job'))
  end

  # --- 6. mode_executor.rb:88 -> nil -------------------------------------------
  test 'mode_executor action_project swallows and returns nil' do
    action = mock('action')
    action.stubs(:object_type).raises(StandardError, 'boom')
    exec = AutomyraBridge::Governance::ModeExecutor.allocate
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil exec.send(:action_project, action)
  end

  # --- 7. attachment_collector.rb:49 -> nil ------------------------------------
  test 'attachment_collector project_id_for swallows and returns nil' do
    attachment = mock('attachment')
    attachment.stubs(:container).raises(StandardError, 'boom')
    collector = AutomyraBridge::Governance::Collectors::AttachmentCollector.allocate
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil collector.send(:project_id_for, attachment)
  end

  # --- 8. operator_controller.rb:177 (endpoint_reachable?) -> false ------------
  test 'operator_controller endpoint_reachable? swallows and returns false' do
    AutomyraBridge::UrlValidator.stubs(:validate!).raises(StandardError, 'boom')
    ctrl = AutomyraBridgeOperatorController.allocate
    # CHARACTERIZATION: current swallow -> false; Task 14 decides keep/surface.
    assert_equal false, ctrl.send(:endpoint_reachable?, 'http://example.com')
  end

  # --- 9. chat_controller.rb:478 (memory_event_sources_for_run) -> [] ----------
  test 'chat_controller memory_event_sources_for_run swallows and returns empty array' do
    AutomyraBridgeMemoryEvent.stubs(:table_exists?).returns(true)
    AutomyraBridgeMemoryEvent.stubs(:where).raises(StandardError, 'boom')
    ctrl = AutomyraBridgeChatController.allocate
    # CHARACTERIZATION: current swallow -> []; Task 14 decides keep/surface.
    assert_equal [], ctrl.send(:memory_event_sources_for_run, 1)
  end

  # --- 10. chat_controller.rb:534 (sources_for_message) -> nil -----------------
  test 'chat_controller sources_for_message swallows and returns nil' do
    message = mock('message')
    message.stubs(:role).returns('assistant')
    message.stubs(:job_id).returns(1)
    message.stubs(:job).returns(nil)
    message.stubs(:id).returns(1)
    AutomyraBridge::RunEventRecorder.stubs(:available?).returns(true)
    AutomyraBridgeRun.stubs(:find_by).raises(StandardError, 'boom')
    ctrl = AutomyraBridgeChatController.allocate
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil ctrl.send(:sources_for_message, message)
  end

  # --- 11. chat_controller.rb:593 (automyra_run_for_message) -> nil ------------
  test 'chat_controller automyra_run_for_message swallows and returns nil' do
    message = mock('message')
    message.stubs(:id).returns(1)
    AutomyraBridgeRun.stubs(:find_by).raises(StandardError, 'boom')
    ctrl = AutomyraBridgeChatController.allocate
    # CHARACTERIZATION: current swallow -> nil; Task 14 decides keep/surface.
    assert_nil ctrl.send(:automyra_run_for_message, message)
  end

  # --- 12. chat_controller.rb:689 (safe_attachment_context) -> metadata --------
  test 'chat_controller safe_attachment_context swallows and returns metadata hash' do
    tempfile = mock('tempfile')
    tempfile.stubs(:rewind).raises(StandardError, 'boom')
    file = mock('file')
    file.stubs(:original_filename).returns('notes.txt')
    file.stubs(:content_type).returns('text/plain')
    file.stubs(:size).returns(10)
    file.stubs(:tempfile).returns(tempfile)
    ctrl = AutomyraBridgeChatController.allocate
    # CHARACTERIZATION: current swallow -> metadata hash (no :text key); Task 14 decides keep/surface.
    result = ctrl.send(:safe_attachment_context, file)
    assert_equal({ filename: 'notes.txt', content_type: 'text/plain', filesize: 10 }, result)
  end

  # --- 13. issue_creation_hook.rb:25 (bare rescue, logs) -> swallowed ----------
  test 'issue_creation_hook automyra_bridge_creation_review swallows raised dispatcher error' do
    AutomyraBridge::IssueCreationHook.install!
    ENV['AUTOMYRA_BRIDGE_CREATION_REVIEW'] = '1'
    AutomyraBridge::CreationReviewDispatcher.stubs(:dispatch).raises(StandardError, 'boom')
    issue = Issue.new
    issue.stubs(:project).returns(Project.find(1))
    # CHARACTERIZATION: bare rescue logs and swallows -> no raise propagates; Task 14 decides keep/surface.
    assert_nothing_raised { issue.send(:automyra_bridge_creation_review) }
  ensure
    ENV.delete('AUTOMYRA_BRIDGE_CREATION_REVIEW')
  end

  # --- 14. issue_status_hook.rb:35 (bare rescue, logs) -> swallowed ------------
  test 'issue_status_hook automyra_auto_close_on_status_change swallows raised error' do
    AutomyraBridge::IssueStatusHook.install!
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge('auto_close_enabled' => '1')
    journal = Journal.new
    journal.stubs(:details).raises(StandardError, 'boom')
    # CHARACTERIZATION: bare rescue logs and swallows -> no raise propagates; Task 14 decides keep/surface.
    assert_nothing_raised { journal.send(:automyra_auto_close_on_status_change) }
  ensure
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge('auto_close_enabled' => '0')
  end
end
