module AutomyraBridge
  class ChatContextBuilder
    def self.from_controller(controller)
      new(controller).build
    end

    def initialize(controller)
      @controller = controller
      @request = controller.request if controller.respond_to?(:request)
      @params = controller.params if controller.respond_to?(:params)
    end

    def build
      ctx = {
        page_type: page_type,
        page_id: page_id,
        project_id: project_id,
        url_path: url_path,
        page_title: page_title,
        user_id: User.current&.id
      }
      ctx.compact
    end

    private

    def page_type
      action = @controller.action_name.to_s
      ctrl = @controller.controller_name.to_s
      [ctrl, action].join('/')
    end

    def page_id
      id_from_params || id_from_instance_variable
    end

    def id_from_params
      @params[:id]&.to_s.presence ||
        @params[:issue_id]&.to_s.presence ||
        @params[:task_id]&.to_s.presence ||
        @params[:page_id]&.to_s.presence
    end

    def id_from_instance_variable
      obj = @controller.instance_variable_get(:@issue) ||
            @controller.instance_variable_get(:@wiki_page) ||
            @controller.instance_variable_get(:@page) ||
            @controller.instance_variable_get(:@task) ||
            @controller.instance_variable_get(:@project)
      obj&.id&.to_s
    end

    def project_id
      pid = @params[:project_id]&.to_s.presence
      return pid if pid

      obj = @controller.instance_variable_get(:@project) ||
            @controller.instance_variable_get(:@issue)&.project ||
            @controller.instance_variable_get(:@wiki_page)&.wiki&.project ||
            @controller.instance_variable_get(:@task)&.project
      obj&.id&.to_s
    end

    def url_path
      @request&.fullpath
    end

    def page_title
      ivar_title || object_title
    end

    def ivar_title
      @controller.instance_variable_get(:@page_title)&.to_s.presence
    end

    def object_title
      obj = @controller.instance_variable_get(:@issue) ||
            @controller.instance_variable_get(:@wiki_page) ||
            @controller.instance_variable_get(:@page) ||
            @controller.instance_variable_get(:@task) ||
            @controller.instance_variable_get(:@project)
      title = obj.try(:subject) || obj.try(:title) || obj.try(:name)
      title&.to_s
    end
  end
end
