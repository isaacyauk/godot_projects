class_name Card
extends Resource

# NOTE: DEFEND occupies the same slot the tutorial calls SKILL, so existing
# .tres files that were authored with `type = 1` keep working unchanged.
enum Type {ATTACK, DEFEND, POWER}
enum Rarity {COMMON, UNCOMMON, RARE}
enum Target {SELF, SINGLE_ENEMY, ALL_ENEMIES, EVERYONE}

const RARITY_COLORS := {
	Card.Rarity.COMMON: Color.GRAY,
	Card.Rarity.UNCOMMON: Color.CORNFLOWER_BLUE,
	Card.Rarity.RARE: Color.GOLD,
}

const UPGRADE_SUFFIX := "+"

@export_group("Card Attributes")
@export var id: String
@export var type: Type
@export var rarity: Rarity
@export var target: Target
@export var cost: int
@export var exhausts: bool = false

@export_group("Card Upgrades")
## Whether this card can be forged at a campfire.
@export var can_upgrade: bool = true
## Set automatically by upgrade(); persisted so saved/copied cards stay upgraded.
@export var upgraded: bool = false
## How much cheaper the card gets when upgraded. 0 means "no cost change".
@export var upgrade_cost_reduction: int = 0
## Numeric bonus granted by upgrade(), interpreted by each concrete card
## (extra damage, extra block, ...). Exported on purpose: plain script vars are
## NOT carried over by Resource.duplicate(), so an upgrade stored in a plain var
## would silently vanish the moment the deck is copied into the draw pile.
@export var upgrade_power: int = 0

@export_group("Card Visuals")
@export var icon: Texture
@export_multiline var tooltip_text: String
@export var sound: AudioStream


func is_single_targeted() -> bool:
	return target == Target.SINGLE_ENEMY


func _get_targets(targets: Array[Node]) -> Array[Node]:
	if not targets:
		return []

	var tree := targets[0].get_tree()

	match target:
		Target.SELF:
			return tree.get_nodes_in_group("player")
		Target.ALL_ENEMIES:
			return tree.get_nodes_in_group("enemies")
		Target.EVERYONE:
			return tree.get_nodes_in_group("player") + tree.get_nodes_in_group("enemies")
		_:
			return []


func play(targets: Array[Node], char_stats: CharacterStats, modifiers: ModifierHandler) -> void:
	Events.card_played.emit(self)
	char_stats.mana -= cost

	if is_single_targeted():
		apply_effects(targets, modifiers)
	else:
		apply_effects(_get_targets(targets), modifiers)


func apply_effects(_targets: Array[Node], _modifiers: ModifierHandler) -> void:
	pass


func get_default_tooltip() -> String:
	return tooltip_text


func get_updated_tooltip(_player_modifiers: ModifierHandler, _enemy_modifiers: ModifierHandler) -> String:
	return tooltip_text


#region Upgrades (S02E03)
## Returns false when the card is already upgraded or is flagged as non-upgradable.
func is_upgradable() -> bool:
	return can_upgrade and not upgraded


## Upgrades this card in place. Concrete cards override _apply_upgrade() to
## bump their own numbers; this method only handles the shared bookkeeping.
func upgrade() -> void:
	if not is_upgradable():
		return

	upgraded = true

	if upgrade_cost_reduction > 0:
		cost = maxi(0, cost - upgrade_cost_reduction)

	if not id.ends_with(UPGRADE_SUFFIX):
		id += UPGRADE_SUFFIX

	if not resource_name.is_empty() and not resource_name.ends_with(UPGRADE_SUFFIX):
		resource_name += UPGRADE_SUFFIX

	_apply_upgrade()


## Override this in a concrete card script to scale its damage/block/draw.
func _apply_upgrade() -> void:
	pass


func get_display_name() -> String:
	return id
#endregion
