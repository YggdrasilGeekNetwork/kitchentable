require "test_helper"

class ScryfallSyncJobTest < ActiveJob::TestCase
  def with_sync_result(result)
    action = CardCatalog::Actions::SyncCardCatalog
    action.singleton_class.alias_method(:original_call, :call)
    action.define_singleton_method(:call) { |*| result }
    yield
  ensure
    action.singleton_class.alias_method(:call, :original_call)
    action.singleton_class.remove_method(:original_call)
  end

  test "a failed sync fails the job instead of passing silently" do
    with_sync_result(Dry::Monads::Result::Failure.new([ :fetch_error, "boom" ])) do
      error = assert_raises(ScryfallSyncJob::SyncFailed) { ScryfallSyncJob.perform_now }
      assert_match "boom", error.message
    end
  end

  test "a successful sync completes" do
    with_sync_result(Dry::Monads::Result::Success.new(imported: 3)) do
      assert_nothing_raised { ScryfallSyncJob.perform_now }
    end
  end

  def with_pending(value)
    ScryfallSyncJob.define_singleton_method(:pending?) { value }
    yield
  ensure
    ScryfallSyncJob.singleton_class.remove_method(:pending?)
  end

  test "the first-boot sync is queued while the catalog is empty" do
    with_pending(false) do
      assert_enqueued_with(job: ScryfallSyncJob) { ScryfallSyncJob.enqueue_unless_catalog_ready }
    end
  end

  test "not again while one is already queued or running" do
    with_pending(true) do
      assert_no_enqueued_jobs { ScryfallSyncJob.enqueue_unless_catalog_ready }
    end
  end

  test "not once the catalog has cards" do
    Card.create!(scryfall_oracle_id: SecureRandom.uuid, name: "Opt")

    with_pending(false) do
      assert_no_enqueued_jobs { ScryfallSyncJob.enqueue_unless_catalog_ready }
    end
  end

  test "outside production there is no Solid Queue table, so nothing counts as pending" do
    refute ScryfallSyncJob.pending?
  end
end
