module Table
  module Views
    # The catalog data the board needs to draw a card, as one entry per face (single-
    # faced cards have one): name, cost, type, rules text, stats, the full image (for
    # hand/zoom) and the art crop (for compact battlefield permanents). Only
    # double-faced cards have their own image per face; split/adventure faces share
    # the card's.
    module CardView
      FACE_FIELDS = %w[name mana_cost type_line oracle_text power toughness loyalty].freeze

      def self.call(card)
        faces = Array(card.card_faces).presence || [ FACE_FIELDS.index_with { |f| card.public_send(f) } ]
        double_faced = faces.size > 1 && faces.all? { |face| face["image_uris"].present? }

        {
          "id" => card.id,
          "name" => card.name,
          "double_faced" => double_faced,
          "faces" => faces.map { |face|
            uris = (double_faced ? face["image_uris"] : card.image_uris) || {}
            face.slice(*FACE_FIELDS).merge("image" => uris["normal"], "art" => uris["art_crop"])
          }
        }
      end
    end
  end
end
