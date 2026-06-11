require File.expand_path('../../../test_helper', __dir__)
require 'rake'
require 'stringio'

class AutomyraBridgeGovernanceRakeTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    Rake.application.rake_require('tasks/automyra_governance', [File.expand_path('../../../../lib', __dir__)])
    Rake::Task.define_task(:environment)
    Rake::Task.tasks.each(&:reenable)
    AutomyraBridge::GovernanceRun.delete_all
    AutomyraBridge::GovernancePolicy.delete_all
    @user = User.find(1)
    @project = Project.find(1)
    @policy = AutomyraBridge::GovernancePolicy.create!(name: 'Rake policy', project: @project, created_by: @user, mode: 'report_only', provider_model: 'manifest/auto')
  end

  test 'healthcheck prints governance counts' do
    output = capture_stdout { Rake::Task['automyra:governance:healthcheck'].invoke }

    assert_includes output, 'policies=1'
    assert_includes output, 'runs=0'
    assert_includes output, 'locked_policies=0'
  end

  test 'run policy task invokes runner' do
    AutomyraBridge::Governance::Runner.expects(:call).with(policy: @policy, mode: 'report_only').returns(AutomyraBridge::Governance::Runner::Result.new(run: nil, status: 'completed', message: 'completed'))

    output = capture_stdout { Rake::Task['automyra:governance:run_policy'].invoke(@policy.id, 'report_only') }

    assert_includes output, 'completed'
  end

  private

  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
