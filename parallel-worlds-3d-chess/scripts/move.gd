## One candidate move produced by BoardRules.
##
## The design doc sketched move-gen as returning Array[Vector3i]. That can't
## express castling (two pieces move), en passant (captured square != target
## square) or promotion, so move-gen returns Move objects instead and the UI
## calls `destinations()` when it just wants squares to highlight.
class_name Move
extends RefCounted

enum Kind {
	NORMAL,      ## quiet move within a board
	CAPTURE,     ## takes an enemy piece on the destination square
	DOUBLE_STEP, ## pawn's two-square opening move (creates an en passant target)
	VERTICAL,    ## up/down exactly one level, same file+rank, destination empty
	CASTLE,      ## king + rook, levels 1 and 3 only
	EN_PASSANT,  ## pawn capture onto an empty square
}

var kind: int = Kind.NORMAL
var piece_id: int = -1
var from: Vector3i = Vector3i.ZERO
var to: Vector3i = Vector3i.ZERO

## Set for CAPTURE and EN_PASSANT.
var captured_id: int = -1
var captured_square: Vector3i = Vector3i(-1, -1, -1)

## Set for CASTLE.
var rook_id: int = -1
var rook_from: Vector3i = Vector3i(-1, -1, -1)
var rook_to: Vector3i = Vector3i(-1, -1, -1)

## Set for DOUBLE_STEP — the square an enemy pawn may capture onto next turn.
var ep_square: Vector3i = Vector3i(-1, -1, -1)

## The pawn ends on its own last rank of level 1 or 3 and must promote.
## GameState refuses to apply the move until `promotion_type` is chosen.
var is_promotion: bool = false
var promotion_type: int = -1

## The pawn drops from level 2 onto its own first rank and loses its two-step
## option until it reaches its second rank.
var sets_restricted: bool = false


static func create(p_kind: int, piece: Piece, p_to: Vector3i) -> Move:
	var m := Move.new()
	m.kind = p_kind
	m.piece_id = piece.id
	m.from = piece.position
	m.to = p_to
	return m


func is_capture() -> bool:
	return kind == Kind.CAPTURE or kind == Kind.EN_PASSANT


func describe() -> String:
	var names := ["normal", "capture", "double-step", "vertical", "castle", "en-passant"]
	var s := "%s %s -> %s" % [names[kind], str(from), str(to)]
	if is_promotion:
		s += " (promotes)"
	if sets_restricted:
		s += " (restricted)"
	return s


## Convenience for highlight code that only cares about target squares.
static func destinations(moves: Array) -> Array:
	var out: Array = []
	for m in moves:
		out.append(m.to)
	return out


static func find_to(moves: Array, square: Vector3i) -> Move:
	for m in moves:
		if m.to == square:
			return m
	return null
