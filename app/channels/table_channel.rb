# Primary (driving) adapter: translates WebSocket commands into Table::Actions calls.
# On subscribe it sends the player the current table as they may see it; after that,
# every successful change pushes each seat a fresh redacted view (from the
# interaction, via Table::Ports::BroadcasterPort), so this channel only transmits the
# initial snapshot and errors back to the issuing client.
class TableChannel < ApplicationCable::Channel
  # The seat is proven by its secret token (the same one in the player's table URL),
  # not by the guest cookie, so a player who lost their cookies can still play.
  def subscribed
    @table_slug = params[:table_slug]
    @seat_id = params[:seat_id].to_s

    return reject unless owns_seat?

    stream_from Broadcasting::ActionCableBroadcaster.seat_stream_name(@table_slug, @seat_id)
    handle_result(Table::Actions::FetchTableView.call(**seat)) { |view| transmit(view) }
  end

  def move_card(data)
    handle_result(Table::Actions::MoveCard.call(
      **seat, card_instance_id: data["card_instance_id"].to_s, to_zone: data["to_zone"].to_s,
      to_position: data["to_position"], to_seat_id: data["to_seat_id"], x: data["x"], y: data["y"]
    ))
  end

  def move_cards(data)
    handle_result(Table::Actions::MoveCards.call(
      **seat, moves: Array(data["moves"]), to_zone: data["to_zone"].to_s,
      to_position: data["to_position"], to_seat_id: data["to_seat_id"]
    ))
  end

  def mana(data)
    handle_result(Table::Actions::ChangeManaPool.call(**seat, color: data["color"], delta: data["delta"].to_i, clear: !!data["clear"]))
  end

  def remove_sickness(data)
    handle_result(Table::Actions::RemoveSummoningSickness.call(**seat, card_instance_id: data["card_instance_id"].to_s))
  end

  def tap_card(data)
    handle_result(Table::Actions::TapCard.call(**seat, card_instance_id: data["card_instance_id"].to_s, tapped: !!data["tapped"]))
  end

  def tap_all(data) = handle_result(Table::Actions::TapAll.call(**seat, tapped: !!data["tapped"]))
  def new_turn(_data) = handle_result(Table::Actions::NewTurn.call(**seat))
  def proliferate(_data) = handle_result(Table::Actions::Proliferate.call(**seat))
  def draw(data) = handle_result(Table::Actions::DrawCards.call(**seat, count: data.fetch("count", 1)))
  def mill(data) = handle_result(Table::Actions::Mill.call(**seat, count: data.fetch("count", 1)))
  def shuffle(_data) = handle_result(Table::Actions::ShuffleLibrary.call(**seat))
  def mulligan(_data) = handle_result(Table::Actions::Mulligan.call(**seat))
  def keep_hand(_data) = handle_result(Table::Actions::KeepHand.call(**seat))
  def pass_turn(_data) = handle_result(Table::Actions::PassTurn.call(**seat))
  def start_turn(data) = handle_result(Table::Actions::StartTurn.call(**seat, out_of_turn: !!data["out_of_turn"]))
  def restart_vote(data) = handle_result(Table::Actions::VoteRestart.call(**seat, answer: data["answer"].to_s))
  def stop_peek(_data) = handle_result(Table::Actions::StopPeek.call(**seat))
  def peek_remaining(data) = handle_result(Table::Actions::PlaceRevealedRest.call(**seat, placement: data["placement"].to_s))
  def top_revealed(data) = handle_result(Table::Actions::RevealLibraryTop.call(**seat, revealed: !!data["revealed"]))

  def set_life(data)
    handle_result(Table::Actions::SetLife.call(**seat, delta: data["delta"].to_i, target_seat_id: data["target_seat_id"]))
  end

  def player_counter(data)
    handle_result(Table::Actions::AdjustPlayerCounter.call(
      **seat, key: data["key"], delta: data["delta"].to_i, target_seat_id: data["target_seat_id"], remove: !!data["remove"]
    ))
  end

  def commander_damage(data)
    handle_result(Table::Actions::DealCommanderDamage.call(
      **seat, commander_instance_id: data["commander_instance_id"].to_s, delta: data["delta"].to_i, target_seat_id: data["target_seat_id"]
    ))
  end

  def card_counter(data)
    handle_result(Table::Actions::AdjustCardCounter.call(
      **seat, card_instance_id: data["card_instance_id"].to_s, key: data["key"], delta: data["delta"].to_i
    ))
  end

  def flip_card(data)
    handle_result(Table::Actions::FlipCard.call(**seat, card_instance_id: data["card_instance_id"].to_s))
  end

  def face_down(data)
    handle_result(Table::Actions::TurnFaceDown.call(**seat, card_instance_id: data["card_instance_id"].to_s, face_down: !!data["face_down"]))
  end

  def reveal(data)
    handle_result(Table::Actions::RevealCards.call(**seat, card_instance_ids: Array(data["card_instance_ids"])))
  end

  def end_reveal(data) = handle_result(Table::Actions::EndReveal.call(**seat, reveal_id: data["reveal_id"].to_s))

  def peek(data)
    handle_result(Table::Actions::PeekLibrary.call(**seat, count: data["count"], target_seat_id: data["target_seat_id"], search: !!data["search"]))
  end

  def create_card(data)
    handle_result(Table::Actions::CreateCard.call(
      **seat, card_id: data["card_id"], name: data["name"], custom: data["custom"],
      token: data.fetch("token", true) != false, count: data.fetch("count", 1), x: data["x"], y: data["y"]
    ))
  end

  def modify_pt(data)
    handle_result(Table::Actions::ModifyPowerToughness.call(
      **seat, card_instance_id: data["card_instance_id"].to_s, power: data["power"].to_i, toughness: data["toughness"].to_i
    ))
  end

  def remove_card(data)
    handle_result(Table::Actions::RemoveCard.call(**seat, card_instance_id: data["card_instance_id"].to_s))
  end

  # Sent back to the asking player only: the tokens their deck can make.
  def deck_tokens(_data)
    handle_result(Table::Actions::SuggestDeckTokens.call(**seat)) { |tokens| transmit({ "type" => "deck_tokens", "tokens" => tokens }) }
  end

  def roll_dice(data) = handle_result(Table::Actions::RollDice.call(**seat, sides: data["sides"]))
  def chat(data) = handle_result(Table::Actions::SendChatMessage.call(**seat, message: data["message"].to_s))

  private

  def seat = { table_slug: @table_slug, seat_id: @seat_id }

  def owns_seat?
    table = ::GameTable.find_by(slug: @table_slug)
    return false unless table && params[:seat_token].present?

    table.seats.exists?(id: @seat_id, token: params[:seat_token].to_s)
  end

  # Not `in Success(value)`: dry-monads destructures an Array value into its elements,
  # so a list result would bind its first element — or not match at all.
  def handle_result(result)
    return yield(result.value!) if result.success? && block_given?
    return if result.success?

    tag, payload = result.failure
    transmit({ "type" => "error", "error" => tag.to_s, "message" => payload.is_a?(String) ? payload : payload.to_s })
  end
end
