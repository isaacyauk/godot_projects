extends Relic

var already_initialized := false


# NOTE: `run` is deliberately left untyped here.
#
# Casting it to `Run` makes this resource depend on run.gd, and run.gd preloads
# shop.tscn and treasure.tscn -- both of which list this very relic in their
# pools. That closes a loop the resource loader cannot walk: opening either
# scene makes Godot re-enter a resource it is already loading, and it reports
# blinding_potion.tres as a missing dependency ("Parse Error: Busy").
#
# Duck typing breaks the cycle without changing behaviour.
func _get_run(owner: RelicUI) -> Node:
	if not owner or not owner.is_inside_tree():
		return null

	return owner.get_tree().get_first_node_in_group("run")


func initialize_relic(owner: RelicUI) -> void:
	# makes sure we don't have extra mana when we
	# keep saving and loading the game
	if already_initialized:
		return

	var run := _get_run(owner)
	if not run or not run.character:
		return

	run.character.max_mana += 1
	run.character.mana = run.character.max_mana
	already_initialized = true


func activate_relic(owner: RelicUI) -> void:
	owner.get_tree().call_group("intent", "set", "modulate", Color.TRANSPARENT)


func deactivate_relic(owner: RelicUI) -> void:
	var run := _get_run(owner)
	if not run or not run.character:
		return

	run.character.max_mana -= 1
	already_initialized = false
