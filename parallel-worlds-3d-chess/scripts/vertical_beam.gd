## The column that marks a vertical move — a piece rising or dropping to the
## adjacent level.
##
## Two jobs, same node:
##   * a standing hint on the selected piece's square whenever it can change
##     level, one instance per direction, so the signature mechanic advertises
##     itself rather than hiding in the highlight list;
##   * a trail during the move animation itself (art doc §5, "a light trail on
##     the vertical axis, since this is the signature mechanic").
##
## Just slow green vertical streaks. An earlier version put a dense haze of tiny
## pale motes underneath them for body; it read as noise rather than as a beam,
## so the lines carry it alone.
class_name VerticalBeam
extends Node3D

## World units per second — a slow, deliberate drift. Scaled with the board so
## the climb between levels reads at the same pace whatever size it is.
const STREAK_SPEED := 0.95 * BoardVisual.SQUARE
const STREAK_AMOUNT := 26

## The level the column starts on, so the focused view can hide a beam whose
## source board is not on screen.
var source_level: int = -1
## Counts how many times the emitters have actually been re-seeded. Only used
## by the tests, which assert that hovering around the board does not churn it.
var restarts: int = 0

var _streaks: GPUParticles3D

# What the column is currently running, so an identical request can be ignored.
var _shown := false
var _base := Vector3.ZERO
var _direction := 0
var _height := 0.0
var _intensity := 0.0


static func create() -> VerticalBeam:
	var b := VerticalBeam.new()
	b.name = "VerticalBeam"
	b.visible = false

	b._streaks = _make_emitter("Streaks", STREAK_AMOUNT)
	b._streaks.process_material = _streak_process_material()
	b._streaks.draw_pass_1 = _streak_mesh()
	b.add_child(b._streaks)
	return b


static func _make_emitter(node_name: String, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = 2.5
	p.preprocess = 2.5      # start already full, so a hint appears instantly
	p.randomness = 0.65
	p.local_coords = false
	p.emitting = false
	# Particles live well outside the emitter's own origin; without this they
	# get culled the moment the emitter leaves the frame.
	var half := 1.5 * BoardVisual.SQUARE
	var span := BoardVisual.LEVEL_GAP * 1.4
	p.visibility_aabb = AABB(Vector3(-half, -span, -half), Vector3(half * 2.0, span * 2.0, half * 2.0))
	return p


# --- the green lines -----------------------------------------------------

static func _streak_process_material() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# The column is as wide as most of a square, so it fills the tile it stands on.
	pm.emission_box_extents = Vector3(0.3, 0.02, 0.3) * BoardVisual.SQUARE
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 1.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = STREAK_SPEED * 0.85
	pm.initial_velocity_max = STREAK_SPEED * 1.15
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color_ramp = _ramp(Palette.BEAM_STREAK, 0.85, 0.6)
	return pm


static func _streak_mesh() -> Mesh:
	# BILLBOARD_FIXED_Y keeps the quad upright while it turns to face the
	# camera, so a tall quad reads as a vertical line from any angle.
	return _billboard_quad(
		Vector2(0.07, 1.5) * BoardVisual.SQUARE, Palette.BEAM_STREAK,
		BaseMaterial3D.BILLBOARD_FIXED_Y)


# --- shared construction -------------------------------------------------

## Fades in off the board and out again before the destination plate, so the
## column has no hard start or stop.
static func _ramp(color: Color, peak: float, tail: float) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.72, 1.0])
	grad.colors = PackedColorArray([
		Color(color, 0.0), Color(color, peak), Color(color, tail), Color(color, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp


## A soft round falloff. Without it the particles render as hard little
## squares, which reads as pixel noise rather than as a shimmer. Shared with
## LatticeDrift.
static func soft_dot_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


static func billboard_quad(size: Vector2, color: Color, billboard: int) -> Mesh:
	return _billboard_quad(size, color, billboard)


static func _billboard_quad(size: Vector2, color: Color, billboard: int) -> Mesh:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = billboard as BaseMaterial3D.BillboardMode
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.albedo_texture = soft_dot_texture()
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad


# --- control -------------------------------------------------------------

## Starts the column at `base`, travelling `height` world units in `direction`
## (+1 up, -1 down). `intensity` scales the particle counts for the move
## animation, which should read a little stronger than the standing hint.
##
## Idempotent, and that matters: re-seeding a GPUParticles3D restarts its whole
## loop, which is visible as a hitch. The caller redraws on every hover change,
## so asking for a column that is already running has to be free.
func show_at(base: Vector3, height: float, direction: int, level: int, intensity: float = 1.0) -> void:
	# Cheap bookkeeping that never touches the emitters.
	source_level = level
	visible = true
	if _shown and direction == _direction \
			and is_equal_approx(height, _height) \
			and is_equal_approx(intensity, _intensity) \
			and base.is_equal_approx(_base):
		return

	_shown = true
	_base = base
	_direction = direction
	_height = height
	_intensity = intensity
	restarts += 1
	position = base
	_arm(_streaks, height, STREAK_SPEED, direction, int(STREAK_AMOUNT * intensity))


func _arm(p: GPUParticles3D, height: float, speed: float, direction: int, amount: int) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, float(direction), 0)
	p.lifetime = maxf(height / speed, 0.2)
	p.preprocess = p.lifetime
	p.amount = maxi(amount, 1)
	p.restart()
	p.emitting = true


func hide_beam() -> void:
	visible = false
	source_level = -1
	if not _shown:
		return
	_shown = false
	_streaks.emitting = false
