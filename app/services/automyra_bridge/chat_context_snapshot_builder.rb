module AutomyraBridge
  class ChatContextSnapshotBuilder
    SUPPORTED_PAGE_TYPES = %w[issue wiki_page task_hub_task project generic global].freeze
    DESCRIPTION_LIMIT = 1000
    COMMENT_LIMIT = 5
    COMMENT_BODY_LIMIT = 500

    def self.build(user:, page_type:, page_id: nil, project_id: nil, url_path: nil, page_title: nil)
      new(user: user, page_type: page_type, page_id: page_id, project_id: project_id, url_path: url_path, page_title: page_title).build
    end

    def self.normalize_page_type(page_type)
      case page_type.to_s
      when 'Issue', 'issue'
        'issue'
      when 'WikiPage', 'wiki_page', 'wiki'
        'wiki_page'
      when 'TaskHub::Task', 'task', 'task_hub_task'
        'task_hub_task'
      when 'Project', 'project'
        'project'
      when 'global'
        'global'
      else
        page_type.to_s.present? ? 'generic' : 'global'
      end
    end

    def initialize(user:, page_type:, page_id: nil, project_id: nil, url_path: nil, page_title: nil)
      @user = user || User.anonymous
      @page_type = self.class.normalize_page_type(page_type)
      @page_id = page_id.presence
      @project_id = project_id.presence
      @url_path = url_path.to_s.presence
      @page_title = page_title.to_s.presence
    end

    def build
      object = visible_object
      project = visible_project_for(object)

      {
        page: page_metadata(object),
        project: project_metadata(project),
        user: user_metadata,
        allowed_actions: allowed_actions(project, object),
        object_summary: object_summary(object),
        generated_at: Time.current.utc.iso8601
      }.compact
    end

    private

    attr_reader :user, :page_type, :page_id, :project_id, :url_path, :page_title

    def visible_object
      case page_type
      when 'issue'
        visible_issue
      when 'wiki_page'
        visible_wiki_page
      when 'task_hub_task'
        visible_task
      when 'project'
        visible_project
      end
    end

    def visible_issue
      return nil if page_id.blank?

      Issue.visible(user).find_by(id: page_id.to_i)
    end

    def visible_wiki_page
      return nil if page_id.blank?

      scope = WikiPage.respond_to?(:visible) ? WikiPage.visible(user) : WikiPage.all
      page = scope.find_by(id: page_id.to_i)
      page if page && (!page.respond_to?(:visible?) || page.visible?(user))
    end

    def visible_task
      return nil unless defined?(TaskHub::Task) && page_id.present?

      if defined?(TaskHub::PermissionFilter)
        TaskHub::PermissionFilter.new(user).scope_visible(user, TaskHub::Task).find_by(id: page_id.to_i)
      else
        task = TaskHub::Task.find_by(id: page_id.to_i)
        task if task&.visible?(user)
      end
    end

    def visible_project
      return nil if project_id.blank? && page_id.blank?

      id = project_id.presence || page_id
      if Project.respond_to?(:visible)
        Project.visible(user).find_by(id: id.to_i)
      else
        project = Project.find_by(id: id.to_i)
        project if project&.visible? || user.member_of?(project)
      end
    end

    def visible_project_for(object)
      project = object_project(object) || visible_project
      return nil unless project
      return project if user.admin?
      return project if AutomyraBridge::ChatProjectResolver.visible_to_user?(user, project)

      nil
    end

    def object_project(object)
      return object if object.is_a?(Project)
      return object.project if object.respond_to?(:project) && object.project
      return object.wiki.project if object.respond_to?(:wiki) && object.wiki

      nil
    end

    def page_metadata(object)
      {
        type: page_type,
        id: object&.id || page_id,
        title: compact_text(object_title(object) || page_title, 200),
        url: compact_text(url_path, 500)
      }.compact
    end

    def project_metadata(project)
      return nil unless project

      { id: project.id, name: project.name, identifier: project.identifier }
    end

    def user_metadata
      { id: user.id, name: user.name, login: user.login }
    end

    def allowed_actions(project, object)
      actions = { use_automyra_bridge: project ? user.allowed_to?(:use_automyra_bridge, project) : false }
      actions[:view_issues] = project ? user.allowed_to?(:view_issues, project) : false
      actions[:edit_issues] = project ? user.allowed_to?(:edit_issues, project) : false
      actions[:add_issue_notes] = project ? user.allowed_to?(:add_issue_notes, project) : false
      actions[:view_wiki_pages] = project ? user.allowed_to?(:view_wiki_pages, project) : false
      actions[:edit_wiki_pages] = project ? user.allowed_to?(:edit_wiki_pages, project) : false
      actions[:view_task_hub_tasks] = project ? user.allowed_to?(:view_task_hub_tasks, project) : false
      actions[:manage_task_hub_tasks] = project ? user.allowed_to?(:manage_task_hub_tasks, project) : false
      actions[:object_visible] = object.present?
      actions
    end

    def object_summary(object)
      case object
      when Issue
        issue_summary(object)
      when WikiPage
        wiki_summary(object)
      else
        if defined?(TaskHub::Task) && object.is_a?(TaskHub::Task)
          task_summary(object)
        elsif object.is_a?(Project)
          { type: 'project', name: object.name, description: compact_text(object.description, DESCRIPTION_LIMIT) }
        end
      end
    end

    def issue_summary(issue)
      {
        type: 'issue', id: issue.id, subject: issue.subject,
        description: compact_text(issue.description, DESCRIPTION_LIMIT),
        status: issue.status&.name, tracker: issue.tracker&.name,
        priority: issue.priority&.name, assignee: principal_name(issue.assigned_to),
        author: principal_name(issue.author), journals: issue_journals(issue)
      }.compact
    end

    def issue_journals(issue)
      scope = issue.journals.includes(:user).reorder(created_on: :desc, id: :desc).limit(COMMENT_LIMIT)
      scope = scope.where(private_notes: false) if Journal.column_names.include?('private_notes') && !user.allowed_to?(:view_private_notes, issue.project)
      scope.map { |journal| { id: journal.id, author: principal_name(journal.user), notes: compact_text(journal.notes, COMMENT_BODY_LIMIT), created_on: journal.created_on&.utc&.iso8601 }.compact }
           .reject { |journal| journal[:notes].blank? }
    end

    def wiki_summary(page)
      content = page.respond_to?(:content) ? page.content : nil
      {
        type: 'wiki_page', id: page.id, title: page.title,
        content_excerpt: compact_text(content&.text, DESCRIPTION_LIMIT)
      }.compact
    end

    def task_summary(task)
      {
        type: 'task_hub_task', id: task.id, title: task.title,
        notes: compact_text(task.notes, DESCRIPTION_LIMIT), status: task.status,
        priority: task.priority, assignee: principal_name(task.assigned_to),
        author: principal_name(task.author), due_date: task.due_date&.iso8601,
        comments: task.comments.reorder(created_at: :desc, id: :desc).limit(COMMENT_LIMIT).map { |comment| { id: comment.id, author: principal_name(comment.author), body: compact_text(comment.body, COMMENT_BODY_LIMIT), created_at: comment.created_at&.utc&.iso8601 }.compact }
      }.compact
    end

    def object_title(object)
      object.try(:subject) || object.try(:title) || object.try(:name)
    end

    def principal_name(principal)
      principal&.name
    end

    def compact_text(value, limit)
      value.to_s.squish.truncate(limit).presence
    end
  end
end
