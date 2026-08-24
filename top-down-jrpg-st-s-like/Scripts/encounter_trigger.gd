class_name EncounterTrigger
extends Area2D

## Drop this on the overworld to start a Slay-the-Spire style encounter.
##
## It hands the encounter to GameState and swaps to res://Scenes/run/run.tscn.
## When the encounter finishes, the player is returned to this exact spot.

@export_group("Encounter")
@export var encounter_type: GameState.EncounterType = GameState.EncounterType.BATTLE
## Leave empty to roll a random battle of the matching tier from
## res://battles/battle_stats_pool.tres.
@export var battle_stats: BattleStats
## Only used when encounter_type is EVENT.
@export var event_scene: PackedScene
@export var is_boss := false

@export_group("Behaviour")
## Trigger the moment the player steps on it, instead of requiring a keypress.
@export var trigger_on_touch := false
@export var interact_action := "ui_accept"
## Once cleared, this trigger stays gone for the rest of the run.
@export var one_shot := true
## Optional: 0.0 = always fires. 0.25 = 25% chance per step for random encounters.
@export_range(0.0, 1.0) var encounter_chance := 1.0

var _fired := false
var _bodies_inside: Array[Node2D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if one_shot and GameState.is_encounter_cleared(_get_key()):
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if trigger_on_touch or _fired or _bodies_inside.is_empty():
		return

	if event.is_action_pressed(interact_action):
		get_viewport().set_input_as_handled()
		_start(_bodies_inside[0])


func _get_key() -> String:
	var scene_path := ""
	if get_tree() and get_tree().current_scene:
		scene_path = get_tree().current_scene.scene_file_path

	return "%s::%s" % [scene_path, get_path()]


func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D:
		return

	if not _bodies_inside.has(body):
		_bodies_inside.append(body)

	if trigger_on_touch:
		_start(body)


func _on_body_exited(body: Node2D) -> void:
	_bodies_inside.erase(body)


func _start(body: Node2D) -> void:
	# Guards against the trigger firing twice while the scene change is still
	# in flight - the same class of bug as the fast-clicked map nodes in the
	# S02 finale (Bug Fix 1).
	if _fired:
		return

	if encounter_chance < 1.0 and randf() > encounter_chance:
		return

	_fired = true
	set_deferred("monitoring", false)

	var return_scene := get_tree().current_scene.scene_file_path
	var return_position: Vector2 = body.global_position

	# Deferred: on a walk-on trigger this runs inside a physics callback, and
	# swapping scenes there frees CollisionObjects mid-step.
	GameState.request_encounter.call_deferred(
		encounter_type,
		return_scene,
		return_position,
		battle_stats,
		event_scene,
		is_boss,
		_get_key() if one_shot else ""
	)
