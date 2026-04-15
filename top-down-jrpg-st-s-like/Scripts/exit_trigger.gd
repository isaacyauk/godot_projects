extends Area2D

func _process(_delta: float) -> void:
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is CharacterBody2D:
			if Input.is_action_just_pressed("ui_accept"):
				get_tree().change_scene_to_file("res://Scenes/test_overworld.tscn")
