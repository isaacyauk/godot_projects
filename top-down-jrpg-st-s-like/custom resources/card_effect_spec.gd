@tool  # card_face.gd previews cards live in the editor; a @tool script can
       # only call methods on other @tool scripts, otherwise Godot hands it a
       # placeholder instance and every method call fails.
class_name CardEffectSpec
extends Resource

## One line of a data-driven card's behaviour, configured entirely in the
## Inspector. A SimpleCard runs its specs in order when played.
##
## Anything genuinely bespoke -- a card that ramps mid-combat, reads the deck,
## or rewrites another card -- still wants its own script. This covers the
## eighty per cent that don't.

enum Kind {
	## Damage, run through the player's DMG_DEALT and the target's DMG_TAKEN.
	DAMAGE,
	## Block on whoever the card targets.
	BLOCK,
	## Draw cards.
	DRAW,
	## Apply a Status resource to the target.
	APPLY_STATUS,
	## Exhaust N random cards from hand.
	EXHAUST_RANDOM,
	## Flat damage that ignores all modifiers.
	DAMAGE_UNMODIFIED,
}

@export var kind: Kind = Kind.DAMAGE
@export var amount := 0
## Added to `amount` once the card has been forged.
@export var upgrade_bonus := 0
## Only used by APPLY_STATUS. Duplicated per application, so one resource can
## be shared across cards safely.
@export var status: Status
## Only used by APPLY_STATUS -- how many stacks or turns to apply.
@export var status_amount := 1
@export var status_upgrade_bonus := 0
## Whether this spec's number appears in the card's tooltip. Turn it off for
## bookkeeping specs you don't want the player counting.
@export var show_in_tooltip := true


func value(upgraded: bool) -> int:
	return amount + (upgrade_bonus if upgraded else 0)


func status_value(upgraded: bool) -> int:
	return status_amount + (status_upgrade_bonus if upgraded else 0)


## The number this spec contributes to the tooltip, already modified where
## modifiers apply. Returns -1 when the spec is not shown.
func tooltip_value(upgraded: bool, player_mods: ModifierHandler, enemy_mods: ModifierHandler) -> int:
	if not show_in_tooltip:
		return -1

	match kind:
		Kind.DAMAGE:
			var dmg := value(upgraded)
			if player_mods:
				dmg = player_mods.get_modified_value(dmg, Modifier.Type.DMG_DEALT)
			if enemy_mods:
				dmg = enemy_mods.get_modified_value(dmg, Modifier.Type.DMG_TAKEN)
			return dmg
		Kind.APPLY_STATUS:
			return status_value(upgraded)
		_:
			return value(upgraded)


## Builds the runtime Effect for this spec. `modifiers` is the player's handler.
func build_effect(upgraded: bool, modifiers: ModifierHandler, sound: AudioStream) -> Effect:
	match kind:
		Kind.DAMAGE:
			var dmg := DamageEffect.new()
			var raw := value(upgraded)
			dmg.amount = modifiers.get_modified_value(raw, Modifier.Type.DMG_DEALT) if modifiers else raw
			dmg.sound = sound
			return dmg

		Kind.DAMAGE_UNMODIFIED:
			var flat := DamageEffect.new()
			flat.amount = value(upgraded)
			flat.receiver_modifier_type = Modifier.Type.NO_MODIFIER
			flat.sound = sound
			return flat

		Kind.BLOCK:
			var block := BlockEffect.new()
			block.amount = value(upgraded)
			block.sound = sound
			return block

		Kind.DRAW:
			var draw := CardDrawEffect.new()
			draw.cards_to_draw = value(upgraded)
			return draw

		Kind.EXHAUST_RANDOM:
			var exhaust := ExhaustRandomEffect.new()
			exhaust.amount = value(upgraded)
			return exhaust

		Kind.APPLY_STATUS:
			if not status:
				push_warning("CardEffectSpec: APPLY_STATUS with no status assigned.")
				return null

			var status_effect := StatusEffect.new()
			var applied: Status = status.duplicate()
			var n := status_value(upgraded)

			# Duration-stacking statuses (Exposed) count turns; intensity ones
			# (Muscle) count stacks. Setting both is harmless -- the handler
			# reads whichever the status actually uses.
			applied.duration = n
			applied.stacks = n
			status_effect.status = applied
			return status_effect

	return null
