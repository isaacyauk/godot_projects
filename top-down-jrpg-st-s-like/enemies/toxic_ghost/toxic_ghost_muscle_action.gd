extends EnemyAction

## ORPHAN -- nothing instances this. toxic_ghost_ai.tscn wires
## toxic_ghost_muscle_buff_action.gd instead, which is the one that actually
## applies the Muscle status. Kept because deleting your files isn't my call;
## safe to remove if you don't want it.
##
## It used to build a Tween and never add a tweener to it, which makes Godot
## print "Tween without commands, aborting" the moment the action runs. Removed
## that so wiring this up later doesn't spam the console.


func perform_action() -> void:
	if not enemy or not target:
		return

	SFXPlayer.play(sound)

	Events.enemy_action_completed.emit(enemy)
