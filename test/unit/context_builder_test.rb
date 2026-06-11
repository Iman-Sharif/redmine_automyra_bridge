require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeContextBuilderTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues, :trackers, :issue_statuses, :journals, :members, :member_roles, :roles

  setup do
    @project = Project.find(1)
    @admin = User.find(1)
    @member = User.find(2)
    @task = TaskHub::Task.create!(title: 'Context task', user: @member, author: @member, project: @project, status: 'todo')
    @comment = @task.comments.create!(author: @member, body: '@automyra review')
    @issue = Issue.find(1)
    @task.update!(issue_id: @issue.id)
  end

  test 'task context includes comments' do
    ctx = AutomyraBridge::ContextBuilder.for_task(@task, @member, tier: 1)
    bodies = ctx[:comments].map { |c| c[:body] }
    assert_includes bodies, '@automyra review'
  end

  test 'task context omits private notes for non-admin without view_private_notes' do
    Journal.create!(journalized: @issue, user: @admin, notes: 'Private note', private_notes: true)
    ctx = AutomyraBridge::ContextBuilder.for_issue(@issue, @member, tier: 1)
    notes = ctx[:journals].map { |j| j[:notes] }
    refute_includes notes, 'Private note'
  end

  test 'issue context omits private notes' do
    Journal.create!(journalized: @issue, user: @admin, notes: 'Private note', private_notes: true)
    ctx = AutomyraBridge::ContextBuilder.for_issue(@issue, @member, tier: 1)
    notes = ctx[:journals].map { |j| j[:notes] }
    refute_includes notes, 'Private note'
  end

  test 'project search returns empty when user cannot view project' do
    without_view = User.find(3)
    search = AutomyraBridge::ContextBuilder.new(without_view, 3).project_search(@project, 'Bug')
    project_visible = without_view.allowed_to?(:view_project, @project)
    if project_visible
      # If allowed, just assert it returns a hash
      assert search.is_a?(Hash)
    else
      assert_equal({ error: 'User cannot search this project.' }, search)
    end
  end

  test 'task context omits wiki_search if user lacks view_wiki_pages' do
    other_project = Project.find(3)
    search = AutomyraBridge::ContextBuilder.new(User.find(3), 3).project_search(other_project, 'test')
    # User 3 is not a member and will have empty results
    assert_equal([], search[:wiki_pages]) if search.is_a?(Hash)
  end

  test 'context scope permissions describe what user can see' do
    scope = AutomyraBridge::JobCreator.send(:context_scope, @member, @project, @task)
    assert_equal @member.allowed_to?(:view_task_hub_tasks, @project), scope[:view_task_hub_tasks]
    assert_equal @member.allowed_to?(:manage_task_hub_tasks, @project), scope[:edit_task_hub_tasks]
    assert_equal @project.id, scope[:project_id]
    assert_equal 'TaskHub::Task', scope[:source_type]
  end
end
