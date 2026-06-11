module AutomyraBridge
  class ContextBuilder
    def self.for_task(task, user, tier: 1)
      new(user, tier).task(task)
    end

    def self.for_issue(issue, user, tier: 1)
      new(user, tier).issue(issue)
    end

    def initialize(user, tier)
      @user = user
      @tier = tier.to_i.clamp(1, 4)
    end

    def task(task)
      context = {
        tier: @tier,
        task: {
          id: task.id,
          title: task.title,
          notes: task.notes,
          status: task.status,
          priority: task.priority,
          due_date: task.due_date&.to_s,
          project_id: task.project_id,
          issue_id: task.issue_id
        }.compact,
        comments: filtered_task_comments(task),
        recent_automyra_actions: AutomyraBridgeActionProposal.visible_on_task(task)
          .order(updated_at: :desc).limit(10).map { |proposal|
          { id: proposal.id, action_type: proposal.action_type, status: proposal.status, updated_at: proposal.updated_at&.iso8601 }
        },
        automyra_memory: AutomyraBridge::MemoryReader.recent(task),
        memory_event: memory_event
      }
      context[:linked_issue] = issue_summary(task.issue) if @tier >= 2 && task.issue
      context[:project_search] = project_search(task.project, task.title) if @tier >= 3 && task.project
      context
    end

    def issue(issue)
      context = {
        tier: @tier,
        issue: issue_summary(issue).merge(description: issue.description).compact,
        journals: filtered_journals(issue),
        automyra_memory: AutomyraBridge::MemoryReader.recent(issue),
        memory_event: memory_event
      }
      context[:project_search] = project_search(issue.project, issue.subject) if @tier >= 3
      context
    end

    def project_search(project, query, limit: 5)
      return { error: 'User cannot search this project.' } unless @user.allowed_to?(:view_project, project)

      q = query.to_s.downcase
      {
        tasks: defined?(TaskHub::Task) ? TaskHub::Task.where(project: project).where('LOWER(title) LIKE ?', "%#{q}%").limit(limit).map { |task|
          { id: task.id, title: task.title, status: task.status }
        } : [],
        issues: Issue.visible(@user).where(project: project).where('LOWER(issues.subject) LIKE ?', "%#{q}%").limit(limit).map { |issue|
          issue_summary(issue)
        },
        wiki_pages: wiki_search(project, q, limit)
      }
    end

    def issue_summary(issue)
      { id: issue.id, subject: issue.subject, status: issue.status&.name, tracker: issue.tracker&.name, assigned_to: issue.assigned_to&.name, project_id: issue.project_id }
    end

    private

    def filtered_task_comments(task)
      task.comments.includes(:author).order(:created_at, :id).map { |comment|
        { id: comment.id, author: comment.author&.name, body: comment.body, created_at: comment.created_at&.iso8601 }
      }
    end

    def filtered_journals(issue)
      visible_journals = issue.journals.visible.order(:created_on, :id)
      unless @user.admin? || @user.allowed_to?(:view_private_notes, issue.project)
        visible_journals = visible_journals.where(private_notes: false)
      end
      visible_journals.map { |journal| { id: journal.id, author: journal.user&.name, notes: journal.notes, created_at: journal.created_on&.iso8601 } }
    end

    def wiki_search(project, query, limit)
      return [] unless @user.allowed_to?(:view_wiki_pages, project)
      WikiPage.joins(:wiki).where(wikis: { project_id: project.id }).where('LOWER(wiki_pages.title) LIKE ?', "%#{query}%").limit(limit).map { |page| { id: page.id, title: page.title } }
    end

    def memory_event
      { type: 'redmica_conversation', user_id: @user.id, user_name: @user.name }
    end
  end
end
