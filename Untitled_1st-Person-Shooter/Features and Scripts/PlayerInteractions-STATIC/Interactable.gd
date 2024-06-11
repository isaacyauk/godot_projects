extends StaticBody3D
class_name Interactable
	
signal interacted(body)
	
@export var prompt_message = "Interact"
@export var prompt_input = "interact"
@export var object_to_instantiate : PackedScene

func get_prompt():
	var key_name = " "
	for action in InputMap.action_get_events(prompt_input):
		if action is InputEventKey:
			key_name = action.as_text_physical_keycode()
			break
	
	return prompt_message + " [" + key_name + "]\n\n\n"


func instantiate_object():
	if object_to_instantiate:
		var new_object = object_to_instantiate.instantiate()
		get_parent().add_child(new_object)
		new_object.global_transform.origin = global_transform.origin + Vector3(2, 2, 2) # Adjust the position if needed
	else:
		print("Error: No scene to instantiate")

func interact(body):
	print(body.name + " interacted with " + name) 	# Debugging
	interacted.emit(body)
	instantiate_object()

