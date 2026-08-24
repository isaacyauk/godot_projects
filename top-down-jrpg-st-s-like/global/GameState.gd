extends Node

## Global run/overworld state.
##
## The overworld sets up an encounter here and swaps to res://Scenes/run/run.tscn.
## The run scene reads the pending encounter, plays it out, writes the results
## back (HP, gold, deck, relics) and then returns the player to the overworld
## exactly where they left it.

enum EncounterType {BATTLE, SHOP, CAMPFIRE, TREASURE, EVENT}

const RUN_SCENE_PATH := "res://Scenes/run/run.tscn"
const DEFAULT_CHARACTER := preload("res://characters/warrior/warrior.tres")

# --- Overworld (pre-existing) ---
var world_map_position: Vector2 = Vector2.ZERO

# --- Persistent run data ---
var character: CharacterStats
var run_stats: RunStats
var relics: Array[Relic] = []

# --- Pending encounter, filled in by an overworld trigger ---
var pending_encounter_type: EncounterType = EncounterType.BATTLE
var pending_battle_stats: BattleStats
var pending_event_scene: PackedScene
var pending_is_boss := false

# --- Where to send the player back to ---
var overworld_scene_path := ""
var overworld_return_position := Vector2.ZERO

# --- One-shot overworld encounters that have already been played ---
# Keyed by "<scene path>::<node path>" so a defeated encounter stays defeated.
var cleared_encounters := {}
var _last_encounter_key := ""


func has_run() -> bool:
	return character != null and run_stats != null


## Creates a fresh character instance + run stats. Safe to call more than once;
## it only does anything when there is no run in progress.
func ensure_run(from_character: CharacterStats = null) -> void:
	if has_run():
		return

	start_new_run(from_character)


func start_new_run(from_character: CharacterStats = null) -> void:
	var source: CharacterStats = from_character if from_character else DEFAULT_CHARACTER
	character = source.create_instance() as CharacterStats
	run_stats = RunStats.new()
	relics.clear()

	if character.starting_relic:
		relics.append(character.starting_relic)


func end_run() -> void:
	character = null
	run_stats = null
	relics.clear()
	cleared_encounters.clear()
	_last_encounter_key = ""


func is_encounter_cleared(key: String) -> bool:
	return cleared_encounters.get(key, false)


func mark_encounter_cleared(key: String) -> void:
	if key.is_empty():
		return

	cleared_encounters[key] = true


## Called by overworld triggers. `return_position` is the tile the player should
## be standing on when they come back.
func request_encounter(
	type: EncounterType,
	return_scene_path: String,
	return_position: Vector2,
	battle_stats: BattleStats = null,
	event_scene: PackedScene = null,
	is_boss: bool = false,
	encounter_key: String = ""
) -> void:
	pending_encounter_type = type
	pending_battle_stats = battle_stats
	pending_event_scene = event_scene
	pending_is_boss = is_boss
	_last_encounter_key = encounter_key
	overworld_scene_path = return_scene_path
	overworld_return_position = return_position
	world_map_position = return_position

	ensure_run()
	get_tree().change_scene_to_file(RUN_SCENE_PATH)


func clear_current_encounter() -> void:
	mark_encounter_cleared(_last_encounter_key)
	_last_encounter_key = ""


func return_to_overworld() -> void:
	get_tree().paused = false
	world_map_position = overworld_return_position

	if overworld_scene_path.is_empty():
		push_warning("GameState: no overworld scene to return to.")
		return

	get_tree().change_scene_to_file(overworld_scene_path)


func store_relics(new_relics: Array[Relic]) -> void:
	relics = new_relics.duplicate()
