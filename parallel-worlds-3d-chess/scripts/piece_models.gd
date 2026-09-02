## Finds and prepares imported piece models, with the primitive stand-ins as an
## automatic fallback.
##
## Drop model files into res://assets/pieces/ and they are used; leave the
## folder empty and the game runs exactly as before on primitives. Nothing else
## in the project needs to know which is in play.
##
## The loader is deliberately forgiving about what it finds, because asset packs
## disagree about naming, units and up-axis:
##   * a file per piece (king.fbx, Chess_King.glb, King_White.fbx …), matched by
##     looking for the piece's name anywhere in the filename;
##   * or one combined scene holding every piece as a child node, matched the
##     same way against node names;
##   * any scale — each model is measured and rescaled to a fixed target height
##     so silhouettes stay readable and consistent from above (art doc §4);
##   * Z-up exports, which are laid upright.
##
## Materials are overridden rather than used as authored. The off-black /
## off-white split and the matte / glossy army variant carry real information
## (art doc §2 and §4) — a pack's own black and white materials would lose the
## army distinction.
class_name PieceModels

const MODEL_DIR := "res://assets/pieces"
const EXTENSIONS := ["glb", "gltf", "fbx", "obj", "dae", "blend", "tscn", "scn", "res"]

## Height as a FRACTION OF ONE SQUARE per Piece.Type — not world units, so the
## board's scale stays the only definition of size. Chosen to keep the type
## hierarchy legible from a top-down or three-quarter camera, and to fill the
## square properly: a piece noticeably narrower than the square it stands on
## reads as a token dropped on a board rather than a chess set. The widest
## footprint (the king) stays under 0.75 of a square, so pieces on adjacent
## squares still read as separate.
const TARGET_HEIGHT := {
	Piece.Type.PAWN: 0.90,
	Piece.Type.KNIGHT: 1.13,
	Piece.Type.BISHOP: 1.16,
	Piece.Type.ROOK: 0.96,
	Piece.Type.QUEEN: 1.33,
	Piece.Type.KING: 1.48,
}


## The target height in world units, which is what callers actually want.
static func target_height(type: int) -> float:
	return TARGET_HEIGHT.get(type, 0.9) * BoardVisual.SQUARE


## Filename fragments that identify each piece, in preference order. Packs do
## not agree on vocabulary and they contain typos: the Complete Chess Set this
## project is aimed at ships the bishop as "Bisop.fbx" and the knight as
## "Horse.fbx". Matching on the single canonical word silently drops both and
## leaves you wondering why two pieces are still primitives, so every plausible
## spelling gets a chance.
const TYPE_ALIASES := {
	Piece.Type.PAWN: ["pawn"],
	Piece.Type.KNIGHT: ["knight", "horse", "knght"],
	Piece.Type.BISHOP: ["bishop", "bisop", "bishp"],
	Piece.Type.ROOK: ["rook", "tower", "castle"],
	Piece.Type.QUEEN: ["queen"],
	Piece.Type.KING: ["king"],
}

## type -> PackedScene or Mesh, or type -> null once we know there is nothing
## to load. Both are possible: Godot imports .fbx and .glb as scenes, but .obj
## defaults to importing as a bare Mesh.
static var _cache: Dictionary = {}
static var _scanned := false
static var _combined: PackedScene = null


## True when at least one piece type resolved to a real model.
static func any_models_found() -> bool:
	_scan()
	for t in TYPE_ALIASES:
		if _cache.get(t) != null:
			return true
	return _combined != null


## Prints what the loader actually resolved, once, at boot.
##
## Falling back to a primitive is silent by design — a partial set has to keep
## working — but silent is exactly wrong when the whole set falls back and you
## are left staring at stand-ins wondering why. This makes the Output panel say
## so, and say which of the two causes it is: nothing found on disk, or files
## found that would not load.
static func report() -> void:
	_scan()
	var files := _list_models()
	var names := {
		Piece.Type.PAWN: "pawn", Piece.Type.KNIGHT: "knight",
		Piece.Type.BISHOP: "bishop", Piece.Type.ROOK: "rook",
		Piece.Type.QUEEN: "queen", Piece.Type.KING: "king",
	}
	var missing: Array[String] = []
	for t in names:
		if _cache.get(t) == null:
			missing.append(names[t])

	if files.is_empty():
		print_rich("[color=yellow]Piece models: none in %s — using primitive stand-ins. "
			% MODEL_DIR + "See assets/pieces/README.md.[/color]")
		return
	if missing.is_empty():
		print("Piece models: all six loaded from %s." % MODEL_DIR)
		return
	if missing.size() == names.size() and _combined != null:
		print("Piece models: no filename matched; reading them out of %s."
			% String(files[0]).get_file())
		return
	push_warning("Piece models: %s fell back to primitives. %d file(s) are in %s, so either "
		% [", ".join(missing), files.size(), MODEL_DIR]
		+ "the names match nothing in PieceModels.TYPE_ALIASES, or the import failed — "
		+ "delete the .godot folder and reopen the project to force a reimport.")


## An upright, correctly scaled instance for this piece type, its base sitting
## at y = 0 and centred on the square. Returns null when no model is available,
## which is the caller's cue to build a primitive instead.
static func build(type: int) -> Node3D:
	_scan()
	var model := _instantiate_for(type)
	if model == null:
		return null
	# The model keeps whatever transform the importer gave it; the holder is
	# what gets fitted, so nothing about the source file has to be assumed.
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(model)
	_fit(model, target_height(type))
	return holder


static func apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		apply_material(child, material)


# --- discovery -----------------------------------------------------------

static func _scan() -> void:
	if _scanned:
		return
	_scanned = true

	var files := _list_models()
	for type in TYPE_ALIASES:
		var best := ""
		for alias in TYPE_ALIASES[type]:
			for path in files:
				var file_name: String = String(path).get_file().to_lower()
				if not file_name.contains(alias):
					continue
				# Prefer a file that does not name a colour: materials are
				# overridden anyway, and the neutral or light variant is the
				# safer base if someone later turns the override off.
				if best.is_empty() or (best.to_lower().contains("black") and not file_name.contains("black")):
					best = String(path)
			if not best.is_empty():
				break      # an earlier alias is a better match than a later one
		_cache[type] = load(best) if not best.is_empty() else null

	# Nothing matched by filename — the pack may be one scene holding them all.
	if not files.is_empty() and _cache.values().all(func(v): return v == null):
		_combined = load(String(files[0])) as PackedScene


static func _list_models() -> Array:
	var out: Array = []
	# DirAccess only sees source files in the editor and in a folder shipped
	# alongside the executable; ResourceLoader.exists() covers exported builds
	# where the source file has been replaced by its imported resource.
	var dir := DirAccess.open(MODEL_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir():
				var ext := entry.get_extension().to_lower()
				# Godot writes a .import sidecar next to each source file; the
				# file we want to load is the source path itself.
				if EXTENSIONS.has(ext):
					out.append(MODEL_DIR.path_join(entry))
			entry = dir.get_next()
		dir.list_dir_end()
	if not out.is_empty():
		return out

	for type in TYPE_ALIASES:
		for alias in TYPE_ALIASES[type]:
			for ext in EXTENSIONS:
				var guess: String = MODEL_DIR.path_join("%s.%s" % [alias, ext])
				if ResourceLoader.exists(guess):
					out.append(guess)
					break
	return out


static func _instantiate_for(type: int) -> Node3D:
	var res: Resource = _cache.get(type)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node3D
	if res is Mesh:
		# An .obj imports as a bare Mesh, not a scene — give it a node to live in.
		var mi := MeshInstance3D.new()
		mi.mesh = res as Mesh
		return mi

	if _combined == null:
		return null
	# Pull the matching child out of the combined scene and drop the rest.
	var root := _combined.instantiate()
	var found: Node = null
	for alias in TYPE_ALIASES[type]:
		found = _find_named(root, alias)
		if found != null:
			break
	if found == null:
		root.queue_free()
		return null
	var holder := Node3D.new()
	found.get_parent().remove_child(found)
	holder.add_child(found)
	(found as Node3D).transform = Transform3D.IDENTITY
	root.queue_free()
	return holder


static func _find_named(node: Node, keyword: String) -> Node:
	if node is Node3D and node.name.to_lower().contains(keyword):
		return node
	for child in node.get_children():
		var hit := _find_named(child, keyword)
		if hit != null:
			return hit
	return null


# --- normalisation -------------------------------------------------------

## Rescales and recentres the model so every pack lands the same way: upright,
## base on the board, centred on its square, at this type's target height.
##
## Each step re-measures rather than predicting where the box moved, so nested
## transforms inside the imported scene never have to be reasoned about.
static func _fit(model: Node3D, target_height: float) -> void:
	var box := _combined_aabb(model, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		return

	# A model authored Z-up arrives lying on its back. Its depth then exceeds
	# its height by a wide margin, which is not true of any upright chess piece.
	if box.size.z > box.size.y * 1.6:
		model.rotate_x(-PI / 2.0)
		box = _combined_aabb(model, Transform3D.IDENTITY)
		if box.size == Vector3.ZERO:
			return

	model.scale *= target_height / maxf(box.size.y, 0.0001)
	box = _combined_aabb(model, Transform3D.IDENTITY)

	# Base on the board, centre of the footprint over the middle of the square.
	var centre := box.get_center()
	model.position -= Vector3(centre.x, box.position.y, centre.z)


static func _combined_aabb(node: Node, xform: Transform3D) -> AABB:
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	var box := AABB()
	var started := false
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			box = here * mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_box := _combined_aabb(child, here)
		if child_box.size == Vector3.ZERO:
			continue
		box = child_box if not started else box.merge(child_box)
		started = true
	return box if started else AABB()
