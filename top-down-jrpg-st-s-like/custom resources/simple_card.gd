@tool  # card_face.gd previews cards live in the editor; a @tool script can
       # only call methods on other @tool scripts, otherwise Godot hands it a
       # placeholder instance and every method call fails.
class_name SimpleCard
extends Card

## A card with no script of its own.
##
## Making a new card is: duplicate an existing SimpleCard .tres, change the
## name, cost, target and the effect list, done. No .gd file, no code.
##
## The tooltip is written with %s placeholders, filled in order from every spec
## with `show_in_tooltip` on -- so the numbers the player reads are always the
## numbers that will actually land, modifiers included.
##
##   tooltip_text : "[center]Deal [color=ff0000]%s[/color] damage.[/center]"
##   effects      : [ DAMAGE, amount 6, upgrade_bonus 3 ]
##
## Reach for a dedicated script only when a card needs to do something this
## can't express -- see warrior_sharp_knife.gd for one that ramps mid-combat.

@export var effects: Array[CardEffectSpec] = []


func apply_effects(targets: Array[Node], modifiers: ModifierHandler) -> void:
	for spec: CardEffectSpec in effects:
		if not spec:
			continue

		var effect := spec.build_effect(upgraded, modifiers, sound)
		if effect:
			effect.execute(targets)


func get_default_tooltip() -> String:
	return _format_tooltip(null, null)


func get_updated_tooltip(player_modifiers: ModifierHandler, enemy_modifiers: ModifierHandler) -> String:
	return _format_tooltip(player_modifiers, enemy_modifiers)


func _format_tooltip(player_mods: ModifierHandler, enemy_mods: ModifierHandler) -> String:
	var values := []

	for spec: CardEffectSpec in effects:
		if not spec:
			continue

		var v := spec.tooltip_value(upgraded, player_mods, enemy_mods)
		if v >= 0:
			values.append(v)

	if values.is_empty():
		return tooltip_text

	# A tooltip with fewer placeholders than values would throw, so format
	# defensively -- a half-written card should look wrong, not crash.
	if tooltip_text.count("%s") != values.size():
		return tooltip_text

	return tooltip_text % values


func _apply_upgrade() -> void:
	# Each spec carries its own upgrade_bonus, so there is nothing to scale
	# here. This exists so is_upgradable() and the "+" suffix still work.
	upgrade_power = 1
