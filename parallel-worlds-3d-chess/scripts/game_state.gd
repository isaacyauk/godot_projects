## Turn tracking, move commitment, win check and single-move undo.
## Owns a BoardState and is the only thing allowed to mutate it.
##
## Headless by design — main.gd drives it and listens to its signals, but the
## whole thing runs from a test script with no scene tree (tests/test_rules.gd).
class_name GameState
extends RefCounted

signal move_committed(move: Move, result: Dictionary)
signal turn_ended(previous_player: int, next_player: int)
signal game_over(winner_id: int)

const MAX_MOVES_PER_TURN := 3
const MAX_MOVES_FIRST_TURN := 2

var state: BoardState

var current_player: int = 0
var moves_made_this_turn: int = 0
## Destination levels already used this turn. No two moves in one turn may END
## on the same level (they may start on the same level).
var levels_ended_on: Array[int] = []
## Each piece may move only once per turn.
var moved_piece_ids: Array[int] = []
## White's very first turn is capped at two moves.
var is_first_turn: bool = true
var winner: int = -1
var turn_number: int = 1

## Snapshot of everything immediately before the most recent move of the
## current, uncommitted turn. Cleared when the turn ends, so undo can never
## reach back across a turn boundary.
var _undo_snapshot: Dictionary = {}


func _init(initial: BoardState = null) -> void:
	state = initial if initial != null else BoardState.create_initial()


# --- turn queries --------------------------------------------------------

func max_moves_this_turn() -> int:
	return MAX_MOVES_FIRST_TURN if is_first_turn else MAX_MOVES_PER_TURN


func moves_remaining() -> int:
	return max_moves_this_turn() - moves_made_this_turn


func can_undo() -> bool:
	return not _undo_snapshot.is_empty() and winner == -1


func is_game_over() -> bool:
	return winner != -1


## True once the player cannot (or need not) move again this turn.
func is_turn_complete() -> bool:
	if winner != -1:
		return true
	if moves_remaining() <= 0:
		return true
	return not has_any_legal_move()


## The levels a move could still END on this turn, for the current player.
##
## This is stricter than "levels not yet used": a level with nothing able to
## reach it is not available either, which is usually the case for the empty
## middle board early on. The indicators read from this rather than from
## `levels_ended_on`, so they never advertise a move that does not exist.
func available_destination_levels() -> Array[int]:
	var out: Array[int] = []
	if winner != -1:
		return out
	for p in state.pieces_of(current_player):
		for m in get_legal_moves(p):
			if not out.has(m.to.z):
				out.append(m.to.z)
		if out.size() == BoardState.LEVELS:
			break
	out.sort()
	return out


func has_any_legal_move() -> bool:
	for p in state.pieces_of(current_player):
		if not get_legal_moves(p).is_empty():
			return true
	return false


func opponent_of(p_owner: int) -> int:
	return 1 - p_owner


static func player_name(p_owner: int) -> String:
	return "White" if p_owner == 0 else "Black"


# --- legality ------------------------------------------------------------

## Rule-legal moves for this piece, filtered by the current turn's constraints.
func get_legal_moves(piece: Piece) -> Array:
	if piece == null or winner != -1:
		return []
	if piece.owner_id != current_player:
		return []
	if moves_remaining() <= 0:
		return []
	if moved_piece_ids.has(piece.id):
		return []
	var out: Array = []
	for m in BoardRules.get_piece_moves(state, piece):
		if levels_ended_on.has(m.to.z):
			continue
		out.append(m)
	return out


## Why a piece can't be picked up right now — used for the rejection cue.
func selection_error(piece: Piece) -> String:
	if winner != -1:
		return "The game is over."
	if piece == null:
		return ""
	if piece.owner_id != current_player:
		return "That is %s's piece." % player_name(piece.owner_id)
	if moves_remaining() <= 0:
		return "No moves left this turn."
	if moved_piece_ids.has(piece.id):
		return "That piece already moved this turn."
	if get_legal_moves(piece).is_empty():
		return "That piece has no legal move left this turn."
	return ""


# --- committing a move ---------------------------------------------------

## Applies `move`. Returns a result dictionary:
##   ok               did anything change
##   reason           human-readable refusal, when ok == false
##   needs_promotion  caller must re-call with a promotion_type
##   captured_id      id of the piece removed, or -1
##   winner           winning owner_id, or -1
##   turn_complete    the turn has no moves left in it
func apply_move(move: Move, promotion_type: int = -1) -> Dictionary:
	var result := {
		"ok": false, "reason": "", "needs_promotion": false,
		"captured_id": -1, "winner": -1, "turn_complete": false,
	}
	if winner != -1:
		result["reason"] = "The game is over."
		return result
	var piece: Piece = state.get_piece_by_id(move.piece_id)
	if piece == null:
		result["reason"] = "That piece is no longer on the board."
		return result
	if piece.owner_id != current_player:
		result["reason"] = "Not your piece."
		return result
	if moves_remaining() <= 0:
		result["reason"] = "No moves left this turn."
		return result
	if moved_piece_ids.has(piece.id):
		result["reason"] = "That piece already moved this turn."
		return result
	if levels_ended_on.has(move.to.z):
		result["reason"] = "A move already ended on level %d this turn." % (move.to.z + 1)
		return result
	if move.is_promotion and promotion_type < 0:
		# The move isn't committed until the player picks a piece.
		result["needs_promotion"] = true
		return result

	_undo_snapshot = _snapshot()

	# 1. Remove the captured piece (its square differs from `to` on en passant).
	var captured: Piece = null
	if move.captured_id >= 0:
		captured = state.get_piece_by_id(move.captured_id)
		if captured != null:
			state.remove_piece(captured)
			result["captured_id"] = captured.id

	# 2. Move the piece itself.
	state.move_piece(piece, move.to)
	piece.has_moved = true

	# 3. Castling moves the rook too.
	if move.kind == Move.Kind.CASTLE:
		var rook: Piece = state.get_piece_by_id(move.rook_id)
		if rook != null:
			state.move_piece(rook, move.rook_to)
			rook.has_moved = true

	# 4. Pawn flags.
	if move.is_promotion and promotion_type >= 0:
		piece.type = promotion_type as Piece.Type
		piece.pawn_restricted_step = false
		move.promotion_type = promotion_type
	if move.sets_restricted:
		piece.pawn_restricted_step = true
	elif piece.type == Piece.Type.PAWN and piece.pawn_restricted_step \
			and piece.position.z != BoardState.MIDDLE_LEVEL \
			and piece.position.y == piece.start_rank():
		# Reached its second rank — moves normally again from here.
		piece.pawn_restricted_step = false

	# 5. A double step leaves an en passant target for the opponent's NEXT turn.
	if move.kind == Move.Kind.DOUBLE_STEP:
		state.pending_en_passant.append({
			"square": move.ep_square, "pawn_id": piece.id, "owner_id": piece.owner_id,
		})

	# 6. Turn bookkeeping.
	moves_made_this_turn += 1
	levels_ended_on.append(move.to.z)
	moved_piece_ids.append(piece.id)

	# 7. Win check — capturing EITHER enemy king ends the game immediately.
	if captured != null and captured.type == Piece.Type.KING:
		winner = opponent_of(captured.owner_id)
		result["winner"] = winner

	result["ok"] = true
	result["turn_complete"] = is_turn_complete()
	move_committed.emit(move, result)
	if winner != -1:
		game_over.emit(winner)
	return result


## Rewinds the most recent move of the current turn. One level deep only, and
## never across a turn boundary (design doc §3).
func undo_last_move() -> bool:
	if not can_undo():
		return false
	_restore(_undo_snapshot)
	_undo_snapshot = {}
	return true


func end_turn() -> void:
	if winner != -1:
		return
	var previous := current_player
	# En passant targets created this turn become live for the opponent, and
	# the ones they could have used expire.
	state.en_passant = state.pending_en_passant
	state.pending_en_passant = []
	if is_first_turn:
		is_first_turn = false
	current_player = opponent_of(current_player)
	moves_made_this_turn = 0
	levels_ended_on = []
	moved_piece_ids = []
	_undo_snapshot = {}
	turn_number += 1
	turn_ended.emit(previous, current_player)


# --- snapshots -----------------------------------------------------------

func _snapshot() -> Dictionary:
	return {
		"board": state.to_dict(),
		"current_player": current_player,
		"moves_made_this_turn": moves_made_this_turn,
		"levels_ended_on": levels_ended_on.duplicate(),
		"moved_piece_ids": moved_piece_ids.duplicate(),
		"is_first_turn": is_first_turn,
		"winner": winner,
		"turn_number": turn_number,
	}


func _restore(snap: Dictionary) -> void:
	state.load_dict(snap["board"])
	current_player = int(snap["current_player"])
	moves_made_this_turn = int(snap["moves_made_this_turn"])
	levels_ended_on.assign(snap["levels_ended_on"])
	moved_piece_ids.assign(snap["moved_piece_ids"])
	is_first_turn = bool(snap["is_first_turn"])
	winner = int(snap["winner"])
	turn_number = int(snap["turn_number"])


## Full serialisation — already what an async/Supabase payload would send.
func to_dict() -> Dictionary:
	return _snapshot()


func load_dict(d: Dictionary) -> void:
	_restore(d)
	_undo_snapshot = {}
