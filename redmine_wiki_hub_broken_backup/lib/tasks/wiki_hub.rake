namespace :wiki_hub do
  desc 'Rebuild wiki hub snapshots, metadata and links from current wiki pages'
  task rebuild: :environment do
    puts '[wiki_hub] Starting full rebuild...'

    started_at = Time.current
    result = WikiHub::Indexer.rebuild_all
    elapsed = Time.current - started_at

    puts "[wiki_hub] Index run id: #{result[:index_run_id]}"
    puts "[wiki_hub] Pages total: #{result[:pages_total]}"
    puts "[wiki_hub] Pages processed: #{result[:pages_processed]}"
    puts "[wiki_hub] Links found: #{result[:links_found]}"

    if result[:errors].any?
      puts "[wiki_hub] Errors: #{result[:errors].size}"
      result[:errors].each { |error| puts "[wiki_hub][error] #{error}" }
      raise "Wiki hub rebuild finished with #{result[:errors].size} indexing error(s)"
    else
      puts '[wiki_hub] Errors: 0'
    end

    puts format('[wiki_hub] Completed in %.2fs', elapsed)
  rescue StandardError => e
    puts "[wiki_hub] Rebuild failed: #{e.class}: #{e.message}"
    raise
  end
end
