class_name Interactable # creating a class here to reference objects elsewhere
extends Node3D

signal interacted(body)

@export var prompt_message = "Interact"
@export var prompt_action = "interact"

# an export variable to set in the editor what object is being created.
@export var object_to_instantiate : PackedScene
# the spawn location of the objext to instantiate
@onready var obj_spawn_loc = $ObjSpawn

var button_pressed = false # a variable to ensure that the button can be pressed only once.

func _ready():
	if object_to_instantiate == null:
		print("Error: No scene assigned to object_to_instantiate")


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
	if object_to_instantiate:
		var new_object = object_to_instantiate.instantiate()
		get_parent().add_child(new_object)
		# Create the new object at the specifiec object spawn location
		new_object.global_transform.origin = obj_spawn_loc.global_transform.origin
		print(new_object.name, " created.")
	else:
		print("Error: No scene to instantiate")
	
