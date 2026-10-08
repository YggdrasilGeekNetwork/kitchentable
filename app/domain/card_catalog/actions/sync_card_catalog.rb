module CardCatalog
  module Actions
    class SyncCardCatalog < Shared::BaseAction
      def call(source: nil)
        Interactions::ImportScryfallBulkData.call(source: source)
      end
    end
  end
end
