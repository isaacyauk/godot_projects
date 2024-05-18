extends PanelContainer

@onready var property_container = %VBoxContainer

#var property
var frames_per_second : String

# Called when the node enters the scene tree for the first time.
func _ready():
	# Set the global reference to self in Global Singleton
	Global.debug = self
	# Hide debug pannel on load
	visible = false
	#add_debug_property("FPS", frames_per_second)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if visible: 
		frames_per_second = ".%2f" % (1.0/delta) # This gets the frames per second every frame
		add_property("FPS", frames_per_second, 2)


func _input(event):
	# Toggle the debug pannel
	if event.is_action_pressed("debug"):
		visible = !visible


# Debug function to add and update property
func add_property(title : String, value, order):
	var target
	target = property_container.find_child(title, true, false) # Try to find Label node with same name
	
	if !target: # If there is no current Label node for property (i.e. inital load)
		target = Label.new() # Create new Label node 
		property_container.add_child(target) # Add new node as child to VBox container
		target.name = title # set name to title 
		target.text = target.name + ": " + str(value) # Set the text value
	elif visible:
		target.text = title + ": " + str(value) # Set the text value
		property_container.move_child(target, order)
	
