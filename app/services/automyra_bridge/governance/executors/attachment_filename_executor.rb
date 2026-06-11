module AutomyraBridge
  module Governance
    module Executors
      class AttachmentFilenameExecutor < BaseExecutor
        def call
          attachment = Attachment.find_by(id: action.object_id)
          return fail_action!('Attachment is no longer available.') unless attachment

          project = attachment.container&.project if attachment.container.respond_to?(:project)
          return fail_action!('Attachment project is no longer available.') unless project

          ensure_permission!(permission_for(attachment), project)
          ensure_current_value!(attachment.filename)
          return fail_action!('Attachment filename already exists on this record.') if duplicate_filename?(attachment)

          rollback = { filename: attachment.filename, attachment_id: attachment.id }
          attachment.update!(filename: finding.recommended_value)
          apply_success!(rollback)
        rescue StandardError => e
          fail_action!(e.message)
        end

        private

        def permission_for(attachment)
          case attachment.container_type.to_s
          when 'WikiPage', 'WikiContent'
            :edit_wiki_pages
          when 'Issue'
            :edit_issues
          when 'Project'
            :manage_files
          else
            raise 'Governance action is not permitted.'
          end
        end

        def duplicate_filename?(attachment)
          Attachment.where(container_type: attachment.container_type, container_id: attachment.container_id)
                    .where('LOWER(filename) = ?', finding.recommended_value.to_s.downcase)
                    .where.not(id: attachment.id)
                    .exists?
        end
      end
    end
  end
end
