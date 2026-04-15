extends Area2D

@export var target_scene: String = ""
@export var randomize: bool = false
@export var random_scenes_folder: String = "res://Scenes/WorldAreas/"

func _process(_delta: float) -> void:
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is CharacterBody2D:
			if Input.is_action_just_pressed("ui_accept"):
				GameState.world_map_position = body.global_position
				
				if randomize:
					var scene = _get_random_scene()
					if scene:
						get_tree().change_scene_to_file(scene)
				else:
					if target_scene:
						get_tree().change_scene_to_file(target_scene)

func _get_random_scene() -> String:
	var scenes := []
	var dir = DirAccess.open(random_scenes_folder)
	
	if dir:
		dir.list_dir_begin()
		var file = dir.get_next()
		while file != "":
			if file.ends_with(".tscn"):
				scenes.append(random_scenes_folder + file)
			file = dir.get_next()
		dir.list_dir_end()
	
	if scenes.is_empty():
		push_error("No scenes found in folder: " + random_scenes_folder)
		return ""
	
	return scenes[randi() % scenes.size()]
