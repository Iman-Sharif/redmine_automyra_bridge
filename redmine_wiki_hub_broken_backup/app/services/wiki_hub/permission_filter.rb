module WikiHub
  class PermissionFilter
    attr_reader :user

    def initialize(user)
      @user = user || User.anonymous
    end

    def can_view?(page)
      project = project_for(page)
      project.present? && user.allowed_to?(:view_wiki_pages, project)
    end

    def can_edit?(page)
      project = project_for(page)
      project.present? && user.allowed_to?(:edit_wiki_pages, project)
    end

    def can_delete?(page)
      project = project_for(page)
      project.present? && user.allowed_to?(:delete_wiki_pages, project)
    end

    def viewable_projects(scope = Project.all)
      permitted_projects(scope, :view_wiki_pages)
    end

    def editable_projects(scope = Project.all)
      permitted_projects(scope, :edit_wiki_pages)
    end

    def deletable_projects(scope = Project.all)
      permitted_projects(scope, :delete_wiki_pages)
    end

    def viewable_pages(scope = WikiPage.all)
      return scope.none if viewable_project_ids.empty?

      scope.joins(:wiki).where(wikis: { project_id: viewable_project_ids })
    end

    def editable_pages(scope = WikiPage.all)
      return scope.none if editable_project_ids.empty?

      scope.joins(:wiki).where(wikis: { project_id: editable_project_ids })
    end

    def viewable_snapshots(scope = WikiHub::PageSnapshot.all)
      return scope.none if viewable_project_ids.empty?

      scope.where(project_id: viewable_project_ids)
    end

    def editable_snapshots(scope = WikiHub::PageSnapshot.all)
      return scope.none if editable_project_ids.empty?

      scope.where(project_id: editable_project_ids)
    end

    def find_viewable_project(value)
      project = resolve_project(value)
      project if can_view?(project)
    end

    def find_editable_project(value)
      project = resolve_project(value)
      project if can_edit?(project)
    end

    private

    def viewable_project_ids
      @viewable_project_ids ||= viewable_projects.map(&:id)
    end

    def editable_project_ids
      @editable_project_ids ||= editable_projects.map(&:id)
    end

    def permitted_projects(scope, permission)
      scope.to_a.filter_map do |record|
        project = record.is_a?(Project) ? record : project_for(record)
        project if project.present? && user.allowed_to?(permission, project)
      end.uniq
    end

    def resolve_project(value)
      return if value.blank?

      if value.to_s.match?(/\A\d+\z/)
        Project.find_by(id: value.to_i)
      else
        Project.find_by(identifier: value)
      end
    end

    def project_for(page)
      case page
      when Project
        page
      when WikiHub::PageSnapshot
        page.project || Project.find_by(id: page.project_id)
      when WikiPage
        page.wiki&.project
      else
        return page.project if page.respond_to?(:project) && page.project.present?

        Project.find_by(id: page.project_id) if page.respond_to?(:project_id)
      end
    end
  end
end
