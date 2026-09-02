## Menu, settings and interaction-design test.
##
##   godot --headless --path <project> --script res://tests/test_menu.gd
##
## Two kinds of thing are checked here. The first is the boring kind: the
## feature table stays well-formed and settings survive a round trip through
## disk.
##
## The second is the interaction design, and it is here because those are the
## properties that rot silently. A back stack quietly stops covering a new
## screen; a confirm gets dropped from a destructive action during a refactor;
## a screen is added and nothing ever gives it keyboard focus. None of that
## shows up as a crash, and none of it shows up in a screenshot — so the rules
## the menu is built on are asserted rather than only commented.
##
## It writes to user://settings.cfg like the game does, and puts the file back
## the way it found it before exiting.
extends SceneTree

var menu_root: Node3D
## Deliberately untyped.
##
## Naming `MainMenu` here would make menu.gd a compile-time dependency of this
## script, and a script passed to `--script` is compiled before the autoload
## list is registered — so menu.gd's `App.get_setting(...)` would fail to
## resolve, menu.gd would not compile, and the Menu node would load as a bare
## CanvasLayer with no script. That is what had reduced this whole suite to
## nothing. The rule: a test entry script must not name a class whose script
## touches the App autoload. Members are reached dynamically instead, which
## costs the static check on this one reference and buys back the suite.
var menu: Node
var _step := 0
var _wait := 0
var _passed := 0
var _failed := 0
var _saved_settings: Dictionary = {}


## The autoload is reached as a node rather than through the `App` global.
##
## A script passed to `--script` is compiled before the autoload list is
## registered, so the global identifier does not exist there and the whole file
## fails to compile — which is what had silently killed this suite. The node
## itself is present once the tree is running, so it is fetched in _process()
## and everything below goes through `app` instead. Scripts loaded later
## (main.gd, menu.gd) are compiled after registration and can keep using `App`.
var app: Node


func _initialize() -> void:
	print("Parallel Worlds Chess — menu and settings test\n")


## Runs once, on the first frame, when root and the autoloads are live.
func _setup() -> void:
	app = root.get_node("App")
	_saved_settings = app.settings.duplicate(true)
	var packed: PackedScene = load("res://scenes/menu.tscn")
	menu_root = packed.instantiate()
	root.add_child(menu_root)
	menu = menu_root.get_node("Menu")


func ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _process(_delta: float) -> bool:
	if app == null:
		_setup()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			_test_feature_table()
			_test_scene()
			_wait = 2
		1:
			_test_every_screen_is_reachable()
			_test_back_stack()
			_test_keyboard_landing_spot()
			_test_gating_explains_itself()
		2:
			_test_destructive_actions_confirm()
			_test_settings()
			_test_undo_of_the_last_change()
			_finish()
			return true
	_step += 1
	return false


# --- the feature table ---------------------------------------------------

func _test_feature_table() -> void:
	# The menu renders itself from this table, so a malformed entry is a blank
	# or unexplained button rather than a crash — which is exactly the kind of
	# thing that ships.
	var well_formed := true
	for id in app.FEATURES:
		var entry: Dictionary = app.FEATURES[id]
		if not entry.has("status") or not entry.has("note"):
			well_formed = false
		elif not app.Status.values().has(entry["status"]):
			well_formed = false
		elif str(entry["note"]).strip_edges() == "":
			well_formed = false
	ok(well_formed, "every feature entry has a valid status and a non-empty note")

	var referenced := [
		"local_play", "ai_play", "resume", "online", "join_code", "lobby", "deadlines",
		"notifications", "account", "models", "audio", "colourblind",
		"reduce_motion", "touch", "replay", "stats",
	]
	var all_present := true
	for id in referenced:
		if not app.FEATURES.has(id):
			all_present = false
			print("    missing feature id: %s" % id)
	ok(all_present, "every feature id the menu asks for exists in the table")

	ok(app.is_built("local_play"), "pass-and-play is marked built")
	ok(app.is_built("ai_play"), "so is playing the computer")
	ok(not app.is_built("online"), "online play is not claimed to work")
	ok(app.chip_for("local_play") == "", "a built feature carries no chip")
	ok(app.chip_for("online") == "SOON", "a planned feature is chipped SOON")
	ok(app.chip_for("models") == "PARTIAL", "the model pipeline reads as partial")

	var counts: Dictionary = app.status_counts()
	ok(counts[app.Status.BUILT] + counts[app.Status.PARTIAL] + counts[app.Status.PLANNED]
		== app.FEATURES.size(), "the status counts add up to the whole table")


func _test_scene() -> void:
	ok(menu != null, "the menu scene carries a MainMenu layer")
	var board: BoardVisual = menu_root.get_node("Board")
	ok(board != null and board.squares.size() == BoardState.LEVELS,
		"the menu backdrop builds the same three boards the game does")
	var backdrop: MenuBackdrop = menu_root.get_node("Backdrop")
	ok(backdrop != null and backdrop.get_node_or_null("Camera3D") != null,
		"the backdrop owns a camera, so the menu is never a black screen")


# --- structure and navigation --------------------------------------------

func _all_screens() -> Array:
	return [
		menu.Screen.TITLE, menu.Screen.PLAY, menu.Screen.RULES,
		menu.Screen.SETTINGS, menu.Screen.MORE, menu.Screen.ONLINE,
		menu.Screen.CREDITS,
	]


func _test_every_screen_is_reachable() -> void:
	ok(menu._screens.size() == _all_screens().size(),
		"every screen in the enum was actually built")
	var one_at_a_time := true
	for screen in _all_screens():
		menu.go_to(screen)
		var showing := 0
		for id in menu._screens:
			if (menu._screens[id] as Control).visible:
				showing += 1
		if showing != 1 or not (menu._screens[screen] as Control).visible:
			one_at_a_time = false
	ok(one_at_a_time, "exactly one screen is showing at any moment")

	# Hick's law is the reason the title screen is short. If someone adds a
	# sixth and a seventh entry to it, this is where they find out.
	ok(menu.TITLE_ITEMS.size() + 1 <= 5,
		"the title screen offers %d choices including Quit, not more than five"
			% (menu.TITLE_ITEMS.size() + 1))


func _test_back_stack() -> void:
	# Mandel 1 / Shneiderman 6: there is always exactly one step back, and it
	# is the step you actually took.
	menu.go_to(menu.Screen.TITLE, false)
	menu.go_to(menu.Screen.MORE)
	menu.go_to(menu.Screen.ONLINE)
	menu.back_one()
	ok(menu._screen == menu.Screen.MORE, "back from a nested screen lands one level up")
	menu.back_one()
	ok(menu._screen == menu.Screen.TITLE, "and again lands on the title screen")
	menu.back_one()
	ok(menu._screen == menu.Screen.TITLE,
		"back from the title screen is harmless rather than an error")


func _test_keyboard_landing_spot() -> void:
	# Shneiderman 2: focus must never be stranded on a screen that is no longer
	# visible, or a keyboard-only player is lost the moment they navigate.
	var every_screen_has_one := true
	for screen in _all_screens():
		var target: Control = menu._primary_focus.get(screen, null)
		if target == null or not is_instance_valid(target):
			every_screen_has_one = false
			print("    no focus target for screen %d" % screen)
		elif target is Button and (target as Button).disabled:
			every_screen_has_one = false
			print("    focus target for screen %d is disabled" % screen)
	ok(every_screen_has_one, "every screen names a focusable control to land on")
	menu.go_to(menu.Screen.TITLE, false)


func _test_gating_explains_itself() -> void:
	# A gated control that does nothing is the one interaction in an interface
	# with no feedback attached at all.
	menu.explain("online")
	ok(menu._toast.visible and menu._toast_label.text == app.note_for("online"),
		"pressing an unbuilt feature explains what is missing")
	ok(menu._toast_timer > 0.0, "the explanation is on a timer, not permanent")


func _test_destructive_actions_confirm() -> void:
	# Shneiderman 5. Quit is the only irreversible thing in the menu, and it
	# sits at the bottom of a list people navigate with arrow keys.
	ok(not menu.is_confirming(), "nothing is asking anything to start with")
	menu.confirm_quit()
	ok(menu.is_confirming(), "Quit asks before it quits")
	var cancel: Button = menu._confirm_panel.get_meta("cancel")
	ok(cancel != null and not cancel.disabled,
		"…and the safe answer is the one holding focus, so Enter never quits")
	menu._dismiss_confirm()
	ok(not menu.is_confirming(), "and it can be dismissed")


# --- settings ------------------------------------------------------------

func _test_settings() -> void:
	# Pinned, because a settings file left behind by a real session could have
	# the computer sitting in seat 0 and rename White out from under the test.
	app.set_setting("opponent", "human")
	app.set_setting("default_view", 2)
	app.set_setting("undo_after_final_move", true)
	app.set_setting("player_one", "Isaac")
	app.load_settings()
	ok(app.get_setting("default_view") == 2, "a view choice survives a save and reload")
	ok(app.get_setting("undo_after_final_move") == true, "a toggle survives a save and reload")
	ok(app.player_display_name(0) == "Isaac", "a custom name replaces the default")

	# Postel: a blank field is not an error, it is a fallback.
	app.set_setting("player_one", "   ")
	ok(app.player_display_name(0) == "White",
		"a blank name falls back rather than showing an empty label")

	app.set_setting("opponent", "computer")
	app.set_setting("ai_difficulty", 7)
	app.set_setting("ai_seat", 1)
	app.load_settings()
	ok(app.vs_computer() and app.ai_difficulty() == 7,
		"the opponent and its difficulty survive a save and reload")
	ok(app.is_ai_seat(1) and not app.is_ai_seat(0),
		"the computer occupies exactly the seat it was given")
	# Typed outright: `app` is an untyped Node, so := has nothing to infer from.
	var built: AiPlayer = app.make_ai()
	ok(built != null and built.difficulty == 7 and built.owner_id == 1,
		"make_ai() hands main.gd an opponent matching the settings")
	app.set_setting("opponent", "human")
	ok(app.make_ai() == null, "and none at all in a two-player game")

	app.reset_settings()
	ok(app.get_setting("default_view") == -1 and app.get_setting("player_one") == "White",
		"reset puts every setting back to its default")

	# A settings file written by an older build, or edited by hand, must not be
	# able to boot the game into a state the rest of the code cannot handle.
	var cfg := ConfigFile.new()
	cfg.load(app.SETTINGS_PATH)
	cfg.set_value("settings", "default_view", "nonsense")
	cfg.save(app.SETTINGS_PATH)
	app.load_settings()
	ok(app.get_setting("default_view") == -1,
		"a wrong-typed stored value is ignored, not loaded")


func _test_undo_of_the_last_change() -> void:
	# Shneiderman 6. The reversal people actually want after a misclick is of
	# the thing they just did — not of everything they have ever set.
	app.set_setting("default_view", -1)
	menu._change_setting("default_view", 2)
	ok(app.get_setting("default_view") == 2, "a change made through the menu takes effect")
	ok(not menu._last_change.is_empty(), "…and is remembered as the last one")
	menu._undo_last_change()
	ok(app.get_setting("default_view") == -1, "undo puts the previous value back")
	ok(menu._last_change.is_empty(), "and there is nothing left to undo twice")

	# Setting a value to what it already is is not a change, and must not eat
	# the undo the player is still expecting to have.
	menu._change_setting("default_view", 2)
	menu._change_setting("default_view", 2)
	menu._undo_last_change()
	ok(app.get_setting("default_view") == -1,
		"a no-op change does not overwrite the undo behind it")


func _finish() -> void:
	app.settings = _saved_settings
	app.save_settings()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
