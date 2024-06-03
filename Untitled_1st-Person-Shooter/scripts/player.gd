extends CharacterBody3D


# The TILT vars allow you to clamp the camera looking to straight up and down. @export for quick tweaking.
@export var TILT_LOWER_LIMIT := deg_to_rad(-90.0)
@export var TILT_UPPER_LIMIT := deg_to_rad(90.0)
@export var CAMERA_CONTROLLER : Node3D
@export var MOUSE_SENSITIVITY : float = 0.25
@export var ANIMATION_PLAYER : AnimationPlayer
@export_range(5, 10, 0.1) var CROUCH_SPEED : float = 7.0 	# This makes the animation run 7 times faster 
@export var CROUCH_SHAPECAST : Node3D
@export var TOGGLE_CROUCH : bool = true
@export var SPEED_SPRINTING : float = 7
@export var SPEED_DEFAULT : float = 5.0
@export var SPEED_CROUCH : float = 2.0
@export var JUMP_VELOCITY = 4.5
@export var ACCELERATION : float = 0.1
@export var DECELERATION : float = 0.25


var _speed : float
var _mouse_input : bool = false
var _mouse_rotation : Vector3
var _rotation_input : float
var _tilt_input : float
var _player_rotation : Vector3
var _camera_rotation : Vector3
var _is_crouching : bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _input(event):
	if event.is_action_pressed("quick_exit"):
		get_tree().quit()
	if event.is_action_pressed("crouch") and is_on_floor():
		toggle_crouch()
		
	# Input check conditions if Toggle Crouch option is disabled.
	if event.is_action_pressed("crouch") and _is_crouching == false and is_on_floor() and TOGGLE_CROUCH == false: # hold to crouch
		crouching(true)
	if event.is_action_released("crouch") and TOGGLE_CROUCH == false: # Release to uncrouch
		if CROUCH_SHAPECAST.is_colliding() == false:
			crouching(false)
		elif CROUCH_SHAPECAST.is_colliding() == true:
			uncrouch_check()


func _unhandled_input(event):
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * MOUSE_SENSITIVITY
		_tilt_input = -event.relative.y * MOUSE_SENSITIVITY


func _update_camera(delta):
	
	# Rotate camera using euler rotation
	_mouse_rotation.x += _tilt_input * delta
	_mouse_rotation.x = clamp(_mouse_rotation.x, TILT_LOWER_LIMIT, TILT_UPPER_LIMIT)
	_mouse_rotation.y += _rotation_input * delta
	
	_player_rotation = Vector3(0.0, _mouse_rotation.y, 0.0)
	_camera_rotation = Vector3(_mouse_rotation.x, 0.0, 0.0)
	
	CAMERA_CONTROLLER.transform.basis = Basis.from_euler(_camera_rotation)
	CAMERA_CONTROLLER.rotation.z = 0.0 # Avoid twisting camera
	
	global_transform.basis = Basis.from_euler(_player_rotation)
	
	_rotation_input = 0.0
	_tilt_input = 0.0


func _ready():
	Global.player = self # When the player controller loads, this refreneces itself to the global var	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	_speed = SPEED_DEFAULT

	CROUCH_SHAPECAST.add_exception($".")

func _physics_process(delta):
	Global.debug.add_property("MovementSpeed", _speed, 1) # This is adding this value to the debug pannel using the custom methods in the debug class
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	_update_camera(delta)
	
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and _is_crouching == false:
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = lerp(velocity.x, direction.x * _speed, ACCELERATION)
		velocity.z = lerp(velocity.z, direction.z * _speed, ACCELERATION)
	else:
		velocity.x = move_toward(velocity.x, 0, DECELERATION)
		velocity.z = move_toward(velocity.z, 0, DECELERATION)

	move_and_slide()

func toggle_crouch():
	if _is_crouching == true and CROUCH_SHAPECAST.is_colliding() == false:
		crouching(false)
	elif _is_crouching == false:
		crouching(true)


func crouching(state : bool):
	match state:
		true: 
			ANIMATION_PLAYER.play("crouch", 0, CROUCH_SPEED)
			set_movement_speed("crouching")
		false:
			ANIMATION_PLAYER.play("crouch", 0, -CROUCH_SPEED, true)
			set_movement_speed("default")

# A function that checks if the player is colliding with something overhead
func uncrouch_check():
	if CROUCH_SHAPECAST.is_colliding() == false:
		crouching(false)
	if CROUCH_SHAPECAST.is_colliding() == true:
		await get_tree().create_timer(0.1).timeout # if crouching is still true, wait 0.1secs and check again.
		uncrouch_check()


func set_movement_speed(state: String):
	match state:
		"default":
			_speed = SPEED_DEFAULT
		"crouching":
			_speed = SPEED_CROUCH

func _on_animation_player_animation_started(anim_name):
	if anim_name == "crouch":
		_is_crouching = !_is_crouching
