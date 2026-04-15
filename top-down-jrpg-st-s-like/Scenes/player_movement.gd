extends CharacterBody2D

const TILE_SIZE = 16
const MOVE_DELAY = 0.15

var move_timer = 0.0

@export var player_sprite: Texture2D
@export var camera_zoom: Vector2 = Vector2(1, 1)

func _ready() -> void:
	$Sprite2D.texture = player_sprite
	$Camera2D.zoom = camera_zoom

func _physics_process(delta: float) -> void:
	move_timer -= delta
	
#	get the input the player is pressing and save it
	var x_axis = Input.get_axis("move_left", "move_right")
	var y_axis = Input.get_axis("move_up", "move_down")
	
	var direction = Vector2.ZERO
	
	
	if x_axis != 0:
		direction = Vector2(sign(x_axis), 0)
	elif y_axis != 0:
		direction = Vector2(0, sign(y_axis))
	
	if direction != Vector2.ZERO and move_timer <= 0:
		move_and_collide(direction * TILE_SIZE)
		move_timer = MOVE_DELAY
