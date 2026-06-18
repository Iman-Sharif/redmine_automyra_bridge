# frozen_string_literal: true

module AutomyraBridge
  # Repository Hub review webhook dispatcher.
  #
  # Dispatches Redmine Repository create/update events to Hermes so the
  # `repo-review` skill can run standards checks, auto-fix high-confidence
  # issues, and create linked advisory issues for low-confidence findings.
  #
  # The Automyra-author loop guard and env flag gate are implemented in
  # RepoHubCreationHook, not duplicated here.
  #
  # Event types logged to AutomyraBridgeActivityLog:
  #   - repository_created_webhook_dispatched: webhook sent to Hermes for create
  #   - repository_updated_webhook_dispatched: webhook sent to Hermes for update
  class RepoHubReviewDispatcher
    CREATE_EVENT_TYPE = 'redmica.repo_hub.repository_created'
    UPDATE_EVENT_TYPE = 'redmica.repo_hub.repository_updated'
    TEXT_PREVIEW_LIMIT = 2_000

    def self.dispatch_create(repository)
      return unless repository.is_a?(::Repository)

      payload = build_payload(repository, CREATE_EVENT_TYPE)
      delivery_id = "repo-review-#{repository.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(CREATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(repository, 'repository_created')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::RepoHubReviewDispatcher] create dispatch failed: #{e.class}: #{e.message}")
    end

    def self.dispatch_update(repository)
      return unless repository.is_a?(::Repository)

      payload = build_payload(repository, UPDATE_EVENT_TYPE)
      delivery_id = "repo-review-update-#{repository.id}-#{SecureRandom.hex(8)}"
      ::AutomyraBridge::HermesWebhookDeliverJob.perform_later(UPDATE_EVENT_TYPE, payload, delivery_id)
      log_dispatch(repository, 'repository_updated')
    rescue StandardError => e
      Rails.logger.error("[AutomyraBridge::RepoHubReviewDispatcher] update dispatch failed: #{e.class}: #{e.message}")
    end

    def self.build_payload(repository, event_type)
      project = repository.project
      scm_type = repository.class.name.to_s.split('::').last

      {
        event_type: event_type,
        repository_id: repository.id,
        scm_type: scm_type,
        identifier: repository.identifier,
        url: sanitize_url(repository.url),
        root_url: sanitize_url(repository.root_url),
        is_default: repository.is_default,
        project_id: project&.id,
        project_identifier: project&.identifier,
        project_name: project&.name,
        created_on: repository.respond_to?(:created_on) ? repository.created_on&.iso8601 : nil,
        updated_at: repository.respond_to?(:updated_on) ? repository.updated_on&.iso8601 : nil,
        snapshot_metadata: build_snapshot_metadata(repository),
        timestamp: Time.current.iso8601
      }
    end
    private_class_method :build_payload

    def self.build_snapshot_metadata(repository)
      snapshot = fetch_snapshot(repository)
      return {} unless snapshot

      {
        snapshot_id: snapshot.id,
        snapshot_identifier: snapshot.identifier.to_s.truncate(TEXT_PREVIEW_LIMIT),
        snapshot_url: sanitize_url(snapshot.url),
        scm_type: snapshot.scm_type,
        searchable_text_preview: snapshot.searchable_text.to_s.truncate(TEXT_PREVIEW_LIMIT),
        repository_created_on: snapshot.repository_created_on&.iso8601
      }
    end
    private_class_method :build_snapshot_metadata

    def self.fetch_snapshot(repository)
      return nil unless defined?(::RepoHub::RepositorySnapshot)

      ::RepoHub::RepositorySnapshot.find_by(repository_id: repository.id)
    end
    private_class_method :fetch_snapshot

    def self.sanitize_url(url)
      return nil if url.blank?

      parsed = URI.parse(url)
      parsed.user = nil
      parsed.password = nil
      parsed.to_s
    rescue URI::Error
      url.to_s.truncate(TEXT_PREVIEW_LIMIT)
    end
    private_class_method :sanitize_url

    def self.log_dispatch(repository, action_label)
      AutomyraBridge::ActivityLogger.log!(
        action_type: "#{action_label}_webhook_dispatched",
        source: 'repo_hub_creation_hook',
        summary: "Repository review webhook dispatched for repository ##{repository.id} (#{repository.identifier})",
        target_type: 'Repository',
        target_id: repository.id,
        project_id: repository.project_id,
        user_id: nil
      )
    end
    private_class_method :log_dispatch
  end
end
