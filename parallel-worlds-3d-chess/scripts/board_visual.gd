## Builds the three board planes and owns every square's material, highlight
## state and pick collider.
##
## Levels 1 and 3 are solid checkered plates that differ in value and finish.
## Level 2 is a translucent glass pane driven by shaders/glass_board.gdshader —
## the board whose rules are wholesale different is the one board made of a
## different material, which reads instantly and does not spend another colour
## from the fixed palette (art doc §3).
class_name BoardVisual
extends Node3D

## The size of one square, and the single place this project defines world
## scale. Everything geometric below is a multiple of it, and the pieces and
## particles derive from it too, so scaling the board is this one number.
const SQUARE := 1.15
const PLATE_THICKNESS := SQUARE * 0.12
## Vertical gap between boards. Wide enough to read all three at once and to
## let the vertical-move animation play legibly (art doc §3, "Board spacing" —
## explicitly a look-at-it-and-adjust number).
const LEVEL_GAP := SQUARE * 6.0
const PICK_LAYER := 1
## Board rims answer raycasts on their own layer so hovering one is
## distinguishable from hovering a square.
const RIM_LAYER := 4
const RIM_HALF := SQUARE * 4.14        ## just outside the board edge

const GLASS_SHADER := preload("res://shaders/glass_board.gdshader")
const RIM_SHADER := preload("res://shaders/rim_ripple.gdshader")
const RIM_PLANE_SIZE := SQUARE * 12.0

var squares: Array = []           ## squares[z][y * 8 + x] -> MeshInstance3D
var _materials: Array = []        ## same indexing -> StandardMaterial3D or ShaderMaterial
var _base_colors: Array = []      ## same indexing -> Color
var _level_roots: Array = []      ## z -> Node3D
var _level_bodies: Array = []     ## z -> Array of StaticBody3D
var _drifts: Array = []           ## the two ambient lattice emitters
var _rims: Array = []             ## z -> MeshInstance3D carrying the ripple shader
var _rim_materials: Array = []    ## z -> ShaderMaterial for that plane
var _rim_bodies: Array = []       ## z -> StaticBody3D that answers hover rays
var _rim_available: Array = []    ## z -> can a move still END on this board
var _rim_intensity: Array = []    ## z -> eased toward the target brightness
var _hover_level := -1
var _frame_materials: Array = []  ## z -> the slab material, or null on the glass level
## z -> opacity multiplier, 1.0 normally. Move shadow drops the top board's so
## you can see the projection through it.
var _level_alpha: Array = []


static func level_height(z: int) -> float:
	return z * LEVEL_GAP


## World position of the centre of a square. Rank 0 sits toward +Z so White's
## level-1 army faces the default camera.
static func square_to_world(sq: Vector3i) -> Vector3:
	return Vector3((sq.x - 3.5) * SQUARE, level_height(sq.z), (3.5 - sq.y) * SQUARE)


static func stack_centre() -> Vector3:
	return Vector3(0, level_height(1), 0)


static func is_glass_level(z: int) -> bool:
	return z == BoardState.MIDDLE_LEVEL


func _ready() -> void:
	for z in BoardState.LEVELS:
		_level_alpha.append(1.0)
	for z in BoardState.LEVELS:
		var root := Node3D.new()
		root.name = "Level%d" % (z + 1)
		add_child(root)
		_level_roots.append(root)
		_build_level(z, root)
		_rim_available.append(false)
		_rim_intensity.append(0.0)
		_build_rim(z, root)
	# Levels 1 and 3 both drift toward the middle board, which is what ties the
	# three planes together as one structure.
	_drifts.append(LatticeDrift.create(0, 1, LEVEL_GAP))
	_drifts.append(LatticeDrift.create(2, -1, LEVEL_GAP))
	for d in _drifts:
		add_child(d)


func _build_level(z: int, root: Node3D) -> void:
	_frame_materials.append(null)
	if is_glass_level(z):
		_build_glass_frame(z, root)
	else:
		# Frame slab underneath, so each board reads as an object in space
		# rather than 64 floating tiles.
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(SQUARE * 8.6, PLATE_THICKNESS * 0.8, SQUARE * 8.6)
		frame.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Palette.BOARD_FRAME[z]
		fmat.roughness = Palette.BOARD_ROUGHNESS[z]
		# Pinned behind the squares in the transparent queue. Depth writing alone
		# still leaves the slab and the squares competing for who draws first,
		# and the slab is directly under every square — it has to be the thing
		# they blend over, every frame, from every angle. Harmless while the
		# board is opaque, since opaque geometry ignores render_priority.
		fmat.render_priority = -1
		frame.material_override = fmat
		frame.position = Vector3(0, level_height(z) - PLATE_THICKNESS * 0.7, 0)
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(frame)
		_frame_materials[z] = fmat

	var level_bodies: Array = []
	var level_squares: Array = []
	var level_materials: Array = []
	var level_colors: Array = []
	level_squares.resize(64)
	level_materials.resize(64)
	level_colors.resize(64)

	for y in BoardState.SIZE:
		for x in BoardState.SIZE:
			var idx := y * BoardState.SIZE + x
			var is_light := (x + y) % 2 == 1
			var pos := square_to_world(Vector3i(x, y, z))

			var mi := MeshInstance3D.new()
			var mat: Material
			var col: Color

			if is_glass_level(z):
				col = Palette.GLASS_LIGHT if is_light else Palette.GLASS_DARK
				var plane := PlaneMesh.new()
				plane.size = Vector2(SQUARE * 0.98, SQUARE * 0.98)
				mi.mesh = plane
				mat = _make_glass_material(col)
				# Transparent surfaces sort back-to-front; these are coplanar and
				# never overlap each other, so no sorting hint is needed.
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				col = Palette.BOARD_LIGHT[z] if is_light else Palette.BOARD_DARK[z]
				var bm := BoxMesh.new()
				bm.size = Vector3(SQUARE * 0.98, PLATE_THICKNESS, SQUARE * 0.98)
				mi.mesh = bm
				var sm := StandardMaterial3D.new()
				sm.albedo_color = col
				sm.roughness = Palette.BOARD_ROUGHNESS[z]
				mat = sm
				# Boards must not shadow each other. The key light comes from
				# above, so a casting board would drop level 1 into the shade of
				# the two above it and make it unreadable. Pieces still cast,
				# which is what grounds them on their own square.
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			mi.material_override = mat
			mi.position = pos
			root.add_child(mi)

			var body := StaticBody3D.new()
			body.collision_layer = PICK_LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(SQUARE, PLATE_THICKNESS, SQUARE)
			shape.shape = box
			body.add_child(shape)
			body.position = pos
			body.set_meta("square", Vector3i(x, y, z))
			root.add_child(body)
			level_bodies.append(body)

			level_squares[idx] = mi
			level_materials[idx] = mat
			level_colors[idx] = col

	squares.append(level_squares)
	_materials.append(level_materials)
	_base_colors.append(level_colors)
	_level_bodies.append(level_bodies)


func _make_glass_material(fill: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("edge_color", Palette.GLASS_EDGE)
	mat.set_shader_parameter("edge_width", 0.07)
	mat.set_shader_parameter("edge_glow", 1.9)
	mat.set_shader_parameter("shimmer_speed", 0.9)
	mat.set_shader_parameter("shimmer_depth", 0.14)
	mat.set_shader_parameter("highlight_color", Color(0, 0, 0, 0))
	mat.set_shader_parameter("highlight_amount", 0.0)
	return mat


## Four glowing bars around the rim instead of a solid slab, so the glass pane
## has a defined outline without a backing plate behind it.
func _build_glass_frame(z: int, root: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Palette.GLASS_RIM
	var y := level_height(z)
	var half := SQUARE * 4.06
	var bars := [
		[Vector3(0, y, half), Vector3(SQUARE * 8.2, SQUARE * 0.045, SQUARE * 0.09)],
		[Vector3(0, y, -half), Vector3(SQUARE * 8.2, SQUARE * 0.045, SQUARE * 0.09)],
		[Vector3(half, y, 0), Vector3(SQUARE * 0.09, SQUARE * 0.045, SQUARE * 8.2)],
		[Vector3(-half, y, 0), Vector3(SQUARE * 0.09, SQUARE * 0.045, SQUARE * 8.2)],
	]
	for bar in bars:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bar[1]
		mi.mesh = bm
		mi.material_override = mat
		mi.position = bar[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## The "can I still end a move on this board?" indicator: a green outline just
## outside the board, with a lighter crest that swells outward from it and fades
## (art doc §6, levels-used tracker). One flat plane per level carrying
## shaders/rim_ripple.gdshader — the ripple needs room to travel, which four
## thin bars do not have.
func _build_rim(z: int, root: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = RIM_SHADER
	mat.set_shader_parameter("rim_color", Palette.LEVEL_RIM)
	mat.set_shader_parameter("ripple_color", Palette.LEVEL_RIPPLE)
	mat.set_shader_parameter("plane_size", RIM_PLANE_SIZE)
	mat.set_shader_parameter("board_half", RIM_HALF)
	mat.set_shader_parameter("intensity", 0.0)

	var plane := PlaneMesh.new()
	plane.size = Vector2(RIM_PLANE_SIZE, RIM_PLANE_SIZE)
	var mi := MeshInstance3D.new()
	mi.name = "Rim"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(0, level_height(z) + 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	root.add_child(mi)

	# Hover target: a thin frame of boxes following the drawn line. Squares and
	# pieces are queried before this layer (main.gd::_pick), so it can be
	# generous without ever stealing a click from the board.
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_meta("rim_level", z)
	var y := level_height(z)
	var span := RIM_HALF * 2.0 + SQUARE * 0.7
	for spec in [
		[Vector3(0, y, RIM_HALF), Vector3(span, SQUARE * 0.4, SQUARE * 0.7)],
		[Vector3(0, y, -RIM_HALF), Vector3(span, SQUARE * 0.4, SQUARE * 0.7)],
		[Vector3(RIM_HALF, y, 0), Vector3(SQUARE * 0.7, SQUARE * 0.4, span)],
		[Vector3(-RIM_HALF, y, 0), Vector3(SQUARE * 0.7, SQUARE * 0.4, span)],
	]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		shape.position = spec[0]
		body.add_child(shape)
	root.add_child(body)

	_rims.append(mi)
	_rim_materials.append(mat)
	_rim_bodies.append(body)


## `levels` are the levels a move could still END on this turn — not merely the
## ones not yet spent. A board nothing can reach gets no outline.
func set_available_levels(levels: Array) -> void:
	for z in BoardState.LEVELS:
		var available: bool = levels.has(z)
		_rim_available[z] = available
		(_rims[z] as MeshInstance3D).visible = available
		(_rim_bodies[z] as StaticBody3D).collision_layer = RIM_LAYER if available else 0
		if not available and _hover_level == z:
			_hover_level = -1


## -1 for none. Only an available board can be hovered; a board with no move
## has no outline to point at.
func set_hovered_level(z: int) -> void:
	_hover_level = z if z >= 0 and z < _rim_available.size() and _rim_available[z] else -1


func hovered_level() -> int:
	return _hover_level


func _process(delta: float) -> void:
	_animate_rims(delta)


## Eases each rim between hidden, resting and hovered. The ripple itself runs
## on TIME inside the shader, so this only has to move one number.
func _animate_rims(delta: float) -> void:
	var weight := clampf(delta * 7.0, 0.0, 1.0)
	for z in BoardState.LEVELS:
		if z >= _rim_materials.size():
			continue
		var target := 0.0
		if _rim_available[z]:
			target = 1.7 if z == _hover_level else 1.0
		_rim_intensity[z] = lerpf(_rim_intensity[z], target, weight)
		(_rim_materials[z] as ShaderMaterial).set_shader_parameter(
			"intensity", _rim_intensity[z])


# --- highlighting --------------------------------------------------------

func clear_highlights() -> void:
	for z in BoardState.LEVELS:
		for idx in 64:
			_reset(z, idx)


func _reset(z: int, idx: int) -> void:
	var mat: Material = _materials[z][idx]
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("highlight_amount", 0.0)
		return
	var sm := mat as StandardMaterial3D
	_set_albedo(sm, _base_colors[z][idx], z)
	sm.emission_enabled = false


## Every write to a solid square's albedo goes through here, so the level's
## opacity survives a highlight, a reset and an invalid flash alike.
##
## Doing it this way rather than through GeometryInstance3D.transparency is
## deliberate: that property is not supported by the Compatibility renderer,
## which is the one this project is pinned to, and it would have failed
## invisibly — exactly the class of bug that cost this project a day already.
func _set_albedo(sm: StandardMaterial3D, color: Color, z: int) -> void:
	var a: float = _level_alpha[z] if z < _level_alpha.size() else 1.0
	sm.albedo_color = Color(color.r, color.g, color.b, color.a * a)
	if a < 1.0:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Transparent surfaces do not write depth by default, so 64 square boxes
		# and the slab under them end up blended in whatever order the renderer
		# sorted them into that frame — which is by distance, so it changes as
		# the camera orbits. That is what made the checker appear to flip: a
		# square blended over the slab from one angle and over the sky from
		# another, giving one base colour two different results. Writing depth
		# makes each square occlude what is behind it, so the order stops
		# mattering.
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	else:
		sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


## Fades one board without touching what is drawn on it. `alpha` 1.0 is solid.
func set_level_alpha(z: int, alpha: float) -> void:
	if z < 0 or z >= _level_alpha.size() or is_equal_approx(_level_alpha[z], alpha):
		return
	_level_alpha[z] = alpha
	if is_glass_level(z):
		return          # the glass pane is already see-through; leave it alone
	for idx in 64:
		var mat: Material = _materials[z][idx]
		if mat is StandardMaterial3D:
			# Repaint from the base colour, which drops any highlight. The caller
			# redraws highlights straight after, so nothing is actually lost.
			_set_albedo(mat as StandardMaterial3D, _base_colors[z][idx], z)
	var fm: Variant = _frame_materials[z]
	if fm is StandardMaterial3D:
		_set_albedo(fm as StandardMaterial3D, Palette.BOARD_FRAME[z], z)


func highlight(sq: Vector3i, color: Color, energy: float = 0.55) -> void:
	if not BoardState.in_bounds(sq):
		return
	var idx := sq.y * BoardState.SIZE + sq.x
	var mat: Material = _materials[sq.z][idx]
	if mat is ShaderMaterial:
		var gm := mat as ShaderMaterial
		# The glass keeps a little of its transparency even when highlighted,
		# so a lit square still reads as part of the pane.
		gm.set_shader_parameter("highlight_color", Color(color, 0.72))
		gm.set_shader_parameter("highlight_amount", clampf(0.55 + energy * 0.45, 0.0, 1.0))
		return
	var sm := mat as StandardMaterial3D
	_set_albedo(sm, color, sq.z)
	sm.emission_enabled = true
	sm.emission = color
	sm.emission_energy_multiplier = energy


## Red-family rejection cue, shared by every illegal-move case including the
## level-2 no-capture blocks (art doc §5 and §11 — deliberately one cue, not
## a special one per rule).
func flash_invalid(sq: Vector3i) -> void:
	if not BoardState.in_bounds(sq):
		return
	highlight(sq, Palette.INVALID, 0.9)
	var idx := sq.y * BoardState.SIZE + sq.x
	var mat: Material = _materials[sq.z][idx]
	var tween := create_tween()
	if mat is ShaderMaterial:
		tween.tween_method(
			func(v: float): (mat as ShaderMaterial).set_shader_parameter("highlight_amount", v),
			1.0, 0.0, 0.45
		)
	else:
		tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.45)
	tween.tween_callback(_reset.bind(sq.z, idx))


# --- view modes ----------------------------------------------------------

## `mode` is -1 for the full stack, or a level index for the focused view
## (art doc §8 — both are supported modes, not a default/fallback pair).
func set_view_mode(mode: int) -> void:
	for z in BoardState.LEVELS:
		var shown := (mode < 0 or mode == z)
		(_level_roots[z] as Node3D).visible = shown
		# Hiding a Node3D does not stop its bodies answering raycasts, so the
		# pick colliders have to be switched off explicitly.
		for body in _level_bodies[z]:
			(body as StaticBody3D).collision_layer = PICK_LAYER if shown else 0
	# The drift only says something about the stack as a whole, so it has no
	# job in the focused single-level view.
	for d in _drifts:
		(d as LatticeDrift).visible = mode < 0
		(d as LatticeDrift).emitting = mode < 0
