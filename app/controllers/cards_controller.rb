class CardsController < ApplicationController
  include HandlesDomainResult

  # GET /cards/search?q=treas — names for the board's card/token picker.
  def search
    result = CardCatalog::Actions::SearchCards.call(query: params[:q])
    result.success? ? render(json: result.value!) : render_failure(result)
  end
end
