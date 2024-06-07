class_name Interactable # creating a class here to reference objects elsewhere
extends StaticBody3D

signal interacted(body)

@export var prompt_message = "Interact"
@export var prompt_action = "interact"

# an export variable to set in the editor what object is being created.
@export var scene_folder_path : String
#@export var object_to_instantiate : PackedScene
# the spawn location of the objext to instantiate
@onready var obj_spawn_loc = $ObjSpawn

var button_pressed = false # a variable to ensure that the button can be pressed only once.
var scene_paths = []

#func _ready():
	#if object_to_instantiate == null:
		#print("Error: No scene assigned to object_to_instantiate")

func _ready():
	if scene_folder_path.is_empty():
		print("Error: No scene folder path is not set.")
	else:
		load_scene_paths()
		
		
func load_scene_paths():
	var dir = DirAccess.open(scene_folder_path)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			scene_paths.append(scene_folder_path + "/" + file_name)
		file_name = dir.get_next()


func get_prompt():
	var key_name = ""
	for action in InputMap.action_get_events(prompt_action):
		if action is InputEventKey:
			key_name = OS.get_keycode_string(action.physical_keycode)
	return prompt_message + " [" + key_name + "]\n\n\n"


# this function should only be run once, if the button has not been pressed
func interact(body):
	if !button_pressed:
		emit_signal("interacted", body)
		print(body.name, " interacted!!!!!")
		instantiate_object()
		button_pressed = true

func instantiate_object():
	if scene_paths.size() > 0:
		var random_index = randi() % scene_paths.size()
		var random_scene_path = scene_paths[random_index]
		var random_scene = load(random_scene_path)
		var new_object = random_scene.instantiate()
		
		get_parent().add_child(new_object)
		new_object.global_transform.origin = obj_spawn_loc.global_transform.origin
		print(new_object.name, " created.")
	else:
		print("Error: No scenes found in the specified folder")
#func instantiate_object():
	#if object_to_instantiate:
		#var new_object = object_to_instantiate.instantiate()
		#get_parent().add_child(new_object)
		## Create the new object at the specifiec object spawn location
		#new_object.global_transform.origin = obj_spawn_loc.global_transform.origin
		#print(new_object.name, " created.")
	#else:
		#print("Error: No scene to instantiate")
	
