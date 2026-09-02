## The main menu.
##
## Rebuilt against three sets of rules, and every non-obvious decision below
## names the one it came from, so the next person can argue with the reasoning
## rather than guess at it.
##
## MANDEL'S THREE GOLDEN RULES are the top-level structure of this file:
##
##   1. Place users in control. Every screen has a way back, Escape always
##      means "back one step", nothing destructive happens without asking, and
##      nothing re-lays itself out under the cursor. See `back_one()`,
##      `_confirm()`.
##   2. Reduce users' memory load. Recognition over recall: every control
##      shows its current value, and the Play screen ends with a plain-English
##      summary of the game you are about to start, so nothing has to be
##      carried in your head from one screen to the next. See `_summary_text()`.
##   3. Make the interface consistent. There is exactly one row idiom, one
##      primary-button idiom and one "not built yet" idiom, and they are the
##      same on every screen. See the design-system section.
##
## SHNEIDERMAN'S EIGHT GOLDEN RULES hang under those:
##
##   1. Consistency — one set of primitives, used everywhere.
##   2. Universal usability — the whole menu is operable from the keyboard,
##      accelerators are printed next to the thing they trigger so they teach
##      themselves, and text size is adjustable.
##   3. Informative feedback — feedback appears AT the control that caused it
##      ("Saved" beside the row), not only in a corner of the screen.
##   4. Dialogs that yield closure — Play is a beginning (who), a middle
##      (how), and an end (a summary and one button).
##   5. Prevent errors — Quit and Reset ask first; a blank name falls back
##      instead of producing an empty label; the difficulty cannot be set out
##      of range because it is a clamped slider, not a field.
##   6. Easy reversal — a real back stack, and Settings can undo its last
##      change specifically rather than only resetting everything.
##   7. Keep the user in charge — no auto-advancing and no surprise relayout;
##      the one setting that must redraw the menu keeps your place.
##   8. Reduce short-term memory load — see Mandel 2.
##
## THE UX LAWS, and where each one actually changed something:
##
##   Fitts        Primary action is the biggest target on the screen; every row
##                is full-width so only vertical travel counts; destructive
##                targets are small and far from the primary one; the
##                difficulty slider gained two large steppers because a slider
##                handle is a bad target.
##   Hick         The title screen offers five choices, not fifteen. Difficulty
##                controls do not exist until you choose to play the computer.
##                The catalogue of unbuilt features moved off the front page.
##   Jakob        This is shaped like a game main menu — one centred column,
##                Play at the top, Quit at the bottom — because that is what
##                people already know how to use.
##   Miller       No group holds more than five items.
##   Doherty      Nothing here takes longer than a frame, and every press
##                acknowledges itself immediately.
##   Von Restorff Exactly one filled, coloured button per screen. If everything
##                is emphasised, nothing is.
##   Serial pos.  Play is first, where it is remembered. Quit is last because
##                that is where people look for it — Jakob wins that conflict —
##                but it is separated by a rule, printed quietly, and confirmed.
##   Prägnanz,    One column, one bounded card per idea, every gap a multiple
##   Proximity,   of one spacing step, and controls that look alike do jobs of
##   Similarity   the same shape.
##   Aesthetic-   The type and space scales below exist so the menu is calm; a
##   usability    calm interface is judged easier to use, and is.
##   Tesler       The opponent's complexity is real and cannot be deleted, so
##                the app absorbs it: a sane default, one slider, and a
##                sentence of plain English. Nobody meets a beam width.
##   Postel       Accepts a blank name, a stale settings file, any stored
##                difficulty; renders something sensible regardless.
##   Zeigarnik    An unfinished game belongs at the top of Play. It is not
##                built, so it sits there gated and says so, rather than being
##                hidden as if it had never been planned.
##   Goal-grad.   The Start button is pinned outside the scroll, so the finish
##                line is visible from the moment the screen opens.
##   Peak-End     The last thing before the board appears is the summary and a
##                confident, unambiguous Start.
##
## The rule carried over unchanged from before: nothing here invents a claim
## about the game. Everything unfinished is declared in App.FEATURES and
## rendered from that table, so the menu cannot drift from the code.
class_name MainMenu
extends CanvasLayer

enum Screen { TITLE, PLAY, RULES, SETTINGS, MORE, ONLINE, CREDITS }

# --- design system -------------------------------------------------------
#
# Aesthetic-usability: one type scale, one spacing scale. Every size in this
# file comes from these, so nothing is chosen ad hoc and the whole menu shares
# a rhythm.

const TYPE := {
	"display": 42, "title": 26, "head": 19, "body": 15, "small": 13, "micro": 11,
}
const STEP := 4                  ## every gap is a multiple of this
const ROW_H := 46                ## Fitts: a comfortable pointer target
const PRIMARY_H := 62            ## Fitts: the primary is unmistakably bigger
const COLUMN := 480              ## measure: roughly 65 characters at body size

## Ground, card and line colours, derived from the environment family in
## palette.gd so the menu belongs to the same world as the board.
##
## These are OPAQUE, and that is the whole point of them. The menu stands in
## front of a live 3D scene — stars, and three boards drifting past on a slow
## orbit — and text over a moving background is not text, it is texture. The
## column gets a solid slab; the sky stays visible around it, where it is
## atmosphere instead of noise.
const PAGE := Color(0.024, 0.071, 0.125)      ## the slab the whole column sits on
const CARD := Color(0.047, 0.118, 0.188)      ## one bounded idea, a step lighter
const ROW_FILL := Color(0.075, 0.157, 0.239)  ## a control, a step lighter again
const CARD_LINE := Color(1, 1, 1, 0.09)
const INK := Color(0.88, 0.92, 0.96)
const INK_2 := Color(0.64, 0.73, 0.83)
const INK_3 := Color(0.45, 0.55, 0.66)

## Von Restorff: the accent belongs to exactly one control per screen. Green,
## because on the board green already means "you may do this" — the menu
## borrows the game's language rather than inventing a second one.
const ACCENT := Palette.MOVE_CAPTURE
const ACCENT_DIM := Palette.MOVE_QUIET

const TITLE_ITEMS := [
	{"label": "Play", "key": "P", "screen": Screen.PLAY, "primary": true},
	{"label": "How to play", "key": "H", "screen": Screen.RULES},
	{"label": "Settings", "key": "S", "screen": Screen.SETTINGS},
	{"label": "More", "key": "M", "screen": Screen.MORE},
]

## Ordered top-down to match the in-game View Boards buttons, and named the same
## way. The setting still stores the level index — only the wording changed —
## but a menu that says "Level 3 only" and a button that says "Top" are two
## names for one thing, and the player has to work out that they match.
const VIEW_CHOICES := [
	{"label": "All three boards", "value": -1},
	{"label": "Top board only", "value": 2},
	{"label": "Middle board only", "value": 1},
	{"label": "Bottom board only", "value": 0},
]

const SIDE_CHOICES := [
	{"label": "You play White", "value": 1},
	{"label": "You play Black", "value": 0},
]

const SCALE_CHOICES := [
	{"label": "Small", "value": 0.9},
	{"label": "Normal", "value": 1.0},
	{"label": "Large", "value": 1.15},
	{"label": "Larger", "value": 1.3},
]

## How long an inline "Saved" stays up: long enough to be seen, short enough
## that it is gone before it becomes clutter.
const FLASH_TIME := 1.4
const TOAST_TIME := 6.0

var _scale := 1.0
var _screen: int = Screen.TITLE
var _screens: Dictionary = {}        ## Screen -> Control
var _history: Array = []             ## Shneiderman 6: a real back stack
var _ui: Control
var _content: Control

var _toast: PanelContainer
var _toast_label: Label
var _toast_timer := 0.0
var _flashes: Array = []             ## [{label, t}] inline "Saved" markers

var _confirm_panel: Control
var _confirm_title: Label
var _confirm_body: Label
var _confirm_button: Button
var _confirm_action: Callable = Callable()

## Shneiderman 6: undo of the LAST setting change, which is what people
## actually want after a misclick. "Reset everything" is a blunter, separate
## tool and sits apart from it.
var _last_change: Dictionary = {}
var _undo_button: Button

var _opponent_buttons: Array = []
var _ai_card: Control
var _names_card: Control
var _ai_value_label: Label
var _ai_detail_label: Label
var _summary_label: Label
var _primary_focus: Dictionary = {}  ## Screen -> Control to focus on arrival


func _ready() -> void:
	layer = 10
	_scale = float(App.get_setting("ui_scale"))
	_build()


# --- scale-aware primitives ----------------------------------------------

func _s(value: float) -> int:
	return int(round(value * _scale))


func _t(size_name: String) -> int:
	return _s(float(TYPE[size_name]))


## An accent laid over the page as a solid colour rather than as transparency.
## Same look, but nothing behind it can show through and move.
func _over_page(tint: Color, amount: float) -> Color:
	return PAGE.lerp(tint, amount)


func _style(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(_s(radius))
	sb.set_content_margin_all(_s(pad))
	return sb


func _panel(bg: Color, border: Color, radius: int = 8, pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, border, radius, pad))
	return p


func _label(text: String, size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _vbox(gaps: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", _s(gaps * STEP))
	return b


func _hbox(gaps: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", _s(gaps * STEP))
	return b


func _gap(height: int = 0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if height > 0:
		c.custom_minimum_size = Vector2(0, _s(height * STEP))
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _gap_h() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule_line() -> Control:
	var line := ColorRect.new()
	line.color = CARD_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Every button in the menu is skinned here, focus ring included.
## Shneiderman 2: a keyboard user has to be able to see where they are, and
## Godot's default focus outline is invisible against this background.
func _skin(b: Button, fill: Color, border: Color, ink: Color, radius: int = 8) -> void:
	b.add_theme_stylebox_override("normal", _style(fill, border, radius, 10))
	# Lightened rather than made more opaque: the fills are already solid, so
	# alpha has nothing left to say.
	b.add_theme_stylebox_override("hover", _style(fill.lightened(0.10), border, radius, 10))
	b.add_theme_stylebox_override("pressed", _style(fill.lightened(0.18), border, radius, 10))
	var focus := _style(fill.lightened(0.10), ACCENT, radius, 10)
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.focus_mode = Control.FOCUS_ALL


## The one dominant control on a screen. There is never more than one.
func _primary(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", _t("head"))
	b.custom_minimum_size = Vector2(0, _s(PRIMARY_H))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin(b, _over_page(ACCENT, 0.24), ACCENT, Color(0.86, 1.0, 0.87), 10)
	return b


## A full-width menu row. Fitts: the target spans the column, so only vertical
## distance costs anything.
func _row(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", _t("body"))
	b.custom_minimum_size = Vector2(0, _s(ROW_H))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin(b, ROW_FILL, Color(1, 1, 1, 0.07), INK)
	return b


func _quiet(text: String, size_name: String = "small") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", _t(size_name))
	b.custom_minimum_size = Vector2(0, _s(34))
	_skin(b, PAGE.lightened(0.06), Color(1, 1, 1, 0.11), INK_2, 6)
	return b


## A row with its accelerator printed at the right edge. The hint is a sibling
## label rather than part of the button text so it can be dimmed on its own —
## and printing it is how a novice becomes an expert without a manual
## (Shneiderman 2).
func _keyed_row(button: Button, key: String, height: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, _s(height))
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(button)
	var hint := _label(key, _t("micro"), INK_3)
	hint.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	hint.position = Vector2(_s(-16), 0)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hint)
	holder.set_meta("button", button)
	return holder


## THE gate idiom. One shape, on every screen, for everything that is in the
## design but not in the code.
##
## Consistency (Mandel 3) plus feedback (Shneiderman 3): it is visibly not a
## normal control, it does not pretend to work, and pressing it explains itself
## instead of doing nothing. A disabled button that swallows the click is the
## one interaction in an interface with no feedback attached at all.
func _locked(text: String, feature_id: String) -> Control:
	var row := _hbox(2)
	var b := _row(text)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.42))
	b.add_theme_color_override("font_hover_color", Palette.INVALID_SOFT)
	b.pressed.connect(func() -> void: explain(feature_id))
	row.add_child(b)
	row.add_child(_chip(feature_id))
	return row


func _chip(feature_id: String) -> Control:
	var text: String = App.chip_for(feature_id)
	if text == "":
		return Control.new()
	var status: int = App.status_of(feature_id)
	var color := Palette.INVALID_SOFT if status == App.Status.PLANNED else Palette.LEVEL_HINT
	var chip := _label(text, _t("micro"), color)
	var sb := _style(Color(color.r, color.g, color.b, 0.12),
		Color(color.r, color.g, color.b, 0.45), 4, 4)
	sb.content_margin_left = _s(7)
	sb.content_margin_right = _s(7)
	chip.add_theme_stylebox_override("normal", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


## A bounded region for one idea (Law of Common Region). Related controls sit
## inside it; unrelated ones never do.
func _card(title: String = "") -> VBoxContainer:
	var panel := _panel(CARD, CARD_LINE, 10, 14)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := _vbox(2)
	panel.add_child(box)
	if title != "":
		box.add_child(_label(title.to_upper(), _t("micro"), INK_3))
	box.set_meta("panel", panel)
	return box


func _add_card(parent: VBoxContainer, title: String = "") -> VBoxContainer:
	var box := _card(title)
	parent.add_child(box.get_meta("panel"))
	return box


# --- construction --------------------------------------------------------

func _build() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	# Jakob: one centred column, the shape every game main menu has.
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, _s(8 * STEP))
	_ui.add_child(margin)

	var centre := HBoxContainer.new()
	margin.add_child(centre)
	centre.add_child(_gap_h())
	# The solid slab. Everything readable sits on this; the 3D scene shows
	# around it, never behind the words.
	var page := _panel(PAGE, CARD_LINE, 14, 5 * STEP)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(page)
	_content = Control.new()
	_content.custom_minimum_size = Vector2(_s(COLUMN), 0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_content)
	centre.add_child(_gap_h())

	_screens[Screen.TITLE] = _build_title()
	_screens[Screen.PLAY] = _build_play()
	_screens[Screen.RULES] = _build_rules()
	_screens[Screen.SETTINGS] = _build_settings()
	_screens[Screen.MORE] = _build_more()
	_screens[Screen.ONLINE] = _build_online()
	_screens[Screen.CREDITS] = _build_credits()

	_build_toast()
	_build_confirm()
	go_to(_screen, false)


## Every screen below the title is the same shape: a back affordance, a
## heading, a scrolling body, and — where there is one — a pinned action.
## Consistency (Mandel 3) and closure (Shneiderman 4).
func _new_screen(screen: int, heading: String, blurb: String) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	_content.add_child(root)

	var column := _vbox(3)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(column)

	var back := _quiet("‹  Back", "small")
	back.custom_minimum_size = Vector2(_s(110), _s(34))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(back_one)
	column.add_child(back)

	column.add_child(_label(heading, _t("title"), INK))
	if blurb != "":
		column.add_child(_wrapped(blurb, _t("small"), INK_2))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var body := _vbox(2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.set_meta("screen_root", root)
	body.set_meta("column", column)
	body.set_meta("back", back)
	# Shneiderman 2: focus must never be left on a screen that is no longer
	# showing. Back is the safe default landing spot; screens with a clear
	# primary action override it below.
	_primary_focus[screen] = back
	return body


func _root_of(body: VBoxContainer) -> Control:
	return body.get_meta("screen_root") as Control


func _column_of(body: VBoxContainer) -> VBoxContainer:
	return body.get_meta("column") as VBoxContainer


# --- the title screen ----------------------------------------------------

func _build_title() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	_content.add_child(root)

	var column := _vbox(0)
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(column)

	column.add_child(_gap(4))
	column.add_child(_label("PARALLEL WORLDS", _t("display"), Palette.OFF_WHITE))
	column.add_child(_label("CHESS", _t("title"), Palette.STAR_TINT))
	column.add_child(_gap(2))
	column.add_child(_wrapped(
		"Three boards. Two armies each. Three moves a turn.", _t("body"), INK_2))
	column.add_child(_gap(6))

	# Hick: four choices plus Quit. Serial position: Play first, where it is
	# both remembered and closest to where the eye lands after the title.
	var list := _vbox(2)
	column.add_child(list)
	var rows: Array = []
	for item in TITLE_ITEMS:
		var screen: int = item["screen"]
		var button: Button
		if bool(item.get("primary", false)):
			button = _primary("▶   %s" % str(item["label"]))
			list.add_child(_keyed_row(button, str(item["key"]), PRIMARY_H))
			list.add_child(_gap(1))
			_primary_focus[Screen.TITLE] = button
		else:
			button = _row(str(item["label"]))
			list.add_child(_keyed_row(button, str(item["key"]), ROW_H))
		button.pressed.connect(func() -> void: go_to(screen))
		rows.append(button)

	list.add_child(_gap(2))
	list.add_child(_rule_line())
	list.add_child(_gap(1))

	# Jakob puts Quit at the bottom; the serial-position effect warns that the
	# bottom is a memorable, easily-hit place for something irreversible. The
	# compromise: it goes where people look for it, printed quietly, at a third
	# of the height of the primary — and it asks first (Shneiderman 5).
	var quit_button := _row("Quit")
	quit_button.custom_minimum_size = Vector2(0, _s(38))
	quit_button.add_theme_color_override("font_color", INK_3)
	quit_button.add_theme_color_override("font_hover_color", Palette.INVALID_SOFT)
	quit_button.pressed.connect(confirm_quit)
	list.add_child(_keyed_row(quit_button, "Q", 38))
	rows.append(quit_button)

	# Explicit up/down wiring rather than Godot's geometric guess, so keyboard
	# travel through the list is exactly the reading order (Shneiderman 2).
	for i in rows.size():
		var b: Button = rows[i]
		b.focus_neighbor_top = (rows[maxi(i - 1, 0)] as Button).get_path()
		b.focus_neighbor_bottom = (rows[mini(i + 1, rows.size() - 1)] as Button).get_path()

	column.add_child(_gap())
	var counts: Dictionary = App.status_counts()
	column.add_child(_label("%s · %d built, %d partial, %d planned" % [
		App.VERSION, counts[App.Status.BUILT], counts[App.Status.PARTIAL],
		counts[App.Status.PLANNED]], _t("micro"), INK_3))
	return root


# --- the play screen -----------------------------------------------------

## Closure (Shneiderman 4): who you are playing, then how, then a summary and
## one button. The Start button lives outside the scroll, so the end of the
## task is visible from the moment the screen opens (goal-gradient).
func _build_play() -> Control:
	var body := _new_screen(Screen.PLAY, "New game",
		"White moves first and gets two moves. Every turn after that is three.")
	var column := _column_of(body)

	var who := _add_card(body, "Who you're playing")
	who.add_child(_build_opponent_switch())

	_names_card = _build_names_card()
	body.add_child(_names_card)
	_ai_card = _build_ai_card()
	body.add_child(_ai_card)

	# Zeigarnik: an unfinished game belongs at the top of this screen. It is
	# not built, so it says so here rather than being quietly absent.
	var later := _add_card(body, "Not yet")
	later.add_child(_locked("Resume the game I left", "resume"))
	later.add_child(_locked("Play online, a move at a time", "online"))

	# --- the pinned end of the dialog ---
	column.add_child(_gap(1))
	var summary_panel := _panel(_over_page(ACCENT, 0.10),
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.40), 10, 14)
	var summary_box := _vbox(1)
	summary_panel.add_child(summary_box)
	summary_box.add_child(_label("STARTING", _t("micro"), Color(0.62, 0.85, 0.64)))
	# Mandel 2 / Shneiderman 8: the whole decision, restated in one sentence,
	# exactly where you commit to it. Nothing has to be remembered or re-checked
	# on another screen.
	_summary_label = _wrapped("", _t("body"), INK)
	summary_box.add_child(_summary_label)
	column.add_child(summary_panel)

	var start := _primary("Start game")
	start.pressed.connect(_start_game)
	column.add_child(start)
	_primary_focus[Screen.PLAY] = start

	_refresh_play()
	return _root_of(body)


## A segmented control, not a dropdown: two options both worth showing, with
## the current one visibly held down (recognition over recall).
func _build_opponent_switch() -> Control:
	var row := _hbox(2)
	_opponent_buttons = []
	var options := [
		{"label": "Another person", "value": "human"},
		{"label": "The computer", "value": "computer"},
	]
	for option in options:
		var value: String = option["value"]
		var b := Button.new()
		b.text = str(option["label"])
		b.add_theme_font_size_override("font_size", _t("body"))
		b.custom_minimum_size = Vector2(0, _s(ROW_H))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		_skin(b, ROW_FILL, Color(1, 1, 1, 0.08), INK_2)
		b.pressed.connect(func() -> void: _set_opponent(value))
		row.add_child(b)
		_opponent_buttons.append({"button": b, "value": value})
	return row


func _set_opponent(value: String) -> void:
	_change_setting("opponent", value)
	_refresh_play()


## Shows and hides; rebuilds nothing. Shneiderman 7 — the page does not jump
## around under the cursor when you change your mind.
func _refresh_play() -> void:
	var computer := App.vs_computer()
	for entry in _opponent_buttons:
		var b: Button = entry["button"]
		var active: bool = (str(entry["value"]) == "computer") == computer
		_skin(b,
			_over_page(ACCENT, 0.22) if active else ROW_FILL,
			ACCENT_DIM if active else Color(1, 1, 1, 0.08),
			INK if active else INK_2)
		b.button_pressed = active
	# Hick / progressive disclosure: the difficulty controls are not a choice
	# you have to consider until you have chosen to play the computer.
	_ai_card.visible = computer
	_names_card.visible = not computer
	_refresh_summary()


func _refresh_summary() -> void:
	if _summary_label != null and is_instance_valid(_summary_label):
		_summary_label.text = _summary_text()


func _summary_text() -> String:
	if App.vs_computer():
		var seat := App.ai_seat()
		var you := "White, moving first" if seat == 1 else "Black, moving second"
		return "You play %s. The computer plays %s at level %d — %s." % [
			you, "Black" if seat == 1 else "White",
			App.ai_difficulty(), AiPlayer.label(App.ai_difficulty())]
	return "%s plays White and moves first; %s plays Black. One device, passed between turns." % [
		App.player_display_name(0), App.player_display_name(1)]


func _build_names_card() -> Control:
	var box := _card("Names")
	box.add_child(_name_field("White", "player_one"))
	box.add_child(_name_field("Black", "player_two"))
	return box.get_meta("panel")


## Postel: a blank field is not an error. The placeholder shows exactly what
## will be used instead, so the fallback is visible rather than a surprise.
func _name_field(fallback: String, key: String) -> Control:
	var row := _hbox(3)
	var caption := _label(fallback, _t("body"), INK_2)
	caption.custom_minimum_size = Vector2(_s(90), 0)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var field := LineEdit.new()
	field.text = str(App.get_setting(key))
	field.placeholder_text = fallback
	field.max_length = 18
	field.add_theme_font_size_override("font_size", _t("body"))
	field.custom_minimum_size = Vector2(_s(160), _s(ROW_H - 8))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(func(value: String) -> void:
		App.set_setting(key, value)
		_refresh_summary())
	row.add_child(field)
	return row


## Tesler: the opponent's complexity is real and has to live somewhere. It
## lives here — one slider, a default that is already reasonable, and a
## sentence of plain English. Nobody has to meet a beam width to use it.
func _build_ai_card() -> Control:
	var box := _card("How hard it plays")
	var current: int = App.ai_difficulty()

	var head := _hbox(3)
	box.add_child(head)
	var caption := _label("Difficulty", _t("body"), INK_2)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(caption)
	_ai_value_label = _label("", _t("head"), ACCENT)
	head.add_child(_ai_value_label)

	# Fitts: a slider handle is a small target and a bad one to have to hit
	# precisely. The two steppers are large fixed targets doing the same job,
	# and they are also what a keyboard user gets for free.
	var track := _hbox(2)
	box.add_child(track)
	var minus := _quiet("−", "head")
	minus.custom_minimum_size = Vector2(_s(44), _s(38))
	track.add_child(minus)

	var slider := HSlider.new()
	slider.min_value = AiPlayer.MIN_DIFFICULTY
	slider.max_value = AiPlayer.MAX_DIFFICULTY
	slider.step = 1
	slider.value = current
	slider.custom_minimum_size = Vector2(0, _s(38))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	track.add_child(slider)

	var plus := _quiet("+", "head")
	plus.custom_minimum_size = Vector2(_s(44), _s(38))
	track.add_child(plus)

	slider.value_changed.connect(func(value: float) -> void:
		_change_setting("ai_difficulty", int(value))
		_refresh_difficulty(int(value)))
	minus.pressed.connect(func() -> void: slider.value = slider.value - 1)
	plus.pressed.connect(func() -> void: slider.value = slider.value + 1)

	var ends := _hbox(0)
	box.add_child(ends)
	var low := _label("1 · beatable", _t("micro"), INK_3)
	low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(low)
	var high := _label("hardest · 10", _t("micro"), INK_3)
	ends.add_child(high)

	# Shneiderman 3: the feedback for moving this slider is not the number. It
	# is the sentence saying what actually changed about the opponent.
	_ai_detail_label = _wrapped("", _t("small"), INK_2)
	box.add_child(_ai_detail_label)

	box.add_child(_gap(1))
	box.add_child(_choice_row("Sides", "ai_seat", SIDE_CHOICES,
		"White always moves first, and gets two moves on that first turn."))
	_refresh_difficulty(current)
	return box.get_meta("panel")


func _refresh_difficulty(value: int) -> void:
	_ai_value_label.text = "%d — %s" % [value, AiPlayer.label(value)]
	_ai_detail_label.text = AiPlayer.describe(value)
	_refresh_summary()


func _start_game() -> void:
	if App.vs_computer():
		App.start_ai_game()
	else:
		App.start_local_game()


# --- settings ------------------------------------------------------------

func _build_settings() -> Control:
	var body := _new_screen(Screen.SETTINGS, "Settings",
		"Changes save as you make them, and the last one can be undone.")
	var column := _column_of(body)

	# Miller: four groups, none longer than four rows.
	var display := _add_card(body, "Display")
	display.add_child(_toggle_row("Fullscreen", "fullscreen",
		"F11 does the same thing while you're playing."))
	display.add_child(_choice_row("Text size", "ui_scale", SCALE_CHOICES,
		"Applies to this menu. The in-game HUD has its own sizes."))

	var board := _add_card(body, "Board")
	board.add_child(_choice_row("Opening view", "default_view", VIEW_CHOICES,
		"What you are looking at when the board appears."))
	board.add_child(_toggle_row("Move shadow on by default", "move_shadow_default",
		"Projects the selected piece and its moves onto the boards it isn't on."))

	var play := _add_card(body, "Play")
	play.add_child(_toggle_row("Keep undo after the third move", "undo_after_final_move",
		"Off, the turn ends the moment the last move lands. On, it waits for "
		+ "End turn so you can still take that move back."))

	var gated := _add_card(body, "Not built yet")
	gated.add_child(_locked("Sound and music", "audio"))
	gated.add_child(_locked("Colour-blind safe palette", "colourblind"))
	gated.add_child(_locked("Reduced motion", "reduce_motion"))
	gated.add_child(_locked("Touch controls", "touch"))

	body.add_child(_gap(1))
	body.add_child(_note(
		"The project is pinned to the Compatibility renderer. Under Forward+ "
		+ "every lit surface renders black on the dev machine — a workaround, "
		+ "not a fix, and worth retrying on other hardware."))

	# Shneiderman 6, and Mandel 1. Undo is the reversal people actually want
	# after a misclick; Reset is a separate, blunter tool, placed apart from it
	# and confirmed, because it throws away work undo cannot bring back.
	column.add_child(_gap(1))
	var footer := _hbox(2)
	_undo_button = _quiet("Undo last change", "body")
	_undo_button.custom_minimum_size = Vector2(0, _s(42))
	_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_button.disabled = _last_change.is_empty()
	_undo_button.pressed.connect(_undo_last_change)
	footer.add_child(_undo_button)
	var reset := _quiet("Reset all", "small")
	reset.custom_minimum_size = Vector2(_s(110), _s(42))
	reset.add_theme_color_override("font_hover_color", Palette.INVALID_SOFT)
	reset.pressed.connect(func() -> void: _confirm(
		"Reset every setting?",
		"Names, difficulty, view and display options all go back to their "
		+ "defaults. This one is not covered by undo.",
		"Reset", _do_reset))
	footer.add_child(reset)
	column.add_child(footer)
	return _root_of(body)


func _do_reset() -> void:
	App.reset_settings()
	_last_change = {}
	_scale = float(App.get_setting("ui_scale"))
	_rebuild(Screen.SETTINGS)
	toast("Every setting is back to its default.", Palette.LEVEL_HINT)


## One row shape for every setting: what it is, what it does, its current
## value, and the space where its confirmation appears. The same on every
## screen (Mandel 3), and the feedback lands next to the control that caused
## it (Shneiderman 3).
func _setting_row(label_text: String, help: String, control: Control) -> Control:
	var row := _vbox(1)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top := _hbox(3)
	row.add_child(top)
	var caption := _label(label_text, _t("body"), INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(caption)
	var flash := _label("", _t("micro"), Palette.LEVEL_HINT)
	flash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(flash)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(control)

	if help != "":
		row.add_child(_wrapped(help, _t("micro"), INK_3))
	row.set_meta("flash", flash)
	return row


func _toggle_row(label_text: String, key: String, help: String) -> Control:
	var check := CheckButton.new()
	check.button_pressed = bool(App.get_setting(key))
	check.focus_mode = Control.FOCUS_ALL
	var row := _setting_row(label_text, help, check)
	check.toggled.connect(func(on: bool) -> void:
		_change_setting(key, on)
		_flash(row.get_meta("flash")))
	return row


func _choice_row(label_text: String, key: String, choices: Array, help: String) -> Control:
	var drop := OptionButton.new()
	drop.add_theme_font_size_override("font_size", _t("small"))
	drop.custom_minimum_size = Vector2(_s(190), _s(ROW_H - 8))
	drop.focus_mode = Control.FOCUS_ALL
	var current: Variant = App.get_setting(key)
	for i in choices.size():
		drop.add_item(str(choices[i]["label"]), i)
		if _same_value(choices[i]["value"], current):
			drop.select(i)
	var row := _setting_row(label_text, help, drop)
	drop.item_selected.connect(func(index: int) -> void:
		var value: Variant = choices[index]["value"]
		_change_setting(key, value)
		_flash(row.get_meta("flash"))
		_refresh_summary()
		# Shneiderman 7: the one setting that must redraw the menu you are
		# standing in keeps your place and your history, so it never feels like
		# the interface took over.
		if key == "ui_scale":
			_scale = float(value)
			_rebuild(_screen))
	return row


func _note(text: String) -> Control:
	var card := _panel(PAGE.lightened(0.05), Color(1, 1, 1, 0.06), 6, 12)
	card.add_child(_wrapped(text, _t("micro"), INK_3))
	return card


## Floats come back from ConfigFile as floats and ints as ints; compare on
## value, so a stored 1 still matches a 1.0 choice (Postel).
func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


## Every change the menu makes goes through here, which is what makes a
## single-step undo possible at all.
func _change_setting(key: String, value: Variant) -> void:
	var previous: Variant = App.get_setting(key)
	if _same_value(previous, value):
		return
	_last_change = {"key": key, "value": previous}
	App.set_setting(key, value)
	if _undo_button != null and is_instance_valid(_undo_button):
		_undo_button.disabled = false


func _undo_last_change() -> void:
	if _last_change.is_empty():
		return
	var key: String = _last_change["key"]
	App.set_setting(key, _last_change["value"])
	_last_change = {}
	if key == "ui_scale":
		_scale = float(App.get_setting("ui_scale"))
	_rebuild(_screen)
	toast("Undone.", Palette.LEVEL_HINT)


func _flash(label: Label, text: String = "Saved") -> void:
	label.text = text
	_flashes.append({"label": label, "t": FLASH_TIME})


# --- rules, more, online, credits ----------------------------------------

func _build_rules() -> Control:
	var body := _new_screen(Screen.RULES, "How to play",
		"Standard chess on the top and bottom boards. Everything new is in how "
		+ "you move between them.")
	_rule_card(body, "The stack",
		"Three 8×8 boards. Level 1 is matte and dark, level 3 is glossy and "
		+ "light, and level 2 between them is a pane of glass. You own two "
		+ "16-piece armies, one on level 1 and one on level 3, mirrored — your "
		+ "level-3 pawns advance the opposite way down the board. Level 2 "
		+ "starts empty.")
	_rule_card(body, "Your turn",
		"Up to three moves a turn, two on White's first turn. One move per "
		+ "piece, and no two moves may end on the same level. The turn ends "
		+ "automatically once you hit the cap, or press End turn to stop early. "
		+ "The level chips in the corner dim as each level is spent.")
	_rule_card(body, "Moving between levels",
		"Any piece except a king can step one level up or down onto the same "
		+ "square, if that square is empty. Never two levels at once. A column "
		+ "of light stands on the piece while it is selected, in each direction "
		+ "it can travel — a piece on the glass board beams both ways.")
	_rule_card(body, "The glass board",
		"On level 2 every piece moves as a queen, whatever it is. Nothing can "
		+ "be captured there and no pawn promotes there. Sliding stops short of "
		+ "any occupied square, friend or enemy — which is also what keeps your "
		+ "own two armies from walking through each other.")
	_rule_card(body, "Pawns",
		"A pawn that drops from the glass board onto its own last rank promotes "
		+ "immediately, and you choose the piece. A pawn that drops onto its own "
		+ "first rank is restricted to single steps — it wears a red halo — "
		+ "until it reaches its second rank, when it moves normally again, "
		+ "double step included.")
	_rule_card(body, "Winning",
		"Capture either of your opponent's two kings and the game ends there. "
		+ "There is no check and no checkmate, so nothing stops you moving into "
		+ "danger — and castling has no through-check restriction.")
	_rule_card(body, "Controls",
		"Left click to select and to move. Left-drag to pan, right-drag to "
		+ "orbit, wheel to zoom. Double-click a board to look down at it. Esc "
		+ "deselects, F11 toggles fullscreen. The View buttons switch between "
		+ "the whole stack and one level at a time.")
	return _root_of(body)


func _rule_card(body: VBoxContainer, title: String, text: String) -> void:
	var box := _add_card(body)
	box.add_child(_label(title, _t("head"), Palette.STAR_TINT))
	box.add_child(_wrapped(text, _t("small"), INK_2))


## Hick: everything interesting but not urgent lives one step off the title
## screen, so the front page stays a decision with five answers.
func _build_more() -> Control:
	var body := _new_screen(Screen.MORE, "More", "")
	var ahead := _add_card(body, "What's coming")
	var online_row := _row("Play online — see the plan")
	online_row.pressed.connect(func() -> void: go_to(Screen.ONLINE))
	var online_holder := _hbox(2)
	online_holder.add_child(online_row)
	online_holder.add_child(_chip("online"))
	ahead.add_child(online_holder)
	ahead.add_child(_locked("Game replay", "replay"))
	ahead.add_child(_locked("Match history", "stats"))
	ahead.add_child(_locked("Real piece models", "models"))

	var about := _add_card(body, "About")
	var credits_row := _row("Credits")
	credits_row.pressed.connect(func() -> void: go_to(Screen.CREDITS))
	about.add_child(credits_row)
	_primary_focus[Screen.MORE] = online_row
	return _root_of(body)


func _build_online() -> Control:
	var body := _new_screen(Screen.ONLINE, "Play online",
		"None of this works yet. It is drawn so the shape is settled before the "
		+ "backend is written — design doc §9B and §10.")

	var banner := _panel(_over_page(Palette.INVALID_SOFT, 0.12),
		Color(Palette.INVALID_SOFT.r, Palette.INVALID_SOFT.g, Palette.INVALID_SOFT.b, 0.5), 8, 14)
	banner.add_child(_wrapped(App.note_for("online"), _t("small"), Palette.INVALID_SOFT))
	body.add_child(banner)

	var games := _add_card(body, "Your games")
	games.add_child(_wrapped(
		"One row per game: who you're playing, whose move it is, and how long "
		+ "is left before the turn lapses.", _t("micro"), INK_3))
	games.add_child(_game_row("Priya", "Your move", "1 day 4 hours left", false))
	games.add_child(_game_row("Sam", "Waiting on Sam", "2 days left", false))
	games.add_child(_game_row("Alex", "Your move", "3 hours left", true))

	var start := _add_card(body, "Start or join")
	start.add_child(_locked("New game — get a code to share", "join_code"))
	start.add_child(_locked("Join with a code", "join_code"))
	start.add_child(_locked("Sign in", "account"))

	var deadlines := _add_card(body, "Deadlines")
	deadlines.add_child(_locked("A deadline per turn, auto-skip when it lapses", "deadlines"))
	deadlines.add_child(_locked("Tell me when it's my move", "notifications"))
	return _root_of(body)


## A placeholder row, dimmed to the same degree as everything else that is not
## real, and deliberately not shaped like a control. The countdown is fixed
## rather than ticking — a live timer over invented data reads as a working
## feature.
func _game_row(opponent: String, state: String, deadline: String, urgent: bool) -> Control:
	var card := _panel(CARD.lightened(0.05), Color(1, 1, 1, 0.06), 6, 10)
	var row := _hbox(3)
	card.add_child(row)
	var who := _label(opponent, _t("body"), Color(1, 1, 1, 0.42))
	who.custom_minimum_size = Vector2(_s(110), 0)
	row.add_child(who)
	var status := _label(state, _t("small"), Color(1, 1, 1, 0.32))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	# The art doc gives the red family to anything running out, so a deadline
	# inside a day wears it and a comfortable one does not.
	row.add_child(_label(deadline, _t("micro"),
		Palette.INVALID_SOFT if urgent else Color(1, 1, 1, 0.28)))
	return card


func _build_credits() -> Control:
	var body := _new_screen(Screen.CREDITS, "Credits", "")
	_rule_card(body, "Engine",
		"Godot 4.7, pinned to the Compatibility (GLES3) renderer. No add-ons "
		+ "and no third-party code — everything in scripts/ is written for this "
		+ "project.")
	_rule_card(body, "Pieces",
		"The pieces on screen are primitive stand-ins with a distinct silhouette "
		+ "and height per type. The loader for the real set is in and tested: "
		+ "drop the LowPoly Chess Set (CC0) .fbx files into assets/pieces/ and "
		+ "they are matched by name, rescaled and stood upright on the next "
		+ "launch. See assets/pieces/README.md.")
	_rule_card(body, "Look",
		"Five fixed colours and their tint ramps, defined once in palette.gd, "
		+ "with one documented exception for the move shadow. The night sky is a "
		+ "shader with no texture asset — two procedural star fields and a faint "
		+ "nebula.")
	_rule_card(body, "The opponent",
		"No engine and no opening book. It searches the same rules you play by, "
		+ "one branch per candidate first move, and the difficulty dial changes "
		+ "how wide it looks and how much of your reply it bothers to check.")
	return _root_of(body)


# --- navigation ----------------------------------------------------------

func go_to(screen: int, remember := true) -> void:
	if remember and screen != _screen:
		_history.append(_screen)
	# The title screen is the root: there is nothing behind it, so arriving
	# there empties the stack rather than leaving stale steps for Escape to
	# walk backwards into.
	if screen == Screen.TITLE:
		_history.clear()
	_screen = screen
	for id in _screens:
		(_screens[id] as Control).visible = id == screen
	# Doherty: the new screen is up this frame, and the keyboard lands
	# somewhere useful without the player having to hunt for it.
	var target: Control = _primary_focus.get(screen, null)
	if target != null and is_instance_valid(target):
		target.call_deferred("grab_focus")


## Shneiderman 6, and Mandel 1: there is always exactly one step back, and
## Escape is always it.
func back_one() -> void:
	if _history.is_empty():
		go_to(Screen.TITLE, false)
		return
	var previous: int = _history.pop_back()
	go_to(previous, false)


func confirm_quit() -> void:
	_confirm("Quit Parallel Worlds Chess?",
		"Nothing is saved between sessions yet, so an unfinished game ends here.",
		"Quit", func() -> void: get_tree().quit())


## Rebuilds the menu and puts the player back exactly where they were —
## same screen, same history, same undo state.
func _rebuild(screen: int) -> void:
	var history := _history.duplicate()
	_screens.clear()
	_primary_focus.clear()
	_flashes.clear()
	_opponent_buttons = []
	_undo_button = null
	_summary_label = null
	if _ui != null:
		_ui.queue_free()
	if _toast != null:
		_toast.queue_free()
	if _confirm_panel != null:
		_confirm_panel.queue_free()
	_screen = screen
	_build()
	_history = history


# --- feedback ------------------------------------------------------------

func explain(feature_id: String) -> void:
	toast(App.note_for(feature_id), Palette.INVALID_SOFT)


func toast(text: String, color: Color) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast_timer = TOAST_TIME


func _build_toast() -> void:
	_toast = _panel(CARD, Palette.SPACE_HORIZON, 8, 14)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(0, _s(-7 * STEP))
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.custom_minimum_size = Vector2(_s(560), 0)
	_toast.visible = false
	_toast_label = _wrapped("", _t("small"), Palette.INVALID_SOFT)
	_toast.add_child(_toast_label)
	add_child(_toast)


## Shneiderman 5. One confirm, reused, so a destructive action always looks and
## reads the same way — and the safe choice is the one that already has focus,
## so Enter never destroys anything.
func _build_confirm() -> void:
	_confirm_panel = Control.new()
	_confirm_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_panel.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.004, 0.04, 0.08, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_panel.add_child(shade)

	var panel := _panel(CARD, Palette.SPACE_HORIZON, 10, 20)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(_s(420), 0)
	_confirm_panel.add_child(panel)

	var box := _vbox(2)
	panel.add_child(box)
	_confirm_title = _label("", _t("head"), INK)
	box.add_child(_confirm_title)
	_confirm_body = _wrapped("", _t("small"), INK_2)
	_confirm_body.custom_minimum_size = Vector2(_s(380), 0)
	box.add_child(_confirm_body)
	box.add_child(_gap(1))

	var row := _hbox(2)
	box.add_child(row)
	var cancel := _quiet("Keep looking around", "body")
	cancel.custom_minimum_size = Vector2(0, _s(42))
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_dismiss_confirm)
	row.add_child(cancel)
	_confirm_button = _quiet("Confirm", "body")
	_confirm_button.custom_minimum_size = Vector2(_s(150), _s(42))
	_confirm_button.add_theme_color_override("font_color", Palette.INVALID_SOFT)
	_confirm_button.pressed.connect(func() -> void:
		var action := _confirm_action
		_dismiss_confirm()
		if action.is_valid():
			action.call())
	row.add_child(_confirm_button)
	_confirm_panel.set_meta("cancel", cancel)
	add_child(_confirm_panel)


func _confirm(title: String, body: String, verb: String, action: Callable) -> void:
	_confirm_title.text = title
	_confirm_body.text = body
	_confirm_button.text = verb
	_confirm_action = action
	_confirm_panel.visible = true
	(_confirm_panel.get_meta("cancel") as Button).call_deferred("grab_focus")


func _dismiss_confirm() -> void:
	_confirm_panel.visible = false
	_confirm_action = Callable()


func is_confirming() -> bool:
	return _confirm_panel != null and is_instance_valid(_confirm_panel) \
		and _confirm_panel.visible


# --- keyboard ------------------------------------------------------------

## Shneiderman 2. The whole menu is reachable without a mouse: arrows and Enter
## come free from Godot's focus system once every control is focusable, Escape
## is always "back one step", and the single-key accelerators are the ones
## printed on the title screen, so they teach themselves.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		if is_confirming():
			_dismiss_confirm()
		elif _screen == Screen.TITLE:
			confirm_quit()
		else:
			back_one()
		get_viewport().set_input_as_handled()
		return
	if is_confirming():
		return
	# Never steal a letter from someone typing a player's name.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if _screen != Screen.TITLE:
		return
	match (event as InputEventKey).keycode:
		KEY_P: go_to(Screen.PLAY)
		KEY_H: go_to(Screen.RULES)
		KEY_S: go_to(Screen.SETTINGS)
		KEY_M: go_to(Screen.MORE)
		KEY_Q: confirm_quit()
		_: return
	get_viewport().set_input_as_handled()


# --- per-frame -----------------------------------------------------------

func _process(delta: float) -> void:
	if _toast != null and is_instance_valid(_toast) and _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
	if _flashes.is_empty():
		return
	var still: Array = []
	for entry in _flashes:
		entry["t"] = float(entry["t"]) - delta
		var flash_label: Label = entry["label"]
		if not is_instance_valid(flash_label):
			continue
		if float(entry["t"]) <= 0.0:
			flash_label.text = ""
		else:
			still.append(entry)
	_flashes = still
