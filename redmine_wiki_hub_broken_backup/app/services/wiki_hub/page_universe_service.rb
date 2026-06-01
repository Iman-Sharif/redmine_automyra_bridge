module WikiHub
  class PageUniverseService
    attr_reader :user

    def initialize(user)
      @user = user || User.anonymous
      @permission_filter = WikiHub::PermissionFilter.new(@user)
    end

    def visible_pages
      WikiHub::PageSnapshot.where(project_id: visible_project_ids)
    end

    private

    attr_reader :permission_filter

    def visible_projects
      projects = Project.visible(user)
                        .joins(:enabled_modules)
                        .where(enabled_modules: { name: 'wiki' })
      projects = projects.where.not(status: Project::STATUS_ARCHIVED) if defined?(Project::STATUS_ARCHIVED)

      projects.distinct
    end

    def visible_project_ids
      @visible_project_ids ||= visible_projects.select { |project| permission_filter.can_view?(project) }.map(&:id)
    end
  end
end
