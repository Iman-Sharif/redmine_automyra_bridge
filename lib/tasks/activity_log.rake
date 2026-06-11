namespace :automyra_bridge do
  desc 'Generate activity log wiki page for today and update index'
  task generate_activity_log_page: :environment do
    date = ENV['DATE'] ? Date.parse(ENV['DATE']) : Date.current
    page = AutomyraBridge::ActivityLogWikiGenerator.generate_daily_page(date)
    if page
      puts "Generated: #{page.title}"
      index = AutomyraBridge::ActivityLogWikiGenerator.generate_index_page
      puts "Index updated: #{index.title}" if index
    else
      puts "No entries for #{date.iso8601}, skipping."
    end
  end
end
