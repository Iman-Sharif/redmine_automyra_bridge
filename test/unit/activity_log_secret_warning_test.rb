# frozen_string_literal: true

require_relative '../test_helper'
require 'automyra_bridge/secret_warnings'

class AutomyraBridgeActivityLogSecretWarningTest < ActiveSupport::TestCase
  setup do
    @original_settings = Setting.plugin_redmine_automyra_bridge
  end

  teardown do
    Setting.plugin_redmine_automyra_bridge = @original_settings
  end

  test 'warns when activity_log_secret is blank' do
    with_activity_log_secret('') do
      Rails.logger.expects(:warn).with(regexp_matches(/activity_log_secret/i))
      AutomyraBridge::SecretWarnings.warn_if_activity_log_secret_insecure
    end
  end

  test 'warns when activity_log_secret is the placeholder default' do
    with_activity_log_secret('change-me-in-production') do
      Rails.logger.expects(:warn).with(regexp_matches(/activity_log_secret/i))
      AutomyraBridge::SecretWarnings.warn_if_activity_log_secret_insecure
    end
  end

  test 'does not warn when activity_log_secret is a real secret' do
    with_activity_log_secret('a-real-production-secret') do
      Rails.logger.expects(:warn).never
      AutomyraBridge::SecretWarnings.warn_if_activity_log_secret_insecure
    end
  end

  test 'does not raise when settings are unavailable' do
    Setting.stubs(:plugin_redmine_automyra_bridge).raises(StandardError)

    assert_nothing_raised do
      AutomyraBridge::SecretWarnings.warn_if_activity_log_secret_insecure
    end
  end

  private

  def with_activity_log_secret(secret)
    Setting.plugin_redmine_automyra_bridge = @original_settings.merge('activity_log_secret' => secret)
    yield
  end
end
