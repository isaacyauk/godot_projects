@tool  # card_face.gd previews cards live in the editor; a @tool script can
       # only call methods on other @tool scripts, otherwise Godot hands it a
       # placeholder instance and every method call fails.
extends Card

const EXPOSED_STATUS = preload("res://statuses/exposed.tres")

var base_damage := 4
var base_exposed_duration := 2


func get_damage() -> int:
	return base_damage + upgrade_power


func get_exposed_duration() -> int:
	return base_exposed_duration + (1 if upgraded else 0)


func get_default_tooltip() -> String:
	return tooltip_text % get_damage()


func get_updated_tooltip(player_modifiers: ModifierHandler, enemy_modifiers: ModifierHandler) -> String:
	var modified_dmg := player_modifiers.get_modified_value(get_damage(), Modifier.Type.DMG_DEALT)

	if enemy_modifiers:
		modified_dmg = enemy_modifiers.get_modified_value(modified_dmg, Modifier.Type.DMG_TAKEN)

	return tooltip_text % modified_dmg


func apply_effects(targets: Array[Node], modifiers: ModifierHandler) -> void:
	var damage_effect := DamageEffect.new()
	damage_effect.amount = modifiers.get_modified_value(get_damage(), Modifier.Type.DMG_DEALT)
	damage_effect.sound = sound
	damage_effect.execute(targets)

	var status_effect := StatusEffect.new()
	var exposed := EXPOSED_STATUS.duplicate()
	exposed.duration = get_exposed_duration()
	status_effect.status = exposed
	status_effect.execute(targets)


func _apply_upgrade() -> void:
	upgrade_power = 3
