@tool  # card_face.gd previews cards live in the editor; a @tool script can
       # only call methods on other @tool scripts, otherwise Godot hands it a
       # placeholder instance and every method call fails.
class_name CardStyle
extends Resource

## Every visual decision a card face makes, in one resource.
##
## Swap fonts, frame art, colours and state feedback here and every card in the
## game changes at once -- the hand, the deck view, the shop, card rewards and
## the tooltip all render through the same CardFace scene.
##
## Art fields are all optional. While a texture is null the face draws a flat
## placeholder colour instead; the moment you assign a texture the placeholder
## disappears. That is the whole upgrade path -- no scene surgery, no code.

@export_group("Fonts")
## Leave any font null to inherit whatever the surrounding Theme provides.
@export var name_font: Font
@export var name_font_size := 13
@export var cost_font: Font
@export var cost_font_size := 26
@export var type_font: Font
@export var type_font_size := 13
@export var text_font: Font
@export var text_font_size := 13

@export_subgroup("Line Spacing")
## Pixel fonts often ship with generous line metrics. These trim the gap
## between wrapped lines so two-word names and three-line rules text fit the
## boxes in card_face.tscn. Retune after swapping a font.
@export_range(-12, 12) var name_line_spacing := -2
@export_range(-12, 12) var text_line_spacing := -2

@export_group("Frame Art", "frame_")
## Nine-patch frames, one per card type. Null = flat placeholder colour.
@export var frame_attack: Texture2D
@export var frame_defend: Texture2D
@export var frame_power: Texture2D
## Nine-patch margin applied to whichever frame texture is in use.
@export var frame_patch_margin := 4

@export_group("Other Art")
@export var cost_badge_texture: Texture2D
@export var banner_texture: Texture2D
@export var rarity_pip_texture: Texture2D
## Drawn in the art window when a card has no icon of its own.
@export var art_fallback_texture: Texture2D

@export_group("Placeholder Colours", "color_")
@export var color_attack := Color(0.42, 0.20, 0.20)
@export var color_defend := Color(0.19, 0.28, 0.42)
@export var color_power := Color(0.32, 0.22, 0.40)
@export var color_art_backing := Color(0.11, 0.12, 0.15)
@export var color_banner := Color(0.08, 0.09, 0.11, 0.85)
@export var color_text_backing := Color(0.13, 0.14, 0.17)
@export var color_cost_badge := Color(0.09, 0.10, 0.13)

@export_group("Text Colours", "ink_")
@export var ink_name := Color(0.96, 0.96, 0.94)
@export var ink_cost := Color(1, 1, 1)
@export var ink_type := Color(0.75, 0.78, 0.84)
@export var ink_text := Color(0.88, 0.90, 0.94)

@export_group("Rarity", "rarity_")
@export var rarity_common := Color(0.62, 0.64, 0.68)
@export var rarity_uncommon := Color(0.39, 0.58, 0.93)
@export var rarity_rare := Color(0.91, 0.76, 0.28)

@export_group("State Feedback", "state_")
## Whole-card modulate per interaction state.
@export var state_normal := Color(1, 1, 1, 1)
@export var state_hover := Color(1.18, 1.18, 1.18, 1)
@export var state_dragging := Color(1, 1, 1, 0.9)
## Applied on top of the above when the player cannot afford the card.
@export var state_unplayable := Color(0.5, 0.5, 0.58, 1)
## How far the card lifts, in pixels, while hovered.
@export var state_hover_lift := 8

@export_group("Type Labels", "label_")
## What the banner reads for each card type. Purely cosmetic.
@export var label_attack := "ATTACK"
@export var label_defend := "SKILL"
@export var label_power := "POWER"


func frame_texture_for(type: int) -> Texture2D:
	match type:
		Card.Type.ATTACK: return frame_attack
		Card.Type.DEFEND: return frame_defend
		Card.Type.POWER:  return frame_power
	return frame_attack


func frame_color_for(type: int) -> Color:
	match type:
		Card.Type.ATTACK: return color_attack
		Card.Type.DEFEND: return color_defend
		Card.Type.POWER:  return color_power
	return color_attack


func label_for(type: int) -> String:
	match type:
		Card.Type.ATTACK: return label_attack
		Card.Type.DEFEND: return label_defend
		Card.Type.POWER:  return label_power
	return ""


func rarity_color_for(rarity: int) -> Color:
	match rarity:
		Card.Rarity.COMMON:   return rarity_common
		Card.Rarity.UNCOMMON: return rarity_uncommon
		Card.Rarity.RARE:     return rarity_rare
	return rarity_common
