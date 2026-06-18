# frozen_string_literal: true

module AutomyraBridge
  # Document Hub review webhook dispatcher.
  #
  # Dispatches native Redmine `Document` create/update and `Attachment`
  # (container is Document) create events to Hermes so the `document-review`
  # skill can run standards checks. The payload is resolved defensively against
  # `DocumentHub::Item` when the snapshot exists, but the dispatcher falls back
  # to native `Document` / `Attachment` fields so it works even when
  # Document Hub has not indexed the record.
  #
  # The Automyra-author loop guard and env flag gate live in
  # `DocumentHubCreationHook`, not here.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - document_created_webhook_dispatched
  #   - document_updated_webhook_dispatched
  class DocumentHubReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.document_hub.document_created'
    UPDATE_EVENT_TYPE = 'redmica.document_hub.document_updated'
    TEXT_PREVIEW_LIMIT = 2_000

    class << self
      def dispatch_create(document)
        return unless document.is_a?(::Document)

        payload = build_payload_from_document(document, CREATE_EVENT_TYPE)
        delivery_id = "document-review-#{document.id}-#{SecureRandom.hex(8)}"
        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
        log_dispatch(document, 'document_created')
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::DocumentHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
      end

      def dispatch_update(document)
        return unless document.is_a?(::Document)

        payload = build_payload_from_document(document, UPDATE_EVENT_TYPE)
        delivery_id = "document-review-update-#{document.id}-#{SecureRandom.hex(8)}"
        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
        log_dispatch(document, 'document_updated')
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::DocumentHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
      end

      # An attachment attached to a Document is treated as adding a new
      # snapshot/version of that document, so it is emitted under the
      # `document_created` event type.
      def dispatch_attachment_create(attachment)
        return unless attachment.is_a?(::Attachment)
        return unless attachment.container_type == 'Document' && attachment.container

        document = attachment.container
        item = find_item_for_attachment(attachment)
        payload = build_payload(document, item, CREATE_EVENT_TYPE, attachment: attachment)
        delivery_id = "document-review-#{document.id}-#{SecureRandom.hex(8)}"
        ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
        log_dispatch(document, 'document_created', attachment: attachment)
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::DocumentHubReviewDispatcher] attachment dispatch failed: #{e.class}: #{e.message}")
      end

      # Public so tests can inspect the payload shape without enqueuing jobs.
      def build_payload(document, item, event_type, attachment: nil)
        project = resolve_project(document, item, attachment)
        author = resolve_author(document, item, attachment)
        category = resolve_category(document, item)

        {
          event_type: event_type,
          item_id: item&.id,
          document_id: document&.id,
          attachment_id: attachment&.id || item&.attachment_id,
          title: safe_trunc(item&.title || document&.title || attachment&.filename),
          filename: safe_trunc(item&.filename || attachment&.filename),
          description: safe_trunc(item&.description || document&.description || attachment&.description),
          content_type: item&.content_type || attachment&.content_type,
          filesize: item&.filesize || attachment&.filesize,
          digest: item&.digest || attachment&.digest,
          project_id: project&.id,
          project_identifier: project&.identifier,
          project_name: project&.name,
          author_id: author&.id,
          author_login: author&.login,
          category_id: category&.id,
          category_name: category&.name,
          container_type: item&.container_type || attachment&.container_type,
          version_id: item&.version_id,
          tags: resolve_tags(item, document, attachment),
          url: build_url(document, attachment),
          timestamp: Time.current.iso8601
        }
      end

      private

      def build_payload_from_document(document, event_type)
        item = find_item_for_document(document)
        build_payload(document, item, event_type)
      end

      def find_item_for_document(document)
        return nil unless defined?(::DocumentHub::Item)

        ::DocumentHub::Item.find_by(document_id: document.id, attachment_id: nil)
      rescue StandardError
        nil
      end

      def find_item_for_attachment(attachment)
        return nil unless defined?(::DocumentHub::Item)

        ::DocumentHub::Item.find_by(attachment_id: attachment.id, document_id: nil)
      rescue StandardError
        nil
      end

      def resolve_project(document, item, attachment)
        project = item&.project
        project ||= document&.project
        project ||= attachment&.project
        project ||= ::Project.find_by(id: item&.project_id) if item&.project_id
        project
      rescue StandardError
        nil
      end

      def resolve_author(document, item, attachment)
        author_id = item&.author_id || attachment&.author_id || document&.author_id
        author_id ||= User.current.id if document && User.current && User.current.logged?
        return nil if author_id.blank?

        ::User.find_by(id: author_id)
      rescue StandardError
        nil
      end

      def resolve_category(document, item)
        category_id = item&.category_id || document&.category_id
        return nil if category_id.blank?

        ::DocumentCategory.find_by(id: category_id)
      rescue StandardError
        nil
      end

      def resolve_tags(item, document, attachment)
        return item.tags.map(&:name) if item.respond_to?(:tags) && item.tags

        tag_source_id = document&.id || attachment&.id
        tag_source_type = tag_source_type_for(tag_source_id, document, attachment)
        return [] unless tag_source_id && tag_source_type && defined?(::DocumentHub::Tagging)

        tag_ids = ::DocumentHub::Tagging.where(
          taggable_type: tag_source_type,
          document_id: tag_source_type == 'Document' ? tag_source_id : nil,
          attachment_id: tag_source_type == 'Attachment' ? tag_source_id : nil
        ).pluck(:tag_id)
        ::DocumentHub::Tag.where(id: tag_ids).order(:name).map(&:name)
      rescue StandardError
        []
      end

      def tag_source_type_for(tag_source_id, document, attachment)
        return nil unless tag_source_id

        return 'Document' if document
        return 'Attachment' if attachment

        nil
      end

      def build_url(document, attachment)
        return attachment_url(attachment) if attachment

        document_url(document)
      end

      def document_url(document)
        return nil unless document

        path = Rails.application.routes.url_helpers.url_for(
          controller: 'documents', action: 'show', id: document.id, only_path: true
        )
        "#{::Setting.protocol}://#{::Setting.host_name}#{path}"
      rescue StandardError
        "#{::Setting.protocol}://#{::Setting.host_name}/documents/#{document.id}"
      end

      def attachment_url(attachment)
        return nil unless attachment

        path = Rails.application.routes.url_helpers.url_for(
          controller: 'attachments', action: 'download', id: attachment.id,
          filename: attachment.filename, only_path: true
        )
        "#{::Setting.protocol}://#{::Setting.host_name}#{path}"
      rescue StandardError
        "#{::Setting.protocol}://#{::Setting.host_name}/attachments/download/#{attachment.id}/#{attachment.filename}"
      end

      def safe_trunc(value)
        value.to_s.truncate(TEXT_PREVIEW_LIMIT)
      end

      def log_dispatch(document, action_label, attachment: nil)
        target_type = attachment ? 'Attachment' : 'Document'
        target_id = attachment&.id || document&.id
        user_id = attachment&.author_id || resolve_author(document, nil, attachment)&.id || User.current&.id
        summary = if attachment
                    "Document review webhook dispatched for attachment ##{attachment.id} on document ##{document.id}"
                  else
                    "Document review webhook dispatched for document ##{document.id} (#{document.title})"
                  end

        AutomyraBridge::ActivityLogger.log!(
          action_type: "#{action_label}_webhook_dispatched",
          source: 'document_hub_creation_hook',
          summary: summary,
          target_type: target_type,
          target_id: target_id,
          project_id: document&.project_id,
          user_id: user_id
        )
      rescue StandardError => e
        Rails.logger.warn("[AutomyraBridge::DocumentHubReviewDispatcher] activity log failed: #{e.class}: #{e.message}")
      end
    end
  end
end
