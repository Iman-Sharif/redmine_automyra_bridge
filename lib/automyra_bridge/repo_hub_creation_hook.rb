# frozen_string_literal: true

module AutomyraBridge
  # Repository Hub review webhook hook.
  #
  # Wires review webhook callbacks onto Redmine's native `Repository` model.
  #
  # When the `redmine_repo_hub` plugin is loaded it prepends
  # `RepoHub::RepositoryLifecycleBridge` to `Repository`. That bridge overrides
  # `save`/`save!` and reindexes after every persist, so a plain
  # `after_commit` on `Repository` would be bypassed for the normal repository
  # form flow. In that case this hook prepends a small wrapper to the lifecycle
  # bridge that calls the dispatcher after a successful `save`/`save!`.
  #
  # When the lifecycle bridge is absent, this hook patches `Repository` directly
  # with `after_commit` callbacks in a Rails `to_prepare` hook.
  #
  # Mirrors the wiki / FAQ / Error Hub hook conventions:
  #   - feature-flagged via `ENV['AUTOMYRA_BRIDGE_REPO_REVIEW']`
  #   - thread-local `:automyra_bridge_skip_webhook` opt-out
  #   - skips records authored by the configured bot user
  #
  # Emits:
  #   - `redmica.repo_hub.repository_created` on create
  #   - `redmica.repo_hub.repository_updated` on update of identifier, url,
  #     root_url, project_id or is_default
  module RepoHubCreationHook
    WATCHED_UPDATE_ATTRIBUTES = %w[
      identifier
      url
      root_url
      project_id
      is_default
    ].freeze

    def self.install!
      require_dependency 'repository' unless defined?(::Repository)
      return unless defined?(::Repository)

      if defined?(::RepoHub::RepositoryLifecycleBridge)
        install_lifecycle_wrapper!
      else
        install_directly!
      end
    end

    def self.install_lifecycle_wrapper!
      return if ::RepoHub::RepositoryLifecycleBridge.included_modules.include?(LifecycleWrapper)

      ::RepoHub::RepositoryLifecycleBridge.prepend(LifecycleWrapper)
    end

    def self.install_directly!
      return if ::Repository.included_modules.include?(InstanceMethods)

      ::Repository.include(InstanceMethods)
    end

    def self.to_prepare
      install!
    end

    # Shared guard + dispatch helpers used by both the direct after_commit path
    # and the lifecycle-bridge wrapper path.
    module DispatchGuards
      private

      def automyra_bridge_repo_hub_dispatch_create
        AutomyraBridge::RepoHubReviewDispatcher.dispatch_create(self)
      end

      def automyra_bridge_repo_hub_dispatch_update
        AutomyraBridge::RepoHubReviewDispatcher.dispatch_update(self)
      end

      def repo_hub_review_enabled?
        ENV['AUTOMYRA_BRIDGE_REPO_REVIEW'].to_s == '1'
      end

      def repo_hub_review_relevant_change?
        changed = saved_changes
        WATCHED_UPDATE_ATTRIBUTES.any? { |attr| changed.key?(attr) }
      end

      def repo_hub_review_will_change?
        WATCHED_UPDATE_ATTRIBUTES.any? { |attr| attribute_changed?(attr) }
      end

      def automyra_bridge_repo_hub_authored_by_automyra?
        login = Setting.plugin_redmine_automyra_bridge['webhook_user_login'].to_s.presence
        return false if login.nil?

        bot = User.find_by(login: login)
        return false if bot.nil?

        author_user_id = defined?(User.current) ? User.current.id : nil
        return false if author_user_id.nil?

        author_user_id == bot.id
      end

      def repo_hub_review_should_dispatch?
        return false unless repo_hub_review_enabled?
        return false if Thread.current[:automyra_bridge_skip_webhook]
        return false unless project
        return false if automyra_bridge_repo_hub_authored_by_automyra?

        true
      end
    end

    # Path used when RepoHub::RepositoryLifecycleBridge is present.
    module LifecycleWrapper
      include DispatchGuards

      def save(...)
        was_new_record = new_record?
        relevant_update = !was_new_record && repo_hub_review_will_change?
        result = super(...)

        if result && repo_hub_review_should_dispatch?
          if was_new_record && persisted?
            automyra_bridge_repo_hub_dispatch_create
          elsif persisted? && relevant_update
            automyra_bridge_repo_hub_dispatch_update
          end
        end

        result
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::RepoHubCreationHook] lifecycle save dispatch failed: #{e.message}")
        result
      end

      def save!(...)
        was_new_record = new_record?
        relevant_update = !was_new_record && repo_hub_review_will_change?
        result = super(...)

        if result && repo_hub_review_should_dispatch?
          if was_new_record && persisted?
            automyra_bridge_repo_hub_dispatch_create
          elsif persisted? && relevant_update
            automyra_bridge_repo_hub_dispatch_update
          end
        end

        result
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::RepoHubCreationHook] lifecycle save! dispatch failed: #{e.message}")
        result
      end
    end

    # Path used when RepoHub::RepositoryLifecycleBridge is absent.
    module InstanceMethods
      extend ActiveSupport::Concern

      include DispatchGuards

      included do
        after_commit :automyra_bridge_repo_hub_review, on: :create
        after_commit :automyra_bridge_repo_hub_update_review, on: :update
      end

      private

      def automyra_bridge_repo_hub_review
        return unless repo_hub_review_should_dispatch?

        automyra_bridge_repo_hub_dispatch_create
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::RepoHubCreationHook] create dispatch failed: #{e.message}")
      end

      def automyra_bridge_repo_hub_update_review
        return unless repo_hub_review_should_dispatch?
        return unless repo_hub_review_relevant_change?

        automyra_bridge_repo_hub_dispatch_update
      rescue StandardError => e
        Rails.logger.error("[AutomyraBridge::RepoHubCreationHook] update dispatch failed: #{e.message}")
      end
    end
  end
end
