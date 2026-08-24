class_name Shop
extends Control

const SHOP_CARD = preload("res://Scenes/shop/shop_card.tscn")
const SHOP_RELIC = preload("res://Scenes/shop/shop_relic.tscn")

## Card removal service (S02E07-E08). The price goes up every time the player
## uses it during a run.
const BASE_REMOVAL_COST := 75
const REMOVAL_COST_INCREASE := 25
## The player should always be left with a playable deck.
const MIN_DECK_SIZE := 5

@export var shop_relics: Array[Relic]
@export var char_stats: CharacterStats
@export var run_stats: RunStats
@export var relic_handler: RelicHandler

@onready var cards: HBoxContainer = %Cards
@onready var relics: HBoxContainer = %Relics
@onready var shop_keeper_animation: AnimationPlayer = %ShopkeeperAnimation
@onready var blink_timer: Timer = %BlinkTimer
@onready var card_tooltip_popup: CardTooltipPopup = %CardTooltipPopup
@onready var modifier_handler: ModifierHandler = $ModifierHandler
@onready var remove_card_button: Button = %RemoveCardButton
@onready var removal_price_label: Label = %RemovalPriceLabel
@onready var card_selection_view: CardSelectionView = %CardSelectionView


func _ready() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.queue_free()

	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.queue_free()

	Events.shop_card_bought.connect(_on_shop_card_bought)
	Events.shop_relic_bought.connect(_on_shop_relic_bought)

	remove_card_button.pressed.connect(_on_remove_card_button_pressed)
	card_selection_view.card_selected.connect(_on_card_to_remove_selected)
	card_selection_view.cancelled.connect(_update_removal_service)

	_blink_timer_setup()
	blink_timer.timeout.connect(_on_blink_timer_timeout)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and card_tooltip_popup.visible:
		card_tooltip_popup.hide_tooltip()


func populate_shop() -> void:
	_generate_shop_cards()
	_generate_shop_relics()
	_update_removal_service()


func _blink_timer_setup() -> void:
	blink_timer.wait_time = randf_range(1.0, 5.0)
	blink_timer.start()


func _generate_shop_cards() -> void:
	var shop_card_array: Array[Card] = []
	var available_cards: Array[Card] = char_stats.draftable_cards.duplicate_cards()
	RNG.array_shuffle(available_cards)
	shop_card_array = available_cards.slice(0, 3)

	for card: Card in shop_card_array:
		var new_shop_card := SHOP_CARD.instantiate() as ShopCard
		cards.add_child(new_shop_card)
		new_shop_card.card = card
		new_shop_card.current_card_ui.tooltip_requested.connect(card_tooltip_popup.show_tooltip)
		new_shop_card.gold_cost = _get_updated_shop_cost(new_shop_card.gold_cost)
		new_shop_card.update(run_stats)


func _generate_shop_relics() -> void:
	var shop_relics_array: Array[Relic] = []
	var available_relics := shop_relics.filter(
		func(relic: Relic):
			var can_appear := relic.can_appear_as_reward(char_stats)
			var already_had_it := relic_handler.has_relic(relic.id)
			return can_appear and not already_had_it
	)

	RNG.array_shuffle(available_relics)
	shop_relics_array = available_relics.slice(0, 3)

	for relic: Relic in shop_relics_array:
		# Guard: once every relic has been collected this list is empty and the
		# old code indexed straight past the end. (S02 finale - Bug Fix 9)
		if not relic:
			continue

		var new_shop_relic := SHOP_RELIC.instantiate() as ShopRelic
		relics.add_child(new_shop_relic)
		new_shop_relic.relic = relic
		new_shop_relic.gold_cost = _get_updated_shop_cost(new_shop_relic.gold_cost)
		new_shop_relic.update(run_stats)


func _update_items() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.update(run_stats)

	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.update(run_stats)

	_update_removal_service()


func _update_item_costs() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.gold_cost = _get_updated_shop_cost(shop_card.gold_cost)
		shop_card.update(run_stats)

	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.gold_cost = _get_updated_shop_cost(shop_relic.gold_cost)
		shop_relic.update(run_stats)

	_update_removal_service()


func _get_updated_shop_cost(original_cost: int) -> int:
	return modifier_handler.get_modified_value(original_cost, Modifier.Type.SHOP_COST)


#region Card removal service
func get_removal_cost() -> int:
	if not run_stats:
		return BASE_REMOVAL_COST

	var base: int = BASE_REMOVAL_COST + run_stats.cards_removed * REMOVAL_COST_INCREASE
	return _get_updated_shop_cost(base)


func _update_removal_service() -> void:
	if not is_node_ready() or not run_stats or not char_stats:
		return

	var cost := get_removal_cost()
	removal_price_label.text = str(cost)

	var deck_too_small: bool = char_stats.deck.cards.size() <= MIN_DECK_SIZE
	# `>=` so that having exactly enough gold is still a purchase.
	# (S02 finale - Bug Fix 10)
	var can_afford: bool = run_stats.gold >= cost

	remove_card_button.disabled = deck_too_small or not can_afford

	if can_afford:
		removal_price_label.remove_theme_color_override("font_color")
	else:
		removal_price_label.add_theme_color_override("font_color", Color.RED)


func _on_remove_card_button_pressed() -> void:
	remove_card_button.disabled = true
	card_selection_view.card_pile = char_stats.deck
	card_selection_view.show_selection("Remove a card", "Cost: %s gold" % get_removal_cost())


func _on_card_to_remove_selected(card: Card) -> void:
	if not card:
		_update_removal_service()
		return

	var cost := get_removal_cost()

	if run_stats.gold < cost:
		_update_removal_service()
		return

	char_stats.deck.remove_card(card)
	run_stats.gold -= cost
	run_stats.cards_removed += 1
	Events.shop_card_removed.emit(card, cost)
	_update_items()
#endregion


func _on_back_button_pressed() -> void:
	Events.shop_exited.emit()


func _on_shop_card_bought(card: Card, gold_cost: int) -> void:
	char_stats.deck.add_card(card)
	run_stats.gold -= gold_cost
	_update_items()


func _on_shop_relic_bought(relic: Relic, gold_cost: int) -> void:
	relic_handler.add_relic(relic)
	run_stats.gold -= gold_cost

	if relic is CouponsRelic:
		var coupons_relic := relic as CouponsRelic
		coupons_relic.add_shop_modifier(self)
		_update_item_costs()
	else:
		_update_items()


func _on_blink_timer_timeout() -> void:
	shop_keeper_animation.play("blink")
	_blink_timer_setup()
