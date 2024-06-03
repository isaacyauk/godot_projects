class_name StateMachine
extends Node

@export var CURRENT_STATE : State
var states: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	# This loops through the child nodes and checks if they have a State class type. If they 
	# 	do, add them to a dictionary for further reference.	
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.transition.connect(on_child_transition)
		else:
			push_warning("State machine contains incompatible child node.")
			
	await owner.ready
	CURRENT_STATE.enter()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	CURRENT_STATE.update(delta)
	Global.debug.add_property("Current State ", CURRENT_STATE.name, 2)


func _physics_process(delta):
	CURRENT_STATE.physics_update(delta)
	

# This proces controls whenever a state is entered or exited and ensures 
# 	that only one state can be active at a time.
func on_child_transition(new_state_name: StringName) -> void:
	var new_state = states.get(new_state_name)
	if new_state != null:
		if new_state != CURRENT_STATE:
			CURRENT_STATE.exit()
			new_state.enter()
			CURRENT_STATE = new_state
	else:
		push_warning("State does not exist.")
