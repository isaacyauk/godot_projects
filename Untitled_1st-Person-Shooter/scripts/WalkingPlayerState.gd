class_name WalkingPlayerState extends PlayerMovementState

@export var TOP_ANIM_SPEED: float = 2.2 # I had to change this value from 2.2 to 20 for things to work. Not sure why...

# This function is called when this state is entered.
func enter () -> void: 
	ANIMATION.play("walking", -1.0, 1.0)
	Global.player._speed = Global.player.SPEED_DEFAULT

func update(delta):
	set_animation_speed(Global.player.velocity.length())
	if Global.player.velocity.length() == 0.0:
		transition.emit("IdlePlayerState")

# This takes in the current speed of the player object and then scales the walking animation bassed on that speed.
func set_animation_speed(spd):
	var alpha = remap(spd, 0.0, Global.player.SPEED_DEFAULT, 0.0, 1.0)
	ANIMATION.speed_scale = lerp(0.0, TOP_ANIM_SPEED, alpha)


func _input(event) -> void:
	if event.is_action_pressed("sprint") and Global.player.is_on_floor():
		transition.emit("SprintingPlayerState")
