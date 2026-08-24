extends Card

var base_damage := 6
var extra_damage_after_use := 4


func get_damage() -> int:
	return base_damage + upgrade_power


func get_default_tooltip() -> String:
	return tooltip_text % [get_damage(), extra_damage_after_use]


func get_updated_tooltip(player_modifiers: ModifierHandler, enemy_modifiers: ModifierHandler) -> String:
	var modified_dmg := player_modifiers.get_modified_value(get_damage(), Modifier.Type.DMG_DEALT)

	if enemy_modifiers:
		modified_dmg = enemy_modifiers.get_modified_value(modified_dmg, Modifier.Type.DMG_TAKEN)

	return tooltip_text % [modified_dmg, extra_damage_after_use]


func apply_effects(targets: Array[Node], modifiers: ModifierHandler) -> void:
	var damage_effect := DamageEffect.new()
	damage_effect.amount = modifiers.get_modified_value(get_damage(), Modifier.Type.DMG_DEALT)
	damage_effect.sound = sound
	damage_effect.execute(targets)

	# Ramps up for the rest of the battle only: base_damage is a plain var, so
	# it resets when the deck is copied into the next battle's draw pile.
	base_damage += extra_damage_after_use


func _apply_upgrade() -> void:
	upgrade_power = 2
