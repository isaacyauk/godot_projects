class_name CardState
extends Node

enum State {BASE, CLICKED, DRAGGING, AIMING, RELEASED}

signal transition_requested(from: CardState, to: State)

@export var state: State

var card_ui: CardUI


func enter() -> void:
	pass


func exit() -> void:
	pass


## Called by the state machine right after this state becomes the current one.
## Use it for work that must happen without waiting for the next input event.
## (S02 finale — Bug Fix 7)
func post_enter() -> void:
	pass


func on_input(_event: InputEvent) -> void:
	pass


func on_gui_input(_event: InputEvent) -> void:
	pass


func on_mouse_entered() -> void:
	pass


func on_mouse_exited() -> void:
	pass
