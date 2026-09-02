## The menu's 3D background: the three empty boards, in the same night sky the
## game uses, on a slow orbit.
##
## It is the real BoardVisual rather than a picture of one, so the menu can
## never show a board the game no longer builds — and it costs nothing, since
## the boards build themselves and there are no pieces on them.
##
## Deliberately not CameraRig: the rig exists to be driven by the player and
## carries pan limits, focus modes and smoothing this has no use for.
class_name MenuBackdrop
extends Node3D

## Degrees per second. Slow enough to read as drift rather than motion — the
## menu is text you are reading, and a background that moves competes with it.
const SPIN := 3.5
const PITCH := -17.0
const DISTANCE := 31.0

var _camera: Camera3D
var _yaw := 28.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 52.0
	add_child(_camera)
	_apply()


func _process(delta: float) -> void:
	_yaw = fmod(_yaw + SPIN * delta, 360.0)
	_apply()


func _apply() -> void:
	var yaw_rad := deg_to_rad(_yaw)
	var pitch_rad := deg_to_rad(PITCH)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)) * DISTANCE
	var centre := BoardVisual.stack_centre()
	_camera.look_at_from_position(centre + offset, centre, Vector3.UP)
