## Scene root: owns the GameState, keeps the 3D view in sync with it, and
## drives the local pass-and-play loop.
##
## The rules engine below this is completely unaware of the scene tree — every
## interaction here is "ask GameState what is legal, tell GameState to commit,
## then animate what it reports".
extends Node3D

const PIECE_LIFT := BoardVisual.PLATE_THICKNESS * 0.5
const MOVE_TIME := 0.28
const VERTICAL_TIME := 0.42
## How far the mouse may travel with the left button down before the gesture
## counts as a camera pan rather than a click. Small enough that a deliberate
## drag is caught immediately, large enough to absorb the hand-wobble that comes
## with clicking a mouse.
const DRAG_THRESHOLD := 6.0
## How far down the top board fades while move shadow is on. Enough to see the
## projection through it, not so far that the board stops being a board.
const SHADOW_BOARD_ALPHA := 0.80
## How long the board sits still before the computer's first move of a turn,
## and between its moves. The search itself is well under half a second, so
## these are for legibility, not for hiding work: three moves landing at once
## is impossible to follow.
const AI_TURN_PAUSE := 0.45
const AI_STEP_PAUSE := 0.28

@onready var board: BoardVisual = $Board
@onready var rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD

var game: GameState
var pieces_root: Node3D
var visuals: Dictionary = {}          ## piece_id -> PieceVisual
## One column per direction. A piece standing on level 2 can go both ways at
## once, so a single shared beam would have to pick a winner.
var beam_up: VerticalBeam
var beam_down: VerticalBeam

var _selected_id := -1
var _legal_moves: Array = []
var _hovered := Vector3i(-1, -1, -1)
var _pending_promotion: Move = null
var _animating := false
var _view_mode := -1

## Left-button gesture state. The left button does double duty — click to
## select, drag to pan — so nothing is decided until the button comes back up.
var _left_down := false
var _press_pos := Vector2.ZERO
var _panning := false
## The release that closes a double-click must not also be read as a click.
var _swallow_release := false
## Move shadow: project the selected piece and its moves onto the other boards.
var _shadow := false
## The computer opponent, or null in a two-player game.
var _ai: AiPlayer = null


func _ready() -> void:
	# Says in the Output panel whether the real models were found. Cheap, and it
	# turns "why are these stand-ins?" into a line you can read.
	PieceModels.report()

	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	add_child(pieces_root)

	beam_up = VerticalBeam.create()
	beam_up.name = "BeamUp"
	add_child(beam_up)
	beam_down = VerticalBeam.create()
	beam_down.name = "BeamDown"
	add_child(beam_down)

	hud.undo_pressed.connect(_on_undo)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.view_mode_changed.connect(_on_view_mode)
	hud.promotion_chosen.connect(_on_promotion_chosen)
	hud.pass_confirmed.connect(_on_pass_confirmed)
	hud.restart_pressed.connect(_start_new_game)
	hud.shadow_toggled.connect(_on_shadow_toggled)
	hud.menu_confirmed.connect(func(): App.return_to_menu())

	_start_new_game()
	_apply_menu_settings()


## The handful of menu settings the game actually reads. Applied through the
## same HUD controls the player would press, so a saved default and a click
## take exactly the same path — there is no second way to enter a view mode.
func _apply_menu_settings() -> void:
	hud.select_view(int(App.get_setting("default_view")))
	hud.set_shadow(bool(App.get_setting("move_shadow_default")))


## The board's level tags and the HUD read from the same turn state, so they are
## always refreshed together.
func _refresh_ui() -> void:
	# One source of truth for both indicators: the levels a move could actually
	# end on right now, which is stricter than "levels not yet spent".
	var open_levels := game.available_destination_levels()
	hud.refresh(game, open_levels)
	board.set_available_levels(open_levels)
	if board.hovered_level() < 0:
		hud.hide_hint()


func _start_new_game() -> void:
	game = GameState.new()
	_selected_id = -1
	_legal_moves = []
	_pending_promotion = null
	_animating = false
	hud.hide_game_over()
	hud.hide_pass_screen()
	hud.show_promotion(false)
	_rebuild_visuals()
	_refresh_ui()
	hud.set_context("")

	# Rebuilt every game rather than held across scenes, so changing the
	# difficulty in the menu always takes effect on the next game.
	_ai = App.make_ai()
	hud.set_thinking(false)
	if _ai_to_move():
		_begin_ai_turn()


# --- the computer opponent -----------------------------------------------

func _ai_to_move() -> bool:
	return _ai != null and not game.is_game_over() and game.current_player == _ai.owner_id


func _begin_ai_turn() -> void:
	if not _ai_to_move():
		return
	_deselect()
	hud.set_thinking(true)
	_refresh_ui()
	# One frame so the indicator is on screen before the search blocks the
	# thread, then a beat so the turn does not start the instant yours ends.
	await get_tree().process_frame
	await get_tree().create_timer(AI_TURN_PAUSE).timeout
	_step_ai()


func _continue_ai_turn() -> void:
	await get_tree().create_timer(AI_STEP_PAUSE).timeout
	_step_ai()


func _step_ai() -> void:
	if not _ai_to_move():
		hud.set_thinking(false)
		_refresh_ui()
		return
	var choice := _ai.choose_move(game)
	if choice.is_empty():
		# Nothing legal left. End the turn rather than stall the game.
		hud.set_thinking(false)
		_finish_turn()
		return
	var move: Move = choice["move"]
	var promotion_type: int = int(choice["promotion_type"])
	if not _execute(move, promotion_type):
		hud.set_thinking(false)
		_finish_turn()


# --- visual sync ---------------------------------------------------------

static func piece_world(sq: Vector3i) -> Vector3:
	return BoardVisual.square_to_world(sq) + Vector3(0, PIECE_LIFT, 0)


## Destroys and recreates every piece node from the current board. Used at
## startup and after undo, because an undo snapshot rebuilds Piece objects
## (and can resurrect a captured piece), so patching in place is not safe.
func _rebuild_visuals() -> void:
	for child in pieces_root.get_children():
		child.queue_free()
	visuals = {}
	for pid in game.state.pieces:
		var p: Piece = game.state.pieces[pid]
		var v := PieceVisual.create_for(p)
		pieces_root.add_child(v)
		v.position = piece_world(p.position)
		visuals[pid] = v
	_apply_view_mode()
	_refresh_markers()


func _refresh_markers() -> void:
	for pid in visuals:
		var p: Piece = game.state.get_piece_by_id(pid)
		var v: PieceVisual = visuals[pid]
		if p == null:
			continue
		v.set_piece_type(p.type)
		v.set_restricted(p.pawn_restricted_step)


func _snap_all() -> void:
	for pid in visuals:
		var p: Piece = game.state.get_piece_by_id(pid)
		var v: PieceVisual = visuals[pid]
		if p == null:
			v.queue_free()
			visuals.erase(pid)
		else:
			v.position = piece_world(p.position)


# --- selection and highlighting ------------------------------------------

func _selected_piece() -> Piece:
	return game.state.get_piece_by_id(_selected_id)


func _select(piece: Piece) -> void:
	_selected_id = piece.id
	_legal_moves = game.get_legal_moves(piece)
	_update_context(piece)
	_redraw_highlights()


func _deselect() -> void:
	_selected_id = -1
	_legal_moves = []
	hud.set_context("")
	_redraw_highlights()


func _update_context(piece: Piece) -> void:
	var notes: Array = []
	if piece.position.z == BoardState.MIDDLE_LEVEL:
		notes.append("Queen rules active — on level 2 every piece moves like a queen, and nothing can be captured.")
	if piece.pawn_restricted_step:
		notes.append("This pawn came down from level 2 onto its first rank: single step only until it reaches its second rank.")
	hud.set_context("\n".join(notes))


func _redraw_highlights() -> void:
	board.clear_highlights()
	var piece := _selected_piece()
	if piece == null:
		_update_beam(null)
		return
	# Shadows first, so a real highlight always paints over one. They can collide:
	# a vertical move's destination is a genuine square on another board, and the
	# projection of the piece lands on that same board too.
	if _shadow:
		_draw_shadow(piece)
	board.highlight(piece.position, Palette.MOVE_SELECTED, 0.7)
	for m in _legal_moves:
		var col: Color = Palette.MOVE_CAPTURE if m.is_capture() else Palette.MOVE_QUIET
		if m.to == _hovered:
			col = Palette.MOVE_HOVER
		board.highlight(m.to, col, 0.75 if m.to == _hovered else 0.45)
	_update_beam(piece)


## Paints the selected piece and its reachable squares onto the two boards it is
## NOT standing on, at the same file and rank.
##
## This answers the question the three-board geometry raises constantly and the
## view cannot: "if this rook were one level up, what would it be attacking?"
## You are looking at a stack of parallel grids, and lining up a square on level
## 1 with the same square on level 3 by eye is genuinely hard.
##
## Nothing drawn here is playable, which is why the shadow is violet rather than
## any shade of the move green: the moment a shadow reads as somewhere you could
## click, the feature has made the board harder to play rather than easier.
func _draw_shadow(piece: Piece) -> void:
	# Only moves that stay on the piece's own board get projected. A vertical
	# move's destination is already a real, lit square on the target board;
	# shadowing it as well would say the same thing twice, in two colours.
	var flat: Array = []
	for m in _legal_moves:
		if m.to.z == piece.position.z:
			flat.append(Vector2i(m.to.x, m.to.y))

	for z in BoardState.LEVELS:
		if z == piece.position.z:
			continue
		for f in flat:
			board.highlight(Vector3i(f.x, f.y, z), Palette.SHADOW_MOVE, 0.22)
		# Last, so the piece's own square wins wherever the two overlap: where it
		# would be standing matters more than where it could then go.
		board.highlight(
			Vector3i(piece.position.x, piece.position.y, z), Palette.SHADOW_PIECE, 0.4)


## A destination highlight on another board is easy to miss, so a piece that can
## change level gets a standing column of motes on its own square, one per
## available direction — the vertical move advertises itself rather than hiding
## among the other destinations.
##
## Works out the wanted state first and applies it, rather than hiding both
## columns and rebuilding. This runs on every hover change, and hiding a running
## column only to immediately ask for it again would re-seed the particles and
## make the beam visibly stutter as the cursor crosses the board.
func _update_beam(piece: Piece) -> void:
	var want_up := false
	var want_down := false
	var from := Vector3i.ZERO
	if piece != null and not _animating:
		for m in _legal_moves:
			if m.kind != Move.Kind.VERTICAL:
				continue
			from = m.from
			if m.to.z > m.from.z:
				want_up = true
			else:
				want_down = true

	if want_up:
		_start_beam(from, 1, 1.0)
	elif beam_up != null:
		beam_up.hide_beam()

	if want_down:
		_start_beam(from, -1, 1.0)
	elif beam_down != null:
		beam_down.hide_beam()


func _hide_beams() -> void:
	if beam_up != null:
		beam_up.hide_beam()
	if beam_down != null:
		beam_down.hide_beam()


func _beam_for(direction: int) -> VerticalBeam:
	return beam_up if direction > 0 else beam_down


func _start_beam(from: Vector3i, direction: int, intensity: float) -> void:
	var b := _beam_for(direction)
	if b == null:
		return
	b.show_at(
		BoardVisual.square_to_world(from) + Vector3(0, PIECE_LIFT, 0),
		BoardVisual.LEVEL_GAP, direction, from.z, intensity
	)
	# Set outright rather than only clearing it: show_at() returns early when the
	# column is already running, so it cannot be relied on to restore visibility.
	b.visible = _view_mode < 0 or _view_mode == from.z


# --- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Camera panning is handled first and stays live during move animations and
	# while a piece is mid-flight — looking around is never "busy".
	if _handle_left_drag(event):
		return
	if _animating or hud.is_blocking():
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_F11:
		_toggle_fullscreen()
		return
	if event.is_action_pressed("ui_cancel"):
		_deselect()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Acted on release, not press, because the press might turn out to be
		# the start of a pan. The press position is what gets picked, so a click
		# that wobbles a pixel or two still lands where it was aimed.
		if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_press_pos)
	elif event is InputEventMouseMotion:
		var at: Vector2 = (event as InputEventMouseMotion).position
		var hit := _pick(at)
		board.set_hovered_level(hit.get("rim", -1))
		if board.hovered_level() >= 0:
			hud.show_hint("Move Available on this Level", at)
		else:
			hud.hide_hint()
		var sq: Vector3i = hit.get("square", Vector3i(-1, -1, -1))
		if sq != _hovered:
			_hovered = sq
			_redraw_highlights()


## F11 goes between the maximized window the game opens in and borderless
## fullscreen. Deliberately not bound to Esc, which deselects.
func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## A drag that is interrupted by the window losing focus never sees its release
## event, which would otherwise leave the button stuck down.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_left_down = false
		_panning = false


## Resolves the left button into either a camera pan or a click.
## Returns true when the event has been consumed as part of a drag gesture.
func _handle_left_drag(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			if mb.double_click:
				# The second press of a double-click is a camera gesture. Its own
				# release must be swallowed too, or the release handler below
				# would run _on_click() a second time on the same square — which
				# on a legal destination means playing the move twice.
				_left_down = false
				_panning = false
				_swallow_release = true
				_on_double_click(mb.position)
				return true
			_left_down = true
			_press_pos = mb.position
			_panning = false
			return true    # swallow the press; the gesture resolves on release
		if _swallow_release:
			_swallow_release = false
			return true
		_left_down = false
		if _panning:
			_panning = false
			return true    # that was a drag — no click at the end of it
		return false       # a genuine click; let the caller act on it
	if event is InputEventMouseMotion and _left_down:
		var mm := event as InputEventMouseMotion
		if not _panning and mm.position.distance_to(_press_pos) < DRAG_THRESHOLD:
			return true    # inside the threshold, still undecided
		_panning = true
		rig.pan(mm.relative)
		return true
	return false


## Physics raycast against the board squares (layer 1) and pieces (layer 2), so
## the player always picks what is visually in front — which matters with three
## boards stacked in one view.
func _pick(screen_pos: Vector2) -> Dictionary:
	var cam := rig.camera
	if cam == null:
		return {}
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var space := get_world_3d().direct_space_state

	# Squares (layer 1) and pieces (layer 2) are queried on their own FIRST. The
	# rim colliders are deliberately fat, and a single combined query would let
	# one sit in front of a legal destination square and swallow the click. Board
	# geometry always wins; the rim is only ever consulted for empty space.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0b11))
	if hit.is_empty():
		var rim := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0b100))
		if rim.is_empty():
			return {}
		var rim_body: Node = rim["collider"]
		if rim_body.has_meta("rim_level"):
			return {"rim": int(rim_body.get_meta("rim_level"))}
		return {}

	var collider: Node = hit["collider"]
	if collider.has_meta("piece_id"):
		var p: Piece = game.state.get_piece_by_id(int(collider.get_meta("piece_id")))
		if p != null:
			return {"square": p.position, "piece": p}
		return {}
	if collider.has_meta("square"):
		return {"square": collider.get_meta("square") as Vector3i}
	return {}


## Double-clicking a board centres the camera on it and looks down at it.
##
## The level is taken from whatever was under the cursor — a square, a piece
## standing on one, or the availability rim around the edge — so any part of a
## board is a valid target for the gesture.
##
## Selection is untouched on purpose. The first click of the pair has already
## done its normal job (picked a piece up, or played a move); this second one
## only moves the camera, so double-clicking can never cost you a move you did
## not mean to make.
func _on_double_click(screen_pos: Vector2) -> void:
	var hit := _pick(screen_pos)
	var level := -1
	if hit.has("rim"):
		level = int(hit["rim"])
	elif hit.has("square"):
		level = (hit["square"] as Vector3i).z
	if level < 0:
		return
	rig.look_down_at(level)

	# On the top and bottom boards there is a right way round to be looking, so
	# turn to it. The middle board starts empty and belongs to neither player,
	# so it has no home side and only gets centred.
	var name: String = BoardState.LEVEL_NAMES[level].to_lower()
	var owner := _view_owner()
	if CameraRig.home_yaw(owner, level) < 0.0:
		hud.show_status("Centred on the %s board." % name)
		return
	rig.face_home_side(owner, level)
	hud.show_status("Centred on the %s board, %s's side."
		% [name, App.player_display_name(owner)])


## Whose side of the board a double-click should turn to.
##
## Against the computer that is always the human, whichever seat they took —
## turning the board to the computer's side would be useless. In pass-and-play
## it is whoever is to move, because the device changes hands and the player
## looking at the screen is the one whose turn it is.
func _view_owner() -> int:
	if _ai != null:
		return 1 - _ai.owner_id
	return game.current_player


func _on_click(screen_pos: Vector2) -> void:
	if game.is_game_over() or _ai_to_move() or hud.is_thinking():
		return
	var hit := _pick(screen_pos)
	if hit.has("rim"):
		return          # the rim is an indicator, not something to click
	if hit.is_empty():
		_deselect()
		return
	var square: Vector3i = hit["square"]
	var piece: Piece = hit.get("piece", null)

	# A legal destination always wins — including clicking an enemy piece to
	# capture it, or a friendly square that a castle passes through.
	if _selected_id >= 0:
		var move: Move = Move.find_to(_legal_moves, square)
		if move != null:
			_execute(move)
			return

	if piece != null:
		var err := game.selection_error(piece)
		if err.is_empty():
			_select(piece)
		else:
			board.flash_invalid(square)
			hud.show_status(err)
		return

	# An empty square that is not a legal destination, with something picked up.
	if _selected_id >= 0:
		board.flash_invalid(square)
		hud.show_status("Not a legal move for that piece.")
	else:
		_deselect()


# --- committing and animating a move -------------------------------------

## Returns true when the move was committed and is now animating. The computer
## needs that answer to know whether its turn is still running.
func _execute(move: Move, promotion_type: int = -1) -> bool:
	var mover: Piece = game.state.get_piece_by_id(move.piece_id)
	var from_pos := mover.position
	var captured_id: int = move.captured_id

	var result := game.apply_move(move, promotion_type)

	if result["needs_promotion"]:
		_pending_promotion = move
		hud.show_promotion(true)
		return false
	if not result["ok"]:
		board.flash_invalid(move.to)
		hud.show_status(result["reason"])
		return false

	_deselect()
	board.clear_highlights()
	_animate(move, from_pos, captured_id)
	return true


func _animate(move: Move, from_pos: Vector3i, captured_id: int) -> void:
	_animating = true
	var v: PieceVisual = visuals.get(move.piece_id, null)
	var tween := create_tween()
	tween.set_parallel(true)

	# The captured piece leaves first so the capturing piece lands on a clear
	# square (art doc §5 placeholder: shrink out, no shatter VFX yet).
	if captured_id >= 0 and visuals.has(captured_id):
		var cv: PieceVisual = visuals[captured_id]
		visuals.erase(captured_id)
		tween.tween_property(cv, "scale", Vector3(0.01, 0.01, 0.01), 0.18)
		tween.chain().tween_callback(cv.queue_free)

	if v != null:
		var target := piece_world(move.to)
		if move.kind == Move.Kind.VERTICAL:
			# The signature mechanic — slower and eased so the level change is
			# unmistakably different from a slide across a board, and trailing
			# the same green column that hinted at it (art doc §5).
			_start_beam(move.from, signi(move.to.z - move.from.z), 1.6)
			tween.tween_property(v, "position", target, VERTICAL_TIME) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		elif v.piece_type == Piece.Type.KNIGHT:
			# A knight's move does not read as a straight line, so it hops.
			var start := v.position
			tween.tween_method(
				func(t: float): v.position = _arc(start, target, t), 0.0, 1.0, MOVE_TIME
			).set_trans(Tween.TRANS_SINE)
		else:
			tween.tween_property(v, "position", target, MOVE_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if move.kind == Move.Kind.CASTLE and visuals.has(move.rook_id):
		var rv: PieceVisual = visuals[move.rook_id]
		tween.tween_property(rv, "position", piece_world(move.rook_to), MOVE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.chain().tween_callback(_after_animation.bind(move))


func _arc(from: Vector3, to: Vector3, t: float) -> Vector3:
	var p := from.lerp(to, t)
	p.y += sin(t * PI) * 0.9
	return p


func _after_animation(move: Move) -> void:
	var v: PieceVisual = visuals.get(move.piece_id, null)
	if v != null and move.promotion_type >= 0:
		v.set_piece_type(move.promotion_type)
		# Scale pulse so the promotion reads as a moment, not a silent swap.
		var t := create_tween()
		t.tween_property(v, "scale", Vector3(1.35, 1.35, 1.35), 0.12)
		t.tween_property(v, "scale", Vector3.ONE, 0.16)
	_snap_all()
	_refresh_markers()
	_animating = false
	_hide_beams()
	_refresh_ui()

	if game.is_game_over():
		hud.set_thinking(false)
		hud.show_game_over(game.winner)
		return
	if game.is_turn_complete():
		# The turn auto-ends at the cap, which takes the undo snapshot with it,
		# so the third move of a turn cannot normally be taken back. The menu
		# setting holds the turn open instead and lets End turn close it — but
		# only for a human, since nobody is waiting to undo the computer's.
		if App.get_setting("undo_after_final_move") and not _ai_to_move():
			hud.show_status("Turn is full — undo, or End turn when you're ready.")
		else:
			_finish_turn()
	elif _ai_to_move():
		_continue_ai_turn()


func _finish_turn() -> void:
	game.end_turn()
	board.clear_highlights()
	hud.set_thinking(false)
	_refresh_ui()
	if _ai != null:
		# No device changes hands against the computer, so there is nothing to
		# pass and no reason to hide the board.
		if _ai_to_move():
			_begin_ai_turn()
		return
	hud.show_pass_screen(game.current_player)


# --- HUD callbacks -------------------------------------------------------

func _on_undo() -> void:
	if _animating or hud.is_thinking() or not game.can_undo():
		return
	game.undo_last_move()
	_deselect()
	_rebuild_visuals()
	_refresh_ui()
	hud.show_status("Last move undone.")


func _on_end_turn() -> void:
	if _animating or hud.is_thinking() or game.is_game_over():
		return
	_deselect()
	_finish_turn()


func _on_promotion_chosen(piece_type: int) -> void:
	hud.show_promotion(false)
	var move := _pending_promotion
	_pending_promotion = null
	if move != null:
		_execute(move, piece_type)


func _on_pass_confirmed() -> void:
	hud.hide_pass_screen()
	_refresh_ui()


func _on_view_mode(mode: int) -> void:
	_view_mode = mode
	_apply_view_mode()
	rig.set_view_mode(mode)


## The top board fades whenever the mode is on, selection or not — that fade is
## how the button reads as engaged from the board itself rather than only from
## the button. Without it, turning the mode on with nothing picked up would look
## like nothing happened.
func _on_shadow_toggled(on: bool) -> void:
	_shadow = on
	board.set_level_alpha(BoardState.LEVELS - 1, SHADOW_BOARD_ALPHA if on else 1.0)
	_redraw_highlights()


func _apply_view_mode() -> void:
	board.set_view_mode(_view_mode)
	for b in [beam_up, beam_down]:
		if b != null and b.source_level >= 0:
			b.visible = _view_mode < 0 or _view_mode == b.source_level
	for pid in visuals:
		var p: Piece = game.state.get_piece_by_id(pid)
		var v: PieceVisual = visuals[pid]
		var shown := _view_mode < 0 or (p != null and p.position.z == _view_mode)
		v.visible = shown
		v.set_pickable(shown)
