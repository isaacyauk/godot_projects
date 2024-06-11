class_name Interactable
extends StaticBody3D
	
signal interacted(body)

@export var prompt_message = "Interact"
@export var prompt_input = "interact"

#@export var object_to_instantiate : PackedScene
@export var scene_folder_path : String
@onready var obj_spawn = $ObjSpawn 	# Get the reference to the ObjSpawn node

var button_pressed = false
var scene_paths = []


func ready():
	if scene_folder_path.is_empty():
		print("Error: Scene folder path is not set")
	else:
		load_scene_paths()
		
	#if object_to_instantiate == null:
		#print("Error: No scene assigned to object_to_instantiate")
	#
	## Ensure obj_spawn is not null
	#if obj_spawn == null:
		#print("Error: No ObjSpawn node found")


func load_scene_paths():
	var dir = DirAccess.open(scene_folder_path)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			scene_paths.append(scene_folder_path + "/" + file_name)
		file_name = dir.get_next()

func get_prompt():
	var key_name = " "
	for action in InputMap.action_get_events(prompt_input):
		if action is InputEventKey:
			key_name = action.as_text_physical_keycode()
			break
	
	return prompt_message + " [" + key_name + "]\n\n\n"


#func instantiate_object():
	#if object_to_instantiate:
		#var new_object = object_to_instantiate.instantiate()
		#get_parent().add_child(new_object)
		#new_object.global_transform.origin = obj_spawn.global_transform.origin	
	#else:
		#print("Error: No scene to instantiate")

func instantiate_random_object():
	print(str(scene_paths.size()))
	if scene_paths.size() > 0:
		var random_index = randi() % scene_paths.size()
		var random_scene_path = scene_paths[random_index]
		var random_scene = load(random_scene_path)
		var new_object = random_scene.instantiate()
		get_parent().add_child(new_object)
		new_object.global_transform.origin = obj_spawn.global_transform.origin
	else:
		print("Error: No scenes found in the specified folder")
		

func interact(body):
	print(body.name + " interacted with " + name) 	# Debugging
	interacted.emit(body)
	instantiate_random_object()
	button_pressed = true

