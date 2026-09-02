## Headless tests for the computer opponent.
##
##   godot --headless --path <project> --script res://tests/test_ai.gd
##
## Two things need proving here, and only one of them is "it plays legal
## moves".
##
## The other is that the difficulty dial does something. That is easy to fake
## and hard to notice being faked, so it is tested three ways: the parameter
## table is asserted monotonic in every column; a position with a free enemy
## king proves every level can see a win; and a position where taking a free
## piece loses a king proves the levels with a reply search decline it and the
## levels without take it. If the slider were wired to nothing, the last of
## those fails.
##
## Search assertions go through `search()`, which is deterministic. Only the
## tests that are specifically about the blunder roll use `choose_move()`, and
## those seed the RNG.
extends SceneTree

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print("Parallel Worlds Chess — computer opponent tests\n")

	test_difficulty_table_is_monotonic()
	test_every_level_describes_itself()
	test_takes_a_free_king()
	test_the_win_is_not_blundered_away_above_level_3()
	test_the_lowest_level_does_miss_the_win()
	test_reply_search_declines_a_poisoned_capture()
	test_moves_are_always_legal()
	test_the_hardest_level_stays_inside_its_budget()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func t(name: String) -> void:
	_current = name
	print("\n%s" % name)


func ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)


# --- the dial itself ------------------------------------------------------

func test_difficulty_table_is_monotonic() -> void:
	t("the difficulty table")
	ok(AiPlayer.TABLE.size() == 10, "there are ten levels")

	var monotonic := true
	var everything_changes := true
	for d in range(AiPlayer.MIN_DIFFICULTY + 1, AiPlayer.MAX_DIFFICULTY + 1):
		var lo := AiPlayer.params(d - 1)
		var hi := AiPlayer.params(d)
		var lo_beams: Array = lo["beams"]
		var hi_beams: Array = hi["beams"]
		if float(hi["blunder"]) > float(lo["blunder"]):
			monotonic = false
		if float(hi["jitter"]) > float(lo["jitter"]):
			monotonic = false
		if int(hi["reply"]) < int(lo["reply"]):
			monotonic = false
		if int(hi["review"]) < int(lo["review"]):
			monotonic = false
		if int(hi_beams[0]) < int(lo_beams[0]):
			monotonic = false
		if hi_beams.size() < lo_beams.size():
			monotonic = false
		if int(hi["budget_ms"]) < int(lo["budget_ms"]):
			monotonic = false
		if not bool(hi["positional"]) and bool(lo["positional"]):
			monotonic = false
		# Two adjacent levels that search identically are two levels the player
		# cannot tell apart, which is the same as a slider notch doing nothing.
		if hi_beams == lo_beams and int(hi["reply"]) == int(lo["reply"]) \
				and int(hi["review"]) == int(lo["review"]) \
				and is_equal_approx(float(hi["blunder"]), float(lo["blunder"])):
			everything_changes = false
	ok(monotonic, "every column moves the same way from level 1 to level 10")
	ok(everything_changes, "no two adjacent levels search identically")

	var lowest := AiPlayer.params(1)
	var highest := AiPlayer.params(10)
	ok(int(lowest["reply"]) == 0, "level 1 never looks at your reply")
	ok(int(highest["reply"]) > 0, "level 10 does")
	ok(not bool(lowest["positional"]), "level 1 counts material and nothing else")
	ok(is_equal_approx(float(highest["blunder"]), 0.0), "level 10 never plays at random")
	ok(float(lowest["blunder"]) > 0.5, "level 1 often does")


func test_every_level_describes_itself() -> void:
	t("what the menu tells the player")
	var all_described := true
	var all_distinct := true
	var seen: Array = []
	for d in range(AiPlayer.MIN_DIFFICULTY, AiPlayer.MAX_DIFFICULTY + 1):
		var text := AiPlayer.describe(d)
		if text.strip_edges() == "" or AiPlayer.label(d).strip_edges() == "":
			all_described = false
		if seen.has(text):
			all_distinct = false
		seen.append(text)
	ok(all_described, "every level has a label and a plain-language description")
	ok(all_distinct, "and no two levels describe themselves the same way")


# --- seeing a win ---------------------------------------------------------

## White queen on an open file with the black king at the end of it.
func _free_king_position() -> GameState:
	return _position([
		[Piece.Type.QUEEN, 0, Vector3i(4, 4, 0)],
		[Piece.Type.KING, 0, Vector3i(0, 0, 0)],
		[Piece.Type.KING, 1, Vector3i(4, 0, 0)],
		[Piece.Type.PAWN, 1, Vector3i(7, 6, 0)],
	], 0)


func test_takes_a_free_king() -> void:
	t("a king sitting there for the taking")
	var found_at_every_level := true
	for d in range(AiPlayer.MIN_DIFFICULTY, AiPlayer.MAX_DIFFICULTY + 1):
		var game := _free_king_position()
		var ai := AiPlayer.new(0, d)
		var plans: Array = ai.search(game)["plans"]
		if plans.is_empty():
			found_at_every_level = false
			continue
		var first: Move = (plans[0]["moves"] as Array)[0]
		if first.to != Vector3i(4, 0, 0) or not first.is_capture():
			found_at_every_level = false
			print("    level %d played %s instead" % [d, first.describe()])
	ok(found_at_every_level, "the search finds it at all ten levels")


func test_the_win_is_not_blundered_away_above_level_3() -> void:
	t("a win, once the level is high enough to be trusted with one")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	var always_taken := true
	for d in range(AiPlayer.ALWAYS_TAKES_THE_WIN_ABOVE + 1, AiPlayer.MAX_DIFFICULTY + 1):
		for _trial in 25:
			var game := _free_king_position()
			var ai := AiPlayer.new(0, d, rng)
			var choice := ai.choose_move(game)
			if choice.is_empty() or (choice["move"] as Move).to != Vector3i(4, 0, 0):
				always_taken = false
	ok(always_taken, "levels 4-10 take it every single time, blunder roll or not")


func test_the_lowest_level_does_miss_the_win() -> void:
	t("and a level that is supposed to be missable")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var missed := 0
	for _trial in 60:
		var game := _free_king_position()
		var ai := AiPlayer.new(0, 1, rng)
		var choice := ai.choose_move(game)
		if choice.is_empty() or (choice["move"] as Move).to != Vector3i(4, 0, 0):
			missed += 1
	# The blunder roll fires 60% of the time at level 1. Missing none of sixty
	# would mean it is not firing at all.
	ok(missed > 0, "level 1 walks past a free king sometimes (%d of 60)" % missed)


# --- seeing a threat ------------------------------------------------------

## Black to move. The knight on d5 is the only thing standing between the white
## queen on d1 and the black king on d8, and it can win a bishop by leaving.
##
## Taking the bishop ends the move on level 1, and no two moves in a turn may
## end on the same level, so the king cannot then step aside — the choice is
## real and it is a choice between a piece and the game.
func _poisoned_capture_position() -> GameState:
	return _position([
		[Piece.Type.QUEEN, 0, Vector3i(3, 0, 0)],
		[Piece.Type.BISHOP, 0, Vector3i(5, 5, 0)],
		[Piece.Type.KING, 0, Vector3i(0, 0, 0)],
		[Piece.Type.KNIGHT, 1, Vector3i(3, 4, 0)],
		[Piece.Type.KING, 1, Vector3i(3, 7, 0)],
	], 1)


func test_reply_search_declines_a_poisoned_capture() -> void:
	t("a free bishop that costs a king")
	var bishop_square := Vector3i(5, 5, 0)

	for d in [1, 2]:
		var game := _poisoned_capture_position()
		var ai := AiPlayer.new(1, d, null)
		var plans: Array = ai.search(game)["plans"]
		var first: Move = (plans[0]["moves"] as Array)[0]
		ok(first.to == bishop_square,
			"level %d grabs it — it never looks at the reply" % d)

	for d in [7, 8, 9, 10]:
		var game := _poisoned_capture_position()
		var ai := AiPlayer.new(1, d, null)
		var found: Dictionary = ai.search(game)
		var plans: Array = found["plans"]
		var first: Move = (plans[0]["moves"] as Array)[0]
		ok(first.to != bishop_square,
			"level %d declines it — it sees the king go" % d)
		ok(float(plans[0]["score"]) > -AiPlayer.WIN,
			"…and level %d has something better than a lost game" % d)


# --- the boring, essential one -------------------------------------------

func test_moves_are_always_legal() -> void:
	t("a whole game, computer against computer")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var white := AiPlayer.new(0, 3, rng)
	var black := AiPlayer.new(1, 6, rng)
	var game := GameState.new()

	var every_move_legal := true
	var every_move_applied := true
	var moves_played := 0
	var promotions_handled := true

	for _turn in 12:
		var ai: AiPlayer = white if game.current_player == 0 else black
		# The move cap is 3; the guard is only here so a bug cannot hang the
		# test suite in an infinite loop.
		for _step in 4:
			if game.is_turn_complete() or game.is_game_over():
				break
			var choice := ai.choose_move(game)
			if choice.is_empty():
				break
			var m: Move = choice["move"]
			var piece: Piece = game.state.get_piece_by_id(m.piece_id)
			if piece == null or Move.find_to(game.get_legal_moves(piece), m.to) == null:
				every_move_legal = false
				break
			if m.is_promotion and int(choice["promotion_type"]) < 0:
				promotions_handled = false
			var result := game.apply_move(m, int(choice["promotion_type"]))
			if not result["ok"]:
				every_move_applied = false
				print("    refused: %s — %s" % [m.describe(), result["reason"]])
				break
			moves_played += 1
		if game.is_game_over():
			break
		game.end_turn()

	ok(moves_played > 20, "it played %d moves without stalling" % moves_played)
	ok(every_move_legal, "every move it chose was one the rules offered it")
	ok(every_move_applied, "every move it chose was accepted by GameState")
	ok(promotions_handled, "it never hands back a promotion without a piece to promote to")


func test_the_hardest_level_stays_inside_its_budget() -> void:
	t("level 10 on a full board")
	var game := GameState.new()
	var ai := AiPlayer.new(0, 10)
	var started := Time.get_ticks_msec()
	var found := ai.search(game)
	var elapsed := Time.get_ticks_msec() - started
	var budget: int = int(AiPlayer.params(10)["budget_ms"])
	ok(not (found["plans"] as Array).is_empty(), "it finds a plan from the opening position")
	ok(int(found["nodes"]) > 0, "it actually searched (%d positions)" % int(found["nodes"]))
	# The deadline is checked between nodes, so overshooting by one node's work
	# is expected; overshooting by a multiple is a runaway.
	ok(elapsed < budget * 3,
		"it came back in %dms against a %dms budget" % [elapsed, budget])


# --- helper ---------------------------------------------------------------

## Builds a position from [type, owner_id, square] triples. Every piece is put
## in army 0, which fixes each side's pawn direction the normal way.
func _position(specs: Array, to_move: int) -> GameState:
	var board := BoardState.new()
	for spec in specs:
		board.add_piece(Piece.create(board.next_id(), spec[0], spec[1], 0, spec[2]))
	var game := GameState.new(board)
	game.current_player = to_move
	game.is_first_turn = false
	return game
