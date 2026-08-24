class_name CardStateMachine
extends Node

# NOTE: the export keeps its original spelling ("inital_state") so the existing
# card_ui.tscn node_paths entry keeps resolving.
@export var inital_state: CardState

var current_state: CardState # Stores current state we're in
var states := {} # Dictionary of all available states in the state machine


func init(card: CardUI) -> void:
#	iterate over all the children in the state machine
	for child in get_children():
		if child is CardState:
#			Add it to the dict of all states we have
			states[child.state] = child
			child.transition_requested.connect(_on_transition_requested)
			child.card_ui = card

	# If we do have an initial state
	if inital_state:
		inital_state.enter()
		current_state = inital_state
		current_state.post_enter()


func on_input(event: InputEvent) -> void:
	if current_state:
		current_state.on_input(event)


func on_gui_input(event: InputEvent) -> void:
	if current_state:
		current_state.on_gui_input(event)


func on_mouse_entered() -> void:
	if current_state:
		current_state.on_mouse_entered()


func on_mouse_exited() -> void:
	if current_state:
		current_state.on_mouse_exited()


func _on_transition_requested(from: CardState, to: CardState.State) -> void:
#	Check if the transitionary states are mismatched and return if they are
	if from != current_state:
		return

	var new_state: CardState = states.get(to)
	if not new_state:
		return

	if current_state:
		current_state.exit()

	new_state.enter()
	current_state = new_state
	# post_enter() lets a state act immediately after it becomes current,
	# without waiting for the next input event. This is what stops unplayed
	# cards from hanging in mid-air on Linux/macOS. (S02 finale — Bug Fix 7)
	new_state.post_enter()
