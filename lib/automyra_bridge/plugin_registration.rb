module AutomyraBridge
  # Registers the Redmine plugin metadata, settings, menus, and permissions.
  # Mirrors the pattern used by redmine_error_hub's plugin_registration.rb.
  module PluginRegistration
    module_function

    def register!
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
                   'hermes_webhook_url' => 'https://automyra.bundecca.co.uk/webhooks/redmica-mentions',
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
                   'mr_t_mention_pattern' => 'mrt',
                   'mr_t_user_login' => '',
                   'hermes_webhook_url_mr_t_mentions' => '',
                   'hermes_webhook_secret' => '',
                   'activity_log_secret' => 'change-me-in-production',
                   'auto_close_enabled' => '0',
                   'auto_close_trigger_status_name' => 'Resolved',
                   'hermes_webhook_retry_interval_minutes' => '30',
                   'hermes_webhook_retry_max_retries' => '3',
                   'hermes_webhook_retry_timeout_minutes' => '60'
                 },
                 partial: 'settings/automyra_bridge_settings'

        project_module :automyra_bridge do
          AutomyraBridge::PluginRegistration.register_permissions(self)
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
    end

    def register_permissions(plugin)
      plugin.permission :use_automyra_bridge,
                        { automyra_bridge: %i[improve_task assistant_request] },
                        require: :member
      plugin.permission :manage_automyra_bridge,
                        {
                          automyra_bridge_operator: %i[index retry_job cancel_job update_settings]
                        },
                        require: :member
    end
  end
end
