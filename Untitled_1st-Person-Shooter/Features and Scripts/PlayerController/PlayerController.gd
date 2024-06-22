extends CharacterBody3D

var speed
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 4.5

# Get the gravity from the project settings to be synced with RigidBody nodes; which is typically 9.8
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Camera head-bob variables 
const BOB_FREQ = 2.0 	# How often bob happens
const BOB_AMP = 0.08 	# How far up and down the camera will move
var T_BOB = 0.0 	# Determines how far along the sine function is

# Camera FOV variables
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5


@onready var HEAD = $CameraRig
@onready var CAMERA = $CameraRig/Camera3D
@export var SENSITIVITY = 0.005

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		HEAD.rotate_y(-event.relative.x * SENSITIVITY)
		CAMERA.rotate_x(-event.relative.y * SENSITIVITY)
		CAMERA.rotation.x = clamp(CAMERA.rotation.x, deg_to_rad(-40), deg_to_rad(60))


func _input(event):
	if event.is_action_pressed("quick_exit"):
		get_tree().quit()


func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	# Handle sprint.
	if Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	# using HEAD.transform here since the HEAD is the game component that is rotating.
	var direction = (HEAD.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)
			
	# ------- Head bob -------
	# using "float(is_on_floor())" returns 1 or 0 depending on if the character is on the floor, giving a nice check that 0's out headbob if falling
	T_BOB += delta * velocity.length() * float(is_on_floor()) 
	# Assing CAMERA to the rseult of the headbobo function
	CAMERA.transform.origin = headbob(T_BOB)
	
	# ------- FOV update -------
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	CAMERA.fov = lerp(CAMERA.fov, target_fov, delta * 8.0)
	
	move_and_slide()


func headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos
