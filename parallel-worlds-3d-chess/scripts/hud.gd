## All 2D UI, built in code so there is one place to read and change it.
##
## Covers the shared HUD elements from art doc §7: turn/player indicator,
## moves-used tracker, levels-used-this-turn tracker, level selector, the
## promotion choice modal, the pass-to-opponent interstitial and game over.
class_name HUD
extends CanvasLayer

signal undo_pressed
signal end_turn_pressed
signal view_mode_changed(mode: int)
signal promotion_chosen(piece_type: int)
signal pass_confirmed
signal restart_pressed
signal shadow_toggled(on: bool)
## Emitted only after the player confirms — leaving loses the game, because
## saving a game in progress is not written yet.
signal menu_confirmed

## Wording for the move-shadow button's hover tooltip. Here rather than inline
## so the test can assert on the same string the player reads.
const SHADOW_HINT := "Shadow a piece's moves above and below it"

const PROMOTION_CHOICES := [
	Piece.Type.QUEEN, Piece.Type.ROOK, Piece.Type.BISHOP, Piece.Type.KNIGHT,
]

## The View Boards selector. Ordered the way the stack reads on screen — top
## first — rather than by level index, which is why Bottom is level 0 and comes
## last. One table rather than parallel label and mode arrays, because the two
## have to agree and select_view() reads the same mapping the buttons were built
## from.
const VIEW_CHOICES := [
	{"label": "All", "mode": -1},
	{"label": BoardState.LEVEL_NAMES[2], "mode": 2},
	{"label": BoardState.LEVEL_NAMES[1], "mode": 1},
	{"label": BoardState.LEVEL_NAMES[0], "mode": 0},
]

var _turn_label: Label
var _moves_label: Label
var _level_chips: Array = []
var _hint_panel: PanelContainer
var _hint_label: Label
var _context_label: Label
var _status_label: Label
var _undo_button: Button
var _end_turn_button: Button
var _shadow_button: Button
var _view_buttons: Array = []

var _promotion_panel: Control
var _pass_panel: Control
var _pass_label: Label
var _gameover_panel: Control
var _gameover_label: Label
var _confirm_panel: Control
var _thinking_label: Label

var _status_timer := 0.0
## While the computer is moving there is nothing for the player to press, and
## Undo would reach into the opponent's turn.
var _thinking := false
var _think_phase := 0.0


func _ready() -> void:
	layer = 10
	_build_status_bar()
	_build_view_selector()
	_build_actions()
	_build_promotion_panel()
	_build_pass_panel()
	_build_gameover_panel()
	_build_confirm_panel()
	_build_hint()


# --- construction --------------------------------------------------------

func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 34)
	return b


func _build_status_bar() -> void:
	var panel := _panel(Color(0.01, 0.10, 0.19, 0.85), Palette.SPACE_HORIZON)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(260, 0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_turn_label = _label("White to move", 22)
	box.add_child(_turn_label)

	_moves_label = _label("", 14, Color(0.72, 0.78, 0.86))
	box.add_child(_moves_label)

	var chips_row := HBoxContainer.new()
	chips_row.add_theme_constant_override("separation", 6)
	box.add_child(chips_row)
	chips_row.add_child(_label("Moves open on", 13, Color(0.6, 0.68, 0.78)))
	for z in BoardState.LEVELS:
		var chip := _label(" %d " % (z + 1), 14)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		chip.add_theme_stylebox_override("normal", sb)
		chips_row.add_child(chip)
		_level_chips.append(chip)

	# Reads as an opponent doing something rather than as the game hanging,
	# which is the whole job of the line — the search is under half a second,
	# but a silent board is a board that looks broken.
	_thinking_label = _label("", 14, Palette.STAR_TINT)
	_thinking_label.visible = false
	box.add_child(_thinking_label)

	_context_label = _label("", 13, Palette.MOVE_SELECTED)
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.custom_minimum_size = Vector2(236, 0)
	box.add_child(_context_label)


func _build_view_selector() -> void:
	var panel := _panel(Color(0.01, 0.10, 0.19, 0.85), Palette.SPACE_HORIZON)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Pinned by its RIGHT edge and left to grow leftwards, rather than positioned
	# by a guessed width. The old -198 was sized for L1/L2/L3; "Bottom" is wider,
	# and any fixed number here goes stale the next time a label changes or the
	# font does.
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 18
	panel.offset_right = -18
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(_label("View Boards", 13, Color(0.6, 0.68, 0.78)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for i in VIEW_CHOICES.size():
		var choice: Dictionary = VIEW_CHOICES[i]
		var b := _button(String(choice["label"]), 14)
		# Wider than the old L1/L2/L3 buttons had to be: "Bottom" is six
		# characters and gets clipped at 40.
		b.custom_minimum_size = Vector2(58, 30)
		b.toggle_mode = true
		b.button_pressed = i == 0
		b.pressed.connect(_on_view_button.bind(i, int(choice["mode"])))
		row.add_child(b)
		_view_buttons.append(b)

	# Sits with the View buttons because it is the same kind of control: it
	# changes how you are looking at the stack, not what is legal.
	_shadow_button = _button("Move shadow", 14)
	_shadow_button.custom_minimum_size = Vector2(0, 30)
	_shadow_button.toggle_mode = true
	_shadow_button.toggled.connect(func(on: bool): shadow_toggled.emit(on))
	# The same cursor tooltip the board rims use, rather than Godot's built-in
	# one, so every hover explanation in the game looks and behaves alike.
	_shadow_button.mouse_entered.connect(func():
		show_hint(SHADOW_HINT, get_viewport().get_mouse_position()))
	_shadow_button.mouse_exited.connect(hide_hint)
	box.add_child(_shadow_button)


func _on_view_button(index: int, mode: int) -> void:
	for i in _view_buttons.size():
		(_view_buttons[i] as Button).button_pressed = i == index
	view_mode_changed.emit(mode)


func _build_actions() -> void:
	var panel := _panel(Color(0.01, 0.10, 0.19, 0.85), Palette.SPACE_HORIZON)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.position = Vector2(-250, -80)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# Sits apart from Undo and End turn in weight rather than in place: it is
	# the only button here that leaves the game, so it is the quietest.
	var menu_button := _button("Menu", 14)
	menu_button.add_theme_color_override("font_color", Color(0.62, 0.7, 0.8))
	menu_button.pressed.connect(func(): _confirm_panel.visible = true)
	row.add_child(menu_button)

	_undo_button = _button("Undo move")
	_undo_button.pressed.connect(func(): undo_pressed.emit())
	row.add_child(_undo_button)

	_end_turn_button = _button("End turn")
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	row.add_child(_end_turn_button)

	_status_label = _label("", 15, Palette.INVALID_SOFT)
	_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.position = Vector2(0, -46)
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)


## A small tooltip that rides the cursor. Kept as a HUD element rather than a
## Label3D so it stays crisp and always sits on top, and so it can carry a
## background plate — the scene behind it is stars and glass, and unbacked text
## over that is unreadable.
func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.11, 0.2, 0.92)
	sb.border_color = Palette.LEVEL_RIM
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	_hint_panel.add_theme_stylebox_override("panel", sb)
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	_hint_label = _label("", 13, Palette.LEVEL_HINT)
	_hint_panel.add_child(_hint_label)
	add_child(_hint_panel)


## Positions the tooltip just off the cursor, nudged back inside the viewport
## when it would otherwise run off an edge.
func show_hint(text: String, at: Vector2) -> void:
	_hint_label.text = text
	_hint_panel.visible = true
	_hint_panel.reset_size()
	var size := _hint_panel.size
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var pos := at + Vector2(18, 16)
	pos.x = minf(pos.x, screen.x - size.x - 8)
	pos.y = minf(pos.y, screen.y - size.y - 8)
	_hint_panel.position = pos.max(Vector2(8, 8))


func hide_hint() -> void:
	if _hint_panel != null:
		_hint_panel.visible = false


func shadow_enabled() -> bool:
	return _shadow_button != null and _shadow_button.button_pressed


func _overlay(dim: float = 0.55) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.004, 0.05, 0.10, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	add_child(root)
	return root


func _centre_panel(parent: Control) -> VBoxContainer:
	var panel := _panel(Color(0.02, 0.14, 0.26, 0.98), Palette.SPACE_HORIZON)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	return box


func _build_promotion_panel() -> void:
	_promotion_panel = _overlay()
	var box := _centre_panel(_promotion_panel)
	box.add_child(_label("Promote your pawn", 22))
	box.add_child(_label("The move is not committed until you choose.", 13, Color(0.7, 0.77, 0.85)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for t in PROMOTION_CHOICES:
		var b := _button(Piece.TYPE_NAMES[t], 16)
		b.custom_minimum_size = Vector2(92, 40)
		b.pressed.connect(func(): promotion_chosen.emit(t))
		row.add_child(b)


func _build_pass_panel() -> void:
	_pass_panel = _overlay(0.96)
	var box := _centre_panel(_pass_panel)
	_pass_label = _label("Pass the device to Black", 24)
	box.add_child(_pass_label)
	box.add_child(_label("The board stays hidden until you are ready.", 13, Color(0.7, 0.77, 0.85)))
	var b := _button("I'm ready", 17)
	b.custom_minimum_size = Vector2(180, 42)
	b.pressed.connect(func(): pass_confirmed.emit())
	box.add_child(b)


func _build_gameover_panel() -> void:
	_gameover_panel = _overlay(0.8)
	var box := _centre_panel(_gameover_panel)
	_gameover_label = _label("White wins", 28)
	box.add_child(_gameover_label)
	box.add_child(_label("A king was captured — the game ends there.", 13, Color(0.7, 0.77, 0.85)))
	var b := _button("New game", 17)
	b.custom_minimum_size = Vector2(180, 42)
	b.pressed.connect(func(): restart_pressed.emit())
	box.add_child(b)


## Leaving mid-game throws the game away, so it asks. This is the one modal
## whose wording will change the day resume exists — at that point it becomes
## "Save and leave" and stops being a warning at all.
func _build_confirm_panel() -> void:
	_confirm_panel = _overlay(0.7)
	var box := _centre_panel(_confirm_panel)
	box.add_child(_label("Leave this game?", 24))
	box.add_child(_label(
		"The game is not saved anywhere, so this one ends here.",
		13, Color(0.7, 0.77, 0.85)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var stay := _button("Keep playing", 16)
	stay.custom_minimum_size = Vector2(160, 40)
	stay.pressed.connect(func(): _confirm_panel.visible = false)
	row.add_child(stay)
	var leave := _button("Leave", 16)
	leave.custom_minimum_size = Vector2(160, 40)
	leave.add_theme_color_override("font_color", Palette.INVALID_SOFT)
	leave.pressed.connect(func():
		_confirm_panel.visible = false
		menu_confirmed.emit())
	row.add_child(leave)


# --- updates -------------------------------------------------------------

func refresh(game: GameState, open_levels: Array = []) -> void:
	_turn_label.text = "%s to move" % App.player_display_name(game.current_player)
	_turn_label.add_theme_color_override(
		"font_color", Palette.OFF_WHITE if game.current_player == 0 else Color(0.62, 0.72, 0.86)
	)
	var used := game.moves_made_this_turn
	var total := game.max_moves_this_turn()
	var suffix := "  (first turn — two moves only)" if game.is_first_turn else ""
	_moves_label.text = "Move %d of %d%s" % [min(used + 1, total), total, suffix]
	for z in BoardState.LEVELS:
		var chip: Label = _level_chips[z]
		var open: bool = open_levels.has(z)
		chip.add_theme_color_override(
			"font_color", Palette.LEVEL_RIM if open else Color(1, 1, 1, 0.22))
	_undo_button.disabled = _thinking or not game.can_undo()
	_end_turn_button.disabled = _thinking or game.is_game_over()
	_end_turn_button.text = "End turn" if used > 0 else "Pass turn"


## The persistent context note — level-2 queen rules and the restricted pawn
## marker both need explaining the moment a piece is picked up (art doc §6).
func set_context(text: String) -> void:
	_context_label.text = text


func show_status(text: String) -> void:
	_status_label.text = text
	_status_timer = 2.2


func set_thinking(on: bool, who: String = "Computer") -> void:
	_thinking = on
	_think_phase = 0.0
	_thinking_label.visible = on
	_thinking_label.text = "%s is thinking" % who
	_undo_button.disabled = on or _undo_button.disabled
	_end_turn_button.disabled = on or _end_turn_button.disabled


func is_thinking() -> bool:
	return _thinking


func _process(delta: float) -> void:
	if _thinking:
		# Three dots on a slow cycle. Cheaper than a spinner node and it cannot
		# be left running by a missed hide, because the label goes with it.
		_think_phase = fmod(_think_phase + delta, 1.5)
		var dots := int(_think_phase / 0.5) + 1
		_thinking_label.text = "%s is thinking%s" % [
			_thinking_label.text.split(" is thinking")[0], ".".repeat(dots)]
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_status_label.text = ""


func show_promotion(active: bool) -> void:
	_promotion_panel.visible = active


func show_pass_screen(next_player: int) -> void:
	_pass_label.text = "Pass the device to %s" % App.player_display_name(next_player)
	_pass_panel.visible = true


func hide_pass_screen() -> void:
	_pass_panel.visible = false


func show_game_over(winner: int) -> void:
	_gameover_label.text = "%s wins" % App.player_display_name(winner)
	_gameover_panel.visible = true


func hide_game_over() -> void:
	_gameover_panel.visible = false


func is_blocking() -> bool:
	return _promotion_panel.visible or _pass_panel.visible \
		or _gameover_panel.visible or _confirm_panel.visible


## Lets the menu's saved defaults drive the same controls the player uses, so
## there is only ever one path into a view mode or into move shadow.
func select_view(mode: int) -> void:
	for i in VIEW_CHOICES.size():
		if int(VIEW_CHOICES[i]["mode"]) == mode:
			_on_view_button(i, mode)
			return


func set_shadow(on: bool) -> void:
	if _shadow_button != null:
		_shadow_button.button_pressed = on
