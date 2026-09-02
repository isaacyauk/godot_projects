## Integration smoke test: boots the real scene, plays a short scripted turn
## and checks the view stays in sync with the rules engine.
##
##   godot --headless --path <project> --script res://tests/test_scene.gd
extends SceneTree

var main: Node3D
var _step := 0
var _wait := 0
var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("Parallel Worlds Chess — scene integration test\n")
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	root.add_child(main)


func ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			ok(main.visuals.size() == 64, "64 piece nodes built from the board")
			ok(main.game != null and main.game.current_player == 0, "White to move at boot")
			# The rim colliders are fat and sit right against the board. Picking
			# must always prefer the board: a rim swallowing a click on a legal
			# destination is the worst possible failure here.
			# A far square can legitimately be occluded by a board above it — that
			# is what the focused views are for. The invariant is narrower and
			# more important: pointing at board geometry must never come back as
			# a rim, whatever else is in the way.
			for edge in [Vector3i(0, 0, 0), Vector3i(7, 0, 0), Vector3i(0, 7, 0), Vector3i(4, 7, 2)]:
				var at: Vector2 = main.rig.camera.unproject_position(main.piece_world(edge))
				var hit: Dictionary = main._pick(at)
				ok(not hit.has("rim"),
					"the rim never swallows a pick aimed at square %s" % str(edge))
			var near: Vector2 = main.rig.camera.unproject_position(main.piece_world(Vector3i(0, 0, 0)))
			ok(main._pick(near).get("square", Vector3i.ZERO) == Vector3i(0, 0, 0),
				"and a clear edge square picks itself exactly")
			_step += 1
		1:
			# Raycast picking through the real physics world.
			var vp_size: Vector2 = main.rig.camera.get_viewport().get_visible_rect().size
			var hit: Dictionary = main._pick(vp_size * 0.5)
			ok(not hit.is_empty(), "a ray through the middle of the screen hits the stack")
			# A level-1 piece can only ever rise, so it gets one beam.
			var kn: Piece = main.game.state.get_piece(Vector3i(1, 0, 0))
			main._select(kn)
			ok(main.beam_up.visible, "a piece that can rise gets an upward beam")
			ok(not main.beam_down.visible, "nothing drops out of the bottom board")
			main._deselect()
			ok(not main.beam_up.visible, "deselecting clears it")
			_step += 1
		2:
			# Vertical move: a level-1 pawn rises to the empty middle board.
			var pawn: Piece = main.game.state.get_piece(Vector3i(4, 1, 0))
			var move: Move = _find(pawn, Vector3i(4, 1, 1))
			ok(move != null and move.kind == Move.Kind.VERTICAL, "the pawn may rise to level 2")
			main._execute(move)
			_wait = 400
			_step += 1
		3:
			var pawn: Piece = main.game.state.get_piece(Vector3i(4, 1, 1))
			ok(pawn != null, "the pawn is on level 2 in the game state")
			var v = main.visuals[pawn.id]
			ok(v.position.distance_to(main.piece_world(Vector3i(4, 1, 1))) < 0.01,
				"its node finished the animation on the right square")
			ok(main.game.moves_made_this_turn == 1, "one move counted against the turn")
			# The board rims track the no-two-moves-per-level rule.
			ok(not main.board._rim_available[1],
				"level 2's rim goes out once a move ends there")
			ok(not main.board._rims[1].visible, "and the outline is hidden")
			ok(main.board._rim_available[0] and main.board._rim_available[2],
				"levels 1 and 3 stay lit")
			# A spent level cannot be hovered, because it has no rim to point at.
			main.board.set_hovered_level(1)
			ok(main.board._hover_level == -1, "a spent level ignores hover")
			main.board.set_hovered_level(0)
			ok(main.board._hover_level == 0, "an available level accepts it")
			main.board.set_hovered_level(0)
			_wait = 30        # let real frames run, which is what animates it
			_step += 1
		4:
			ok(main.board.hovered_level() == 0, "the rim reports itself hovered")
			ok(main.board._rim_intensity[0] > 1.2,
				"and brightens while pointed at (%.2f)" % main.board._rim_intensity[0])
			ok(main.board._rim_intensity[2] < 1.2, "an unhovered rim stays at rest")
			main.hud.show_hint("Move Available on this Level", Vector2(400, 300))
			ok(main.hud._hint_panel.visible, "the cursor tooltip shows")
			ok(main.hud._hint_label.text == "Move Available on this Level",
				"with the right wording")
			main.board.set_hovered_level(-1)
			main.hud.hide_hint()
			_wait = 60
			_step += 1
		5:
			ok(not main.hud._hint_panel.visible, "the tooltip goes away with the hover")
			ok(main.board._rim_intensity[0] < 1.1, "and the rim eases back to rest")
			_step += 1
		6:
			# Second move on White's capped first turn ends it and raises the
			# pass-the-device screen.
			var knight: Piece = main.game.state.get_piece(Vector3i(1, 0, 0))
			main._execute(_find(knight, Vector3i(2, 2, 0)))
			_wait = 400
			_step += 1
		7:
			ok(main.game.current_player == 1, "the turn auto-ended after the second move")
			ok(main.board._rim_available[1], "every board's rim relights on the new turn")
			ok(main.hud.is_blocking(), "the pass-to-opponent screen is up")
			main._on_pass_confirmed()
			ok(not main.hud.is_blocking(), "confirming the handoff clears it")
			_step += 1
		8:
			# Level 2 really is queen-rules and capture-free.
			var pawn: Piece = main.game.state.get_piece(Vector3i(4, 1, 1))
			var dests: Array = Move.destinations(BoardRules.get_piece_moves(main.game.state, pawn))
			ok(dests.has(Vector3i(7, 1, 1)), "the pawn slides like a queen on level 2")
			_step += 1
		9:
			# A left-drag past the threshold pans the camera and must NOT select.
			var origin_before: Vector3 = main.rig._target_origin
			_press(Vector2(640, 400))
			_drag(Vector2(700, 430), Vector2(60, 30))
			_release(Vector2(700, 430))
			ok(main.rig._target_origin != origin_before, "a left-drag pans the camera")
			ok(main._selected_id == -1, "and does not select anything")
			ok(not main._panning, "the pan gesture ends cleanly on release")
			_step += 1
		10:
			# The pan clamp keeps the board findable.
			for i in 80:
				main.rig.pan(Vector2(60, 0))
			var d: float = (main.rig._target_origin - BoardVisual.stack_centre()).length()
			ok(d < 20.0, "panning is clamped near the stack (drifted %.1f units)" % d)
			main.rig.set_view_mode(-1)
			ok(main.rig._target_origin == BoardVisual.stack_centre(), "the View buttons recentre")
			_step += 1
		11:
			# A left-click that barely moves still selects. Black is to move by
			# now, so this picks a Black knight on level 3 — the top board, where
			# nothing can occlude the pick ray.
			var square := Vector3i(1, 0, 2)
			var knight: Piece = main.game.state.get_piece(square)
			if knight == null or main.game.current_player != knight.owner_id:
				ok(false, "test fixture: expected an unmoved Black knight on level 3")
			else:
				var screen: Vector2 = main.rig.camera.unproject_position(
					main.piece_world(square) + Vector3(0, 0.35, 0))
				_press(screen)
				_drag(screen + Vector2(2, 1), Vector2(2, 1))
				_release(screen + Vector2(2, 1))
				ok(main._selected_id == knight.id, "a click with 2px of wobble still selects")
				# Level 3 is the top board: this knight can only drop.
				ok(main.beam_down.visible, "a piece that can drop gets a downward beam")
				ok(not main.beam_up.visible, "nothing rises off the top board")
			_step += 1
		12:
			# Slide the level-2 pawn to the middle of the board, where both the
			# square above and the square below are empty. At (4,1,1) the level-3
			# square directly overhead holds a Black pawn, so it can only drop.
			main._deselect()
			main.game.end_turn()          # hand the move back to White
			var mid: Piece = main.game.state.get_piece(Vector3i(4, 1, 1))
			main._execute(_find(mid, Vector3i(4, 4, 1)))
			_wait = 400
			_step += 1
		13:
			# A piece on level 2 with clear air both ways runs both columns.
			main.game.end_turn()
			main.game.end_turn()          # back to White, with a fresh turn
			var mid2: Piece = main.game.state.get_piece(Vector3i(4, 4, 1))
			ok(mid2 != null, "the pawn slid to the middle of level 2")
			main._select(mid2)
			ok(main.beam_up.visible, "it beams upward")
			ok(main.beam_down.visible, "and downward at the same time")
			_step += 1
		14:
			# Hovering redraws the highlights on every square change. That must
			# not re-seed the particle emitters, which would restart the loop and
			# show up as a stutter every time the cursor crosses a square.
			var up_before: int = main.beam_up.restarts
			var down_before: int = main.beam_down.restarts
			for sq in [Vector3i(0, 0, 1), Vector3i(7, 7, 1), Vector3i(3, 5, 0), Vector3i(2, 2, 2)]:
				var at: Vector2 = main.rig.camera.unproject_position(main.piece_world(sq))
				_hover(at)
			# And directly, in case none of those rays landed on a new square.
			for i in 5:
				main._hovered = Vector3i(i, i, 1)
				main._redraw_highlights()
			ok(main.beam_up.restarts == up_before,
				"hovering does not re-seed the upward column (%d -> %d)"
					% [up_before, main.beam_up.restarts])
			ok(main.beam_down.restarts == down_before, "nor the downward one")
			ok(main.beam_up.visible and main.beam_down.visible, "and both stay lit")
			_step += 1
		15:
			# Deselecting still stops them, and re-selecting re-seeds once.
			var seeds: int = main.beam_up.restarts
			main._deselect()
			ok(not main.beam_up.visible, "deselecting hides the column")
			main._select(main.game.state.get_piece(Vector3i(4, 4, 1)))
			ok(main.beam_up.restarts == seeds + 1, "re-selecting re-seeds it exactly once")
			_step += 1
		16:
			# Move shadow: the selected piece and its flat moves get painted onto
			# the two boards it is not on, and the top board fades so you can see
			# through to them.
			var sel: Piece = main.game.state.get_piece(Vector3i(4, 4, 1))
			ok(sel != null and main._selected_id == sel.id, "the level-2 pawn is still picked up")
			var alpha_before: float = main.board._level_alpha[2]
			main._on_shadow_toggled(true)
			ok(main.board._level_alpha[2] < alpha_before, "the top board fades")
			ok(main.board._level_alpha[0] == 1.0, "and the other boards do not")
			ok(_lit(Vector3i(4, 4, 0)) and _lit(Vector3i(4, 4, 2)),
				"the piece is shadowed onto both other boards")
			# A square this piece can reach on level 2 must appear on 1 and 3 too.
			var reach := Vector3i(-1, -1, -1)
			for m in main._legal_moves:
				if m.to.z == 1 and m.to != sel.position:
					reach = m.to
					break
			ok(reach.x >= 0, "test fixture: the pawn has a move on its own level")
			ok(_lit(Vector3i(reach.x, reach.y, 0)), "its destinations are shadowed down")
			ok(_lit(Vector3i(reach.x, reach.y, 2)), "and up")
			_step += 1
		17:
			# The shadow is dimmer than a real move, which is what stops it
			# reading as a square you may click.
			var real := Vector3i(-1, -1, -1)
			for m in main._legal_moves:
				if m.to.z == 1 and m.to != main._selected_piece().position:
					real = m.to
					break
			var shadow_energy: float = _energy(Vector3i(real.x, real.y, 0))
			ok(shadow_energy < 0.45,
				"a shadowed square stays well below a real one (%.2f)" % shadow_energy)
			main._on_shadow_toggled(false)
			ok(main.board._level_alpha[2] == 1.0, "turning it off restores the top board")
			# Checked on a projected destination, not on the piece's own column:
			# this pawn is on level 2, so (4,4,0) and (4,4,2) are real vertical
			# moves and stay lit whether the shadow is on or not.
			ok(not _lit(Vector3i(real.x, real.y, 0)), "and clears the projection")
			ok(_lit(Vector3i(4, 4, 0)), "while a real vertical move stays lit")
			ok(main.hud.SHADOW_HINT.contains("above and below"),
				"the button explains itself on hover")
			_step += 1
		18:
			# Double-clicking a board centres the camera on it, looking down,
			# without hiding the other two or disturbing the selection.
			main._deselect()
			main._on_view_mode(-1)
			var sq := Vector3i(4, 4, 0)
			var at: Vector2 = main.rig.camera.unproject_position(main.piece_world(sq))
			var pitch_before: float = main.rig._target_pitch
			_double_click(at)
			ok(main.rig._target_origin.is_equal_approx(
					Vector3(0, BoardVisual.level_height(0), 0)),
				"double-click centres on the board that was clicked")
			ok(main.rig._target_pitch < pitch_before, "and tips the camera down")
			ok(main.rig._target_pitch == CameraRig.LOOK_DOWN_PITCH, "to the look-down angle")
			ok(main.board._level_roots[2].visible, "the other boards stay on screen")
			# The camera must clear the top of the stack, or the board above the
			# one you asked for fills the screen and hides it.
			var eye: float = main.rig._target_origin.y \
				+ main.rig._target_distance * sin(deg_to_rad(-CameraRig.LOOK_DOWN_PITCH))
			ok(eye > BoardVisual.level_height(BoardState.LEVELS - 1),
				"and rises above the top board (eye %.1f, stack top %.1f)"
					% [eye, BoardVisual.level_height(BoardState.LEVELS - 1)])
			_step += 1
		19:
			# The second press of a double-click, and the release that closes it,
			# must not ALSO be read as an ordinary click. Without the guard the
			# release falls through to _on_click() on the same square, which on a
			# legal destination means playing the move twice.
			var at2: Vector2 = main.rig.camera.unproject_position(
				main.piece_world(Vector3i(4, 4, 0)))
			var moves_before: int = main.game.moves_made_this_turn
			_double_press(at2)
			ok(main._swallow_release, "the double-click arms the release guard")
			_release(at2)
			ok(not main._swallow_release, "the release is swallowed, not clicked")
			ok(main.game.moves_made_this_turn == moves_before,
				"and the gesture plays no move of its own")
			_step += 1
		20:
			# Double-clicking the top or bottom board also turns the camera to
			# the side the player's own army is on.
			var who: int = main._view_owner()
			for level in [0, 2]:
				# Aimed from the wide stack view, not the steep look-down one: at
				# -60 degrees the ray to the middle of the bottom board passes
				# through the boards above it and picks the wrong level.
				_aim_stack(90.0)
				var at3: Vector2 = main.rig.camera.unproject_position(
					main.piece_world(Vector3i(4, 4, level)))
				main._on_double_click(at3)
				# Asserted first so a pick that landed on the wrong board fails
				# here, saying so, instead of surfacing as a puzzling yaw.
				ok(main.rig._target_origin.is_equal_approx(
						Vector3(0, BoardVisual.level_height(level), 0)),
					"the %s board is what got picked" % BoardState.LEVEL_NAMES[level].to_lower())
				ok(is_equal_approx(main.rig._target_yaw, CameraRig.home_yaw(who, level)),
					"double-clicking the %s board faces %s's side (yaw %.0f)"
						% [BoardState.LEVEL_NAMES[level].to_lower(),
							GameState.player_name(who), main.rig._target_yaw])
			_step += 1
		21:
			# The middle board belongs to neither player, so it centres without
			# turning — spinning the view there would be a change with no meaning
			# behind it.
			_aim_stack(90.0)
			var mid: Vector2 = main.rig.camera.unproject_position(
				main.piece_world(Vector3i(4, 4, BoardState.MIDDLE_LEVEL)))
			main._on_double_click(mid)
			ok(main.rig._target_origin.is_equal_approx(
					Vector3(0, BoardVisual.level_height(BoardState.MIDDLE_LEVEL), 0)),
				"the middle board is what got picked")
			ok(is_equal_approx(main.rig._target_yaw, 90.0),
				"and it centres without turning (yaw %.0f)" % main.rig._target_yaw)
			_step += 1
		22:
			# Yaw accumulates without bound as you drag, so the turn has to be
			# taken the short way round rather than by assigning a raw angle —
			# otherwise a player who has orbited a few times watches the camera
			# unwind all of it.
			main.rig.yaw = 710.0
			main.rig._target_yaw = 710.0
			main.rig.face_home_side(0, 0)      # wants yaw 0, i.e. 720 from here
			var turn: float = absf(main.rig._target_yaw - 710.0)
			ok(turn <= 180.0,
				"a turn from yaw 710 goes the short way (%.0f degrees, not 710)" % turn)
			ok(is_equal_approx(fposmod(main.rig._target_yaw, 360.0), 0.0),
				"and still lands on the right side of the board")
			_step += 1
		23:
			# The View Boards buttons are named for where the boards are, and
			# every button maps to the mode the selector says it does.
			# The choice table is read off the HUD instance rather than named as
			# a class constant. Naming the class here would make hud.gd a
			# compile-time dependency of this script, and hud.gd calls
			# App.player_display_name(); an entry script passed to --script is
			# compiled before autoloads are registered, so that reference would
			# not resolve and this whole suite would stop running.
			var choices: Array = main.hud.VIEW_CHOICES
			ok(main.hud._view_buttons.size() == choices.size(),
				"a button per view choice")
			var names: Array = []
			for b in main.hud._view_buttons:
				names.append((b as Button).text)
			ok(names == ["All", "Top", "Mid", "Bottom"],
				"named top-down: %s" % str(names))
			for idx in choices.size():
				var choice: Dictionary = choices[idx]
				main.hud.select_view(int(choice["mode"]))
				main._on_view_mode(int(choice["mode"]))
				ok((main.hud._view_buttons[idx] as Button).button_pressed,
					"selecting mode %d lights the %s button"
						% [int(choice["mode"]), String(choice["label"])])
			main.hud.select_view(-1)
			main._on_view_mode(-1)
			_step += 1
		24:
			print("\n%d passed, %d failed" % [_passed, _failed])
			quit(1 if _failed > 0 else 0)
	return false


## True when this square is carrying any highlight at all.
func _lit(sq: Vector3i) -> bool:
	return _energy(sq) > 0.0


## How brightly a square is lit, 0.0 when it is at its base colour. Reads the
## material rather than any bookkeeping, so it cannot pass on a board that only
## thinks it drew something.
func _energy(sq: Vector3i) -> float:
	var idx := sq.y * BoardState.SIZE + sq.x
	var mat: Material = main.board._materials[sq.z][idx]
	if mat is ShaderMaterial:
		return float((mat as ShaderMaterial).get_shader_parameter("highlight_amount"))
	var sm := mat as StandardMaterial3D
	return sm.emission_energy_multiplier if sm.emission_enabled else 0.0


## Puts the camera in the wide stack view at a given yaw and settles it, so a
## screen position computed next is against the transform the pick will use.
## Without the _apply() the rig's transform is still wherever the last frame
## left it, and unproject_position() hands back a point aimed somewhere else.
func _aim_stack(yaw: float) -> void:
	main.rig.yaw = yaw
	main.rig._target_yaw = yaw
	main.rig._target_pitch = CameraRig.STACK_PITCH
	main.rig._target_distance = CameraRig.STACK_DISTANCE
	main.rig._target_origin = BoardVisual.stack_centre()
	main.rig._apply(1.0)


## The second press of a pair, the one the OS flags as a double-click.
func _double_press(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	e.position = at
	main._unhandled_input(e)


## The full four events the OS sends for a double-click.
func _double_click(at: Vector2) -> void:
	_press(at)
	_release(at)
	_double_press(at)
	_release(at)


func _press(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	main._unhandled_input(e)


func _drag(to: Vector2, relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = to
	e.relative = relative
	main._unhandled_input(e)


func _hover(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = Vector2(4, 4)
	main._unhandled_input(e)


func _release(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	main._unhandled_input(e)


func _find(piece: Piece, square: Vector3i) -> Move:
	for m in main.game.get_legal_moves(piece):
		if m.to == square:
			return m
	return null
