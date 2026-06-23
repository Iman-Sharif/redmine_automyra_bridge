# frozen_string_literal: true

require 'redmine'

Redmine::Plugin.register :redmine_automyra_bridge do
  name 'Automyra Bridge'
  author 'OpenCode'
  description 'Policy-controlled Redmica to Automyra integration bridge.'
  version '0.1.0'

  requires_redmine version: '6.0'

  settings default: {
             'automyra_endpoint' => '',
             'automyra_token' => '',
             'request_timeout_seconds' => '15',
             'memory_endpoint' => '',
             'memory_token' => '',
             'memory_session_key' => 'main',
             'memory_model' => 'manifest/auto',
             'memory_lancedb_config_path' => '/root/.openclaw/openclaw.json',
             'memory_lancedb_uri' => '',
             'memory_lancedb_table' => 'memories',
             'memory_lancedb_redmine_table' => 'redmine-memories',
             'webhook_secret' => '',
             'webhook_user_login' => '',
             'hermes_webhook_url' => 'https://automyra.sbg-server.com/webhooks/redmica-mentions',
             'hermes_webhook_url_mentions' => '',
             'hermes_webhook_url_creation_review' => '',
             'hermes_webhook_url_auto_close' => '',
             'hermes_webhook_url_wiki_review' => '',
             'hermes_webhook_url_faq_review' => '',
             'hermes_webhook_url_faq_status_changed' => '',
             'hermes_webhook_url_error_review' => '',
             'hermes_webhook_url_error_status_changed' => '',
             'hermes_webhook_url_task_review' => '',
             'hermes_webhook_url_task_status_changed' => '',
             'hermes_webhook_url_contacts_review' => '',
             'hermes_webhook_url_contacts_status_changed' => '',
             'hermes_webhook_url_document_review' => '',
             'hermes_webhook_url_repo_review' => '',
             'hermes_webhook_secret' => '',
             'activity_log_secret' => 'change-me-in-production',
             'auto_close_enabled' => '0',
             'auto_close_trigger_status_name' => 'Resolved'
           },
           partial: 'settings/automyra_bridge_settings'

  project_module :automyra_bridge do
    permission :use_automyra_bridge,
               { automyra_bridge: %i[improve_task assistant_request] },
               require: :member
    permission :manage_automyra_bridge,
               {
                 automyra_bridge_operator: %i[index retry_job cancel_job update_settings]
               },
               require: :member
  end

  menu :project_menu,
       :automyra_bridge,
       { controller: 'automyra_bridge_operator', action: 'index' },
       caption: 'Automyra',
       after: :activity,
       param: :project_id

  Redmine::MenuManager.map(:application_menu).delete(:issues)
  Redmine::MenuManager.map(:application_menu).push(
    :issues,
    { controller: 'issues', action: 'index' },
    if: proc do
      User.current.allowed_to?(:view_issues, nil, global: true) &&
        EnabledModule.exists?(project: Project.visible, name: :issue_tracking)
    end,
    caption: :label_issue_plural,
    after: :projects
  )
end

Rails.application.config.after_initialize do
  top_menu = Redmine::MenuManager.items(:top_menu)
  issues = top_menu.children.find { |child| child.name == :issues }
  if issues
    top_menu.children.delete(issues)
    projects = top_menu.children.find { |child| child.name == :projects }
    if projects
      idx = top_menu.children.index(projects)
      top_menu.children.insert(idx + 1, issues)
    else
      top_menu.children.unshift(issues)
    end
    issues.parent = top_menu
  end
end

prepare_automyra_bridge = proc do
  require_dependency File.expand_path('app/services/automyra_bridge/chat_permission', __dir__)
  require_dependency File.expand_path('app/controllers/automyra_bridge_webhooks_controller', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_project_resolver', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/audit_recorder', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/mention_detector', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_context_builder', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_job_creator', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_message_creator', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_poll_service', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_thread_toggle', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/hermes_webhook_notifier', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/job_creator', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/run_event_recorder', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/job_processor', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/memory_writer', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/memory_reader', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/memory_sync', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/chat_memory_writer', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/base_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/semantic_read_helpers', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_create_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_update_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_cancel_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_complete_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_reopen_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_assign_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_set_priority_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_set_due_date_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_add_comment_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_link_issue_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_promote_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_search_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_hub_count_my_open_tasks_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_hub_get_my_open_tasks_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/task_hub_search_my_tasks_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_create_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_update_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_assign_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_set_status_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_set_priority_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_set_due_date_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_link_related_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_search_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_summarize_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_assign_to_requester_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issue_add_comment_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/issues_get_my_open_issues_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_read_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_search_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_create_page_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_update_page_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_create_draft_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_summarize_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_backlinks_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/wiki_related_pages_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_current_object_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_current_page_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_current_thread_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_linked_objects_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_project_search_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_memory_search_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/context_expand_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tools/project_status_summary_tool', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/tool_registry', __dir__)
  AutomyraBridge::ToolRegistry.validate_tool_classes!
  require_dependency File.expand_path('app/services/automyra_bridge/action_proposal_creator', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/action_proposal_executor', __dir__)
  require_dependency File.expand_path('app/models/automyra_bridge_project_setting', __dir__)
  require_dependency File.expand_path('app/models/automyra_bridge_chat_thread', __dir__)
  require_dependency File.expand_path('app/models/automyra_bridge_chat_message', __dir__)
  require_dependency File.expand_path('app/models/automyra_bridge_run', __dir__)
  require_dependency File.expand_path('app/models/automyra_bridge_run_event', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/view_hooks', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/journal_hook', __dir__)
  AutomyraBridge::JournalHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/issue_status_hook', __dir__)
  AutomyraBridge::IssueStatusHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/issue_creation_hook', __dir__)
  AutomyraBridge::IssueCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/wiki_creation_hook', __dir__)
  AutomyraBridge::WikiCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/env', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/faq_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/faq_hub_creation_hook', __dir__)
  AutomyraBridge::FaqHubCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/faq_status_hook', __dir__) unless defined?(AutomyraBridge::FaqStatusHook)
  require_dependency File.expand_path('app/services/automyra_bridge/faq_hub_status_dispatcher', __dir__)
  AutomyraBridge::FaqStatusHook.install!
  require_dependency File.expand_path('app/services/automyra_bridge/error_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/error_hub_creation_hook', __dir__)
  AutomyraBridge::ErrorHubCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/error_status_hook', __dir__) unless defined?(AutomyraBridge::ErrorStatusHook)
  require_dependency File.expand_path('app/services/automyra_bridge/error_hub_status_dispatcher', __dir__)
  AutomyraBridge::ErrorStatusHook.install!
  require_dependency File.expand_path('app/services/automyra_bridge/task_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/task_hub_creation_hook', __dir__)
  AutomyraBridge::TaskHubCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/task_status_hook', __dir__) unless defined?(AutomyraBridge::TaskStatusHook)
  require_dependency File.expand_path('app/services/automyra_bridge/task_hub_status_dispatcher', __dir__)
  AutomyraBridge::TaskStatusHook.install!
  require_dependency File.expand_path('app/services/automyra_bridge/contacts_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/contacts_hub_creation_hook', __dir__)
  AutomyraBridge::ContactsHubCreationHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/contacts_status_hook', __dir__) unless defined?(AutomyraBridge::ContactsStatusHook)
  require_dependency File.expand_path('app/services/automyra_bridge/contacts_hub_status_dispatcher', __dir__)
  AutomyraBridge::ContactsStatusHook.install!
  require_dependency File.expand_path('lib/automyra_bridge/document_hub_creation_hook', __dir__)
  AutomyraBridge::DocumentHubCreationHook.install!
  require_dependency File.expand_path('app/services/automyra_bridge/document_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('app/services/automyra_bridge/repo_hub_review_dispatcher', __dir__)
  require_dependency File.expand_path('lib/automyra_bridge/repo_hub_creation_hook', __dir__)
  AutomyraBridge::RepoHubCreationHook.install!
end

prepare_automyra_bridge.call
Rails.configuration.to_prepare(&prepare_automyra_bridge)
