extends CharacterBody3D

# --- Player Nodes ---
@onready var head = $head
@onready var standing_collision_shape = $standing_collision_shape
@onready var crouching_collision_shape = $crouching_collision_shape
#@onready var ray_cast_3d = $RayCast3D

@onready var rc_crouch_check = $RC_CrouchCheck

# --- Speed Variables ---
# const means that the thing in question will never change, and will not be variable.
# @export adds the field into the godot inspector
var CURRENT_SPEED = 5.0
const WALKING_SPEED = 5.0
const SPRINTING_SPEED = 8.0
const CROUCH_SPEED = 3.0

# --- Movement Variables --- 
const JUMP_VELOCITY = 4.5
var LERP_SPEED = 10.0 # This will be used to gradually change the inputs and speed variables
var CROUCH_DEPTH = -0.5 # this is how much the camera will lower by when "crouch" is pressed.

# --- Input Variables --- 
var direction = Vector3.ZERO
const MOUSE_SENSITIVITY = 0.25
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# ------- FUNCTIONS/MAIN -------
# the ready function is run once, at the beginning of the game run
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # This locks the mouse into the play window
	
# The _input function caputures EVERY input event! 
func _input(event):
	# --- Mouse Look Logic ---
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		head.rotate_x(deg_to_rad(-event.relative.y * MOUSE_SENSITIVITY))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-98), deg_to_rad(98)) # Lock the rotation of the player head so that you can't do some paranormal activity crap

func _physics_process(delta):
# ------- Handling Movements -------
	Global.debug.add_property("MovementSpeed", CURRENT_SPEED, 1) # This is adding this value to the debug pannel using the custom methods in the debug class
	# --- Crouching Logic ---
	if Input.is_action_pressed("crouch"):
		CURRENT_SPEED = CROUCH_SPEED
		head.position.y = lerp(head.position.y, 1.8 + CROUCH_DEPTH, delta * LERP_SPEED)
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false # Enable/Disable collision shape according to current standing mode.

	# --- Standing Logic ---
	elif !rc_crouch_check.is_colliding():
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true
		head.position.y = lerp(head.position.y, 1.8, delta * LERP_SPEED)

		# --- Sprinting Logic ---
		if Input.is_action_pressed("sprint"):
			CURRENT_SPEED = SPRINTING_SPEED

		else:
			# --- Walking Logic ---
			CURRENT_SPEED = WALKING_SPEED	
	
	# Add the gravity. This checks to see if the player is on the floor, if not, apply gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump. This looks to see if the player is on the floor AND has pressed a jump button
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("left", "right", "forward", "backward")
	direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*LERP_SPEED)
	
	if direction:
		velocity.x = direction.x * CURRENT_SPEED
		velocity.z = direction.z * CURRENT_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, CURRENT_SPEED)
		velocity.z = move_toward(velocity.z, 0, CURRENT_SPEED)

	move_and_slide()
