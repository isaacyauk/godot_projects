extends RayCast3D

@onready var prompt = $Prompt


func _ready():
	add_exception(owner)


func _physics_process(_delta):
	prompt.text = " "
	if is_colliding():
		var collider = get_collider()
		prompt.text = "Colliding with: " + str(collider.name)
		
		if collider is Interactable:
			prompt.text = "detecting " + collider.prompt_message

