class_name BattleOverPanel
extends Panel

enum Type {WIN, LOSE}

@onready var label: Label = %Label
@onready var continue_button: Button = %ContinueButton
@onready var main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	continue_button.pressed.connect(func(): Events.battle_won.emit())
	# The original "Restart" button reloaded the battle in place, which left
	# freed tweens running and soft-locked the game. Leaving the scene entirely
	# is what fixes it. (S02 finale - Bug Fix 8)
	main_menu_button.text = "Overworld"
	main_menu_button.pressed.connect(_on_quit_pressed)
	Events.battle_over_screen_requested.connect(show_screen)


func show_screen(text: String, type: Type) -> void:
	label.text = text
	continue_button.visible = type == Type.WIN
	main_menu_button.visible = type == Type.LOSE
	show()
	get_tree().paused = true


func _on_quit_pressed() -> void:
	get_tree().paused = false
	GameState.end_run()
	GameState.return_to_overworld()
