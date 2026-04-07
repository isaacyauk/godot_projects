
extends CardState

const MOUSE_Y_SAPBACK_TRESHOLD := 138

func enter() -> void:
	card_ui.color.color = Color.WEB_PURPLE
	card_ui.state.text = "AIMING"
	card_ui.targets.clear()# clear the card's array of targets, since aiming means there must be a SPECIFIC target declared!
	
	# Calculate the card offset to animate the aimer to the mouse
	var offset := Vector2(card_ui.parent.size.x / 2, -card_ui.size.y / 2)
	offset.x -= card_ui.size.x / 2
	card_ui.animate_to_position(card_ui.parent.global_position + offset, 0.2)
	card_ui.drop_point_detector.monitoring = false
	Events.card_aim_started.emit(card_ui) # Use the event bus to emit the start of the important signal 

func exit() -> void:
	Events.card_aim_ended.emit(card_ui)
	
func on_input(event: InputEvent) -> void:
	# Aiming actually happens here
	var mouse_motion := event is InputEventMouseMotion
	var mouse_at_bottom := card_ui.get_global_mouse_position().y > MOUSE_Y_SAPBACK_TRESHOLD
	
	# if aiming somehow needs to end
	if (mouse_motion and mouse_at_bottom) or event.is_action_pressed("right_mouse"):
		transition_requested.emit(self, CardState.State.BASE)
	elif event.is_action_released("left_mouse") or  event.is_action_pressed("left_mouse"):
		get_viewport().set_input_as_handled()
		transition_requested.emit(self, CardState.State.RELEASED)
