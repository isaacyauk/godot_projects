## The three 8x8 boards plus every live Piece.
##
## Per design doc §4 the boards are three separate grids rather than one
## unified 3D array, because level 2's rules are wholesale different and
## special-casing it is simpler than generalising move-gen.
##
## Each board is stored flat (64 entries, index = y * 8 + x) purely so lookups
## are one array access; always go through get_piece()/set_piece() with a
## Vector3i so the layout stays an implementation detail.
class_name BoardState
extends RefCounted

const SIZE := 8
const LEVELS := 3

## z index of the special middle board. NOTE: the design doc's pseudocode says
## `piece.position.z == 2` for level 2, which is an off-by-one — with levels
## 1,2,3 stored as z = 0,1,2 the middle board is z == 1.
const MIDDLE_LEVEL := 1

## What the player calls each board, indexed by level. Both vocabularies are
## load-bearing and neither replaces the other: the design doc numbers the
## boards 1-3 and so does this code, but a player looking at a stack sees a top
## and a bottom. Anything the player reads uses these; anything about rules uses
## the number.
const LEVEL_NAMES := ["Bottom", "Mid", "Top"]


## Which army starts on a board: 0 is the army that begins on the bottom board,
## 1 the one that begins on the top. -1 for the middle board, which starts
## empty and belongs to neither.
##
## This matters beyond setup because the two armies are MIRRORED
## (Piece.forward_for): a player's bottom-board army faces one way and their
## top-board army the other. Anything that needs to know which end of a board a
## player's pieces live on has to go through here rather than assume colour
## decides it.
static func army_on_level(z: int) -> int:
	if z == MIDDLE_LEVEL:
		return -1
	return 0 if z < MIDDLE_LEVEL else 1


## Standard chess back rank, files a..h.
const BACK_RANK := [
	Piece.Type.ROOK, Piece.Type.KNIGHT, Piece.Type.BISHOP, Piece.Type.QUEEN,
	Piece.Type.KING, Piece.Type.BISHOP, Piece.Type.KNIGHT, Piece.Type.ROOK,
]

var boards: Array = []           ## boards[z] -> Array of 64 (Piece or null)
var pieces: Dictionary = {}      ## id -> Piece, live pieces only
var captured: Array = []         ## Pieces removed from play, in capture order
var _next_id: int = 0

## En passant targets an enemy pawn may capture onto during the CURRENT turn.
## Entries: {"square": Vector3i, "pawn_id": int, "owner_id": int}
var en_passant: Array = []
## Targets created during the current turn; they become `en_passant` when the
## turn ends, so the opponent gets exactly one turn to use them.
var pending_en_passant: Array = []


func _init() -> void:
	_clear()


func _clear() -> void:
	boards = []
	for z in LEVELS:
		var b: Array = []
		b.resize(SIZE * SIZE)
		b.fill(null)
		boards.append(b)
	pieces = {}
	captured = []
	en_passant = []
	pending_en_passant = []
	_next_id = 0


# --- geometry -----------------------------------------------------------

static func in_bounds(sq: Vector3i) -> bool:
	return sq.x >= 0 and sq.x < SIZE \
		and sq.y >= 0 and sq.y < SIZE \
		and sq.z >= 0 and sq.z < LEVELS


static func is_middle(sq: Vector3i) -> bool:
	return sq.z == MIDDLE_LEVEL


func get_piece(sq: Vector3i) -> Piece:
	if not in_bounds(sq):
		return null
	return boards[sq.z][sq.y * SIZE + sq.x]


func set_piece(sq: Vector3i, piece: Piece) -> void:
	boards[sq.z][sq.y * SIZE + sq.x] = piece


func is_empty(sq: Vector3i) -> bool:
	return in_bounds(sq) and get_piece(sq) == null


func get_piece_by_id(pid: int) -> Piece:
	return pieces.get(pid, null)


func pieces_of(p_owner: int) -> Array:
	var out: Array = []
	for pid in pieces:
		var p: Piece = pieces[pid]
		if p.owner_id == p_owner:
			out.append(p)
	return out


# --- mutation (used by GameState; not legality-aware) --------------------

func add_piece(piece: Piece) -> void:
	pieces[piece.id] = piece
	set_piece(piece.position, piece)
	_next_id = max(_next_id, piece.id + 1)


func move_piece(piece: Piece, to: Vector3i) -> void:
	set_piece(piece.position, null)
	piece.position = to
	set_piece(to, piece)


func remove_piece(piece: Piece) -> void:
	set_piece(piece.position, null)
	pieces.erase(piece.id)
	captured.append(piece)


func next_id() -> int:
	var v := _next_id
	_next_id += 1
	return v


# --- setup --------------------------------------------------------------

## Level 1 gets the standard layout; level 3 is MIRRORED across the ranks
## (design doc §3), so each player's two armies face each other across the
## stack rather than both facing the same absolute direction.
static func create_initial() -> BoardState:
	var s := BoardState.new()
	# army 0 lives on level 1 (z = 0), army 1 on level 3 (z = 2).
	s._place_army(0, 0, 0)  # White, army 0, level 1
	s._place_army(1, 0, 0)  # Black, army 0, level 1
	s._place_army(0, 1, 2)  # White, army 1, level 3
	s._place_army(1, 1, 2)  # Black, army 1, level 3
	# Level 2 (z = 1) starts empty.
	return s


func _place_army(p_owner: int, p_army: int, z: int) -> void:
	var fwd := Piece.forward_for(p_owner, p_army)
	var back_y := 0 if fwd > 0 else 7
	var pawn_y := back_y + fwd
	for x in SIZE:
		var back := Piece.create(next_id(), BACK_RANK[x], p_owner, p_army, Vector3i(x, back_y, z))
		add_piece(back)
		var pawn := Piece.create(next_id(), Piece.Type.PAWN, p_owner, p_army, Vector3i(x, pawn_y, z))
		add_piece(pawn)


# --- serialisation (undo snapshots, save/load, async move payloads) ------

func to_dict() -> Dictionary:
	var plist: Array = []
	for pid in pieces:
		plist.append((pieces[pid] as Piece).to_dict())
	var clist: Array = []
	for p in captured:
		clist.append((p as Piece).to_dict())
	return {
		"pieces": plist,
		"captured": clist,
		"next_id": _next_id,
		"en_passant": _ep_to_array(en_passant),
		"pending_en_passant": _ep_to_array(pending_en_passant),
	}


## Restores into THIS instance so existing references stay valid.
func load_dict(d: Dictionary) -> void:
	_clear()
	for pd in d["pieces"]:
		add_piece(Piece.from_dict(pd))
	for pd in d.get("captured", []):
		captured.append(Piece.from_dict(pd))
	_next_id = int(d["next_id"])
	en_passant = _ep_from_array(d.get("en_passant", []))
	pending_en_passant = _ep_from_array(d.get("pending_en_passant", []))


static func from_dict(d: Dictionary) -> BoardState:
	var s := BoardState.new()
	s.load_dict(d)
	return s


func _ep_to_array(src: Array) -> Array:
	var out: Array = []
	for e in src:
		var sq: Vector3i = e["square"]
		out.append({"square": [sq.x, sq.y, sq.z], "pawn_id": e["pawn_id"], "owner_id": e["owner_id"]})
	return out


func _ep_from_array(src: Array) -> Array:
	var out: Array = []
	for e in src:
		var sq: Array = e["square"]
		out.append({
			"square": Vector3i(int(sq[0]), int(sq[1]), int(sq[2])),
			"pawn_id": int(e["pawn_id"]),
			"owner_id": int(e["owner_id"]),
		})
	return out


# --- debugging ----------------------------------------------------------

const _GLYPHS := ["p", "n", "b", "r", "q", "k"]

## ASCII dump of one board — rank 7 at the top, White uppercase.
func dump_level(z: int) -> String:
	var lines: Array = []
	lines.append("  level %d" % (z + 1))
	for y in range(SIZE - 1, -1, -1):
		var row := "%d " % y
		for x in SIZE:
			var p := get_piece(Vector3i(x, y, z))
			if p == null:
				row += ". "
			else:
				var g: String = _GLYPHS[p.type]
				row += (g.to_upper() if p.owner_id == 0 else g) + " "
		lines.append(row)
	lines.append("  0 1 2 3 4 5 6 7")
	return "\n".join(lines)


func dump() -> String:
	var out: Array = []
	for z in range(LEVELS - 1, -1, -1):
		out.append(dump_level(z))
	return "\n".join(out)
