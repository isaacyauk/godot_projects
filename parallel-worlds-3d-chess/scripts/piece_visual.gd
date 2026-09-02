## The Node3D that stands in for one Piece. Purely visual + pickable — it holds
## no rules state, only the `piece_id` it mirrors, because undo rebuilds every
## Piece object from a snapshot and object identity does not survive that.
##
## Placeholder art stage (art doc §4): primitive stand-ins with a distinct
## silhouette and height per type, off-white / off-black per player, matte vs
## glossy per army. Swapping in Kenney models later means replacing
## `_build_meshes()` and nothing else.
class_name PieceVisual
extends Node3D

const PICK_LAYER := 2
## The primitive stand-ins are modelled against a 1.0 square at roughly the
## pre-scale heights, so they need both the size bump the models got and the
## board's own scale. Without this the fallback set looks tiny beside a real one.
const PRIMITIVE_SCALE := 1.45

var piece_id: int = -1
var piece_type: int = Piece.Type.PAWN
var owner_id: int = 0
var army: int = 0

var _material: StandardMaterial3D
var _mesh_root: Node3D
var _marker: MeshInstance3D
var _body: StaticBody3D


static func create_for(piece: Piece) -> PieceVisual:
	var v := PieceVisual.new()
	v.piece_id = piece.id
	v.piece_type = piece.type
	v.owner_id = piece.owner_id
	v.army = piece.army
	v.name = "Piece%d" % piece.id
	return v


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Palette.piece_albedo(owner_id)
	_material.roughness = Palette.piece_roughness(army)
	_material.metallic = Palette.piece_metallic(army)

	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	_build_meshes()

	# The pick collider follows the piece's height rather than being a fixed
	# box, so the top half of a king is as clickable as its base.
	var height: float = PieceModels.target_height(piece_type)
	_body = StaticBody3D.new()
	_body.collision_layer = PICK_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4 * BoardVisual.SQUARE
	cyl.height = height
	shape.shape = cyl
	shape.position = Vector3(0, height * 0.5, 0)
	_body.add_child(shape)
	_body.set_meta("piece_id", piece_id)
	add_child(_body)

	_build_marker()


## Hidden boards must also stop answering raycasts (focused view mode).
func set_pickable(on: bool) -> void:
	if _body != null:
		_body.collision_layer = PICK_LAYER if on else 0


## Rebuilds the silhouette after a promotion.
func set_piece_type(t: int) -> void:
	if t == piece_type:
		return
	piece_type = t
	for c in _mesh_root.get_children():
		c.queue_free()
	_build_meshes()


## The small persistent marker on a pawn that dropped from level 2 onto its own
## first rank and has lost its two-step move (art doc §6).
func set_restricted(on: bool) -> void:
	if _marker != null:
		_marker.visible = on


func _add_mesh(mesh: Mesh, y: float, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.position = Vector3(0, y, 0)
	mi.rotation.y = rot_y
	_mesh_root.add_child(mi)
	return mi


func _build_meshes() -> void:
	# A real model if one has been dropped into res://assets/pieces, otherwise
	# the primitive stand-in below. Materials are overridden either way, so the
	# off-black / off-white split and the matte / glossy army variant survive
	# whichever art is in play.
	var model := PieceModels.build(piece_type)
	if model != null:
		PieceModels.apply_material(model, _material)
		_mesh_root.add_child(model)
		_mesh_root.scale = Vector3.ONE     # models are already at target height
		_place_marker()
		return
	_mesh_root.scale = Vector3.ONE * PRIMITIVE_SCALE * BoardVisual.SQUARE

	match piece_type:
		Piece.Type.PAWN:
			var c := CylinderMesh.new()
			c.top_radius = 0.14
			c.bottom_radius = 0.24
			c.height = 0.38
			_add_mesh(c, 0.19)
			var s := SphereMesh.new()
			s.radius = 0.16
			s.height = 0.32
			_add_mesh(s, 0.5)
		Piece.Type.KNIGHT:
			var base := CylinderMesh.new()
			base.top_radius = 0.24
			base.bottom_radius = 0.28
			base.height = 0.22
			_add_mesh(base, 0.11)
			var head := BoxMesh.new()
			head.size = Vector3(0.22, 0.5, 0.42)
			var mi := _add_mesh(head, 0.48, deg_to_rad(20))
			mi.rotation.x = deg_to_rad(-14)
		Piece.Type.BISHOP:
			var base := CylinderMesh.new()
			base.top_radius = 0.24
			base.bottom_radius = 0.28
			base.height = 0.16
			_add_mesh(base, 0.08)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.22
			cone.height = 0.62
			_add_mesh(cone, 0.47)
		Piece.Type.ROOK:
			var body := BoxMesh.new()
			body.size = Vector3(0.42, 0.52, 0.42)
			_add_mesh(body, 0.26)
			var crown := BoxMesh.new()
			crown.size = Vector3(0.5, 0.14, 0.5)
			_add_mesh(crown, 0.59)
		Piece.Type.QUEEN:
			var base := CylinderMesh.new()
			base.top_radius = 0.13
			base.bottom_radius = 0.3
			base.height = 0.72
			_add_mesh(base, 0.36)
			var orb := SphereMesh.new()
			orb.radius = 0.15
			orb.height = 0.3
			_add_mesh(orb, 0.82)
		Piece.Type.KING:
			var base := CylinderMesh.new()
			base.top_radius = 0.18
			base.bottom_radius = 0.3
			base.height = 0.76
			_add_mesh(base, 0.38)
			var v := BoxMesh.new()
			v.size = Vector3(0.1, 0.3, 0.1)
			_add_mesh(v, 0.9)
			var h := BoxMesh.new()
			h.size = Vector3(0.28, 0.09, 0.09)
			_add_mesh(h, 0.92)


func _build_marker() -> void:
	_marker = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.13
	t.outer_radius = 0.2
	_marker.mesh = t
	var m := StandardMaterial3D.new()
	m.albedo_color = Palette.INVALID_SOFT
	m.emission_enabled = true
	m.emission = Palette.INVALID_SOFT
	m.emission_energy_multiplier = 0.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = m
	_place_marker()
	_marker.visible = false
	add_child(_marker)


## Sits the halo just clear of whatever the piece's silhouette actually is.
func _place_marker() -> void:
	if _marker == null:
		return
	_marker.position = Vector3(0, PieceModels.target_height(piece_type) + 0.3 * BoardVisual.SQUARE, 0)


func _process(delta: float) -> void:
	if _marker != null and _marker.visible:
		_marker.rotate_y(delta * 1.5)
