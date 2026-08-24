class_name CardSelectionView
extends Control

## Full-screen deck browser where clicking a card *picks* it instead of just
## showing its tooltip. Used by the campfire Forge (S02E09) and by the shop's
## card removal service (S02E07-E08).

signal card_selected(card: Card)
signal cancelled

const CARD_MENU_UI_SCENE := preload("res://Scenes/ui/card_menu_ui.tscn")

@export var card_pile: CardPile

@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
@onready var cards: GridContainer = %Cards
@onready var back_button: Button = %BackButton

var _filter: Callable
var _locked := false


func _ready() -> void:
	back_button.pressed.connect(_on_cancelled)

	for card: Node in cards.get_children():
		card.queue_free()

	hide()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancelled()


func show_selection(new_title: String, new_subtitle: String = "", card_filter: Callable = Callable()) -> void:
	_locked = false
	_filter = card_filter
	title.text = new_title
	subtitle.text = new_subtitle
	subtitle.visible = not new_subtitle.is_empty()

	for card: Node in cards.get_children():
		card.queue_free()

	_populate.call_deferred()


func _populate() -> void:
	if not card_pile:
		return

	for card: Card in card_pile.cards:
		if _filter.is_valid() and not _filter.call(card):
			continue

		var new_card := CARD_MENU_UI_SCENE.instantiate() as CardMenuUI
		cards.add_child(new_card)
		new_card.card = card
		new_card.tooltip_requested.connect(_on_card_picked)

	show()


func _on_card_picked(card: Card) -> void:
	# Guards against a double click landing on two different cards while the
	# view is fading out.
	if _locked:
		return

	_locked = true
	hide()
	card_selected.emit(card)


func _on_cancelled() -> void:
	if _locked:
		return

	_locked = true
	hide()
	cancelled.emit()
