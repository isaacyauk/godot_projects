@tool
class_name CardFace
extends Control

## The progenitor card face. Every card the player ever sees -- in hand, in the
## deck view, on the shop shelf, in a reward pick, inside a tooltip -- is an
## instance of card_face.tscn.
##
## Three things feed it, and they are deliberately separate:
##
##   LAYOUT   lives in card_face.tscn. Move a node, resize the art window,
##            reorder things -- this script never fights you for position.
##   LOOK     lives in a CardStyle resource. Fonts, frame art, colours.
##   CONTENT  comes from the Card resource handed to it.
##
## It runs as a @tool script, so editing the scene or the style resource
## redraws the card live in the editor.

enum VisualState { NORMAL, HOVER, DRAGGING }

const DEFAULT_STYLE := preload("res://card_styles/default_card_style.tres")

@export var card: Card : set = set_card
## Leave null to use res://card_styles/default_card_style.tres.
@export var style: CardStyle : set = set_style
## Redraw in the editor after you change something.
@export var refresh_in_editor := false : set = _editor_refresh

@onready var frame_color: ColorRect = $FrameColor
@onready var frame_texture: NinePatchRect = $FrameTexture
@onready var art_backing: ColorRect = $ArtBacking
@onready var art: TextureRect = $Art
@onready var banner_color: ColorRect = $BannerColor
@onready var banner_texture: NinePatchRect = $BannerTexture
@onready var type_label: Label = $TypeLabel
@onready var text_backing: ColorRect = $TextBacking
@onready var text_label: RichTextLabel = $TextLabel
@onready var name_label: Label = $NameLabel
@onready var cost_badge_color: ColorRect = $CostBadgeColor
@onready var cost_badge_texture: TextureRect = $CostBadgeTexture
@onready var cost_label: Label = $CostLabel
@onready var rarity_pip: ColorRect = $RarityPip
@onready var rarity_pip_texture: TextureRect = $RarityPipTexture

var visual_state: VisualState = VisualState.NORMAL : set = set_visual_state
var playable := true : set = set_playable

var _base_position_y := 0.0
var _captured_base_y := false


func _ready() -> void:
	_base_position_y = position.y
	_captured_base_y = true
	redraw()


#region Public API
func set_card(value: Card) -> void:
	card = value
	redraw()


func set_style(value: CardStyle) -> void:
	style = value
	redraw()


func set_visual_state(value: VisualState) -> void:
	visual_state = value
	_apply_state()


func set_playable(value: bool) -> void:
	playable = value
	_apply_state()


## Returns the style actually in use, falling back to the project default.
func active_style() -> CardStyle:
	return style if style else DEFAULT_STYLE


## Rebuilds everything from `card` and `style`. Safe to call at any time.
func redraw() -> void:
	if not is_node_ready():
		return

	var s := active_style()
	if not s:
		return

	_apply_fonts(s)
	_apply_frame(s)
	_apply_content(s)
	_apply_state()
#endregion


#region Drawing
func _apply_fonts(s: CardStyle) -> void:
	_set_font(name_label, s.name_font, s.name_font_size, s.ink_name)
	_set_font(cost_label, s.cost_font, s.cost_font_size, s.ink_cost)
	_set_font(type_label, s.type_font, s.type_font_size, s.ink_type)
	_set_rich_font(text_label, s.text_font, s.text_font_size, s.ink_text)

	name_label.add_theme_constant_override("line_spacing", s.name_line_spacing)
	text_label.add_theme_constant_override("line_separation", s.text_line_spacing)


func _apply_frame(s: CardStyle) -> void:
	var type: int = card.type if card else Card.Type.ATTACK

	# Frame: texture wins when present, placeholder colour otherwise.
	var frame_tex := _frame_texture(s, type)
	frame_texture.texture = frame_tex
	frame_texture.visible = frame_tex != null
	frame_color.visible = frame_tex == null
	frame_color.color = _frame_color(s, type)

	if frame_tex:
		var m := s.frame_patch_margin
		frame_texture.patch_margin_left = m
		frame_texture.patch_margin_top = m
		frame_texture.patch_margin_right = m
		frame_texture.patch_margin_bottom = m

	# Banner.
	banner_texture.texture = s.banner_texture
	banner_texture.visible = s.banner_texture != null
	banner_color.visible = s.banner_texture == null
	banner_color.color = s.color_banner

	# Cost badge.
	cost_badge_texture.texture = s.cost_badge_texture
	cost_badge_texture.visible = s.cost_badge_texture != null
	cost_badge_color.visible = s.cost_badge_texture == null
	cost_badge_color.color = s.color_cost_badge

	art_backing.color = s.color_art_backing
	text_backing.color = s.color_text_backing


func _apply_content(s: CardStyle) -> void:
	if not card:
		name_label.text = "Card"
		cost_label.text = "0"
		type_label.text = s.label_attack
		text_label.text = ""
		art.texture = s.art_fallback_texture
		rarity_pip.color = s.rarity_common
		rarity_pip_texture.visible = false
		rarity_pip.visible = true
		return

	name_label.text = _display_name()
	cost_label.text = str(card.cost)
	type_label.text = _type_label(s, card.type)
	text_label.text = _rules_text()

	var icon: Texture2D = card.icon if card.icon else s.art_fallback_texture
	art.texture = icon
	art.visible = icon != null

	var rarity_color := _rarity_color(s, card.rarity)
	if s.rarity_pip_texture:
		rarity_pip_texture.texture = s.rarity_pip_texture
		rarity_pip_texture.modulate = rarity_color
		rarity_pip_texture.visible = true
		rarity_pip.visible = false
	else:
		rarity_pip.color = rarity_color
		rarity_pip.visible = true
		rarity_pip_texture.visible = false


func _apply_state() -> void:
	if not is_node_ready():
		return

	var s := active_style()
	if not s:
		return

	var tint: Color
	match visual_state:
		VisualState.HOVER:    tint = s.state_hover
		VisualState.DRAGGING: tint = s.state_dragging
		_:                    tint = s.state_normal

	if not playable:
		tint *= s.state_unplayable

	modulate = tint

	# The lift is a position nudge rather than an animation so it composes with
	# the hand's own tweening instead of fighting it.
	if _captured_base_y and not Engine.is_editor_hint():
		var lift := s.state_hover_lift if visual_state == VisualState.HOVER else 0
		position.y = _base_position_y - lift
#endregion


#region Editor-safe reads
## In the editor, Godot gives non-@tool scripts a "placeholder instance":
## properties read fine but calling a method fails outright. Rather than
## require @tool on every card script anyone ever writes, the preview checks
## first and falls back to plain property reads.
##
## At runtime this always returns true, so the real game pays nothing.
func _callable(res: Resource) -> bool:
	if not Engine.is_editor_hint():
		return true
	if res == null:
		return false

	var sc := res.get_script() as Script
	return sc == null or sc.is_tool()


func _display_name() -> String:
	if _callable(card):
		return card.get_display_name()

	# Fallback: the same shape get_display_name() produces, from properties only.
	var base: String = card.card_name
	if base.is_empty():
		base = card.id
		for prefix in ["warrior_", "wizard_", "assassin_"]:
			base = base.trim_prefix(prefix)
		base = base.trim_suffix("+").capitalize()
	if card.upgraded and not base.ends_with("+"):
		base += "+"
	return base


func _rules_text() -> String:
	if _callable(card):
		return card.get_default_tooltip()

	return card.tooltip_text


func _frame_texture(s: CardStyle, type: int) -> Texture2D:
	if _callable(s):
		return s.frame_texture_for(type)

	match type:
		Card.Type.DEFEND: return s.frame_defend
		Card.Type.POWER:  return s.frame_power
		_:                return s.frame_attack


func _frame_color(s: CardStyle, type: int) -> Color:
	if _callable(s):
		return s.frame_color_for(type)

	match type:
		Card.Type.DEFEND: return s.color_defend
		Card.Type.POWER:  return s.color_power
		_:                return s.color_attack


func _type_label(s: CardStyle, type: int) -> String:
	if _callable(s):
		return s.label_for(type)

	match type:
		Card.Type.DEFEND: return s.label_defend
		Card.Type.POWER:  return s.label_power
		_:                return s.label_attack


func _rarity_color(s: CardStyle, rarity: int) -> Color:
	if _callable(s):
		return s.rarity_color_for(rarity)

	match rarity:
		Card.Rarity.UNCOMMON: return s.rarity_uncommon
		Card.Rarity.RARE:     return s.rarity_rare
		_:                    return s.rarity_common
#endregion


#region Helpers
func _set_font(label: Label, font: Font, size: int, color: Color) -> void:
	if not label:
		return

	if font:
		label.add_theme_font_override("font", font)
	else:
		label.remove_theme_font_override("font")

	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


func _set_rich_font(label: RichTextLabel, font: Font, size: int, color: Color) -> void:
	if not label:
		return

	if font:
		label.add_theme_font_override("normal_font", font)
	else:
		label.remove_theme_font_override("normal_font")

	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_color_override("default_color", color)


func _editor_refresh(_value: bool) -> void:
	refresh_in_editor = false
	redraw()
#endregion
