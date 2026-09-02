## Orbit camera around the three-board stack.
##
## PC controls (art doc §8): left-drag to pan, right-drag or middle-drag to
## rotate, wheel to zoom. Left-click still selects — main.gd owns the left
## button and decides click versus drag on release. Smoothed so the
## vertical-move animation between levels stays readable while the camera moves.
class_name CameraRig
extends Node3D

const MIN_PITCH := -80.0
const MAX_PITCH := -5.0
const MIN_DISTANCE := 8.0
const MAX_DISTANCE := 42.0
## Framing for the whole stack, and for one board seen from above. Shared by the
## View buttons and by double-clicking a board, so the two ways of asking to
## look at a level agree on what that looks like.
const STACK_PITCH := -26.0
const STACK_DISTANCE := 24.0
const FOCUS_PITCH := -58.0
const FOCUS_DISTANCE := 13.0
## Framing for the double-click focus, which keeps all three boards on screen.
## It cannot reuse FOCUS_DISTANCE: that is tuned for the single-level view where
## the other two boards are hidden, and at 13 units the camera sits *between*
## the levels, so the board above fills the screen and hides the one you asked
## to look at. The camera has to clear the top of the stack — 2 * LEVEL_GAP
## above level 1 — before it can look down through it.
const LOOK_DOWN_PITCH := -60.0
const LOOK_DOWN_DISTANCE := BoardVisual.LEVEL_GAP * 2.0 / sin(deg_to_rad(60.0)) + 6.0
## Pan is scaled by distance so a drag moves the same amount of board across the
## screen whether you are zoomed in on one square or looking at the whole stack.
const PAN_SPEED := 0.0017
## How far the view may wander from the stack before it stops. Without this it
## is far too easy to pan off into empty space and lose the board entirely.
## Expressed in squares, so a bigger board gets proportionally more room and the
## limit still lands just outside its edge.
const PAN_LIMIT_HORIZONTAL := BoardVisual.SQUARE * 9.6
const PAN_LIMIT_BELOW := BoardVisual.SQUARE * 3.5
const PAN_LIMIT_ABOVE := BoardVisual.SQUARE * 5.2

@export var yaw := 0.0
@export var pitch := -26.0
@export var distance := 24.0

var camera: Camera3D

var _target_yaw := 0.0
var _target_pitch := -26.0
var _target_distance := 24.0
var _target_origin := Vector3.ZERO
var _dragging := false
## -1 for the full stack, otherwise the level the focused view is on.
var _focus_level := -1


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 55.0
	add_child(camera)
	_target_yaw = yaw
	_target_pitch = pitch
	_target_distance = distance
	_target_origin = BoardVisual.stack_centre()
	position = _target_origin
	_apply(1.0)


## mode -1 = whole stack, 0..2 = focus one level from a steeper angle.
func set_view_mode(mode: int) -> void:
	_focus_level = mode
	if mode < 0:
		_target_origin = BoardVisual.stack_centre()
		_target_pitch = STACK_PITCH
		_target_distance = STACK_DISTANCE
	else:
		_target_origin = Vector3(0, BoardVisual.level_height(mode), 0)
		_target_pitch = FOCUS_PITCH
		_target_distance = FOCUS_DISTANCE


## Centres on one board and tips the camera down at it, leaving all three boards
## on screen. This is what double-clicking a board does.
##
## Deliberately NOT set_view_mode(): that hides the other two levels, which is
## the opposite of what you want here. Double-clicking level 1 is how you ask
## "what is directly above and below this?", and hiding the answer would defeat
## it. The camera moves; nothing else changes, so the yaw you had chosen and the
## piece you had picked up both survive.
func look_down_at(level: int) -> void:
	_target_origin = Vector3(0, BoardVisual.level_height(level), 0)
	_target_pitch = LOOK_DOWN_PITCH
	_target_distance = clampf(LOOK_DOWN_DISTANCE, MIN_DISTANCE, MAX_DISTANCE)
	_clamp_origin()


## The yaw that seats a player behind their own army on one board: their pieces
## nearest the camera, the opponent's across the board from them.
##
## The side is NOT decided by colour alone, and that is the whole subtlety here.
## The two armies are mirrored (design doc §3, `Piece.forward_for`), so White
## starts at low ranks on the bottom board and at HIGH ranks on the top one.
## Hardcoding "White faces from yaw 0" would seat White behind Black's pieces
## on the top board — backwards, on exactly the board the mirroring exists to
## make interesting. So the answer is derived from the army's own forward
## direction instead.
##
## Geometry it depends on: `BoardVisual.square_to_world` puts rank 0 toward +Z,
## and yaw 0 puts the camera on the +Z side. So an army advancing toward rank 7
## (forward > 0) started at rank 0 and is viewed from yaw 0.
##
## Returns -1.0 for the middle board, which starts empty and belongs to neither
## player, so there is no home side to turn to.
static func home_yaw(owner_id: int, level: int) -> float:
	var army := BoardState.army_on_level(level)
	if army < 0:
		return -1.0
	return 0.0 if Piece.forward_for(owner_id, army) > 0 else 180.0


## Turns to sit behind `owner_id`'s army on `level`. No-op on the middle board.
func face_home_side(owner_id: int, level: int) -> void:
	var wanted := home_yaw(owner_id, level)
	if wanted < 0.0:
		return
	_target_yaw = _shortest_way_to(wanted)


## Yaw accumulates without bound as you drag, so the same view can be 0, 360 or
## -1080. Assigning a raw angle would send the camera all the way round, and
## sometimes round several times, for what should be a half turn at most. This
## picks whichever equivalent of `degrees` is nearest where the camera actually
## is, so the turn is always the short way.
func _shortest_way_to(degrees: float) -> float:
	return yaw + fposmod(degrees - yaw + 180.0, 360.0) - 180.0


## Slides the point the camera looks at, in the screen's own plane, so the board
## follows the cursor. Driven by main.gd, which owns the left mouse button and
## decides whether a given drag is a pan or a click.
func pan(relative: Vector2) -> void:
	if camera == null:
		return
	var basis := global_transform.basis
	var step := distance * PAN_SPEED
	# Drag right and the board should travel right, which means looking further
	# left; drag down and the board travels down, so look further up.
	_target_origin -= basis.x * relative.x * step
	_target_origin += basis.y * relative.y * step
	_clamp_origin()


## Back to framing the whole stack, or the focused level, without changing the
## current angle or zoom. The View buttons call set_view_mode(), which does this
## as a side effect, so re-clicking the active one is the in-game "recentre".
func recentre() -> void:
	_target_origin = BoardVisual.stack_centre() if _focus_level < 0 \
		else Vector3(0, BoardVisual.level_height(_focus_level), 0)


func _clamp_origin() -> void:
	var centre := BoardVisual.stack_centre()
	_target_origin.x = clampf(
		_target_origin.x, centre.x - PAN_LIMIT_HORIZONTAL, centre.x + PAN_LIMIT_HORIZONTAL)
	_target_origin.z = clampf(
		_target_origin.z, centre.z - PAN_LIMIT_HORIZONTAL, centre.z + PAN_LIMIT_HORIZONTAL)
	_target_origin.y = clampf(
		_target_origin.y, -PAN_LIMIT_BELOW,
		BoardVisual.level_height(BoardState.LEVELS - 1) + PAN_LIMIT_ABOVE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - 1.6, MIN_DISTANCE, MAX_DISTANCE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + 1.6, MIN_DISTANCE, MAX_DISTANCE)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_target_yaw -= mm.relative.x * 0.35
		_target_pitch = clampf(_target_pitch - mm.relative.y * 0.25, MIN_PITCH, MAX_PITCH)


func _process(delta: float) -> void:
	_apply(clampf(delta * 8.0, 0.0, 1.0))


func _apply(weight: float) -> void:
	yaw = lerp(yaw, _target_yaw, weight)
	pitch = lerp(pitch, _target_pitch, weight)
	distance = lerp(distance, _target_distance, weight)
	position = position.lerp(_target_origin, weight)
	rotation_degrees = Vector3(pitch, yaw, 0)
	camera.position = Vector3(0, 0, distance)
