require 'redmine'
require_relative './lib/task_hub'
require_relative './lib/task_hub/hooks/issue_hooks'

Redmine::Plugin.register :redmine_task_hub do
  name 'Task Hub'
  author 'OpenCode'
  description 'Unified task hub plugin for global and project task management entry points.'
  version '0.1.0'

  requires_redmine version: '6.0'

  settings default: {}, partial: nil

  project_module :task_hub do
    permission :view_task_hub_tasks,
               {
                 task_hub: %i[index my_tasks due_today overdue recently_completed],
                 task_hub_standalone: %i[index show],
                 task_hub_issue_tasks: %i[index show],
                 task_hub_promotion: [:new]
               },
               require: :member
    permission :manage_task_hub_tasks,
               {
                 task_hub_standalone: %i[new create edit update complete cancel reopen destroy move],
                 task_hub_issue_tasks: %i[new create edit update complete cancel reopen destroy reorder move],
                 task_hub_promotion: [:create],
                 task_hub_templates: %i[index new create edit update destroy]
               },
               require: :member
  end

  menu :top_menu,
       :task_hub,
       { controller: 'task_hub', action: 'index' },
       caption: 'Task Hub'

  menu :top_menu, :task_hub_templates,
       { controller: 'task_hub_templates', action: 'index' },
       caption: 'Templates', parent: :task_hub
end

if defined?(Redmine::Hook)
  Redmine::Hook.add_listener(TaskHub::Hooks::IssueHooks)
end
