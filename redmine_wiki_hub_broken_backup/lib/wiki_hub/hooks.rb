module WikiHub
  class Hooks < Redmine::Hook::Listener
    class << self
      def install_lifecycle_bridge!
        return unless defined?(WikiController)
        return unless WikiController.instance_methods.include?(:rename)
        return unless WikiController.instance_methods.include?(:destroy)
        return if WikiController < WikiHub::WikiControllerLifecycleBridge

        WikiController.prepend(WikiHub::WikiControllerLifecycleBridge)
      end

      def reindex_page_safely(page, action:)
        return unless page

        WikiHub::Indexer.reindex_page(page)
      rescue StandardError => e
        log_lifecycle_failure(action: action, operation: 'reindex', page_id: page&.id, error: e)
      end

      def remove_page_safely(page_id, action:)
        return unless page_id

        WikiHub::Indexer.remove_page(page_id)
      rescue StandardError => e
        log_lifecycle_failure(action: action, operation: 'cleanup', page_id: page_id, error: e)
      end

      def handle_rename(previous_title:, page:)
        return unless page
        return if previous_title.blank?
        return if page.title.to_s == previous_title.to_s

        reindex_page_safely(page, action: 'rename')
      end

      def handle_destroy(page_id:)
        return unless page_id
        return if WikiPage.exists?(page_id)

        remove_page_safely(page_id, action: 'destroy')
      end

      private

      def log_lifecycle_failure(action:, operation:, page_id:, error:)
        Rails.logger.error("[redmine_wiki_hub] wiki #{action} #{operation} failed page_id=#{page_id} error=#{error.class}: #{error.message}")
      end
    end

    def controller_wiki_edit_after_save(context = {})
      page = context[:page]
      self.class.reindex_page_safely(page, action: 'save')
    end

    def controller_wiki_edit_post(context = {})
      controller_wiki_edit_after_save(context)
    end
  end

  module WikiControllerLifecycleBridge
    def rename
      previous_title = lifecycle_page&.title
      result = super

      WikiHub::Hooks.handle_rename(previous_title: previous_title, page: lifecycle_page)

      result
    end

    def destroy
      page_id = lifecycle_page&.id
      result = super

      WikiHub::Hooks.handle_destroy(page_id: page_id)

      result
    end

    private

    def lifecycle_page
      instance_variable_defined?(:@page) ? @page : nil
    end
  end
end
