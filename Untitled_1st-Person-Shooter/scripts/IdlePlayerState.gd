class_name IdlePlayerState extends PlayerMovementState


# This function is called when this state is entered.
func enter () -> void: 
	ANIMATION.pause()


func update(delta):
	if Global.player.velocity.length() > 0.0 and Global.player.is_on_floor():
		transition.emit("WalkingPlayerState")
