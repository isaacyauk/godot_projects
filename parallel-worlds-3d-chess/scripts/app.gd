## Application-wide state that outlives any one scene: the player's settings,
## the configuration chosen for the next game, and the single table of what is
## and is not built yet.
##
## Registered as the `App` autoload. It deliberately knows nothing about the
## board, the rules or the HUD — the menu writes to it, main.gd reads from it,
## and neither has to know the other exists.
##
## The FEATURES table below is the point of this file. The menu is built from
## it rather than from hard-coded buttons, so a feature graduating from PLANNED
## to BUILT is one line here plus the code that makes it true. Without that the
## menu becomes a second, quietly drifting claim about what the game does.
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

const VERSION := "v1 · two players or the computer"

enum Status {
	BUILT,    ## works now
	PARTIAL,  ## works, but not the way the docs describe it
	PLANNED,  ## in the design or art doc, not written
}

const STATUS_LABEL := {
	Status.BUILT: "",
	Status.PARTIAL: "PARTIAL",
	Status.PLANNED: "SOON",
}

## id -> { status, note }. The note is what the player is shown when they click
## something that is not there yet: plain language first, doc section second,
## never a dead button that silently does nothing.
const FEATURES := {
	# --- modes -----------------------------------------------------------
	"local_play": {
		"status": Status.BUILT,
		"note": "Two players, one device, passing it between turns.",
	},
	"ai_play": {
		"status": Status.BUILT,
		"note": "One player against the computer, at a difficulty from 1 to 10.",
	},
	"resume": {
		"status": Status.PLANNED,
		"note": "Saving a game in progress is not written yet. GameState.to_dict() "
			+ "already round-trips a whole game through JSON, so this is the small "
			+ "half of it — the file I/O is all that's missing.",
	},
	"online": {
		"status": Status.PLANNED,
		"note": "Async remote play is the last item in the build order and nothing "
			+ "networked exists yet. Design doc §9B and §10.",
	},
	"join_code": {
		"status": Status.PLANNED,
		"note": "Shareable game codes come with the async backend. Design doc §10.",
	},
	"lobby": {
		"status": Status.PLANNED,
		"note": "The game list, with whose move it is and how long is left, needs "
			+ "the Supabase rows behind it. Design doc §9B.",
	},
	"deadlines": {
		"status": Status.PLANNED,
		"note": "Move deadlines, auto-skip on a lapse and commit-and-end on a "
			+ "partial turn are all backend-side. Design doc §3 and §10.",
	},
	"notifications": {
		"status": Status.PLANNED,
		"note": "Push and email 'your move' notifications ship with async play. "
			+ "Design doc §10.",
	},
	"account": {
		"status": Status.PLANNED,
		"note": "There is no account system — local play needs no identity.",
	},
	# --- presentation ----------------------------------------------------
	"models": {
		"status": Status.PARTIAL,
		"note": "The model loader is in and tested; the LowPoly Chess Set (CC0) "
			+ "files are not in the repo. Drop the .fbx files into assets/pieces/ "
			+ "and they are picked up on the next launch — see the README there.",
	},
	"audio": {
		"status": Status.PLANNED,
		"note": "There is no sound in the project yet — no music, no move sounds.",
	},
	"colourblind": {
		"status": Status.PLANNED,
		"note": "Green-valid and red-invalid are the whole feedback language, so a "
			+ "safe variant means a second ramp in palette.gd. Worth doing, not done.",
	},
	"reduce_motion": {
		"status": Status.PLANNED,
		"note": "The vertical beam, the lattice drift and the move tweens all read "
			+ "from their own constants today; one switch over them is not wired.",
	},
	"touch": {
		"status": Status.PLANNED,
		"note": "No touch input and no mobile layout. The two camera view modes it "
			+ "depends on already work. Design doc §8 stage 3.",
	},
	# --- after the game --------------------------------------------------
	"replay": {
		"status": Status.PLANNED,
		"note": "Move history is kept only as a one-deep undo snapshot, so there is "
			+ "nothing to replay from yet.",
	},
	"stats": {
		"status": Status.PLANNED,
		"note": "Nothing is recorded between games.",
	},
}

## Settings the game actually reads today. Anything the menu shows that is not
## in here is gated by the table above and says so on screen — a settings
## screen that pretends to change something it doesn't is worse than no
## settings screen.
const DEFAULTS := {
	"fullscreen": false,
	"ui_scale": 1.0,
	"opponent": "human",         ## "human" (pass and play) or "computer"
	"ai_difficulty": 5,          ## 1..10, see AiPlayer.TABLE
	"ai_seat": 1,                ## which owner_id the computer plays; 1 = Black
	"default_view": -1,          ## -1 all levels, 0..2 a single level
	"move_shadow_default": false,
	"undo_after_final_move": false,
	"player_one": "White",
	"player_two": "Black",
}

var settings: Dictionary = {}

## What the menu asked for, read by main.gd when the game scene boots.
var pending_game: Dictionary = {"mode": "local"}


func _ready() -> void:
	load_settings()
	apply_display()


# --- persistence ---------------------------------------------------------

func load_settings() -> void:
	settings = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key("settings", key):
			var stored: Variant = cfg.get_value("settings", key)
			# Only accept a stored value of the same type as the default, so a
			# hand-edited or stale settings file can never boot the game into a
			# state the rest of the code does not expect.
			if typeof(stored) == typeof(DEFAULTS[key]):
				settings[key] = stored


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)


func get_setting(key: String) -> Variant:
	return settings.get(key, DEFAULTS.get(key, null))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_settings()
	if key == "fullscreen":
		apply_display()


func reset_settings() -> void:
	settings = DEFAULTS.duplicate(true)
	save_settings()
	apply_display()


## F11 in-game toggles the same two modes, so both routes agree on what
## "not fullscreen" looks like: the maximized window the game opens in.
func apply_display() -> void:
	if get_setting("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


# --- the feature table ---------------------------------------------------

func feature(id: String) -> Dictionary:
	return FEATURES.get(id, {"status": Status.PLANNED, "note": "Not built yet."})


func status_of(id: String) -> int:
	return int(feature(id)["status"])


func is_built(id: String) -> bool:
	return status_of(id) == Status.BUILT


func note_for(id: String) -> String:
	return str(feature(id)["note"])


func chip_for(id: String) -> String:
	return str(STATUS_LABEL[status_of(id)])


## Used by the home screen's one-line honesty strip.
func status_counts() -> Dictionary:
	var counts := {Status.BUILT: 0, Status.PARTIAL: 0, Status.PLANNED: 0}
	for id in FEATURES:
		counts[FEATURES[id]["status"]] += 1
	return counts


# --- scene flow ----------------------------------------------------------

func start_local_game() -> void:
	set_setting("opponent", "human")
	pending_game = {"mode": "local"}
	get_tree().change_scene_to_file(GAME_SCENE)


func start_ai_game() -> void:
	set_setting("opponent", "computer")
	pending_game = {"mode": "computer", "difficulty": get_setting("ai_difficulty")}
	get_tree().change_scene_to_file(GAME_SCENE)


# --- the computer opponent ------------------------------------------------

func vs_computer() -> bool:
	return str(get_setting("opponent")) == "computer"


## Which side the computer is playing, or -1 in a two-player game.
func ai_seat() -> int:
	return int(get_setting("ai_seat")) if vs_computer() else -1


func is_ai_seat(p_owner: int) -> bool:
	return vs_computer() and p_owner == ai_seat()


func ai_difficulty() -> int:
	return clampi(int(get_setting("ai_difficulty")),
		AiPlayer.MIN_DIFFICULTY, AiPlayer.MAX_DIFFICULTY)


## The opponent for a fresh game, or null in a two-player game. main.gd asks
## for one at the start of every game rather than holding one across scenes,
## so changing the difficulty in the menu always takes effect.
func make_ai() -> AiPlayer:
	if not vs_computer():
		return null
	return AiPlayer.new(ai_seat(), ai_difficulty())


func return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func player_display_name(owner_id: int) -> String:
	if is_ai_seat(owner_id):
		return "Computer (%d — %s)" % [ai_difficulty(), AiPlayer.label(ai_difficulty())]
	var custom: String = str(get_setting("player_one" if owner_id == 0 else "player_two")).strip_edges()
	return custom if custom != "" else GameState.player_name(owner_id)
