require 'json'
require 'open3'
require 'timeout'

module AutomyraBridge
  class MemoryReader
    DEFAULT_OPENCLAW_CONFIG = '/root/.openclaw/openclaw.json'.freeze

    def self.recent(container, limit: 30)
      return [] if container.blank?

      local = recent_local(container, limit: limit)
      external = recall_for_container(container, limit: limit)

      (local + external).sort_by { |event| event[:created_at].to_s }.last(limit)
    end

    def self.configured?(settings = Setting.plugin_redmine_automyra_bridge)
      config = lancedb_configuration(settings)
      File.directory?(config[:uri].to_s)
    rescue StandardError
      false
    end

    def self.recall(thread_key:, limit: 3)
      return [] if thread_key.blank?

      payload = Timeout.timeout(2) { lancedb_query(thread_key.to_s, nil, limit.to_i.positive? ? limit.to_i : 3) }
      Array(payload['results']).map { |row| normalize_lancedb_row(row) }.compact.first(limit.to_i.positive? ? limit.to_i : 3)
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridge memory recall failed for #{thread_key}: #{e.message}") if defined?(Rails)
      []
    end

    def self.recent_local(container, limit: 30)
      return [] unless AutomyraBridgeMemoryEvent.table_exists?

      AutomyraBridgeMemoryEvent.for_container(container.class.name, container.id)
        .order(created_at: :desc, id: :desc)
        .limit(limit)
        .to_a
        .reverse
        .map do |event|
          {
            id: event.id,
            role: event.role,
            event_type: event.event_type,
            user: event.user&.name,
            content: event.content,
            payload: event.payload_hash,
            created_at: event.created_at&.iso8601
          }
        end
    end

    def self.recall_for_container(container, limit: 30)
      payload = Timeout.timeout(2) { lancedb_query(thread_id_for(container), project_id_for(container), limit) }
      Array(payload['results']).map { |row| normalize_lancedb_row(row) }.compact
    rescue StandardError => e
      Rails.logger.warn("AutomyraBridge memory recall failed: #{e.message}") if defined?(Rails)
      []
    end

    def self.lancedb_configuration(settings = Setting.plugin_redmine_automyra_bridge)
      config_path = settings['memory_lancedb_config_path'].to_s.presence || ENV['AUTOMYRA_MEMORY_CONFIG'] || DEFAULT_OPENCLAW_CONFIG
      config = JSON.parse(File.read(config_path))
      entry = config.dig('plugins', 'entries', 'memory-lancedb-pro', 'config') || {}
      embedding = entry['embedding'] || {}

      {
        config_path: config_path,
        uri: settings['memory_lancedb_uri'].to_s.presence || entry['dbPath'].to_s.presence || '/root/.openclaw/memory/lancedb-pro',
        table: settings['memory_lancedb_table'].to_s.presence || 'memories',
        redmine_table: settings['memory_lancedb_redmine_table'].to_s.presence || 'redmine-memories',
        embedding_model: embedding['model'],
        embedding_base_url: embedding['baseURL'],
        embedding_dimensions: embedding['dimensions']
      }
    rescue Errno::ENOENT, JSON::ParserError
      {
        config_path: config_path,
        uri: settings['memory_lancedb_uri'].to_s.presence || '/root/.openclaw/memory/lancedb-pro',
        table: settings['memory_lancedb_table'].to_s.presence || 'memories',
        redmine_table: settings['memory_lancedb_redmine_table'].to_s.presence || 'redmine-memories'
      }
    end

    def self.lancedb_query(thread_id, project_id, limit)
      config = lancedb_configuration
      script = <<~'PY'
        import json, sys, lancedb
        opts = json.loads(sys.stdin.read())
        db = lancedb.connect(opts['uri'])
        results = []
        for table_name in [opts.get('table') or 'memories', opts.get('redmine_table') or 'redmine-memories']:
          try:
            table = db.open_table(table_name)
            rows = table.to_arrow().to_pylist()
          except Exception:
            continue
          for row in rows:
            searchable = json.dumps({k: v for k, v in row.items() if k != 'vector'}, default=str)
            if opts.get('thread_id') and opts['thread_id'] in searchable:
              row['_table'] = table_name
              results.append(row)
            elif opts.get('project_id') and str(row.get('project_id', '')) == str(opts['project_id']):
              row['_table'] = table_name
              results.append(row)
        results.sort(key=lambda r: str(r.get('updated_on') or r.get('created_on') or r.get('timestamp') or ''))
        print(json.dumps({'results': results[-int(opts.get('limit') or 30):]}, default=str))
      PY
      stdout, stderr, status = Open3.capture3('python3', '-c', script, stdin_data: config.merge(thread_id: thread_id, project_id: project_id, limit: limit).to_json)
      raise "lancedb query failed: #{stderr}" unless status.success?

      JSON.parse(stdout.presence || '{"results":[]}')
    end

    def self.thread_id_for(container)
      kind = container.class.name.demodulize.underscore
      kind = 'task' if container.class.name == 'TaskHub::Task'
      "redmica-#{kind}-#{container.id}"
    end

    def self.project_id_for(container)
      container.respond_to?(:project_id) ? container.project_id : nil
    end

    def self.normalize_lancedb_row(row)
      cache_key = row['cache_key'].presence || row['id'].presence || row['metadata'].to_s
      @metadata_cache ||= {}
      metadata = @metadata_cache[cache_key] ||= (JSON.parse(row['metadata'].to_s.presence || '{}') rescue {})
      content = row['content'].presence || row['text'].presence || metadata['l2_content'].presence || metadata['l1_overview']
      return nil if content.blank?

      {
        id: row['id'],
        role: 'memory',
        event_type: 'lancedb_recall',
        user: row['author'],
        content: content,
        payload: row.except('vector').merge('metadata_hash' => metadata),
        created_at: (row['created_on'] || row['timestamp']).to_s,
        source: "lancedb:#{row['_table']}"
      }
    end
  end
end
