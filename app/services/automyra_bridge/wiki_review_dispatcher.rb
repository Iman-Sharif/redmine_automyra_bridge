# frozen_string_literal: true

module AutomyraBridge
  # Wiki review webhook dispatcher.
  #
  # Dispatches wiki page create/update events to Hermes so the `wiki-review`
  # skill can run standards checks, auto-fix high-confidence issues, and
  # create linked advisory issues for low-confidence findings.
  #
  # Mirrors AutomyraBridge::CreationReviewDispatcher (which is bound to Issue),
  # but operates on WikiContent. The Automyra-author loop guard is implemented
  # in WikiCreationHook, not duplicated here.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - wiki_created_webhook_dispatched: webhook sent to Hermes for create
  #   - wiki_updated_webhook_dispatched: webhook sent to Hermes for update
  #
  class WikiReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.wiki_created'
    UPDATE_EVENT_TYPE = 'redmica.wiki_updated'
    TEXT_PREVIEW_LIMIT = 2_000

    def self.dispatch_create(wiki_content)
      return unless wiki_content.is_a?(WikiContent)

      payload = build_payload(wiki_content, CREATE_EVENT_TYPE)
      delivery_id = build_delivery_id('creation', wiki_content)
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(wiki_content, 'wiki_created')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::WikiReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_update(wiki_content)
      return unless wiki_content.is_a?(WikiContent)

      payload = build_payload(wiki_content, UPDATE_EVENT_TYPE)
      delivery_id = build_delivery_id('update', wiki_content)
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(wiki_content, 'wiki_updated')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::WikiReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(wiki_content, event_type)
      page = wiki_content.page
      project = page&.wiki&.project
      {
        event_type: event_type,
        wiki_page_id: page&.id,
        wiki_page_title: page&.title,
        wiki_content_version: wiki_content.version,
        text_preview: wiki_content.text.to_s.truncate(TEXT_PREVIEW_LIMIT),
        project_id: project&.identifier,
        project_name: project&.name,
        author_id: wiki_content.author_id,
        author_name: wiki_content.author&.login,
        created_at: wiki_content.updated_on&.iso8601,
        url: build_url(page, project),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_delivery_id(action_label, wiki_content)
      page_id = wiki_content.page_id
      version = wiki_content.version
      "wiki-#{action_label}-#{page_id}-v#{version}"
    end
    private_class_method :build_delivery_id

    def self.build_url(page, project)
      return nil unless page && project

      "#{Setting.protocol}://#{Setting.host_name}/projects/#{project.identifier}/wiki/#{page.title}"
    end
    private_class_method :build_url

    def self.log_dispatch(wiki_content, action_label)
      page_id = wiki_content.page_id
      version = wiki_content.version
      title = wiki_content.page&.title
      AutomyraBridge::ActivityLogger.log!(
        action_type: "#{action_label}_webhook_dispatched",
        source: 'wiki_creation_hook',
        summary: "Wiki review webhook dispatched for page ##{page_id} v#{version} (#{title})",
        target_type: 'WikiPage',
        target_id: page_id,
        project_id: wiki_content.page&.wiki&.project_id,
        user_id: wiki_content.author_id
      )
    end
    private_class_method :log_dispatch
  end
end
