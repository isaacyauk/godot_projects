## Dev check: does the loader actually find a model for every piece type, and
## does each one come out at the height it is supposed to be?
##
## The failure this exists to catch is silent: a pack whose filenames the alias
## list misses loads nothing, PieceVisual quietly builds a primitive instead,
## and the only symptom is that the set looks wrong.
##
##   godot --headless --path <project> --script res://tests/test_models.gd
extends SceneTree

const NAMES := {
	Piece.Type.PAWN: "pawn",
	Piece.Type.KNIGHT: "knight",
	Piece.Type.BISHOP: "bishop",
	Piece.Type.ROOK: "rook",
	Piece.Type.QUEEN: "queen",
	Piece.Type.KING: "king",
}


func _initialize() -> void:
	print("Piece model loader\n")
	print("  any_models_found: %s" % PieceModels.any_models_found())
	print("  files seen: %s\n" % str(PieceModels._list_models()))

	var missing := 0
	for type in NAMES:
		var model := PieceModels.build(type)
		if model == null:
			missing += 1
			print("  MISSING  %-7s -> falls back to a primitive" % NAMES[type])
			continue
		root.add_child(model)
		var box := PieceModels._combined_aabb(model, Transform3D.IDENTITY)
		var want := PieceModels.target_height(type)
		var ok := absf(box.size.y - want) < 0.02 and absf(box.position.y) < 0.02
		print("  %s  %-7s h=%.3f (want %.3f)  base_y=%+.3f  width=%.3f" % [
			"OK     " if ok else "OFF    ", NAMES[type], box.size.y, want,
			box.position.y, maxf(box.size.x, box.size.z)])
		model.queue_free()

	print("\n%d of %d types missing a model." % [missing, NAMES.size()])
	quit(1 if missing > 0 else 0)
