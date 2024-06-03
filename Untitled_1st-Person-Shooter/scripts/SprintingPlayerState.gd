class_name SprintingPlayerState extends PlayerMovementState

@export var TOP_ANIM_SPEED: float = 1.6 # Tweak this as needed


func enter() -> void:
	ANIMATION.play("sprinting", 0.5, 1.0)
	Global.player._speed = Global.player.SPEED_SPRINTING


func update(delta):
	set_animation_speed(Global.player.velocity.length())


# This takes in the current speed of the player object and then scales the walking animation bassed on that speed.
func set_animation_speed(spd):
	var alpha = remap(spd, 0.0, Global.player.SPEED_SPRINTING, 0.0, 1.0)
	ANIMATION.speed_scale = lerp(0.0, TOP_ANIM_SPEED, alpha)


func _input(event) -> void:
	if event.is_action_released("sprint"):
		transition.emit("WalkingPlayerState")
