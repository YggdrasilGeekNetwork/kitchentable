class ScryfallSyncJob < ApplicationJob
  class SyncFailed < StandardError; end

  queue_as :default

  # The first-boot sync (db/seeds.rb, run on every boot): only while the catalog is
  # empty and no sync is already queued or running — so restarting during the first
  # sync doesn't queue a second one.
  def self.enqueue_unless_catalog_ready
    perform_later unless Card.exists? || pending?
  end

  def self.pending?
    SolidQueue::Job.table_exists? && SolidQueue::Job.where(class_name: name, finished_at: nil).exists?
  end

  # Raises when the sync fails, so the run shows up as a failed job (and the next
  # daily run tries again) instead of passing silently with an empty catalog.
  def perform
    result = CardCatalog::Actions::SyncCardCatalog.call
    raise SyncFailed, result.failure.inspect if result.failure?
  end
end
