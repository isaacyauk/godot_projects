extends CardState


func enter() -> void:
	card_ui.set_debug_state(Color.DARK_VIOLET, "RELEASED")

	if card_ui.targets.is_empty():
		return

	var single_targeted := card_ui.card.is_single_targeted()
	var first_target_is_enemy := card_ui.targets[0] is BattleEnemy

	if single_targeted and not first_target_is_enemy:
		return

	Events.tooltip_hide_requested.emit()
	card_ui.play()


# Snapping back happens here instead of in on_input(), otherwise an unplayed
# card stays frozen in mid-air until the mouse moves again on Linux/macOS.
# (S02 finale - Bug Fix 7)
func post_enter() -> void:
	transition_requested.emit(self, CardState.State.BASE)
