# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeActivityLogAuthTest < ActionDispatch::IntegrationTest
  fixtures :users, :projects

  setup do
    AutomyraBridgeActivityLog.delete_all
    @original_settings = Setting.plugin_redmine_automyra_bridge
  end

  teardown do
    Setting.plugin_redmine_automyra_bridge = @original_settings
  end

  test 'POST /automyra/activity_log returns 401 when activity_log_secret is blank' do
    with_activity_log_secret('') do
      post '/automyra/activity_log', params: valid_log_params,
                                     headers: { 'Authorization' => 'Bearer anything' }

      assert_response :unauthorized
    end
  end

  test 'POST /automyra/activity_log returns 401 when activity_log_secret is nil' do
    with_activity_log_secret(nil) do
      post '/automyra/activity_log', params: valid_log_params,
                                     headers: { 'Authorization' => 'Bearer anything' }

      assert_response :unauthorized
    end
  end

  test 'POST /automyra/activity_log returns 401 with a wrong token' do
    with_activity_log_secret('real-secret') do
      post '/automyra/activity_log', params: valid_log_params,
                                     headers: { 'Authorization' => 'Bearer wrong-secret' }

      assert_response :unauthorized
    end
  end

  test 'POST /automyra/activity_log creates a record with the correct token' do
    with_activity_log_secret('real-secret') do
      assert_difference 'AutomyraBridgeActivityLog.count', 1 do
        post '/automyra/activity_log', params: valid_log_params,
                                       headers: { 'Authorization' => 'Bearer real-secret' }

        assert_response :created
      end
    end
  end

  private

  def with_activity_log_secret(secret)
    Setting.plugin_redmine_automyra_bridge = @original_settings.merge('activity_log_secret' => secret)
    yield
  end

  def valid_log_params
    {
      action_type: 'note_created',
      source: 'trilium',
      summary: 'Auth gate test entry',
      idempotency_key: "auth-gate-#{SecureRandom.hex(8)}",
      occurred_at: Time.current.iso8601
    }
  end
end
