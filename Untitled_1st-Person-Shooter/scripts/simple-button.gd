class_name Interactable # creating a class here to reference objects elsewhere
extends Node3D

signal interacted(body)

@export var prompt_message = "Interact"
@export var prompt_action = "interact"


func get_prompt():
	var key_name = ""
	for action in InputMap.action_get_events(prompt_action):
		if action is InputEventKey:
			key_name = OS.get_keycode_string(action.physical_keycode)
	return prompt_message + "\n[" + key_name + "]"
	

func interact(body):
	emit_signal("interacted", body)
	print(body.name, " interacted!!!!!")
	# something small did this stays??
