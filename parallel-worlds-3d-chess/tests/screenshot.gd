## Dev utility: boots the scene, waits for it to settle, and writes a PNG.
## Not part of the game — used to eyeball the composition without opening the
## editor.
##
##   xvfb-run godot --path <project> --script res://tests/screenshot.gd
extends SceneTree

var main: Node
var _frames := 0
var _shots := 0


func _initialize() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 60:
		# Put a piece on the middle board so both beam directions are in shot.
		var pawn: Piece = main.game.state.get_piece(Vector3i(3, 1, 0))
		main.game.apply_move(_vertical(pawn))
		main.game.end_turn()
		main.game.end_turn()
		main._snap_all()
	elif _frames == 90:
		main._select(main.game.state.get_piece(Vector3i(3, 1, 1)))
	elif _frames == 100:
		var at: Vector2 = main.rig.camera.unproject_position(
			Vector3(BoardVisual.RIM_HALF, BoardVisual.level_height(0), 1.5))
		var e := InputEventMouseMotion.new()
		e.position = at
		main._unhandled_input(e)
	elif _frames == 130:
		_grab("user://shot_stack.png")
	elif _frames == 135:
		main._on_view_mode(0)
	elif _frames == 195:
		_grab("user://shot_level1.png")
	elif _frames == 200:
		# Move shadow, from the stack view, with a piece picked up on level 2 so
		# the projection lands on both of the other boards.
		main._on_view_mode(-1)
		main._select(main.game.state.get_piece(Vector3i(3, 1, 1)))
		main._on_shadow_toggled(true)
	elif _frames == 260:
		_grab("user://shot_shadow.png")
	elif _frames == 265:
		# And the double-click framing on its own: centred on level 1, looking
		# down, with the other two boards still in shot.
		main._on_shadow_toggled(false)
		main._deselect()
		main.rig.look_down_at(0)
	elif _frames == 330:
		_grab("user://shot_focus.png")
	elif _frames == 335:
		# The top board turned to White's side. White's top-board army is
		# mirrored, so this is the view from yaw 180 — White's pieces nearest
		# the camera even though that is the opposite end from level 1.
		main.rig.look_down_at(2)
		main.rig.face_home_side(0, 2)
	elif _frames == 410:
		_grab("user://shot_home_top.png")
	elif _frames > 415:
		quit(0)
	return false


func _grab(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("wrote %s -> %s" % [path, ProjectSettings.globalize_path(path)])
	_shots += 1


func _vertical(piece: Piece) -> Move:
	for m in main.game.get_legal_moves(piece):
		if m.kind == Move.Kind.VERTICAL:
			return m
	return null
