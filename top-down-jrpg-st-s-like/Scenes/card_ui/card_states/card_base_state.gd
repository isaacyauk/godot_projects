extends CardState

# Tracks whether the cursor is actually over this card. Without it you could
# right-click a card, move the cursor away and then left-click to drag a card
# you are not hovering. (S02 finale — Bug Fix 3)
var mouse_over_card := false


func enter() -> void:
	# wait for the Card UI to be ready (children nodes in a scene get ready before parents!)
	if not card_ui.is_node_ready():
		await card_ui.ready

	# check if card's tween is running and stop it if it is (prevents mouse dragging bugs)
	if card_ui.tween and card_ui.tween.is_running():
		card_ui.tween.kill()

	card_ui.card_face.visual_state = CardFace.VisualState.NORMAL
	card_ui.reparent_requested.emit(card_ui)
	card_ui.set_debug_state(Color.WEB_GREEN, "BASE")
	card_ui.pivot_offset = Vector2.ZERO
	Events.tooltip_hide_requested.emit()


func on_gui_input(event: InputEvent) -> void:
	if not card_ui.playable or card_ui.disabled:
		return

	if mouse_over_card and event.is_action_pressed("left_mouse"):
		card_ui.pivot_offset = card_ui.get_global_mouse_position() - card_ui.global_position
		transition_requested.emit(self, CardState.State.CLICKED)


func on_mouse_entered() -> void:
	mouse_over_card = true

	if not card_ui.playable or card_ui.disabled:
		return

	card_ui.card_face.visual_state = CardFace.VisualState.HOVER
	card_ui.request_tooltip()


func on_mouse_exited() -> void:
	mouse_over_card = false

	if not card_ui.playable or card_ui.disabled:
		return

	card_ui.card_face.visual_state = CardFace.VisualState.NORMAL
	Events.tooltip_hide_requested.emit()
