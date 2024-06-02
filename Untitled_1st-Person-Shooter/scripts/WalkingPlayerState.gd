class_name WalkingPlayerState
extends State

@export var ANIMATION : AnimationPlayer
@export var TOP_ANIM_SPEED: float = 19 # I had to change this value from 2.2 to 20 for things to work. Not sure why...

# This function is called when this state is entered.
func enter () -> void: 
	ANIMATION.play("walking", -1.0, 1.0)

func update(delta):
	set_animation_speed(Global.player.velocity.length())
	if Global.player.velocity.length() == 0.0:
		transition.emit("IdlePlayerState")

# This takes in the current speed of the player object and then scales the walking animation bassed on that speed.
func set_animation_speed(spd):
	var alpha = remap(spd, 0.0, Global.player.SPEED_DEFAULT, 0.0, 0.1)
	ANIMATION.speed_scale = lerp(0.0, TOP_ANIM_SPEED, alpha)
