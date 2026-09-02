## Move generation. Pure static functions over a BoardState — no scene tree,
## no input, no rendering (design doc §6 / KISS note in §3).
##
## There is deliberately NO check or checkmate detection: the variant is won by
## capturing either enemy king outright, so no move ever needs to be simulated
## to see whether it leaves a king attacked. That also means castling has no
## "may not castle through check" restriction here.
class_name BoardRules

const SIZE := BoardState.SIZE
const MIDDLE := BoardState.MIDDLE_LEVEL

const ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const QUEEN_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const KNIGHT_STEPS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]


## Every move this piece could make ignoring turn bookkeeping.
## GameState.get_legal_moves() applies the per-turn constraints on top.
static func get_piece_moves(state: BoardState, piece: Piece) -> Array:
	var moves: Array = []
	if piece.position.z == MIDDLE:
		moves.append_array(_queen_moves_no_capture(state, piece))
	else:
		moves.append_array(_standard_moves(state, piece))
	# "Any piece except a king may move straight up or down one level."
	if piece.type != Piece.Type.KING:
		moves.append_array(_vertical_moves(state, piece))
	return moves


static func all_moves_for_owner(state: BoardState, p_owner: int) -> Array:
	var out: Array = []
	for p in state.pieces_of(p_owner):
		out.append_array(get_piece_moves(state, p))
	return out


# --- levels 1 & 3: standard chess ---------------------------------------

static func _standard_moves(state: BoardState, piece: Piece) -> Array:
	match piece.type:
		Piece.Type.PAWN:
			return _pawn_moves(state, piece)
		Piece.Type.KNIGHT:
			return _step_moves(state, piece, KNIGHT_STEPS)
		Piece.Type.BISHOP:
			return _slide_moves(state, piece, DIAG)
		Piece.Type.ROOK:
			return _slide_moves(state, piece, ORTHO)
		Piece.Type.QUEEN:
			return _slide_moves(state, piece, QUEEN_DIRS)
		Piece.Type.KING:
			var m := _step_moves(state, piece, QUEEN_DIRS)
			m.append_array(_castle_moves(state, piece))
			return m
	return []


static func _slide_moves(state: BoardState, piece: Piece, dirs: Array) -> Array:
	var moves: Array = []
	for d in dirs:
		var step := 1
		while true:
			var t := Vector3i(piece.position.x + d.x * step, piece.position.y + d.y * step, piece.position.z)
			if not BoardState.in_bounds(t):
				break
			var occ := state.get_piece(t)
			if occ == null:
				moves.append(Move.create(Move.Kind.NORMAL, piece, t))
			else:
				if occ.owner_id != piece.owner_id:
					moves.append(_capture(piece, t, occ))
				break
			step += 1
	return moves


static func _step_moves(state: BoardState, piece: Piece, steps: Array) -> Array:
	var moves: Array = []
	for d in steps:
		var t := Vector3i(piece.position.x + d.x, piece.position.y + d.y, piece.position.z)
		if not BoardState.in_bounds(t):
			continue
		var occ := state.get_piece(t)
		if occ == null:
			moves.append(Move.create(Move.Kind.NORMAL, piece, t))
		elif occ.owner_id != piece.owner_id:
			moves.append(_capture(piece, t, occ))
	return moves


static func _capture(piece: Piece, t: Vector3i, victim: Piece) -> Move:
	var m := Move.create(Move.Kind.CAPTURE, piece, t)
	m.captured_id = victim.id
	m.captured_square = t
	return m


static func _pawn_moves(state: BoardState, piece: Piece) -> Array:
	var moves: Array = []
	var pos := piece.position
	var f := piece.forward
	var z := pos.z

	var one := Vector3i(pos.x, pos.y + f, z)
	if BoardState.in_bounds(one) and state.is_empty(one):
		moves.append(_pawn_step(piece, one, Move.Kind.NORMAL))
		# Two-square move. Gated on standing on the pawn's own second rank
		# rather than on has_moved, because a pawn that drops from level 2 onto
		# its first rank must regain the option once it steps up (rules §
		# "Pawn Transitions"), and pawn_restricted_step suppresses it until then.
		if pos.y == piece.start_rank() and not piece.pawn_restricted_step:
			var two := Vector3i(pos.x, pos.y + 2 * f, z)
			if BoardState.in_bounds(two) and state.is_empty(two):
				var m := _pawn_step(piece, two, Move.Kind.DOUBLE_STEP)
				m.ep_square = one
				moves.append(m)

	for dx in [-1, 1]:
		var t := Vector3i(pos.x + dx, pos.y + f, z)
		if not BoardState.in_bounds(t):
			continue
		var occ := state.get_piece(t)
		if occ != null:
			if occ.owner_id != piece.owner_id:
				var m := _pawn_step(piece, t, Move.Kind.CAPTURE)
				m.captured_id = occ.id
				m.captured_square = t
				moves.append(m)
		else:
			var ep := _find_en_passant(state, piece, t)
			if not ep.is_empty():
				var victim: Piece = state.get_piece_by_id(int(ep["pawn_id"]))
				if victim != null:
					var m := _pawn_step(piece, t, Move.Kind.EN_PASSANT)
					m.captured_id = victim.id
					m.captured_square = victim.position
					moves.append(m)
	return moves


static func _find_en_passant(state: BoardState, piece: Piece, square: Vector3i) -> Dictionary:
	for e in state.en_passant:
		if e["square"] == square and int(e["owner_id"]) != piece.owner_id:
			return e
	return {}


## Builds a pawn move and tags promotion. Promotion fires whenever a pawn ends
## on its own last rank of level 1 or 3, whatever level it came from — that is
## what makes the "level 2 -> last rank promotes immediately" rule fall out for
## free. It never fires while the pawn ends on level 2.
static func _pawn_step(piece: Piece, to: Vector3i, kind: int) -> Move:
	var m := Move.create(kind, piece, to)
	if to.z != MIDDLE and to.y == piece.last_rank():
		m.is_promotion = true
	return m


# --- level 2: every piece moves as a queen, nothing may be captured ------

static func _queen_moves_no_capture(state: BoardState, piece: Piece) -> Array:
	var moves: Array = []
	for d in QUEEN_DIRS:
		var step := 1
		while true:
			var t := Vector3i(piece.position.x + d.x * step, piece.position.y + d.y * step, piece.position.z)
			if not BoardState.in_bounds(t):
				break
			# Any occupied square blocks — friend OR foe. No captures exist on
			# level 2, which also stops a player's own two armies overlapping.
			if state.get_piece(t) != null:
				break
			moves.append(Move.create(Move.Kind.NORMAL, piece, t))
			step += 1
	# A pawn reaching the last rank while on level 2 does not promote, so no
	# promotion tagging happens anywhere in this branch.
	return moves


# --- vertical movement ---------------------------------------------------

## Straight up or down to the IMMEDIATELY adjacent level only, same file+rank,
## destination must be empty. Never level 1 <-> level 3 directly — the `dz`
## list below is intentionally just [-1, 1]; widening it to "any level" is the
## easy off-by-one this rule invites.
static func _vertical_moves(state: BoardState, piece: Piece) -> Array:
	var moves: Array = []
	for dz in [-1, 1]:
		var t := Vector3i(piece.position.x, piece.position.y, piece.position.z + dz)
		if not BoardState.in_bounds(t):
			continue
		if not state.is_empty(t):
			continue  # no captures on a vertical move, ever
		var m := Move.create(Move.Kind.VERTICAL, piece, t)
		if piece.type == Piece.Type.PAWN and piece.position.z == MIDDLE:
			# Leaving level 2 for an outer board.
			if t.y == piece.last_rank():
				m.is_promotion = true
			elif t.y == piece.home_rank():
				m.sets_restricted = true
		moves.append(m)
	return moves


# --- castling (levels 1 and 3) ------------------------------------------

static func _castle_moves(state: BoardState, king: Piece) -> Array:
	var moves: Array = []
	if king.has_moved:
		return moves
	var z := king.position.z
	if z == MIDDLE:
		return moves
	var home := king.home_rank()
	if king.position.y != home or king.position.x != 4:
		return moves

	for rook_file in [7, 0]:
		var rook := state.get_piece(Vector3i(rook_file, home, z))
		if rook == null or rook.type != Piece.Type.ROOK:
			continue
		if rook.owner_id != king.owner_id or rook.has_moved:
			continue
		var lo: int = min(king.position.x, rook_file) + 1
		var hi: int = max(king.position.x, rook_file) - 1
		var clear := true
		for x in range(lo, hi + 1):
			if state.get_piece(Vector3i(x, home, z)) != null:
				clear = false
				break
		if not clear:
			continue
		var king_to := 6 if rook_file == 7 else 2
		var rook_to := 5 if rook_file == 7 else 3
		var m := Move.create(Move.Kind.CASTLE, king, Vector3i(king_to, home, z))
		m.rook_id = rook.id
		m.rook_from = rook.position
		m.rook_to = Vector3i(rook_to, home, z)
		moves.append(m)
	return moves
