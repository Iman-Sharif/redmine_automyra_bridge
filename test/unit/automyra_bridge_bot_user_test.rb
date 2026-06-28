require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeBotUserTest < ActiveSupport::TestCase
  fixtures :users, :projects, :roles, :members, :member_roles, :enabled_modules

  setup do
    # Ensure a clean state — remove any 'Automyra' user from fixtures so tests
    # are deterministic. We create it explicitly when needed.
    User.where(login: 'Automyra').destroy_all
  end

  teardown do
    User.where(login: 'webhook-bot-test').destroy_all
    User.where(login: 'Automyra').destroy_all
  end

  test 'resolves user from settings webhook_user_login' do
    custom_bot = User.create!(
      login: 'webhook-bot-test',
      firstname: 'Webhook',
      lastname: 'Bot',
      mail: 'webhook-bot@example.test',
      status: Principal::STATUS_ACTIVE
    )

    result = AutomyraBridge::BotUser.call('webhook_user_login' => 'webhook-bot-test')
    assert_equal custom_bot, result
  end

  test 'falls back to default Automyra login when settings login not found' do
    automyra = User.create!(
      login: 'Automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'automyra@example.test',
      status: Principal::STATUS_ACTIVE
    )

    result = AutomyraBridge::BotUser.call('webhook_user_login' => 'nonexistent_login')
    assert_equal automyra, result
  end

  test 'falls back to default Automyra login when settings login is blank' do
    automyra = User.create!(
      login: 'Automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'automyra@example.test',
      status: Principal::STATUS_ACTIVE
    )

    result = AutomyraBridge::BotUser.call('webhook_user_login' => '')
    assert_equal automyra, result
  end

  test 'falls back to first active admin when no Automyra user exists' do
    admin = User.active.where(admin: true).order(:id).first

    result = AutomyraBridge::BotUser.call('webhook_user_login' => 'nonexistent')
    assert_equal admin, result
  end

  test 'falls back to first active admin when settings are nil' do
    admin = User.active.where(admin: true).order(:id).first

    result = AutomyraBridge::BotUser.call(nil)
    assert_equal admin, result
  end

  test 'falls back to first active admin when settings are empty hash' do
    admin = User.active.where(admin: true).order(:id).first

    result = AutomyraBridge::BotUser.call({})
    assert_equal admin, result
  end

  test 'returns nil when no bot user can be found at all' do
    # Temporarily remove all active admins and Automyra users
    User.active.where(admin: true).update_all(status: Principal::STATUS_LOCKED)
    User.where(login: 'Automyra').destroy_all

    result = AutomyraBridge::BotUser.call({})
    assert_nil result
  ensure
    # Restore admin users
    User.where(admin: true).update_all(status: Principal::STATUS_ACTIVE)
  end

  test 'prefers settings login over default Automyra login' do
    automyra = User.create!(
      login: 'Automyra',
      firstname: 'Automyra',
      lastname: 'Bot',
      mail: 'automyra@example.test',
      status: Principal::STATUS_ACTIVE
    )
    custom = User.create!(
      login: 'webhook-bot-test',
      firstname: 'Custom',
      lastname: 'Bot',
      mail: 'custom@example.test',
      status: Principal::STATUS_ACTIVE
    )

    result = AutomyraBridge::BotUser.call('webhook_user_login' => 'webhook-bot-test')
    assert_equal custom, result
    assert_not_equal automyra, result
  end

  test 'does not resolve inactive user from settings login' do
    User.create!(
      login: 'webhook-bot-test',
      firstname: 'Inactive',
      lastname: 'Bot',
      mail: 'inactive@example.test',
      status: Principal::STATUS_LOCKED
    )

    # Should fall through to admin fallback (no Automyra user exists in setup)
    admin = User.active.where(admin: true).order(:id).first
    result = AutomyraBridge::BotUser.call('webhook_user_login' => 'webhook-bot-test')
    assert_equal admin, result
  end

  test 'uses default settings when no argument provided' do
    # Setting.plugin_redmine_automyra_bridge returns a hash by default
    # With no webhook_user_login configured and no Automyra user, falls to admin
    admin = User.active.where(admin: true).order(:id).first

    result = AutomyraBridge::BotUser.call
    assert_equal admin, result
  end
end