require 'digest'

module AutomyraBridge
  class ChatThreadChannelResolver
    def self.channel_key(user: nil, thread_kind: nil, page_type: nil, page_id: nil, project_id: nil, url_path: nil)
      new(
        user: user,
        thread_kind: thread_kind,
        page_type: page_type,
        page_id: page_id,
        project_id: project_id,
        url_path: url_path
      ).channel_key
    end

    def self.page_type(page_type)
      if defined?(AutomyraBridge::ChatContextSnapshotBuilder)
        AutomyraBridge::ChatContextSnapshotBuilder.normalize_page_type(page_type)
      else
        page_type.to_s
      end
    end

    def initialize(user: nil, thread_kind: nil, page_type: nil, page_id: nil, project_id: nil, url_path: nil)
      @user = user
      @thread_kind = thread_kind.to_s.presence
      @page_type = self.class.page_type(page_type)
      @page_id = page_id.presence
      @project_id = project_id.presence
      @url_path = url_path.to_s.presence
    end

    def channel_key
      return global_key if global?

      case page_type
      when 'project'
        "project:#{canonical_project_id}"
      when 'issue'
        "issue:#{canonical_page_id}"
      when 'wiki_page'
        "wiki_page:#{canonical_page_id}"
      when 'task_hub_task'
        "task_hub_task:#{canonical_page_id}"
      else
        generic_key
      end
    end

    private

    attr_reader :user, :thread_kind, :page_type, :page_id, :project_id, :url_path

    def global?
      thread_kind == 'global' || page_type == 'global'
    end

    def global_key
      "global:user:#{user_id}"
    end

    def user_id
      user.respond_to?(:id) ? user.id : user
    end

    def canonical_project_id
      project_id.presence || canonical_page_id
    end

    def canonical_page_id
      page_id.to_i
    end

    def generic_key
      "generic:#{canonical_project_id}:#{url_hash}"
    end

    def url_hash
      Digest::SHA256.hexdigest(url_path.presence || page_id.to_s)[0, 16]
    end
  end
end
