namespace :db do
  # primary/cache/queue share one physical database in production (config/database.yml),
  # and db:prepare only prepares primary. Loading cache_schema.rb / queue_schema.rb
  # recreates their tables (force: :cascade), so it must only happen the first time —
  # on every boot it would drop queued jobs and the cache.
  desc "Load the Solid Cache/Queue schemas, only where their tables don't exist yet"
  task prepare_solid: :environment do
    { "cache" => "solid_cache_entries", "queue" => "solid_queue_jobs" }.each do |role, table|
      next unless ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: role)
      next if ActiveRecord::Base.connection.table_exists?(table)

      Rake::Task["db:schema:load:#{role}"].invoke
    end
  end
end
