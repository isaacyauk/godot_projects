## Headless test suite for the rules engine.
##
##   godot --headless --path <project> --script res://tests/test_rules.gd
##
## No scene tree, no rendering — this is the "testable via plain function calls"
## milestone from the design doc's KISS note (§3) and build order step 2.
extends SceneTree

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print("Parallel Worlds Chess — rules engine tests\n")

	test_initial_setup()
	test_mirrored_armies()
	test_pawn_basic_moves()
	test_vertical_movement()
	test_king_cannot_move_vertically()
	test_level2_queen_movement()
	test_level2_forbids_capture()
	test_level2_no_promotion()
	test_promotion_leaving_level2()
	test_restricted_pawn_after_level2_drop()
	test_promotion_requires_choice()
	test_castling()
	test_en_passant()
	test_turn_move_cap()
	test_one_move_per_level()
	test_one_move_per_piece()
	test_win_on_king_capture()
	test_available_levels()
	test_undo()
	test_serialisation_round_trip()
	test_home_side_orientation()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- tiny assert helpers -------------------------------------------------

func t(name: String) -> void:
	_current = name


func ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s — %s" % [_current, what])
	else:
		_failed += 1
		print("  FAIL  %s — %s" % [_current, what])


func eq(a, b, what: String) -> void:
	ok(a == b, "%s (got %s, expected %s)" % [what, str(a), str(b)])


# --- fixtures ------------------------------------------------------------

## An empty board with no pieces at all, for isolating one rule at a time.
func empty_state() -> BoardState:
	return BoardState.new()


func put(s: BoardState, type: int, p_owner: int, p_army: int, sq: Vector3i) -> Piece:
	var p := Piece.create(s.next_id(), type as Piece.Type, p_owner, p_army, sq)
	s.add_piece(p)
	return p


func destinations_of(g: GameState, p: Piece) -> Array:
	return Move.destinations(g.get_legal_moves(p))


func rule_destinations(s: BoardState, p: Piece) -> Array:
	return Move.destinations(BoardRules.get_piece_moves(s, p))


# --- tests ---------------------------------------------------------------

func test_initial_setup() -> void:
	t("initial setup")
	var s := BoardState.create_initial()
	eq(s.pieces.size(), 64, "four 16-piece armies on the board")
	var level2_count := 0
	for x in 8:
		for y in 8:
			if s.get_piece(Vector3i(x, y, 1)) != null:
				level2_count += 1
	eq(level2_count, 0, "level 2 starts empty")
	var kings := 0
	for pid in s.pieces:
		if (s.pieces[pid] as Piece).type == Piece.Type.KING:
			kings += 1
	eq(kings, 4, "two kings per player")
	eq(s.get_piece(Vector3i(4, 0, 0)).type, Piece.Type.KING, "White king on e1 of level 1")
	eq(s.get_piece(Vector3i(4, 0, 0)).owner_id, 0, "…and it is White's")


func test_mirrored_armies() -> void:
	t("mirrored armies")
	var s := BoardState.create_initial()
	var w1 := s.get_piece(Vector3i(0, 1, 0))   # White pawn, level 1
	var w3 := s.get_piece(Vector3i(0, 6, 2))   # White pawn, level 3
	eq(w1.owner_id, 0, "White pawn on level 1")
	eq(w3.owner_id, 0, "White pawn on level 3")
	eq(w1.forward, 1, "level-1 White pawns advance up the ranks")
	eq(w3.forward, -1, "level-3 White army is mirrored")
	eq(s.get_piece(Vector3i(0, 1, 2)).owner_id, 1, "Black holds level 3's low ranks")


func test_pawn_basic_moves() -> void:
	t("pawn moves")
	var s := empty_state()
	var p := put(s, Piece.Type.PAWN, 0, 0, Vector3i(4, 1, 0))
	var d := rule_destinations(s, p)
	ok(d.has(Vector3i(4, 2, 0)), "single step forward")
	ok(d.has(Vector3i(4, 3, 0)), "double step from its own second rank")
	put(s, Piece.Type.PAWN, 1, 0, Vector3i(5, 2, 0))
	put(s, Piece.Type.PAWN, 0, 0, Vector3i(3, 2, 0))
	d = rule_destinations(s, p)
	ok(d.has(Vector3i(5, 2, 0)), "captures an enemy diagonally")
	ok(not d.has(Vector3i(3, 2, 0)), "does not capture its own piece")


func test_vertical_movement() -> void:
	t("vertical movement")
	var s := empty_state()
	var r := put(s, Piece.Type.ROOK, 0, 0, Vector3i(2, 3, 0))
	var d := rule_destinations(s, r)
	ok(d.has(Vector3i(2, 3, 1)), "rises one level onto the same square")
	ok(not d.has(Vector3i(2, 3, 2)), "never skips straight from level 1 to level 3")
	put(s, Piece.Type.PAWN, 1, 0, Vector3i(2, 3, 1))
	d = rule_destinations(s, r)
	ok(not d.has(Vector3i(2, 3, 1)), "blocked by an occupied square — no capture on a vertical move")


func test_king_cannot_move_vertically() -> void:
	t("king is level-bound")
	var s := empty_state()
	var k := put(s, Piece.Type.KING, 0, 0, Vector3i(4, 3, 0))
	var d := rule_destinations(s, k)
	ok(not d.has(Vector3i(4, 3, 1)), "the king may not change level")
	ok(d.has(Vector3i(4, 4, 0)), "…but still walks normally")


func test_level2_queen_movement() -> void:
	t("level 2 queen rules")
	var s := empty_state()
	var n := put(s, Piece.Type.KNIGHT, 0, 0, Vector3i(3, 3, 1))
	var d := rule_destinations(s, n)
	ok(d.has(Vector3i(7, 3, 1)), "a knight slides like a queen on level 2")
	ok(d.has(Vector3i(0, 0, 1)), "…diagonally too")
	ok(not d.has(Vector3i(4, 5, 1)), "…and loses its own knight move")
	ok(d.has(Vector3i(3, 3, 0)) and d.has(Vector3i(3, 3, 2)), "can still drop to either outer board")


func test_level2_forbids_capture() -> void:
	t("level 2 forbids capture")
	var s := empty_state()
	var q := put(s, Piece.Type.QUEEN, 0, 0, Vector3i(0, 0, 1))
	put(s, Piece.Type.PAWN, 1, 0, Vector3i(3, 0, 1))
	var d := rule_destinations(s, q)
	ok(not d.has(Vector3i(3, 0, 1)), "an enemy piece on level 2 cannot be taken")
	ok(d.has(Vector3i(2, 0, 1)), "movement stops just short of it")
	ok(not d.has(Vector3i(4, 0, 1)), "and cannot slide past it")


func test_level2_no_promotion() -> void:
	t("no promotion on level 2")
	var s := empty_state()
	var p := put(s, Piece.Type.PAWN, 0, 0, Vector3i(3, 6, 1))
	for m in BoardRules.get_piece_moves(s, p):
		if m.to == Vector3i(3, 7, 1):
			ok(not m.is_promotion, "reaching the last rank on level 2 does not promote")


func test_promotion_leaving_level2() -> void:
	t("promotion leaving level 2")
	var s := empty_state()
	var p := put(s, Piece.Type.PAWN, 0, 0, Vector3i(3, 7, 1))
	var found := false
	for m in BoardRules.get_piece_moves(s, p):
		if m.to == Vector3i(3, 7, 0):
			found = m.is_promotion
	ok(found, "dropping from level 2 onto its own last rank promotes immediately")


func test_restricted_pawn_after_level2_drop() -> void:
	t("restricted pawn")
	var s := empty_state()
	put(s, Piece.Type.KING, 0, 0, Vector3i(7, 7, 0))
	put(s, Piece.Type.KING, 1, 0, Vector3i(0, 7, 0))
	var p := put(s, Piece.Type.PAWN, 0, 0, Vector3i(3, 0, 1))
	var g := GameState.new(s)

	var drop: Move = null
	for m in g.get_legal_moves(p):
		if m.to == Vector3i(3, 0, 0):
			drop = m
	ok(drop != null and drop.sets_restricted, "dropping onto its own first rank flags the pawn")
	g.apply_move(drop)
	ok(p.pawn_restricted_step, "the restriction is recorded on the piece")

	var d := rule_destinations(s, p)
	ok(d.has(Vector3i(3, 1, 0)), "it may still step one square")
	ok(not d.has(Vector3i(3, 2, 0)), "but has lost its two-step option")

	g.end_turn()
	g.end_turn()
	var step: Move = null
	for m in g.get_legal_moves(p):
		if m.to == Vector3i(3, 1, 0):
			step = m
	g.apply_move(step)
	ok(not p.pawn_restricted_step, "the restriction lifts on reaching its second rank")
	ok(rule_destinations(s, p).has(Vector3i(3, 3, 0)), "and the two-step option comes back")


func test_promotion_requires_choice() -> void:
	t("promotion choice")
	var s := empty_state()
	put(s, Piece.Type.KING, 0, 0, Vector3i(7, 0, 0))
	put(s, Piece.Type.KING, 1, 0, Vector3i(0, 0, 0))
	var p := put(s, Piece.Type.PAWN, 0, 0, Vector3i(3, 6, 0))
	var g := GameState.new(s)
	var promo: Move = null
	for m in g.get_legal_moves(p):
		if m.to == Vector3i(3, 7, 0):
			promo = m
	ok(promo != null and promo.is_promotion, "reaching the last rank on level 1 promotes")
	var r := g.apply_move(promo)
	ok(r["needs_promotion"] and not r["ok"], "the move is held until a piece is chosen")
	eq(p.type, Piece.Type.PAWN, "nothing changed on the board yet")
	r = g.apply_move(promo, Piece.Type.KNIGHT)
	ok(r["ok"], "committing with a choice succeeds")
	eq(p.type, Piece.Type.KNIGHT, "the player's chosen piece is used, not an auto-queen")


func test_castling() -> void:
	t("castling")
	var s := empty_state()
	var k := put(s, Piece.Type.KING, 0, 0, Vector3i(4, 0, 0))
	put(s, Piece.Type.ROOK, 0, 0, Vector3i(7, 0, 0))
	put(s, Piece.Type.ROOK, 0, 0, Vector3i(0, 0, 0))
	var d := rule_destinations(s, k)
	ok(d.has(Vector3i(6, 0, 0)), "kingside castle offered")
	ok(d.has(Vector3i(2, 0, 0)), "queenside castle offered")

	put(s, Piece.Type.BISHOP, 0, 0, Vector3i(5, 0, 0))
	ok(not rule_destinations(s, k).has(Vector3i(6, 0, 0)), "a blocked path removes it")

	var g := GameState.new(s)
	var castle: Move = null
	for m in g.get_legal_moves(k):
		if m.kind == Move.Kind.CASTLE and m.to == Vector3i(2, 0, 0):
			castle = m
	g.apply_move(castle)
	eq(k.position, Vector3i(2, 0, 0), "king lands on c1")
	eq(s.get_piece(Vector3i(3, 0, 0)).type, Piece.Type.ROOK, "rook jumps to d1")
	ok(s.get_piece(Vector3i(0, 0, 0)) == null, "…and left its corner")


func test_en_passant() -> void:
	t("en passant")
	var s := empty_state()
	put(s, Piece.Type.KING, 0, 0, Vector3i(7, 0, 0))
	put(s, Piece.Type.KING, 1, 0, Vector3i(0, 7, 0))
	var w := put(s, Piece.Type.PAWN, 0, 0, Vector3i(4, 1, 0))
	var b := put(s, Piece.Type.PAWN, 1, 0, Vector3i(5, 3, 0))
	var g := GameState.new(s)

	var dbl: Move = null
	for m in g.get_legal_moves(w):
		if m.to == Vector3i(4, 3, 0):
			dbl = m
	eq(dbl.kind, Move.Kind.DOUBLE_STEP, "White's two-square move is tagged")
	g.apply_move(dbl)
	ok(g.state.en_passant.is_empty(), "the target is not live during White's own turn")
	g.end_turn()
	eq(g.state.en_passant.size(), 1, "it becomes live for Black's turn")

	var ep: Move = null
	for m in g.get_legal_moves(b):
		if m.kind == Move.Kind.EN_PASSANT:
			ep = m
	ok(ep != null and ep.to == Vector3i(4, 2, 0), "Black may capture onto the skipped square")
	g.apply_move(ep)
	ok(s.get_piece_by_id(w.id) == null, "the passed pawn is removed")
	eq(b.position, Vector3i(4, 2, 0), "the capturing pawn lands behind it")
	g.end_turn()
	g.end_turn()
	ok(g.state.en_passant.is_empty(), "the window closes after one turn")


func test_turn_move_cap() -> void:
	t("moves per turn")
	var g := GameState.new()
	eq(g.max_moves_this_turn(), 2, "White's first turn is capped at two")
	var s := g.state
	# level 1 -> level 2, then a knight, then try a third move.
	var a := s.get_piece(Vector3i(0, 1, 0))
	g.apply_move(_move_to(g, a, Vector3i(0, 1, 1)))
	var b := s.get_piece(Vector3i(1, 0, 0))
	g.apply_move(_move_to(g, b, Vector3i(2, 2, 0)))
	eq(g.moves_remaining(), 0, "both moves used")
	ok(g.is_turn_complete(), "the turn is complete")
	g.end_turn()
	eq(g.current_player, 1, "Black to move")
	eq(g.max_moves_this_turn(), 3, "every later turn allows three")


func test_one_move_per_level() -> void:
	t("one move per destination level")
	var g := GameState.new()
	var s := g.state
	var a := s.get_piece(Vector3i(0, 1, 0))
	g.apply_move(_move_to(g, a, Vector3i(0, 2, 0)))
	var b := s.get_piece(Vector3i(1, 1, 0))
	var second := _move_to(g, b, Vector3i(1, 2, 0))
	ok(second == null, "a second move ending on level 1 is not even offered")
	ok(_move_to(g, b, Vector3i(1, 1, 1)) != null, "but ending on level 2 is fine")


func test_one_move_per_piece() -> void:
	t("one move per piece")
	var g := GameState.new()
	var s := g.state
	var a := s.get_piece(Vector3i(1, 0, 0))  # knight
	g.apply_move(_move_to(g, a, Vector3i(2, 2, 0)))
	ok(g.get_legal_moves(a).is_empty(), "that piece is done for the turn")
	ok(g.selection_error(a).length() > 0, "and says why when picked up again")


func test_win_on_king_capture() -> void:
	t("win condition")
	var s := empty_state()
	var q := put(s, Piece.Type.QUEEN, 0, 0, Vector3i(0, 0, 0))
	put(s, Piece.Type.KING, 1, 0, Vector3i(0, 5, 0))
	put(s, Piece.Type.KING, 1, 1, Vector3i(7, 7, 2))
	put(s, Piece.Type.KING, 0, 0, Vector3i(7, 0, 0))
	var g := GameState.new(s)
	var kill := _move_to(g, q, Vector3i(0, 5, 0))
	var r := g.apply_move(kill)
	eq(r["winner"], 0, "capturing either enemy king wins outright")
	ok(g.is_game_over(), "the game is over even though Black's other king survives")


func test_available_levels() -> void:
	t("available destination levels")
	var s := empty_state()
	# Kings are the one piece that cannot change level, so a board holding only
	# kings can never reach the middle board.
	put(s, Piece.Type.KING, 0, 0, Vector3i(4, 0, 0))
	put(s, Piece.Type.KING, 1, 0, Vector3i(4, 7, 0))
	var g := GameState.new(s)
	eq(g.available_destination_levels(), [0] as Array[int],
		"kings alone offer moves on level 1 only")

	var rook := put(s, Piece.Type.ROOK, 0, 0, Vector3i(0, 3, 0))
	ok(g.available_destination_levels().has(1),
		"a rook that can rise makes level 2 reachable")

	# Spending a level takes it back out, even though pieces can still get there.
	var up: Move = null
	for m in g.get_legal_moves(rook):
		if m.to == Vector3i(0, 3, 1):
			up = m
	g.apply_move(up)
	ok(not g.available_destination_levels().has(1),
		"and it drops out again once a move has ended there")


func test_undo() -> void:
	t("undo")
	var g := GameState.new()
	var s := g.state
	var before := s.dump()
	var a := s.get_piece(Vector3i(4, 1, 0))
	g.apply_move(_move_to(g, a, Vector3i(4, 3, 0)))
	ok(g.can_undo(), "undo is offered mid-turn")
	ok(g.undo_last_move(), "undo succeeds")
	ok(s.dump() == before, "the board is exactly as it was")
	eq(g.moves_made_this_turn, 0, "the move no longer counts against the turn")
	ok(not g.can_undo(), "only one move deep")
	g.apply_move(_move_to(g, s.get_piece(Vector3i(4, 1, 0)), Vector3i(4, 3, 0)))
	g.end_turn()
	ok(not g.can_undo(), "undo does not reach back across a committed turn")


func test_serialisation_round_trip() -> void:
	t("serialisation")
	var g := GameState.new()
	var s := g.state
	g.apply_move(_move_to(g, s.get_piece(Vector3i(4, 1, 0)), Vector3i(4, 3, 0)))
	var d := g.to_dict()
	var json := JSON.stringify(d)
	ok(json.length() > 0, "the whole game state stringifies to JSON")
	var g2 := GameState.new()
	g2.load_dict(JSON.parse_string(json))
	ok(g2.state.dump() == s.dump(), "and reloads into an identical board")
	eq(g2.moves_made_this_turn, g.moves_made_this_turn, "…with the turn state intact")


## Which way the camera turns to sit behind a player's army on a board.
##
## Checked against where the pieces ACTUALLY start rather than against a table
## of expected angles, because the interesting part is precisely that colour
## does not decide it: the armies are mirrored, so White is at low ranks on the
## bottom board and at high ranks on the top one. An expected-angle table would
## just be the implementation written twice, and would agree with a version
## that seats White behind Black's pieces on the top board.
func test_home_side_orientation() -> void:
	t("home side")
	var s := BoardState.create_initial()
	eq(BoardState.army_on_level(0), 0, "the bottom board holds each player's army 0")
	eq(BoardState.army_on_level(2), 1, "the top board holds army 1")
	eq(BoardState.army_on_level(BoardState.MIDDLE_LEVEL), -1,
		"the middle board belongs to neither")
	ok(CameraRig.home_yaw(0, BoardState.MIDDLE_LEVEL) < 0.0,
		"so the middle board has no home side to turn to")

	# Rank 0 sits toward +Z and yaw 0 puts the camera on the +Z side, so a yaw
	# of 0 must be the side whose pieces are on the low ranks.
	for level in [0, 2]:
		for owner in [0, 1]:
			var ranks: Array = []
			for p in s.pieces_of(owner):
				if p.position.z == level:
					ranks.append(p.position.y)
			ok(ranks.size() == 16, "%s has 16 pieces on the %s board"
				% [GameState.player_name(owner), BoardState.LEVEL_NAMES[level].to_lower()])
			var low: bool = _mean(ranks) < 3.5
			var yaw := CameraRig.home_yaw(owner, level)
			ok(yaw == (0.0 if low else 180.0),
				"%s on the %s board (mean rank %.1f) is viewed from yaw %.0f"
					% [GameState.player_name(owner),
						BoardState.LEVEL_NAMES[level].to_lower(), _mean(ranks), yaw])

	# The mirroring, stated outright: the same player looks from opposite sides
	# on the two boards. This is the assertion that fails if someone "simplifies"
	# home_yaw() to depend on colour alone.
	for owner in [0, 1]:
		ok(CameraRig.home_yaw(owner, 0) != CameraRig.home_yaw(owner, 2),
			"%s faces opposite ways on the two boards, because the armies mirror"
				% GameState.player_name(owner))
	ok(CameraRig.home_yaw(0, 0) != CameraRig.home_yaw(1, 0),
		"and the two players face each other on the bottom board")
	ok(CameraRig.home_yaw(0, 2) != CameraRig.home_yaw(1, 2), "and on the top board")


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / float(values.size())


# --- helper --------------------------------------------------------------

func _move_to(g: GameState, piece: Piece, square: Vector3i) -> Move:
	for m in g.get_legal_moves(piece):
		if m.to == square:
			return m
	return null
