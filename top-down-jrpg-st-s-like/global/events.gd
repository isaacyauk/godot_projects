extends Node

# Card-related events
signal card_drag_started(card_ui: CardUI)
signal card_drag_ended(card_ui: CardUI)
signal card_aim_started(card_ui: CardUI)
signal card_aim_ended(card_ui: CardUI)
signal card_played(card: Card)
signal card_tooltip_requested(icon: Texture, text: String)
signal tooltip_hide_requested

# Player-related events
signal player_hand_drawn
signal player_hand_discarded
signal player_turn_ended
signal player_hit
signal player_died

# Enemy-related events
signal enemy_action_completed(enemy: BattleEnemy)
signal enemy_turn_ended
signal enemy_died(enemy: BattleEnemy)

# Battle-related events
signal battle_over_screen_requested(text: String, type: BattleOverPanel.Type)
signal battle_won
signal status_tooltip_requested(statuses: Array[Status])

# Overworld <-> encounter events (this project uses the overworld instead of
# the tutorial's node map, so `encounter_started` replaces `map_exited`)
signal encounter_started
signal encounter_finished

# Shop-related events
signal shop_entered(shop: Shop)
signal shop_relic_bought(relic: Relic, gold_cost: int)
signal shop_card_bought(card: Card, gold_cost: int)
signal shop_card_removed(card: Card, gold_cost: int)
signal shop_exited

# Campfire-related events
signal campfire_exited
signal card_upgraded(card: Card)

# Battle Reward-related events
signal battle_reward_exited

# Treasure Room-related events
signal treasure_room_exited(found_relic: Relic)

# Relic-related events
signal relic_tooltip_requested(relic: Relic)
signal relic_gained(relic: Relic)

# Random Event room-related events
signal event_room_exited
