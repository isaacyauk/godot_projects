@tool  # card_face.gd previews cards live in the editor; a @tool script can
       # only call methods on other @tool scripts, otherwise Godot hands it a
       # placeholder instance and every method call fails.
extends Card

var base_damage := 6


func get_damage() -> int:
	return base_damage + upgrade_power


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


func _apply_upgrade() -> void:
	upgrade_power = 3
