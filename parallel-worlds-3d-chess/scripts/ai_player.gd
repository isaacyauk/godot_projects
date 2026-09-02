## A computer opponent, and a difficulty dial that changes how well it plays
## rather than how fast it moves.
##
## Headless like the rest of the rules layer: it takes a GameState, clones it,
## and searches on the clone by calling the same `get_legal_moves()` and
## `apply_move()` a human's clicks go through. It carries no second copy of the
## rules, so it cannot drift from them — the price is that every search node
## costs a serialise/restore, which is what the node and time budgets below are
## sized around.
##
## Why the search is shaped this way. A turn here is up to three moves, with
## one move per piece and no two moves ending on the same level, so the unit of
## planning is a whole turn, not a move. Full enumeration is out of reach —
## with the glass board open a side can easily have 200+ legal moves, so three
## moves is 8 million sequences. Instead this does a narrowing beam over the
## turn (scoring moves statically, keeping the best few, extending those), and
## then re-ranks the surviving plans by what the opponent could do about them.
##
## There is no check in this variant and capturing either enemy king wins on
## the spot, so "don't leave a king takeable" is not a rule the move generator
## enforces — it is something a player has to see. That reply search is where
## most of the AI's strength lives, and switching it off is most of what makes
## the low difficulties beatable.
class_name AiPlayer
extends RefCounted

## Large enough to dominate any positional term, small enough to stay far from
## float precision trouble when it gets negated and added to.
const WIN := 1000000.0

## Indexed by Piece.Type. The king's number only matters inside the reply
## search — an actual king capture ends the game and short-circuits to WIN —
## but it has to outweigh every other piece on the board so that a reply which
## takes a king is always the reply the search finds.
const VALUES := [100.0, 320.0, 330.0, 500.0, 900.0, 20000.0]

const CENTRE := [0.0, 3.0, 6.0, 9.0, 9.0, 6.0, 3.0, 0.0]

## One row per difficulty, 1..10.
##
##   beams       beams[0] is how many different first moves it tries; the rest
##               are how wide the beam stays while it fills in the second and
##               third move of each of those. Its length is how many moves
##               ahead it plans — at 1 it picks each move greedily, with no
##               idea what its other two moves will be.
##   reply       how many of your moves it checks before committing to a plan.
##               0 means it will happily hang a queen, or a king.
##   review      how many of those first moves get that reply check. A first
##               move that does not get one is not played — an idea it never
##               examined is not a candidate — so at levels 3 and 4, where this
##               is smaller than beams[0], it is genuinely only considering its
##               favourite two or three ideas. From level 5 up it checks all of
##               them.
##   blunder     chance of throwing the plan away and playing at random.
##   jitter      noise added to plan scores, so it is not the same game twice.
##   positional  false = counts material and nothing else.
##   budget_ms   soft deadline; the search stops widening when it is spent.
##
## Every column is monotonic in difficulty, and tests/test_ai.gd asserts it.
const TABLE := [
	{"beams": [1], "reply": 0, "review": 0, "blunder": 0.60, "jitter": 90.0,
		"positional": false, "budget_ms": 60},
	{"beams": [2], "reply": 0, "review": 0, "blunder": 0.42, "jitter": 70.0,
		"positional": false, "budget_ms": 80},
	{"beams": [3, 2], "reply": 1, "review": 2, "blunder": 0.28, "jitter": 50.0,
		"positional": true, "budget_ms": 120},
	{"beams": [4, 2], "reply": 1, "review": 3, "blunder": 0.18, "jitter": 35.0,
		"positional": true, "budget_ms": 160},
	{"beams": [5, 2, 2], "reply": 2, "review": 5, "blunder": 0.11, "jitter": 22.0,
		"positional": true, "budget_ms": 220},
	{"beams": [6, 3, 2], "reply": 2, "review": 6, "blunder": 0.06, "jitter": 14.0,
		"positional": true, "budget_ms": 280},
	{"beams": [7, 3, 2], "reply": 3, "review": 7, "blunder": 0.03, "jitter": 8.0,
		"positional": true, "budget_ms": 340},
	{"beams": [8, 3, 2], "reply": 3, "review": 8, "blunder": 0.01, "jitter": 4.0,
		"positional": true, "budget_ms": 400},
	{"beams": [9, 4, 2], "reply": 3, "review": 9, "blunder": 0.0, "jitter": 0.0,
		"positional": true, "budget_ms": 460},
	{"beams": [10, 4, 3], "reply": 3, "review": 10, "blunder": 0.0, "jitter": 0.0,
		"positional": true, "budget_ms": 520},
]

const LABELS := [
	"Barely trying", "Beginner", "Novice", "Learner", "Casual",
	"Steady", "Careful", "Sharp", "Strong", "Hardest",
]

const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 10

## Above this, a blunder roll is not allowed to throw away a move that wins the
## game outright. Levels 1-3 will still miss a king sitting there for the
## taking, which is a large part of why they are beatable.
const ALWAYS_TAKES_THE_WIN_ABOVE := 3

var owner_id: int
var difficulty: int
var rng: RandomNumberGenerator

var _deadline_usec: int = 0
var _nodes: int = 0


func _init(p_owner: int, p_difficulty: int, p_rng: RandomNumberGenerator = null) -> void:
	owner_id = p_owner
	difficulty = clampi(p_difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY)
	if p_rng != null:
		rng = p_rng
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()


# --- difficulty ----------------------------------------------------------

static func params(p_difficulty: int) -> Dictionary:
	return TABLE[clampi(p_difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY) - 1]


static func label(p_difficulty: int) -> String:
	return LABELS[clampi(p_difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY) - 1]


## The line the menu shows under the slider. It names what actually changes,
## because a difficulty dial that only says "hard" is indistinguishable from
## one that does nothing.
static func describe(p_difficulty: int) -> String:
	var p := params(p_difficulty)
	var beams: Array = p["beams"]
	var parts: Array = []
	parts.append("tries %d opening move%s" % [beams[0], "" if beams[0] == 1 else "s"])
	parts.append("plans %s of its three" % ["one", "two", "all three"][beams.size() - 1])
	var reply: int = p["reply"]
	if reply == 0:
		parts.append("never checks what you would play back")
	else:
		parts.append("checks your best %d repl%s" % [reply, "y" if reply == 1 else "ies"])
	if not bool(p["positional"]):
		parts.append("counts material and nothing else")
	var blunder: float = p["blunder"]
	if blunder > 0.0:
		parts.append("plays at random %d%% of the time" % int(round(blunder * 100.0)))
	var last: String = parts.pop_back()
	return "It %s, and %s." % [", ".join(parts), last]


# --- the public move ------------------------------------------------------

## The move to play now, as {"move": Move, "promotion_type": int}, or {} when
## there is nothing legal left this turn.
##
## This is `search()` plus the difficulty's randomness. Tests drive `search()`
## directly when they want a deterministic answer.
func choose_move(game: GameState) -> Dictionary:
	var found := search(game)
	var plans: Array = found["plans"]
	if plans.is_empty():
		return {}
	var p := params(difficulty)
	var best: Dictionary = plans[0]

	var winning: bool = float(best["score"]) >= WIN
	if not (winning and difficulty > ALWAYS_TAKES_THE_WIN_ABOVE):
		if rng.randf() < float(p["blunder"]):
			var roots: Array = found["root_moves"]
			if not roots.is_empty():
				return _as_choice(game, roots[rng.randi_range(0, roots.size() - 1)])
		elif float(p["jitter"]) > 0.0:
			best = _shuffled_pick(plans, float(p["jitter"]))

	var seq: Array = best["moves"]
	if seq.is_empty():
		return {}
	return _as_choice(game, seq[0])


## Deterministic. Returns:
##   plans       finished turn plans, best first; each {moves, score}
##   root_moves  every legal move right now, for the blunder roll
##   nodes       positions expanded, for the tests and for tuning
func search(game: GameState) -> Dictionary:
	var p := params(difficulty)
	_nodes = 0
	_deadline_usec = Time.get_ticks_usec() + int(p["budget_ms"]) * 1000

	var sim := GameState.new()
	sim.load_dict(game.to_dict())
	var root_dict := sim.to_dict()
	var root_moves := _legal_moves(sim)
	if root_moves.is_empty():
		return {"plans": [], "root_moves": [], "nodes": 0}

	var beams: Array = p["beams"]
	# One branch per candidate FIRST move, each filled in to a whole turn
	# independently. A single beam over the turn would be cheaper, but it can
	# collapse onto one first move by the last step — and then the reply check
	# below has nothing to compare, which is the failure that lets it walk into
	# a lost king with a big smile on its face.
	var branches: Array = []
	for m in _top_moves(sim, root_moves, beams[0], p):
		if Time.get_ticks_usec() > _deadline_usec:
			break
		sim.load_dict(root_dict)
		if not sim.apply_move(m, _promotion_for(m))["ok"]:
			continue
		_nodes += 1
		var node := {"moves": [m], "dict": sim.to_dict(), "score": _evaluate(sim, p)}
		branches.append(_extend(sim, node, beams, p))
	if branches.is_empty():
		return {"plans": [], "root_moves": root_moves, "nodes": _nodes}
	branches.sort_custom(_by_score)

	# Everything above judged a plan by the position it leaves behind, with no
	# thought for what the opponent does next. That is exactly the mistake a
	# beginner makes, so it is left in at the low difficulties and corrected
	# here at the high ones.
	if int(p["reply"]) > 0:
		var review: int = mini(int(p["review"]), branches.size())
		for i in review:
			branches[i]["score"] = _score_after_reply(sim, branches[i], p)
		# Only the checked branches stay. Leaving the rest in would mix two
		# different scales — an unchecked plan is scored on the fantasy that
		# the opponent does nothing, which beats a checked plan every time and
		# would make a bigger reply search play *worse*.
		branches = branches.slice(0, review)
		branches.sort_custom(_by_score)

	return {"plans": branches, "root_moves": root_moves, "nodes": _nodes}


## Fills in the second and third move of one branch and returns its best
## finished plan. The branch keeps its own frontier, so a first move is never
## dropped for being a slow start.
func _extend(sim: GameState, node: Dictionary, beams: Array, p: Dictionary) -> Dictionary:
	var frontier: Array = [node]
	for step in range(1, beams.size()):
		var width: int = beams[step]
		var candidates: Array = []
		for n in frontier:
			sim.load_dict(n["dict"])
			# A plan that has already run out of turn cannot be extended, but it
			# is still a plan — carry it forward to be ranked with the rest.
			if sim.is_game_over() or sim.is_turn_complete():
				candidates.append(n)
				continue
			var moves := _legal_moves(sim)
			if moves.is_empty():
				candidates.append(n)
				continue
			for m in _top_moves(sim, moves, width, p):
				if Time.get_ticks_usec() > _deadline_usec:
					break
				sim.load_dict(n["dict"])
				if not sim.apply_move(m, _promotion_for(m))["ok"]:
					continue
				_nodes += 1
				candidates.append({
					"moves": (n["moves"] as Array) + [m],
					"dict": sim.to_dict(),
					"score": _evaluate(sim, p),
				})
		if candidates.is_empty():
			break
		candidates.sort_custom(_by_score)
		frontier = candidates.slice(0, width)
		if Time.get_ticks_usec() > _deadline_usec:
			break
	return frontier[0] as Dictionary


# --- the reply search -----------------------------------------------------

## Ends the turn on the plan's position and lets the opponent take their best
## few moves, greedily. Greedy rather than searched because it is only there to
## answer one question — "does this hang something?" — and a hung piece or king
## is always the top-scoring reply available.
func _score_after_reply(sim: GameState, node: Dictionary, p: Dictionary) -> float:
	var plies: int = p["reply"]
	if plies <= 0:
		return float(node["score"])
	sim.load_dict(node["dict"])
	if sim.is_game_over():
		return _evaluate(sim, p)
	# Ends the turn even when the plan has moves left in it. At the difficulties
	# that plan fewer than three moves this hands the opponent a turn slightly
	# early, which errs toward caution — the wrong direction to err in is the
	# other one.
	sim.end_turn()
	for _i in plies:
		if sim.is_game_over() or Time.get_ticks_usec() > _deadline_usec:
			break
		var moves := _legal_moves(sim)
		if moves.is_empty():
			break
		var best: Move = null
		var best_gain := -INF
		for m in moves:
			var gain := _move_score(sim, m, p)
			if gain > best_gain:
				best_gain = gain
				best = m
		if best == null:
			break
		if not sim.apply_move(best, _promotion_for(best))["ok"]:
			break
		_nodes += 1
	return _evaluate(sim, p)


# --- evaluation -----------------------------------------------------------

## Always from this AI's point of view: positive is good for `owner_id`.
func _evaluate(sim: GameState, p: Dictionary) -> float:
	if sim.winner == owner_id:
		return WIN
	if sim.winner >= 0:
		return -WIN
	var total := 0.0
	var positional: bool = p["positional"]
	for pid in sim.state.pieces:
		var piece: Piece = sim.state.pieces[pid]
		var v: float = VALUES[piece.type]
		if positional:
			v += _square_value(piece, piece.position)
		total += v if piece.owner_id == owner_id else -v
	return total


## What a move looks like worth before playing it, to the side making it. Used
## to order the beam and to pick the opponent's greedy replies, so it must be
## cheap — no board copies, no move generation.
func _move_score(sim: GameState, m: Move, p: Dictionary) -> float:
	var score := 0.0
	if m.captured_id >= 0:
		var victim: Piece = sim.state.get_piece_by_id(m.captured_id)
		if victim != null:
			if victim.type == Piece.Type.KING:
				return WIN
			score += VALUES[victim.type]
	if m.is_promotion:
		score += VALUES[Piece.Type.QUEEN] - VALUES[Piece.Type.PAWN]
	if not p["positional"]:
		return score
	var mover: Piece = sim.state.get_piece_by_id(m.piece_id)
	if mover != null:
		score += _square_value(mover, m.to) - _square_value(mover, m.from)
	if m.sets_restricted:
		# Dropping onto its own first rank costs the pawn its double step until
		# it walks back out, which is usually not worth whatever took it there.
		score -= 18.0
	return score


static func _square_value(piece: Piece, sq: Vector3i) -> float:
	if sq.z == BoardState.MIDDLE_LEVEL:
		# On the glass board every piece moves as a queen and none of them can
		# be captured. That is a real promotion for a pawn and a smaller gain
		# for anything else, which pays for giving up the ability to capture
		# while it sits up there.
		return 26.0 if piece.type == Piece.Type.PAWN else 6.0
	var v: float = CENTRE[sq.x] + CENTRE[sq.y]
	if piece.type == Piece.Type.PAWN:
		v += absf(float(sq.y - piece.home_rank())) * 9.0
	elif piece.type == Piece.Type.KING:
		# Kings cannot change level at all, so the only safety available to one
		# is staying out of the middle of its own board.
		v -= (CENTRE[sq.x] + CENTRE[sq.y]) * 2.0
	return v


# --- helpers --------------------------------------------------------------

func _legal_moves(sim: GameState) -> Array:
	var out: Array = []
	for piece in sim.state.pieces_of(sim.current_player):
		out.append_array(sim.get_legal_moves(piece))
	return out


func _top_moves(sim: GameState, moves: Array, width: int, p: Dictionary) -> Array:
	var scored: Array = []
	for m in moves:
		scored.append({"move": m, "score": _move_score(sim, m, p)})
	scored.sort_custom(_by_score)
	var out: Array = []
	for i in mini(width, scored.size()):
		out.append(scored[i]["move"])
	return out


## An instance method rather than a static one purely so passing it to
## sort_custom() is unambiguous.
func _by_score(a: Dictionary, b: Dictionary) -> bool:
	return float(a["score"]) > float(b["score"])


## Always a queen. A rook or knight underpromotion can only matter when a queen
## would be worse, and with no check in this variant there is no stalemate to
## avoid and no fork a knight reaches that a queen does not.
static func _promotion_for(m: Move) -> int:
	return Piece.Type.QUEEN if m.is_promotion else -1


func _shuffled_pick(plans: Array, jitter: float) -> Dictionary:
	var best: Dictionary = plans[0]
	var best_score := -INF
	for plan in plans:
		var score := float(plan["score"]) + rng.randfn(0.0, jitter)
		if score > best_score:
			best_score = score
			best = plan
	return best


## The searched move came off a clone. Hand back the equivalent move generated
## from the real game instead, so what main.gd commits was produced by the same
## state it is committing against.
func _as_choice(game: GameState, m: Move) -> Dictionary:
	var piece: Piece = game.state.get_piece_by_id(m.piece_id)
	var chosen := m
	if piece != null:
		for candidate in game.get_legal_moves(piece):
			if candidate.to == m.to and candidate.kind == m.kind:
				chosen = candidate
				break
	return {"move": chosen, "promotion_type": _promotion_for(chosen)}
