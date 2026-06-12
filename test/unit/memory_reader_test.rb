require File.expand_path('../test_helper', __dir__)

class AutomyraBridgeMemoryReaderTest < ActiveSupport::TestCase
  fixtures :users, :projects

  setup do
    skip 'memory events table is not available' unless defined?(AutomyraBridgeMemoryEvent) && AutomyraBridgeMemoryEvent.table_exists?

    AutomyraBridgeMemoryEvent.delete_all
    @user = User.find(2)
    @project = Project.find(1)
    @task = TaskHub::Task.create!(title: 'Recall task', user: @user, author: @user, project: @project, status: 'todo')
  end

  test 'recent includes local Redmica memory events' do
    AutomyraBridgeMemoryEvent.create!(
      container_type: @task.class.name,
      container_id: @task.id,
      user: @user,
      role: 'user',
      event_type: 'user_mention',
      content: 'local-memory-event',
      payload: { thread_id: 'redmica-task-ignored' }.to_json,
      correlation_id: SecureRandom.uuid
    )
    AutomyraBridge::MemoryReader.stubs(:recall_for_container).returns([])

    assert_equal(['local-memory-event'], AutomyraBridge::MemoryReader.recent(@task).map { |row| row[:content] })
  end

  test 'recent retrieves LanceDB memories correlated by task thread id and project id' do
    AutomyraBridge::MemoryReader.expects(:lancedb_query).with("redmica-task-#{@task.id}", @project.id, 30).returns(
      'results' => [
        {
          'id' => 'mem-1',
          '_table' => 'memories',
          'text' => 'thread correlated memory',
          'metadata' => { thread_id: "redmica-task-#{@task.id}" }.to_json,
          'timestamp' => 1_775_928_334_831
        },
        {
          'id' => 'redmine:issue:1',
          '_table' => 'redmine-memories',
          'project_id' => @project.id.to_s,
          'content' => 'project correlated memory',
          'created_on' => '2026-05-01T12:00:00Z'
        }
      ]
    )

    contents = AutomyraBridge::MemoryReader.recent(@task).map { |row| row[:content] }
    assert_includes contents, 'thread correlated memory'
    assert_includes contents, 'project correlated memory'
  end

  test 'discovers LanceDB configuration from OpenClaw config' do
    file = Tempfile.new('openclaw-memory')
    file.write({
      plugins: {
        entries: {
          'memory-lancedb-pro': {
            config: {
              dbPath: '/tmp/lancedb-pro',
              embedding: { model: 'nomic-embed-text', baseURL: 'http://127.0.0.1:11434/v1', dimensions: 768 }
            }
          }
        }
      }
    }.to_json)
    file.close

    config = AutomyraBridge::MemoryReader.lancedb_configuration('memory_lancedb_config_path' => file.path)
    assert_equal '/tmp/lancedb-pro', config[:uri]
    assert_equal 'memories', config[:table]
    assert_equal 'redmine-memories', config[:redmine_table]
    assert_equal 'nomic-embed-text', config[:embedding_model]
    assert_equal 768, config[:embedding_dimensions]
  ensure
    file&.unlink
  end
end
