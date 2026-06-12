module AutomyraBridge
  module Governance
    module Collectors
      class AttachmentCollector < BaseCollector
        DEFAULT_CONTAINER_TYPES = %w[WikiPage Issue Project].freeze

        def self.call(**kwargs)
          new(**kwargs).call
        end

        def call
          return [] unless (project || policy&.global?) && defined?(Attachment)

          Attachment.order(:id).limit(limit * 10).each_with_object([]) do |attachment, candidates|
            next unless included_container_type?(attachment)
            next unless governable_project_id?(project_id_for(attachment))
            next if excluded?(attachment.filename)

            candidates << candidate(attachment)
            break candidates if candidates.size >= limit
          end
        end

        private

        def included_container_type?(attachment)
          container_types.include?(attachment.container_type.to_s)
        end

        def container_types
          configured = Array(config['attachment_container_types']).map(&:to_s).reject(&:blank?)
          configured.presence || DEFAULT_CONTAINER_TYPES
        end

        def governable_project_id?(project_id)
          return false if project_id.blank?
          return project_id.to_i == project.id if project

          active_project_ids.include?(project_id.to_i)
        end

        def project_id_for(attachment)
          container = attachment.container
          return container.id if container.is_a?(Project)
          return container.project_id if container.respond_to?(:project_id) && container.project_id.present?
          return container.project.id if container.respond_to?(:project) && container.project

          nil
        rescue StandardError => e
          Rails.logger.warn("Automyra attachment collector project_id resolution failed: #{e.class}: #{e.message}") if defined?(Rails)
          nil
        end

        def candidate(attachment)
          {
            object_type: 'Attachment',
            object_id: attachment.id,
            filename: attachment.filename,
            title: attachment.filename,
            project_id: project_id_for(attachment),
            container_type: attachment.container_type,
            container_id: attachment.container_id,
            current_value: attachment.filename
          }
        end
      end
    end
  end
end
