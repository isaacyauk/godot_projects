class_name CardMenuUI
extends CenterContainer

signal tooltip_requested(card: Card)

@export var card: Card : set = set_card

@onready var visuals: CardFace = $Visuals


func _on_visuals_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("left_mouse"):
		tooltip_requested.emit(card)


func _on_visuals_mouse_entered() -> void:
	visuals.visual_state = CardFace.VisualState.HOVER


func _on_visuals_mouse_exited() -> void:
	visuals.visual_state = CardFace.VisualState.NORMAL


func set_card(value: Card) -> void:
	if not is_node_ready():
		await ready

	card = value
	visuals.card = card
