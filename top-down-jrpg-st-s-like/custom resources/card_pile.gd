class_name CardPile
extends Resource

signal card_pile_size_changed(cards_amount)

@export var cards: Array[Card] = []


func empty() -> bool:
	return cards.is_empty()


func draw_card() -> Card:
	var card = cards.pop_front() # Bear in mind that a refactor here might be necessary one day. Popping from front vs back can be resource intensive in SOME cases
	card_pile_size_changed.emit(cards.size())
	return card


func add_card(card: Card) -> void:
	cards.append(card)
	card_pile_size_changed.emit(cards.size())


func remove_card(card: Card) -> void:
	var index := cards.find(card)
	if index == -1:
		return

	cards.remove_at(index)
	card_pile_size_changed.emit(cards.size())


func shuffle() -> void:
	RNG.array_shuffle(cards)


func clear() -> void:
	cards.clear()
	card_pile_size_changed.emit(cards.size())


# Godot's built-in duplicate(true) does not deep-copy Resources held in a
# typed Array, so in-battle card mutations (temporary 0-cost effects, the
# Sharp Knife ramp, Confusing Staff, ...) would leak back into the persistent
# deck. These two helpers do the copy explicitly.
# See https://github.com/godotengine/godot/issues/74918
# (S02 finale — Bug Fix 5)
func duplicate_cards() -> Array[Card]:
	var new_array: Array[Card] = []

	for card: Card in cards:
		new_array.append(card.duplicate())

	return new_array


func custom_duplicate() -> CardPile:
	var new_card_pile := CardPile.new()
	new_card_pile.cards = duplicate_cards()

	return new_card_pile


func _to_string() -> String:
	var _card_strings: PackedStringArray = []
	for i in range(cards.size()):
		_card_strings.append("%s: %s" % [i + 1, cards[i].id])
	return "\n".join(_card_strings)
