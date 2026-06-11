require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeWebhooksControllerTest < ActionController::TestCase
  tests AutomyraBridgeWebhooksController

  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    AutomyraBridgeJob.delete_all
    @project = Project.find_by!(identifier: 'ecookbook')
    enable_automyra_bridge!(@project)
    @user = User.find_by!(login: 'admin')
    Setting.plugin_redmine_automyra_bridge = Setting.plugin_redmine_automyra_bridge.merge(
      'webhook_secret' => 'test-secret',
      'webhook_user_login' => @user.login
    )
  end

  test 'rejects missing bearer token' do
    post :incoming, params: valid_payload

    assert_response :unauthorized
  end

  test 'rejects invalid bearer token' do
    @request.env['HTTP_AUTHORIZATION'] = 'Bearer wrong-secret'

    post :incoming, params: valid_payload

    assert_response :unauthorized
  end

  test 'rejects missing subject or body' do
    @request.env['HTTP_AUTHORIZATION'] = 'Bearer test-secret'

    post :incoming, params: { project_identifier: @project.identifier, subject: '' }

    assert_response :unprocessable_entity
  end

  test 'queues outlook email webhook job' do
    @request.env['HTTP_AUTHORIZATION'] = 'Bearer test-secret'

    post :incoming, params: valid_payload.merge(format: 'json')

    assert_response :accepted
    body = JSON.parse(response.body)
    job = AutomyraBridgeJob.find(body['job_id'])
    assert_equal 'WebhookIncoming', job.source_type
    assert_equal 'queued', job.status
    assert_equal @project, job.project
    assert_equal @user, job.user
    assert_equal 'email_ingestion', job.payload['action']
    assert_equal 'outlook', job.payload['source']
    assert_equal 'issue', job.payload['destination']
    assert_equal 'Route this customer email', job.payload['subject']
  end

  private

  def valid_payload
    {
      project_identifier: @project.identifier,
      source: 'outlook',
      destination: 'issue',
      message_id: 'outlook-message-1',
      subject: 'Route this customer email',
      from: 'sender@example.com',
      sent_at: '2026-05-04T12:00:00Z',
      body: 'Please create the right Redmica artifact for this email.',
      attachments: []
    }
  end

  def enable_automyra_bridge!(project)
    EnabledModule.create!(project: project, name: 'automyra_bridge') unless project.module_enabled?(:automyra_bridge)
  end
end
