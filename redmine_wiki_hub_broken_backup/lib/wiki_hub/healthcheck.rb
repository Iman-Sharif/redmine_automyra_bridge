module WikiHub
  class Healthcheck
    REQUIRED_TABLES = %w[
      wiki_hub_page_snapshots
      wiki_hub_page_links
      wiki_hub_page_profiles
      wiki_hub_index_runs
    ].freeze
    RECENT_INDEX_WINDOW = 24.hours

    class << self
      def call
        latest_index_run = latest_index_run_record
        details = {
          missing_tables: missing_tables,
          pg_trgm_enabled: pg_trgm_enabled?,
          recent_successful_index_run_at: recent_successful_index_run_at,
          latest_index_run_completed_at: latest_index_run&.completed_at,
          latest_index_run_status: latest_index_run&.status,
          latest_index_run_error: latest_index_run&.error_message
        }

        errors = {}
        errors[:missing_tables] = details[:missing_tables] if details[:missing_tables].any?
        errors[:pg_trgm] = 'pg_trgm extension is not enabled' unless details[:pg_trgm_enabled]
        if latest_index_run_failed?(latest_index_run)
          errors[:index_run] = latest_index_run_failure_message(latest_index_run)
        elsif details[:recent_successful_index_run_at].blank?
          errors[:index_run] = 'no successful index run in the last 24 hours'
        end

        {
          status: errors.empty? ? 'ok' : 'error',
          details: details.merge(errors: errors)
        }
      rescue StandardError => e
        {
          status: 'error',
          details: {
            errors: {
              exception: "#{e.class}: #{e.message}"
            }
          }
        }
      end

      private

      def missing_tables
        REQUIRED_TABLES.reject { |table_name| ActiveRecord::Base.connection.data_source_exists?(table_name) }
      end

      def pg_trgm_enabled?
        ActiveRecord::Base.connection.extension_enabled?('pg_trgm')
      end

      def recent_successful_index_run_at
        WikiHub::IndexRun.completed_successfully
                         .where('completed_at >= ?', Time.current - RECENT_INDEX_WINDOW)
                         .maximum(:completed_at)
      end

      def latest_index_run_record
        WikiHub::IndexRun.recent_first.first
      end

      def latest_index_run_failed?(latest_index_run)
        latest_index_run&.status == 'failed'
      end

      def latest_index_run_failure_message(latest_index_run)
        base_message = 'latest index run failed'
        return base_message if latest_index_run.error_message.blank?

        "#{base_message}: #{latest_index_run.error_message}"
      end
    end
  end
end
