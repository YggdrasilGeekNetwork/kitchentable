class ScryfallSyncJob < ApplicationJob
  queue_as :default

  def perform
    CardCatalog::Actions::SyncCardCatalog.call
  end
end
