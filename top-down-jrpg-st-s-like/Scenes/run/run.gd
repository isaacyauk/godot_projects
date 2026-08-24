class_name Run
extends Node

## Hosts a single overworld encounter (battle, shop, campfire, treasure or
## random event) plus the persistent run top-bar, then hands control back to
## the overworld.
##
## This replaces the tutorial's node-map driven Run: the map is the overworld,
## and GameState carries the run between scene changes.

const BATTLE_SCENE := preload("res://Scenes/battle/battle.tscn")
const BATTLE_REWARD_SCENE := preload("res://Scenes/battle_reward/battle_reward.tscn")
const CAMPFIRE_SCENE := preload("res://Scenes/campfire/campfire.tscn")
const SHOP_SCENE := preload("res://Scenes/shop/shop.tscn")
const TREASURE_SCENE := preload("res://Scenes/treasure/treasure.tscn")
const BATTLE_POOL := preload("res://battles/battle_stats_pool.tres")

@onready var current_view: Node = $CurrentView
@onready var health_ui: HealthUI = %HealthUI
@onready var gold_ui: GoldUI = %GoldUI
@onready var relic_handler: RelicHandler = %RelicHandler
@onready var relic_tooltip: RelicTooltip = %RelicTooltip
@onready var deck_button: CardPileOpener = %DeckButton
@onready var deck_view: CardPileView = %DeckView
@onready var pause_menu: PauseMenu = $PauseMenu

var stats: RunStats
var character: CharacterStats
var current_battle_stats: BattleStats


func _ready() -> void:
	GameState.ensure_run()
	character = GameState.character
	stats = GameState.run_stats

	pause_menu.save_and_quit.connect(_exit_to_overworld)

	_setup_event_connections()
	_setup_top_bar()
	_start_pending_encounter.call_deferred()


#region Setup
func _setup_event_connections() -> void:
	Events.battle_won.connect(_on_battle_won)
	Events.battle_reward_exited.connect(_exit_to_overworld)
	Events.campfire_exited.connect(_exit_to_overworld)
	Events.shop_exited.connect(_exit_to_overworld)
	Events.event_room_exited.connect(_exit_to_overworld)
	Events.treasure_room_exited.connect(_on_treasure_room_exited)


func _setup_top_bar() -> void:
	character.stats_changed.connect(health_ui.update_stats.bind(character))
	health_ui.update_stats(character)
	gold_ui.run_stats = stats

	relic_handler.add_relics(GameState.relics)
	Events.relic_tooltip_requested.connect(relic_tooltip.show_tooltip)

	deck_button.card_pile = character.deck
	deck_view.card_pile = character.deck
	deck_button.pressed.connect(deck_view.show_current_view.bind("Deck"))
#endregion


#region Encounter flow
func _change_view(scene: PackedScene) -> Node:
	if current_view.get_child_count() > 0:
		current_view.get_child(0).queue_free()

	get_tree().paused = false
	var new_view := scene.instantiate()
	current_view.add_child(new_view)

	return new_view


func _start_pending_encounter() -> void:
	Events.encounter_started.emit()

	match GameState.pending_encounter_type:
		GameState.EncounterType.BATTLE:
			_start_battle()
		GameState.EncounterType.SHOP:
			_start_shop()
		GameState.EncounterType.CAMPFIRE:
			_start_campfire()
		GameState.EncounterType.TREASURE:
			_start_treasure()
		GameState.EncounterType.EVENT:
			_start_event()


func _start_battle() -> void:
	current_battle_stats = GameState.pending_battle_stats

	if not current_battle_stats:
		BATTLE_POOL.setup()
		var tier: int = 2 if GameState.pending_is_boss else 0
		current_battle_stats = BATTLE_POOL.get_random_battle_for_tier(tier)

	var battle_scene := _change_view(BATTLE_SCENE) as Battle
	battle_scene.char_stats = character
	battle_scene.battle_stats = current_battle_stats
	battle_scene.relics = relic_handler
	battle_scene.start_battle()


func _start_shop() -> void:
	var shop := _change_view(SHOP_SCENE) as Shop
	shop.char_stats = character
	shop.run_stats = stats
	shop.relic_handler = relic_handler
	Events.shop_entered.emit(shop)
	shop.populate_shop()


func _start_campfire() -> void:
	var campfire := _change_view(CAMPFIRE_SCENE) as Campfire
	campfire.char_stats = character


func _start_treasure() -> void:
	var treasure_scene := _change_view(TREASURE_SCENE) as Treasure
	treasure_scene.relic_handler = relic_handler
	treasure_scene.char_stats = character
	treasure_scene.generate_relic()


func _start_event() -> void:
	if not GameState.pending_event_scene:
		_exit_to_overworld()
		return

	var event_room := _change_view(GameState.pending_event_scene) as EventRoom
	event_room.character_stats = character
	event_room.run_stats = stats
	event_room.setup()


func _show_battle_rewards() -> void:
	var reward_scene := _change_view(BATTLE_REWARD_SCENE) as BattleReward
	reward_scene.run_stats = stats
	reward_scene.character_stats = character
	reward_scene.relic_handler = relic_handler

	if current_battle_stats:
		reward_scene.add_gold_reward(current_battle_stats.roll_gold_reward())

	reward_scene.add_card_reward()


func _on_battle_won() -> void:
	_show_battle_rewards()


func _on_treasure_room_exited(relic: Relic) -> void:
	var reward_scene := _change_view(BATTLE_REWARD_SCENE) as BattleReward
	reward_scene.run_stats = stats
	reward_scene.character_stats = character
	reward_scene.relic_handler = relic_handler

	# Guarded: the relic pool can legitimately come back empty once every relic
	# has been collected. (S02 finale - Bug Fix 9)
	reward_scene.add_relic_reward(relic)
#endregion


func _exit_to_overworld() -> void:
	GameState.store_relics(relic_handler.get_all_relics())
	GameState.clear_current_encounter()
	GameState.pending_battle_stats = null
	GameState.pending_event_scene = null
	Events.encounter_finished.emit()
	GameState.return_to_overworld()
