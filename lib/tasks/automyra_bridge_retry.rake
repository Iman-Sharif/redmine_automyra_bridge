# frozen_string_literal: true

namespace :automyra_bridge do
  desc 'Process pending webhook retry checks'
  task process_retries: :environment do
    checked = AutomyraBridge::RetryChecker.call
    Rails.logger.info("[automyra_bridge:process_retries] checked #{checked} deliveries")
  end
end
