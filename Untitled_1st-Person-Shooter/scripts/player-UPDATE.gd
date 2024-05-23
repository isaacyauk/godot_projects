extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var _mouse_input : bool = false
var _mouse_rotation : Vector3
var _rotation_input : float
var _tilt_input : float

# These titl vars allow you to clamp the camera looking to straight up and down. @export for quick tweaking.
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Camera3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


func _input(event):
	if event.is_action_pressed("quick_exit"):
		get_tree().quit()


func _unhandled_input(event):
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x
		_tilt_input = -event.relative.y


func _update_camera(delta):
	
	# Rotate camera using euler rotation
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta
	
	CAMERA_CONTROLLER.transform.basis = Basis.from_euler(_mouse_rotation)
	CAMERA_CONTROLLER.rotation.z = 0.0 # Avoid twisting camera
	
	_rotation_input = 0.0
	_tilt_input = 0.0


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	_update_camera(delta)
	
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
