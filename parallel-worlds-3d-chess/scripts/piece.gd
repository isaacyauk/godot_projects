## A single chess piece as pure game-logic data.
##
## Deliberately has NO knowledge of the scene tree, meshes or input — the rules
## engine is testable with plain function calls (see tests/test_rules.gd).
## `PieceVisual` mirrors one of these by matching `id`.
class_name Piece
extends Resource

enum Type { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING }

const TYPE_NAMES := ["Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]

## Stable identity. Board snapshots (undo / save) rebuild Piece objects from
## scratch, so visuals and selection state must key off `id`, never off object
## identity.
@export var id: int = -1
@export var type: Type = Type.PAWN
## 0 = White, 1 = Black.
@export var owner_id: int = 0
## Which of the owner's two armies this piece belongs to.
## 0 = the army that started on level 1, 1 = the army that started on level 3.
## Pure bookkeeping for legality (see design doc §3) — it only drives the
## material variant in the visuals and the pawn `forward` direction below.
@export var army: int = 0
## x = file (0-7), y = rank (0-7), z = level (0,1,2 -> boards 1,2,3).
@export var position: Vector3i = Vector3i.ZERO
@export var has_moved: bool = false
## Set when a pawn drops from level 2 onto its own first rank. While true the
## pawn cannot use its two-step move. Cleared once it reaches its second rank.
@export var pawn_restricted_step: bool = false
## +1 = this piece's pawns advance toward rank 7, -1 = toward rank 0.
## Fixed at setup from (owner_id, army) because the two armies are MIRRORED
## (design doc §3), and never changes afterwards — a pawn that travels through
## level 2 keeps its own forward direction.
@export var forward: int = 1


static func create(p_id: int, p_type: Type, p_owner: int, p_army: int, p_pos: Vector3i) -> Piece:
	var p := Piece.new()
	p.id = p_id
	p.type = p_type
	p.owner_id = p_owner
	p.army = p_army
	p.position = p_pos
	p.forward = forward_for(p_owner, p_army)
	return p


## White's level-1 army advances up the board; its level-3 army is mirrored.
## Black is the reverse of White on each level.
static func forward_for(p_owner: int, p_army: int) -> int:
	var by_owner := 1 if p_owner == 0 else -1
	var by_army := 1 if p_army == 0 else -1
	return by_owner * by_army


## The rank this piece's pawns start on (and may double-step from).
func start_rank() -> int:
	return 1 if forward > 0 else 6


## The rank behind the pawn line — "own first rank" in the level-2 transition rule.
func home_rank() -> int:
	return 0 if forward > 0 else 7


## The promotion rank — "own last rank".
func last_rank() -> int:
	return 7 if forward > 0 else 0


func is_white() -> bool:
	return owner_id == 0


func type_name() -> String:
	return TYPE_NAMES[type]


func describe() -> String:
	return "%s %s (id %d, army %d) @ %s" % [
		"White" if owner_id == 0 else "Black", type_name(), id, army, str(position)
	]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": int(type),
		"owner_id": owner_id,
		"army": army,
		"position": [position.x, position.y, position.z],
		"has_moved": has_moved,
		"pawn_restricted_step": pawn_restricted_step,
		"forward": forward,
	}


static func from_dict(d: Dictionary) -> Piece:
	var p := Piece.new()
	p.id = int(d["id"])
	p.type = int(d["type"]) as Type
	p.owner_id = int(d["owner_id"])
	p.army = int(d["army"])
	var pos: Array = d["position"]
	p.position = Vector3i(int(pos[0]), int(pos[1]), int(pos[2]))
	p.has_moved = bool(d["has_moved"])
	p.pawn_restricted_step = bool(d["pawn_restricted_step"])
	p.forward = int(d["forward"])
	return p
