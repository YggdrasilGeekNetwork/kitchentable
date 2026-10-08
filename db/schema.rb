# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_10_08_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "cards", force: :cascade do |t|
    t.uuid "scryfall_oracle_id", null: false
    t.string "name", null: false
    t.string "name_normalized", null: false
    t.string "mana_cost"
    t.decimal "cmc"
    t.string "type_line"
    t.text "oracle_text"
    t.jsonb "colors", default: [], null: false
    t.jsonb "color_identity", default: [], null: false
    t.jsonb "legalities", default: {}, null: false
    t.jsonb "image_uris", default: {}, null: false
    t.string "layout"
    t.string "set_code"
    t.string "collector_number"
    t.string "rarity"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "front_face_name_normalized"
    t.jsonb "card_faces", default: [], null: false
    t.string "alternate_names_normalized", default: [], null: false, array: true
    t.string "power"
    t.string "toughness"
    t.string "loyalty"
    t.jsonb "related_tokens", default: [], null: false
    t.index ["alternate_names_normalized"], name: "index_cards_on_alternate_names_normalized", using: :gin
    t.index ["front_face_name_normalized"], name: "index_cards_on_front_face_name_normalized"
    t.index ["name_normalized"], name: "index_cards_on_name_normalized"
    t.index ["scryfall_oracle_id"], name: "index_cards_on_scryfall_oracle_id", unique: true
  end

  create_table "game_tables", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name"
    t.string "format", null: false
    t.integer "status", default: 0, null: false
    t.string "host_session_id", null: false
    t.integer "max_seats", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "last_activity_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_activity_at"], name: "index_game_tables_on_last_activity_at"
    t.index ["slug"], name: "index_game_tables_on_slug", unique: true
  end

  create_table "seats", force: :cascade do |t|
    t.bigint "game_table_id", null: false
    t.integer "seat_number", null: false
    t.string "session_id", null: false
    t.string "display_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "token", null: false
    t.index ["game_table_id", "seat_number"], name: "index_seats_on_game_table_id_and_seat_number", unique: true
    t.index ["game_table_id", "session_id"], name: "index_seats_on_game_table_id_and_session_id", unique: true
    t.index ["game_table_id"], name: "index_seats_on_game_table_id"
    t.index ["token"], name: "index_seats_on_token", unique: true
  end

  add_foreign_key "seats", "game_tables"
end
