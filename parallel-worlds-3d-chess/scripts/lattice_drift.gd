## Ambient motes that drift between the boards along the grid itself.
##
## Every particle spawns on a lattice point of a board — a square corner or the
## midpoint of a square edge — and drifts slowly toward the middle board. The
## effect is that the three levels quietly read as one connected structure,
## with the same 8x8 grid running through all of them, rather than as three
## unrelated planes floating in space.
##
## Deliberately rare and faint. One drifts past every second or so out of 225
## possible columns, each barely above the background, so it registers in
## peripheral vision without ever pulling attention off the board.
class_name LatticeDrift
extends GPUParticles3D

## World units per second — a slow fall, not a dart. Scaled with the board so a
## drift takes the same time to cross the gap whatever size the squares are.
const SPEED := 0.75 * BoardVisual.SQUARE
const AMOUNT := 10            ## how many can be in flight at once, across the whole board


## `level` is the board the drift leaves from, `direction` +1 for up or -1 for
## down, `height` how far it travels before fading out.
static func create(level: int, direction: int, height: float) -> LatticeDrift:
	var d := LatticeDrift.new()
	d.name = "LatticeDrift%d" % (level + 1)
	d.position = Vector3(0, BoardVisual.level_height(level), 0)
	d.amount = AMOUNT
	d.lifetime = height / SPEED
	d.preprocess = d.lifetime * 0.5
	# High randomness staggers the spawns, so they never fall in a rhythm.
	d.randomness = 0.85
	d.local_coords = false
	d.emitting = true
	var reach := 5.5 * BoardVisual.SQUARE
	d.visibility_aabb = AABB(
		Vector3(-reach, -height - 1.0, -reach), Vector3(reach * 2.0, (height + 1.0) * 2.0, reach * 2.0))
	d.process_material = _process_material(direction)
	d.draw_pass_1 = VerticalBeam.billboard_quad(
		Vector2(0.12, 1.1) * BoardVisual.SQUARE, Palette.LATTICE_DRIFT,
		BaseMaterial3D.BILLBOARD_FIXED_Y
	)
	return d


static func _process_material(direction: int) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	# EMISSION_SHAPE_POINTS picks one of the supplied points at random per
	# particle, which is exactly "snap every spawn onto the lattice".
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	var points := _lattice_points()
	pm.emission_point_count = points.size()
	pm.emission_point_texture = _points_texture(points)
	pm.direction = Vector3(0, float(direction), 0)
	pm.spread = 0.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = SPEED * 0.85
	pm.initial_velocity_max = SPEED * 1.15
	pm.scale_min = 0.6
	pm.scale_max = 1.3

	var c := Palette.LATTICE_DRIFT
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(c, 0.0), Color(c, 0.6), Color(c, 0.42), Color(c, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	return pm


## The 81 square corners plus the 144 edge midpoints of an 8x8 board, in the
## board's local space. Squares are centred on half-integers, so corners land
## on the integers -4..4 — times BoardVisual.SQUARE, because these have to sit
## exactly on the real grid, not on a unit one.
static func _lattice_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := BoardState.SIZE
	var s := BoardVisual.SQUARE
	for i in n + 1:
		for j in n + 1:
			pts.append(Vector3(i - 4.0, 0.0, j - 4.0) * s)          # corners
	for i in n + 1:
		for j in n:
			pts.append(Vector3(i - 4.0, 0.0, j - 3.5) * s)          # edges running in Z
			pts.append(Vector3(j - 3.5, 0.0, i - 4.0) * s)          # edges running in X
	return pts


## Godot takes emission points as a texture of positions, one texel per point.
static func _points_texture(points: PackedVector3Array) -> ImageTexture:
	var img := Image.create_empty(points.size(), 1, false, Image.FORMAT_RGBF)
	for i in points.size():
		var p := points[i]
		img.set_pixel(i, 0, Color(p.x, p.y, p.z))
	return ImageTexture.create_from_image(img)
