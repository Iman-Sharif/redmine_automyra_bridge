module AutomyraBridge
  class ChatPermission
    SUPPORTED_PAGE_TYPES = %w[issue Issue wiki_page WikiPage task task_hub_task TaskHub::Task project Project generic global].freeze

    def self.allowed?(user, project: nil, page_type: nil, page_id: nil, thread: nil)
      return false unless user&.logged?
      return true if user.admin?

      return allowed_for_thread?(user, thread) if thread

      project ||= ChatProjectResolver.from_page(page_type, page_id)
      if project
        return project_visible_to_user?(user, project) && user.allowed_to?(:use_automyra_bridge, project)
      end

      allowed_for_any_visible_project?(user)
    end

    def self.allowed_for_thread?(user, thread)
      return false unless thread&.user_id == user&.id
      return true if user.admin?

      project = ChatProjectResolver.from_page(thread.page_type, thread.page_id) || thread.project
      project ? project_visible_to_user?(user, project) && user.allowed_to?(:use_automyra_bridge, project) : false
    end

    def self.valid_thread_kind?(kind)
      %w[page global].include?(kind.to_s)
    end

    def self.valid_page_type?(page_type)
      SUPPORTED_PAGE_TYPES.include?(page_type.to_s)
    end

    def self.allowed_for_any_visible_project?(user)
      Project.all.any? do |project|
        project_visible_to_user?(user, project) && user.allowed_to?(:use_automyra_bridge, project)
      end
    end
    private_class_method :allowed_for_any_visible_project?

    def self.project_visible_to_user?(user, project)
      return false unless user && project

      project.visible? || user.member_of?(project)
    end
    private_class_method :project_visible_to_user?
  end
end
