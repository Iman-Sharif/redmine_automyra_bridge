module AutomyraBridge
  class ChatThreadToggle
    # Result structure for toggle operations
    class Result
      attr_reader :thread, :kind, :action

      def initialize(thread, kind, action)
        @thread = thread
        @kind = kind
        @action = action
      end

      def page?
        @kind == 'page'
      end

      def global?
        @kind == 'global'
      end
    end

    # Toggle between page and global thread for a user and context
    # Returns a Result object with the active thread, its kind, and the action taken
    #
    # Actions:
    # - 'created_page': Created a new page thread
    # - 'switched_to_global': Switched from page to global thread
    # - 'switched_to_page': Switched from global to existing page thread
    # - 'using_global': Using existing global thread (no page thread exists)
    # - 'using_page': Using existing page thread (already on page thread)
    def self.toggle_for(user, page_type, page_id, project_id: nil, url_path: nil)
      context = normalize_context(user, page_type, page_id, project_id: project_id, url_path: url_path)

      # Ensure global thread exists
      global_thread = ensure_global_thread(user, project_id)

      # Check for existing page thread
      page_thread = find_page_thread(user, context)

      if page_thread
        # Page thread exists - return it
        Result.new(page_thread, 'page', 'using_page')
      else
        # No page thread - create one
        new_page_thread = create_page_thread(user, context[:page_type], context[:page_id], project_id, url_path: url_path)
        Result.new(new_page_thread, 'page', 'created_page')
      end
    end

    # Get the current active thread for a user and context
    # Returns a Result object with the active thread and its kind
    def self.current_for(user, page_type, page_id, project_id: nil, url_path: nil)
      context = normalize_context(user, page_type, page_id, project_id: project_id, url_path: url_path)

      # Check for active page thread first
      page_thread = find_page_thread(user, context)

      if page_thread
        Result.new(page_thread, 'page', 'using_page')
      else
        # Fall back to global thread
        global_thread = AutomyraBridgeChatThread
          .global_for(user)
          .active
          .first

        if global_thread
          Result.new(global_thread, 'global', 'using_global')
        else
          # Create global thread if it doesn't exist
          new_global = create_global_thread(user)
          Result.new(new_global, 'global', 'created_global')
        end
      end
    end

    # Switch to global thread for a user
    # Returns a Result object with the global thread
    def self.switch_to_global(user, project_id: nil)
      global_thread = ensure_global_thread(user, project_id)
      Result.new(global_thread, 'global', 'switched_to_global')
    end

    # Switch to page thread for a user and context
    # Creates the page thread if it doesn't exist
    # Returns a Result object with the page thread
    def self.switch_to_page(user, page_type, page_id, project_id: nil, url_path: nil)
      context = normalize_context(user, page_type, page_id, project_id: project_id, url_path: url_path)

      page_thread = find_page_thread(user, context)

      if page_thread
        Result.new(page_thread, 'page', 'switched_to_page')
      else
        new_page_thread = create_page_thread(user, context[:page_type], context[:page_id], project_id, url_path: url_path)
        Result.new(new_page_thread, 'page', 'created_page')
      end
    end

    private

    # Ensure a global thread exists for the user
    def self.ensure_global_thread(user, project_id)
      global_thread = AutomyraBridgeChatThread
        .global_for(user)
        .active
        .first

      if global_thread
        global_thread.update_column(:project_id, project_id) if global_thread.project_id.blank? && project_id.present?
        backfill_channel_key(global_thread)
        global_thread
      else
        create_global_thread(user, project_id)
      end
    end

    # Create a new global thread for the user
    def self.create_global_thread(user, project_id = nil)
      attrs = {
        user: user,
        thread_kind: 'global',
        page_key: AutomyraBridge::ChatThreadChannelResolver.channel_key(user: user, thread_kind: 'global'),
        status: 'active',
        unread_count: 0,
        project_id: project_id
      }
      attrs[:channel_key] = attrs[:page_key] if AutomyraBridgeChatThread.column_names.include?('channel_key')
      AutomyraBridgeChatThread.create!(attrs)
    end

    # Create a new page thread for the user
    def self.create_page_thread(user, page_type, page_id, project_id = nil, url_path: nil)
      context = normalize_context(user, page_type, page_id, project_id: project_id, url_path: url_path)
      attrs = {
        user: user,
        thread_kind: 'page',
        page_type: context[:page_type],
        page_id: context[:page_id],
        page_key: context[:page_key],
        url_path: url_path,
        status: 'active',
        unread_count: 0,
        project_id: project_id
      }
      attrs[:channel_key] = context[:page_key] if AutomyraBridgeChatThread.column_names.include?('channel_key')
      AutomyraBridgeChatThread.create!(attrs)
    end

    def self.normalize_context(user, page_type, page_id, project_id: nil, url_path: nil)
      normalized_page_type = AutomyraBridge::ChatThreadChannelResolver.page_type(page_type)
      normalized_page_id = page_id.to_i
      {
        page_type: normalized_page_type,
        page_id: normalized_page_id,
        project_id: project_id,
        url_path: url_path,
        page_key: AutomyraBridge::ChatThreadChannelResolver.channel_key(
          user: user,
          thread_kind: 'page',
          page_type: normalized_page_type,
          page_id: normalized_page_id,
          project_id: project_id,
          url_path: url_path
        )
      }
    end

    def self.find_page_thread(user, context)
      exact_scope = AutomyraBridgeChatThread.where(user: user, thread_kind: 'page').active
      exact_scope = exact_scope.where(
        AutomyraBridgeChatThread.column_names.include?('channel_key') ? '(page_key = :key OR channel_key = :key)' : 'page_key = :key',
        key: context[:page_key]
      )
      thread = exact_scope.first || AutomyraBridgeChatThread
          .for_page(user, context[:page_type], context[:page_id], project_id: context[:project_id], url_path: context[:url_path])
          .active
          .first
      backfill_channel_key(thread) if thread
      thread
    end

    def self.backfill_channel_key(thread)
      return unless thread&.has_attribute?(:channel_key)
      return if thread[:channel_key].present?

      thread.update_column(:channel_key, thread.canonical_channel_key)
    end
  end
end
