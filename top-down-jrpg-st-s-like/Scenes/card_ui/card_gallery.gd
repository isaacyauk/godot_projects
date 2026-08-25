extends Control

## Every card in the game, on one screen. Press F6 with this scene open.
##
## This is the iteration loop for card art: change something in
## card_styles/default_card_style.tres or in card_face.tscn, run this, see all
## of it at once. It also catches names that overflow and tooltips whose %s
## placeholders don't match their effect list.

const CARD_FACE := preload("res://Scenes/card_ui/card_face.tscn")

## Folders scanned for card resources, non-recursively.
@export var card_folders: PackedStringArray = [
	"res://characters/warrior/cards",
	"res://common_cards",
]
## Assign a different CardStyle here to preview it without touching the default.
@export var preview_style: CardStyle
## Show every card a second time in its upgraded form.
@export var show_upgraded := true

@onready var grid: GridContainer = %Grid
@onready var title: Label = %Title


func _ready() -> void:
	for child in grid.get_children():
		child.queue_free()

	var cards := _collect_cards()
	cards.sort_custom(func(a, b): return a.id < b.id)

	for card: Card in cards:
		_add_face(card)

		if show_upgraded and card.is_upgradable():
			var upgraded: Card = card.duplicate()
			upgraded.upgrade()
			_add_face(upgraded)

	title.text = "%d cards" % grid.get_child_count()


func _collect_cards() -> Array[Card]:
	var found: Array[Card] = []

	for folder: String in card_folders:
		var dir := DirAccess.open(folder)
		if not dir:
			push_warning("Card gallery: no folder at %s" % folder)
			continue

		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := ResourceLoader.load(folder.path_join(file))
				if res is Card:
					# duplicate() so previewing an upgrade never writes back
					# to the resource on disk
					found.append(res.duplicate())
			file = dir.get_next()
		dir.list_dir_end()

	return found


func _add_face(card: Card) -> void:
	var face := CARD_FACE.instantiate() as CardFace
	grid.add_child(face)

	if preview_style:
		face.style = preview_style

	face.card = card
