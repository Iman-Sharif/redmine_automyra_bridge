# frozen_string_literal: true

module AutomyraBridge
  # Wires Document Hub review webhook hooks onto native `Document` and
  # `Attachment` records, mirroring `DocumentHub::NativeHooks`.
  #
  # Native `Document` create/update commits dispatch document review events.
  # Native `Attachment` create commits dispatch the same document review event
  # when the attachment is attached to a Document (treated as adding a
  # snapshot/version to the document). Attachments on Project or Version are
  # not currently dispatched; the hook is still patched on Attachment because
  # that is the pattern used by DocumentHub.
  #
  # Gating (mirroring FAQ/Error Hub hooks):
  #   - feature-flagged via `ENV['AUTOMYRA_BRIDGE_DOCUMENT_REVIEW']`
  #   - thread-local `:automyra_bridge_skip_webhook` opt-out
  #   - skips records authored by the configured bot user
  module DocumentHubCreationHook
    def self.install!
      return unless defined?(::DocumentHub)

      patch_document!
      patch_attachment!
    end

    def self.patch_document!
      return unless defined?(::Document)
      return if ::Document.included_modules.include?(::AutomyraBridge::DocumentHubCreationHook::DocumentInstanceMethods)

      ::Document.include ::AutomyraBridge::DocumentHubCreationHook::DocumentInstanceMethods
    end

    def self.patch_attachment!
      return unless defined?(::Attachment)
      return if ::Attachment.included_modules.include?(::AutomyraBridge::DocumentHubCreationHook::AttachmentInstanceMethods)

      ::Attachment.include ::AutomyraBridge::DocumentHubCreationHook::AttachmentInstanceMethods
    end

    def self.dispatch_document_review(document)
      return unless ENV['AUTOMYRA_BRIDGE_DOCUMENT_REVIEW'].to_s == '1'
      return if Thread.current[:automyra_bridge_skip_webhook]
      return unless document.is_a?(::Document) && document.project
      return if authored_by_automyra?(document)
      return if authored_by_automyra?(resolve_item(document))

      action = detect_action(document)

      if action == :create
        AutomyraBridge::DocumentHubReviewDispatcher.dispatch_create(document)
      else
        AutomyraBridge::DocumentHubReviewDispatcher.dispatch_update(document)
      end
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::DocumentHubCreationHook] document dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_attachment_review(attachment)
      return unless ENV['AUTOMYRA_BRIDGE_DOCUMENT_REVIEW'].to_s == '1'
      return if Thread.current[:automyra_bridge_skip_webhook]
      return unless attachment.is_a?(::Attachment)
      return if authored_by_automyra?(attachment)
      return unless attachment.container_type == 'Document' && attachment.container
      return if authored_by_automyra?(resolve_item(attachment.container))

      AutomyraBridge::DocumentHubReviewDispatcher.dispatch_attachment_create(attachment)
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::DocumentHubCreationHook] attachment dispatch failed: #{e.class}: #{e.message}")
    end

    # Detects whether the committed change was a create or an update. After
    # commit, `saved_changes` is usually reset, so this helper falls back to
    # id presence when state is unavailable. It is only consulted for
    # Document callbacks (Attachment create commits are always create events).
    def self.detect_action(document)
      return :create if document.respond_to?(:id_previously_changed?) && document.id_previously_changed?

      :update
    rescue StandardError
      :update
    end
    private_class_method :detect_action

    def self.resolve_item(document)
      return nil unless defined?(::DocumentHub::Item)

      ::DocumentHub::Item.find_by(document_id: document.id, attachment_id: nil)
    rescue StandardError
      nil
    end
    private_class_method :resolve_item

    def self.authored_by_automyra?(record)
      login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].to_s.presence
      return false if login.nil?

      bot = ::User.find_by(login: login)
      return false if bot.nil?

      author_id = record.respond_to?(:author_id) ? record.author_id : nil
      author_id ||= record['author_id'] if record.respond_to?(:[])
      author_id ||= record.respond_to?(:user_id) ? record.user_id : nil
      author_id ||= User.current.id if record.is_a?(::Document) && User.current && User.current.logged?
      author_id == bot.id
    end
    private_class_method :authored_by_automyra?

    module DocumentInstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_document_hub_review, on: :create
        after_commit :automyra_bridge_document_hub_update_review, on: :update
      end

      private

      def automyra_bridge_document_hub_review
        AutomyraBridge::DocumentHubCreationHook.dispatch_document_review(self)
      end

      def automyra_bridge_document_hub_update_review
        AutomyraBridge::DocumentHubCreationHook.dispatch_document_review(self)
      end
    end

    module AttachmentInstanceMethods
      extend ActiveSupport::Concern

      included do
        after_commit :automyra_bridge_document_hub_attachment_review, on: :create
      end

      private

      def automyra_bridge_document_hub_attachment_review
        return if destroyed?
        return unless %w[Document Project Version].include?(container_type)

        AutomyraBridge::DocumentHubCreationHook.dispatch_attachment_review(self)
      end
    end
  end
end
