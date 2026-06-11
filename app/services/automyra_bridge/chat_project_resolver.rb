module AutomyraBridge
  class ChatProjectResolver
    def self.from_context(context)
      return nil unless context.is_a?(Hash)
      from_page(context[:page_type], context[:page_id]) || from_project_id(context[:project_id]) || context[:project]
    end

    def self.from_project_id(project_id)
      return nil if project_id.blank?

      Project.find_by(id: project_id.to_i)
    end

    def self.from_page(page_type, page_id)
      return nil if page_type.blank? || page_id.blank?

      case page_type.to_s
      when 'issue', 'Issue'
        Issue.find_by(id: page_id.to_i)&.project
      when 'wiki_page', 'WikiPage'
        WikiPage.find_by(id: page_id.to_i)&.wiki&.project
      when 'task', 'task_hub_task', 'TaskHub::Task'
        return nil unless defined?(TaskHub::Task)
        TaskHub::Task.find_by(id: page_id.to_i)&.project
      when 'project', 'Project'
        from_project_id(page_id)
      end
    end

    def self.visible_to_user?(user, project)
      return false unless user && project

      project.visible? || user.member_of?(project)
    end
  end
end
