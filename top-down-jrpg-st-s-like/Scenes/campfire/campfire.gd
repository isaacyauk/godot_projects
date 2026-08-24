class_name Campfire
extends Control

const HEAL_PERCENT := 0.3

@export var char_stats: CharacterStats

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var rest_button: Button = %RestButton
@onready var forge_button: Button = %ForgeButton
@onready var card_selection_view: CardSelectionView = %CardSelectionView


func _ready() -> void:
	card_selection_view.card_selected.connect(_on_card_to_upgrade_selected)
	card_selection_view.cancelled.connect(_on_forge_cancelled)


func _on_rest_button_pressed() -> void:
	# Disabling on the very first click is what stops spam-clicking during the
	# fade-out from healing several times. (S02 finale - Bug Fix 2)
	rest_button.disabled = true
	forge_button.disabled = true
	char_stats.heal(ceili(char_stats.max_health * HEAL_PERCENT))
	animation_player.play("fade_out")


func _on_forge_button_pressed() -> void:
	forge_button.disabled = true
	rest_button.disabled = true

	if not char_stats or not char_stats.deck:
		return

	card_selection_view.card_pile = char_stats.deck
	card_selection_view.show_selection(
		"Forge",
		"Pick a card to upgrade",
		func(card: Card): return card.is_upgradable()
	)


func _on_card_to_upgrade_selected(card: Card) -> void:
	if not card:
		_on_forge_cancelled()
		return

	card.upgrade()
	Events.card_upgraded.emit(card)
	animation_player.play("fade_out")


func _on_forge_cancelled() -> void:
	forge_button.disabled = false
	rest_button.disabled = false


# This is called from the AnimationPlayer
# at the end of 'fade_out'.
func _on_fade_out_finished() -> void:
	Events.campfire_exited.emit()
