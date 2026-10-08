require "test_helper"
require "rake"

class PrepareSolidTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["db:prepare_solid"]
    @task.reenable
  end

  Config = Struct.new(:name)

  def with_roles(roles)
    original = ActiveRecord::Base.configurations.method(:configs_for)
    ActiveRecord::Base.configurations.define_singleton_method(:configs_for) do |env_name: nil, name: nil, **rest|
      name ? (roles.include?(name) ? Config.new(name) : nil) : original.call(env_name: env_name, **rest)
    end
    yield
  ensure
    ActiveRecord::Base.configurations.singleton_class.send(:remove_method, :configs_for)
  end

  def loaded_schemas
    loaded = []
    %w[cache queue].each do |role|
      Rake::Task["db:schema:load:#{role}"].clear if Rake::Task.task_defined?("db:schema:load:#{role}")
      Rake::Task.define_task("db:schema:load:#{role}") { loaded << role }
    end
    yield
    loaded
  end

  test "does nothing where there are no cache/queue roles (development, test)" do
    assert_empty(loaded_schemas { @task.invoke })
  end

  test "loads a role's schema only when its table is missing" do
    connection = ActiveRecord::Base.connection
    exists = connection.method(:table_exists?)
    connection.define_singleton_method(:table_exists?) { |table| table == "solid_cache_entries" || exists.call(table) }

    loaded = with_roles(%w[cache queue]) { loaded_schemas { @task.invoke } }

    assert_equal %w[queue], loaded
  ensure
    connection.singleton_class.send(:remove_method, :table_exists?)
  end
end
