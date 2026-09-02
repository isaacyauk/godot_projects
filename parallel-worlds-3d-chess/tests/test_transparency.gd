## Renders the faded top board from several camera angles and checks the
## checker pattern is the same every time.
##
## This exists because it was not: with move shadow on, the top board's light
## and dark squares appeared to swap as the camera orbited. Transparent surfaces
## do not write depth by default, so the 64 square boxes and the slab under them
## were blended in whatever order the renderer sorted them into — and that order
## is by distance to the camera, so it changed as you moved. One base colour
## ended up with two different results depending on whether the slab or the sky
## got drawn underneath it.
##
## Checking this by eye does not work: it needs two angles side by side and the
## difference is a few squares. So it is measured off the actual rendered
## pixels, which is the only thing that can honestly answer "does it still
## happen".
##
##   xvfb-run godot --path <project> --script res://tests/test_transparency.gd
extends SceneTree

## Yaws to sample from. The bug showed up between angles, not at any one of
## them, so one is useless — it takes a spread.
const YAWS := [0.0, 40.0, 95.0, 150.0, 215.0]
const TOP := BoardState.LEVELS - 1
## Ranks with no pieces on them at the start, so a sample hits the board rather
## than a bishop's hat.
const EMPTY_RANKS := [2, 3, 4, 5]

var main: Node3D
var _frames := 0
var _yaw_index := 0
var _samples: Array = []      ## one Dictionary per yaw: "light" and "dark" luminance arrays
var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("Faded-board transparency across camera angles\n")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		# The HUD panels sit over the board and would poison the samples.
		main.hud.visible = false
		main._on_view_mode(-1)
		main._on_shadow_toggled(true)
		ok(main.board._level_alpha[TOP] < 1.0, "the top board is faded")
		_aim(YAWS[0])
	elif _frames > 30 and (_frames - 30) % 12 == 0:
		_samples.append(_sample())
		_yaw_index += 1
		if _yaw_index < YAWS.size():
			_aim(YAWS[_yaw_index])
		else:
			_report()
			return true
	return false


## Snaps the camera to a yaw rather than easing, so each sample is taken from a
## settled view instead of somewhere along the way.
func _aim(yaw: float) -> void:
	main.rig._target_yaw = yaw
	main.rig._target_pitch = -48.0
	main.rig._target_distance = 26.0
	main.rig._target_origin = Vector3(0, BoardVisual.level_height(TOP), 0)
	main.rig._apply(1.0)


## Reads the rendered luminance at the centre of every empty square on the top
## board, split by what the checker says the square should be.
func _sample() -> Dictionary:
	var img := root.get_texture().get_image()
	var size := Vector2(img.get_width(), img.get_height())
	var light: Array = []
	var dark: Array = []
	for y in EMPTY_RANKS:
		for x in BoardState.SIZE:
			var world := BoardVisual.square_to_world(Vector3i(x, y, TOP))
			var at: Vector2 = main.rig.camera.unproject_position(world)
			if at.x < 2 or at.y < 2 or at.x >= size.x - 2 or at.y >= size.y - 2:
				continue
			var lum := _luminance(img, at)
			# The checker: (x + y) odd is the light square, same test the board
			# itself uses when it builds them.
			if (x + y) % 2 == 1:
				light.append(lum)
			else:
				dark.append(lum)
	return {"light": light, "dark": dark}


func _luminance(img: Image, at: Vector2) -> float:
	var c := img.get_pixel(int(at.x), int(at.y))
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _report() -> void:
	var all_light: Array = []
	var all_dark: Array = []
	for i in _samples.size():
		var s: Dictionary = _samples[i]
		var lo := _min_of(s["light"])
		var hi := _max_of(s["dark"])
		ok(s["light"].size() > 8 and s["dark"].size() > 8,
			"yaw %.0f: sampled %d light and %d dark squares"
				% [YAWS[i], s["light"].size(), s["dark"].size()])
		# The real assertion: at THIS angle, every light square is brighter than
		# every dark one. A square that swapped lands on the wrong side and
		# collapses the gap.
		ok(lo > hi,
			"yaw %.0f: every light square beats every dark one (%.3f vs %.3f)"
				% [YAWS[i], lo, hi])
		all_light.append_array(s["light"])
		all_dark.append_array(s["dark"])

	# And across angles: the same square must not change which side it is on.
	ok(_min_of(all_light) > _max_of(all_dark),
		"the split holds across every angle (%.3f vs %.3f)"
			% [_min_of(all_light), _max_of(all_dark)])

	# A square's own brightness should also be stable as the camera moves. Some
	# variation is honest — the key light is directional — but a square that
	# flips changes by a lot, so the spread is capped well under the light/dark
	# gap itself.
	var gap: float = _min_of(all_light) - _max_of(all_dark)
	var worst := 0.0
	for i in _samples[0]["light"].size():
		var vals: Array = []
		for s in _samples:
			if i < s["light"].size():
				vals.append(s["light"][i])
		worst = maxf(worst, _max_of(vals) - _min_of(vals))
	ok(worst < gap,
		"a square's brightness stays stable as the camera orbits (drift %.3f, gap %.3f)"
			% [worst, gap])

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _min_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var m: float = values[0]
	for v in values:
		m = minf(m, v)
	return m


func _max_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var m: float = values[0]
	for v in values:
		m = maxf(m, v)
	return m
