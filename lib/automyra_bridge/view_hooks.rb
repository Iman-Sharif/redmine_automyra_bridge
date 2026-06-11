module AutomyraBridge
  class ViewHooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(_context = {})
      stylesheet_link_tag('automyra_chat', plugin: 'redmine_automyra_bridge') +
        stylesheet_link_tag('automyra_governance', plugin: 'redmine_automyra_bridge') +
        javascript_include_tag('automyra_chat', plugin: 'redmine_automyra_bridge')
    end

    def view_layouts_base_body_bottom(context = {})
      page_context = automyra_page_context(context)
      return unless automyra_chat_available?(page_context)
      thread = automyra_chat_thread(page_context, context[:project])

      controller = context[:controller]
      return unless controller

      button_html = controller.send(
        :render_to_string,
        partial: 'automyra_bridge_chat/floating_button',
        locals: { thread: thread, page_context: page_context }
      )

      panel_html = controller.send(
        :render_to_string,
        partial: 'automyra_bridge_chat/panel',
        locals: { thread: thread, page_context: page_context }
      )

      "#{button_html}\n#{panel_html}"
    end

    private

    def automyra_chat_available?(page_context)
      project = AutomyraBridge::ChatProjectResolver.from_context(page_context)
      AutomyraBridge::ChatPermission.allowed?(User.current, project: project)
    end

    def automyra_page_context(context)
      controller = context[:controller]
      request = context[:request]
      project = context[:project] || controller&.instance_variable_get(:@project)
      issue = context[:issue] || controller&.instance_variable_get(:@issue)
      wiki_page = context[:page] || controller&.instance_variable_get(:@page)
      wiki_page = nil unless wiki_page.is_a?(WikiPage)
      task = controller&.instance_variable_get(:@task)
      task = nil unless task.is_a?(TaskHub::Task)
      task_project = task&.project

      page_type = automyra_canonical_page_type(issue: issue, wiki_page: wiki_page, task: task, project: project)

      {
        controller: controller&.controller_name,
        action: controller&.action_name,
        page_title: automyra_page_title(controller),
        url_path: request&.path,
        project: project || issue&.project || wiki_page&.wiki&.project || task_project,
        project_id: project&.id || issue&.project_id || wiki_page&.wiki&.project_id || task_project&.id,
        page_type: page_type,
        page_id: issue&.id || wiki_page&.id || task&.id || (page_type == 'project' ? project&.id : nil),
        issue_id: issue&.id,
        wiki_page_id: wiki_page&.id,
        wiki_page_title: wiki_page&.title,
        task_id: task&.id
      }
    end

    def automyra_canonical_page_type(issue:, wiki_page:, task:, project:)
      return 'issue' if issue
      return 'wiki_page' if wiki_page
      return 'task_hub_task' if task
      return 'project' if project

      'global'
    end

    def automyra_page_title(controller)
      controller&.view_context&.html_title
    rescue StandardError
      nil
    end

    def automyra_chat_thread(page_context, project)
      page_type, page_id = automyra_thread_page(page_context)

      if page_type && page_id
        AutomyraBridgeChatThread
          .for_page(User.current, page_type, page_id)
          .active
          .first || AutomyraBridgeChatThread.new(
            user: User.current,
            project: project,
            thread_kind: 'page',
            page_type: page_type,
            page_id: page_id,
            page_key: AutomyraBridgeChatThread.generate_page_key(page_type, page_id),
            status: 'active',
            unread_count: 0
          )
      else
        AutomyraBridgeChatThread
          .global_for(User.current)
          .active
          .first || AutomyraBridgeChatThread.new(
            user: User.current,
            project: project,
            thread_kind: 'global',
            page_key: 'global',
            status: 'active',
            unread_count: 0
          )
      end
    end

    def automyra_thread_page(page_context)
      return ['Issue', page_context[:issue_id]] if page_context[:issue_id].present?
      return ['WikiPage', page_context[:wiki_page_id]] if page_context[:wiki_page_id].present?
      return ['task_hub_task', page_context[:task_id]] if page_context[:task_id].present?
      return ['project', page_context[:project_id]] if page_context[:page_type] == 'project' && page_context[:project_id].present?

      nil
    end
  end
end
