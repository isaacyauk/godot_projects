extends RayCast3D

@onready var prompt = $Prompt
@onready var rc_interact = $"."


func _physics_process(delta):
	prompt.text = " "
	if rc_interact.is_colliding():
		var detected = get_collider() # get the collider of the object that is overlapping with the raycast
		
		# if it is of the class "Interactable"
		if detected is Interactable:
			prompt.text = detected.get_prompt()
			
			if Input.is_action_just_pressed(detected.prompt_action):
				detected.interact(owner)
