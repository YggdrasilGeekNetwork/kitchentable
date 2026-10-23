require "test_helper"
require "rake"

class PrepareSolidTaskTest < ActiveSupport::TestCase
  Config = Struct.new(:name)

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:prepare_solid")
    @task = Rake::Task["db:prepare_solid"]
    @task.reenable
  end

  # Pretends the cache/queue roles exist (they only do in production) and records which
  # schemas would be loaded, without touching the test database.
  def run_task(roles:, existing_tables: [])
    loaded = []
    tasks = ActiveRecord::Tasks::DatabaseTasks
    configs = ActiveRecord::Base.configurations
    connection = ActiveRecord::Base.connection

    stub(configs, :configs_for) { |env_name: nil, name: nil, **| roles.include?(name) ? Config.new(name) : nil }
    stub(connection, :table_exists?) { |table| existing_tables.include?(table) }
    stub(tasks, :with_temporary_connection) { |_config, &block| block.call }
    stub(tasks, :load_schema) { |config| loaded << config.name }
    @task.invoke
    loaded
  ensure
    [ configs, connection, tasks ].each { |o| o.singleton_class.instance_methods(false).each { |m| o.singleton_class.remove_method(m) } }
  end

  def stub(object, method, &impl) = object.define_singleton_method(method, &impl)

  test "does nothing where there are no cache/queue roles (development, test)" do
    assert_empty run_task(roles: [])
  end

  test "loads a role's schema only when its table is missing" do
    assert_equal %w[queue], run_task(roles: %w[cache queue], existing_tables: %w[solid_cache_entries])
  end

  test "loads nothing once both are there" do
    assert_empty run_task(roles: %w[cache queue], existing_tables: %w[solid_cache_entries solid_queue_jobs])
  end
end
