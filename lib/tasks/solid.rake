namespace :db do
  # primary/cache/queue share one physical database in production (config/database.yml),
  # and db:prepare only prepares primary. Loading cache_schema.rb / queue_schema.rb
  # recreates their tables (force: :cascade), so it must only happen the first time —
  # on every boot it would drop queued jobs and the cache.
  #
  # Loads through DatabaseTasks directly: the db:schema:load:* tasks refuse to run in
  # production (ProtectedEnvironmentError), which is right for them — they're meant to
  # wipe a database — but this only ever creates tables that don't exist yet.
  desc "Load the Solid Cache/Queue schemas, only where their tables don't exist yet"
  task prepare_solid: :environment do
    { "cache" => "solid_cache_entries", "queue" => "solid_queue_jobs" }.each do |role, table|
      db_config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: role)
      next unless db_config
      next if ActiveRecord::Base.connection.table_exists?(table)

      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(db_config) do
        ActiveRecord::Tasks::DatabaseTasks.load_schema(db_config)
      end
    end
  end
end
