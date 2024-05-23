class_name State
extends Node

signal transition(new_state_name : StringName)


func enter() -> void:
	pass

func exit() -> void:
	pass

# This runs every frame
func update(delta: float) -> void:
	pass

# This is the physics process
func physics_update(delta: float) -> void:
	pass
