# Parallel Worlds Chess — v1

Godot 4.7 / GDScript. Local pass-and-play implementation of the ruleset in
`parallel_worlds_chess_design_doc.html`, with the placeholder art stage from
`parallel_worlds_chess_art_animation_doc.html`.

## Running

Open the project in Godot 4.7 and press F5. Or from a terminal:

```
godot --path .                                     # play
godot --headless --path . --script res://tests/test_rules.gd   # rules engine tests
godot --headless --path . --script res://tests/test_scene.gd   # scene integration test
godot --headless --path . --script res://tests/test_models.gd  # did the piece models load?
```

Two more need a real framebuffer, because they check rendered pixels. Under
`xvfb-run` on a headless box, or just run them windowed:

```
xvfb-run godot --path . --script res://tests/test_transparency.gd  # faded-board sorting
xvfb-run godot --path . --script res://tests/screenshot.gd         # writes PNGs to user://
```

All suites currently pass (91 rules + 82 scene + 40 menu + 30 AI + 13 transparency).

## Controls

| Input | Does |
| --- | --- |
| Left click | Select a piece / move to a highlighted square |
| Left double-click a board | Centre on it, look down, and turn to your side of it |
| Left drag | Pan the view |
| Right or middle drag | Orbit the camera |
| Scroll | Zoom |
| View Boards button (click the active one) | Recentre on the stack |
| F11 | Toggle fullscreen |
| Esc | Deselect |
| View Boards: All / Top / Mid / Bottom | Full stack or focused single-board view |
| Move shadow | Project the selected piece and its moves onto the other two boards |
| Undo move | Rewind the most recent move of the current, uncommitted turn |
| End turn | Commit early with fewer than the allowed moves |

## Layout

```
scripts/
  piece.gd          Piece data Resource — no scene-tree knowledge
  move.gd           One candidate move (kind, capture, castle, promotion flags)
  board_state.gd    Three 8x8 boards, live pieces, setup, JSON serialisation
  board_rules.gd    Move generation. Pure static functions, fully headless
  game_state.gd     Turn tracking, commit, win check, single-move undo
  palette.gd        The fixed five-colour palette and its tint ramps
  board_visual.gd   Three board planes, square materials, highlights, view modes
  piece_visual.gd   Piece nodes: model or primitive, army materials, markers
  piece_models.gd   Loads and normalises models from assets/pieces/
  vertical_beam.gd  The mote column that marks a vertical move
  lattice_drift.gd  Ambient motes drifting the board grid between levels
  camera_rig.gd     Orbit camera
  hud.gd            All in-game 2D UI, built in code
  main.gd           Game scene root: input, animation, pass-and-play loop
  ai_player.gd      The computer opponent and its difficulty table
  app.gd            `App` autoload: settings, the feature table, scene flow
  menu.gd           The main menu, built in code
  menu_backdrop.gd  The menu's slowly orbiting camera
shaders/
  night_sky.gdshader   Backdrop: blue gradient, procedural stars, faint nebula
  glass_board.gdshader Level 2's translucent pane and its luminous grid
  rim_ripple.gdshader  The availability outline and its outward ripple
scenes/menu.tscn    The main menu: same sky, same boards, no pieces
scenes/main.tscn    Environment, lights, board, camera rig, HUD
tests/              Headless test scripts + a screenshot utility
```

## The backdrop

`shaders/night_sky.gdshader` draws the whole sky — no texture, no asset to
ship. Every value is a uniform, so the look is tuned in the inspector under
**WorldEnvironment → Environment → Sky → Sky Material**, grouped as Gradient,
Stars and Nebula. The ones worth reaching for first:

- `gradient_low` / `gradient_high` set the slice of the view the gradient ramp
  is spread across. They are deliberately narrow: the camera looks down at the
  stack and only ever sees a band of sky, so a ramp stretched over the full
  sphere reads as flat.
- `small_*` and `large_*` are two independent star fields — many faint pinpricks
  plus fewer, larger, softer ones. `coverage` is the fraction of grid cells that
  hold a star; `star_bloom` is how much soft halo each gets.
- `nebula_direction` points at the faint pale patch. `-Z` is where the camera
  looks from its default angle.

Stars are placed by hashing a cube-face grid rather than spherical coordinates,
which keeps them evenly spread instead of bunching at the poles.

The rules engine (`piece`, `move`, `board_state`, `board_rules`, `game_state`)
has no dependency on the scene tree, rendering or input, per the design doc's
KISS framing. `tests/test_rules.gd` exercises it with plain function calls.

## Coordinates

`Vector3i(x, y, z)` — x = file 0-7, y = rank 0-7, z = level 0/1/2 for boards
1/2/3. **The middle board is `z == 1`.** The design doc's §6 pseudocode says
`piece.position.z == 2` for level 2, which is an off-by-one against its own
0-indexing note; `BoardState.MIDDLE_LEVEL` is the single source of truth here.

## Interpretations worth knowing

These are places the source docs were silent or slightly self-contradictory.
Each is a small, isolated change if you want it decided differently.

**Pawn direction is a per-piece property.** The docs resolve that the level-1
and level-3 armies are mirrored, *and* that a pawn returning from level 2
"keeps its normal forward direction (white advances toward rank 8)". Those two
can't both be literally true once a pawn changes level. Implemented: each piece
gets a `forward` at setup from `(owner_id, army)` and keeps it forever, so a
mirrored level-3 White pawn advances toward rank 0 wherever it goes. See
`Piece.forward_for()`.

**Double-step eligibility is rank-based, not `has_moved`-based.** The level-2
transition rule says a pawn dropped on its first rank "moves normally" again
once it reaches the second rank — which includes regaining the two-step option.
Gating on `has_moved` would permanently deny it. See `BoardRules._pawn_moves()`.

**En passant lasts exactly one opponent turn.** Standard chess says "capture
immediately", but a turn here holds up to three moves. Targets created during
your turn go live when it ends and expire when the opponent's turn ends, so
they are usable by any of the opponent's up-to-three moves. See
`BoardState.pending_en_passant`.

**Castling has no check restrictions.** There is no check concept in this
variant, so the only conditions are: king and rook unmoved, on their home
squares, path clear. Works identically on the mirrored level-3 army.

**Turns auto-end at the move cap**, per the design doc. That means the third
move of a turn cannot be undone. If you would rather keep undo available until
the player confirms the handoff, stop `main.gd::_after_animation()` from
calling `_finish_turn()` and let the End turn button do it.

**Board identity is carried by material, not just colour.** The art doc
suggests tinting boards 1 and 3 to echo "the army that starts there", but both
players have an army on both outer boards. Implemented instead as a material
echo: level 1 is matte and darker, level 3 is glossy and lighter, matching the
matte/glossy variant that separates a player's two armies.

Level 2 went further. Against a navy sky a navy board disappears, and spending
a sixth colour on it would break the fixed five-colour palette — so the board
whose rules are wholesale different is the one board made of a different
material: a translucent pane with a luminous grid, stars and the board below
visible through it. It separates instantly at any brightness, and "pieces pass
through this level" is what the middle board actually means.

**Board spacing and camera framing** (`BoardVisual.LEVEL_GAP`,
`CameraRig.pitch/distance`) are the look-at-it-and-adjust numbers the art doc
called out. Current values keep all three boards readable at once; a steeper
angle reads level 3 better but occludes level 1's far ranks.

**World scale lives in exactly one number**: `BoardVisual.SQUARE`, the edge
length of one square, currently `1.15`. Every other geometric constant in the
project is written as a multiple of it — plate thickness, level gap, the frame
slab, the glass rim bars, the rim colliders, `square_to_world()`, the beam and
lattice particle sizes and speeds, and the camera's pan limits. Piece heights in
`PieceModels.TARGET_HEIGHT` are fractions of a square and are converted by
`PieceModels.target_height()`, so pieces keep their proportion to the tile they
stand on automatically.

So "make the board 15% bigger" is one edit: raise `SQUARE`. Nothing else needs
touching, and nothing drifts out of alignment — importantly, the lattice drift
points must stay on the real grid, which is why `LatticeDrift._lattice_points()`
multiplies through by `SQUARE` rather than using bare integers.

Do **not** do this by moving the camera closer. Camera distance changes apparent
size but not the actual world, so anything that reasons in world units — pick
ray lengths, pan limits, particle extents, the visibility AABBs — silently stops
matching what is on screen. The two knobs are independent on purpose:
`CameraRig.distance` frames the stack, `BoardVisual.SQUARE` sizes it.

To change the piece-to-square ratio *without* resizing the board, edit
`PieceModels.TARGET_HEIGHT` alone — those are the only numbers that express a
piece's size relative to its tile.

## Window

The game opens **maximized** (`display/window/size/mode=2`), with 1600x900 as the
size it falls back to when un-maximized. F11 toggles borderless fullscreen and
back; that is bound in `main.gd::_toggle_fullscreen()` rather than the input map,
and deliberately not on Esc, which deselects.

Stretch is set to **`disabled`**, not `canvas_items`. The HUD is built entirely
from anchored Controls, so at native pixel size it re-anchors to any window and
every extra pixel goes to the board. Under `canvas_items` the panels would scale
with the window and balloon on a large monitor, eating the view they are meant to
sit beside. Worth revisiting for the mobile target in §8, where scaling the UI up
is usually what you want.

The camera keeps vertical framing as the window widens (`Camera3D.keep_aspect`
defaults to KEEP_HEIGHT), so a wider window shows more space either side of the
stack rather than a smaller board.

## Renderer

The project is pinned to **Compatibility (GLES3)**, not Forward+, in
`project.godot`. Changing it needs an editor restart.

Forward+ renders every lit surface pure black on the dev machine (Intel Iris Xe
on Mesa): the sky, the glass board and the HUD draw correctly because they are
unshaded, but the boards and pieces receive no light at all. That is undiagnosed
— it is a workaround, not a fix, and worth revisiting if you have other hardware
to test on.

Two reasons it is a reasonable default anyway: everything visual in this project
was tuned against Compatibility, so what you see matches the screenshots; and
Compatibility is the renderer for the mobile target in the design doc's §8, so
the project would likely have ended up here regardless.

## Lighting

Two directional lights plus a fixed ambient colour. Three things are load-bearing:

- **The lights are aimed by computed transforms, not hand-typed ones.** A
  `DirectionalLight3D` shines along its local −Z, so a basis typed by eye is
  very easy to get inverted — and an inverted key light looks fine under the
  Compatibility renderer (ambient carries the scene) while rendering pure black
  under Forward+. If you edit a light, drag it in the editor or set
  `rotation_degrees`; don't hand-write the matrix.
- **Ambient is `AMBIENT_SOURCE_COLOR`, not the sky.** The sky is now very dark,
  so sky-derived ambient is nearly zero, and the two renderers disagree about
  how much light it yields. A fixed colour is predictable.
- **Boards do not cast shadows** (`cast_shadow = OFF` on the plates, frames and
  glass rim). The key light comes from above, so casting boards drop level 1
  into the shade of the two above it. Pieces still cast, which is what grounds
  them on their squares.

## Mouse handling

The left button does double duty — click to select, drag to pan — so nothing is
decided until the button comes back up. `main.gd::_handle_left_drag()` owns the
whole gesture: it swallows the press, and if the cursor travels past
`DRAG_THRESHOLD` (6 px) the motion becomes a `CameraRig.pan()` and the release
produces no click. Under the threshold, the release runs the normal click
against the **press** position, so a click that wobbles a pixel or two still
lands where it was aimed.

Two consequences worth knowing before changing this. Selection now happens on
release rather than press. And panning is deliberately handled ahead of the
`_animating` guard, so the view stays draggable while a move is playing —
looking around is never "busy". Panning is clamped near the stack so the board
cannot be lost off-screen; clicking the active View Boards button recentres.

**Double-click** is layered on top of the same gesture. The second press arrives
flagged `double_click`, and `_handle_left_drag()` takes it as a camera gesture:
it centres on whatever board was under the cursor and looks down at it. That
press sets `_swallow_release`, because otherwise the release closing the
double-click falls straight through to `_on_click()` on the same square — and on
a legal destination that plays the move a second time. The first click of the
pair still does its ordinary job; only the second one is a camera move, so
double-clicking can never cost you a move you did not mean to make.

The gesture calls `CameraRig.look_down_at()`, **not** `set_view_mode()`. The
View Boards buttons hide the other two levels; this deliberately does not.
Double-clicking the bottom board is how you ask what is directly above it, and
hiding the answer would defeat the question.

On the top and bottom boards it then calls `CameraRig.face_home_side()`, which
turns the camera so the player's own pieces are nearest and the opponent's face
them across the board.

**Which side that is depends on the board, not only on the colour.** The two
armies are mirrored (`Piece.forward_for`), so White starts at low ranks on the
bottom board and at HIGH ranks on the top one. `home_yaw()` therefore derives
the angle from the army's own forward direction rather than from `owner_id`.
Hardcoding "White views from yaw 0" seats White behind Black's pieces on the top
board — backwards, on exactly the board the mirroring exists to make
interesting. `test_rules.gd::test_home_side_orientation()` pins this against
where the pieces actually start rather than against a table of expected angles,
because a table of expected angles is just the implementation written twice.

The middle board starts empty and belongs to neither player, so it is centred
without turning; `home_yaw()` returns -1 for it.

Two smaller things the implementation has to get right. Yaw accumulates without
bound as you drag, so the same view can be 0, 360 or -1080 — `_shortest_way_to()`
picks the equivalent nearest the current angle, or a player who has orbited a few
times watches the camera unwind all of it. And whose side to turn to is
`main.gd::_view_owner()`: against the computer it is always the human, whichever
seat they took, since turning to the computer's side would be useless; in
pass-and-play it is whoever is to move, because the device changes hands.

## Move shadow

A toggle beside the View Boards buttons. While it is on, the selected piece and every
square it can reach **on its own board** are painted onto the two boards it is
not standing on, at the same file and rank, and the top board fades to
`SHADOW_BOARD_ALPHA` so you can see the projection through it.

This exists because lining up a square on level 1 with the same square on level 3
by eye is genuinely hard, and it is the question the geometry raises constantly:
if this rook were one level up, what would it be attacking?

Three decisions worth keeping:

- **Only flat moves are projected.** A vertical move's destination is already a
  real, lit square on the target board; shadowing it too would say the same thing
  twice in two colours. Where a projection and a real highlight do collide, the
  real one wins — `_draw_shadow()` runs first for exactly that reason.
- **The shadow is violet, not green**, and this is the one place the five-colour
  palette gets a sixth hue. Every other colour already means something that
  would be wrong here: green says "you may click this", red says "you may not",
  blue is level 2's glass, and the greys are the boards themselves — a grey
  shadow on a grey board reads as a lighting artefact, not a marker. A shadow is
  not a move state, so it gets a hue no move state uses. It also stays separable
  from green under the common forms of colour blindness, which a second green
  would not. The values stay dim on top of that: nothing here is clickable.
- **The fade goes through `BoardVisual._set_albedo()`, not
  `GeometryInstance3D.transparency`.** That property is unsupported by the
  Compatibility renderer this project is pinned to, and it fails invisibly —
  the same class of bug that already cost this project a day. Every write to a
  solid square's albedo routes through `_set_albedo()` so the level's opacity
  survives highlights, resets and invalid flashes alike.

### Why the faded board writes depth

A transparent surface does not write depth by default, so Godot draws the
transparent queue back-to-front **by distance to the camera**. With 64 square
boxes sitting on a slab, that order changes as you orbit — and a square blended
over the slab is a different colour from the same square blended over the sky.
The visible symptom was the top board's checker appearing to flip as the camera
moved.

Two things hold it steady, and both are needed:

- `depth_draw_mode = DEPTH_DRAW_ALWAYS` on a faded square, so it occludes what
  is behind it and the order between squares stops mattering.
- `render_priority = -1` on the frame slab, so it is always drawn before the
  squares that sit on it. Depth writing alone still leaves those two competing.
  It is harmless while the board is opaque — opaque geometry ignores
  `render_priority`.

`tests/test_transparency.gd` guards this, and it has to measure rendered pixels
to do so: it orbits to five yaws, samples the luminance at the centre of every
empty square on the top board, and asserts every light square outreads every
dark one at every angle. Reverting either fix fails it 7 ways, with individual
squares drifting 0.36 in luminance as the camera turns. Checking this by eye
does not work — it needs two angles side by side and the difference is a few
squares.

Pieces on the top board are **not** faded, only the plate. If the stack still
reads as cluttered from above, fading them too is a small change in
`main.gd::_on_shadow_toggled()` — but it was not asked for, and the plate alone
already opens the view down the stack.

## Piece models

`assets/pieces/` is empty, so the game runs on the primitive stand-ins built in
`piece_visual.gd`. Drop model files in that folder and they are used instead —
no code changes. **`assets/pieces/README.md` has the full instructions**,
including how to add the CC0 LowPoly Chess Set the project is aimed at.

`piece_models.gd` is forgiving on purpose, since packs disagree about naming,
units and up-axis. It matches any of a piece's aliases anywhere in a filename,
accepts either a file per piece or one combined scene, measures each model and
rescales it to a fixed target height, lays Z-up exports upright, and falls back
per type so a partial set still runs. Materials are always overridden from
`Palette`, because piece colour carries the player and the army here and a
pack's own black/white materials would lose the army distinction.

**`PieceModels.TARGET_HEIGHT` is the size dial.** Every model is rescaled to the
height listed there, so the pack's own units are irrelevant and pieces from
different sources end up consistent. Squares are 1.0 across; the king is 1.48
tall with a 0.70 footprint, which fills the square without crowding its
neighbours. The primitive fallbacks are modelled at roughly the pre-scale
heights and get multiplied by `PieceVisual.PRIMITIVE_SCALE` to match — change one
and change the other, or the fallback set will look wrong beside a real one.
Pick colliders and the restricted-pawn halo both derive from `TARGET_HEIGHT`, so
they follow automatically.

**The alias list matters more than it looks.** A pack that names a file something
unexpected fails silently — that type just stays a primitive, with no error. The
Complete Chess Set ships `Bisop.fbx` (a typo of its own) and `Horse.fbx`, which
is why `TYPE_ALIASES` carries spellings rather than one canonical word per piece.

## Availability indicators

Two of them, showing the same thing: which levels a move could still END on this
turn. The HUD carries `Moves open on 1 2 3` in the top-left; each board wears a
green outline that ripples gently outward while it will still take a move.

**They read from `GameState.available_destination_levels()`, not from
`levels_ended_on`.** That distinction is the whole point: a level nobody can
reach is not available either, which is normally true of the empty middle board
early on. Driving the indicators off "levels not yet spent" made them advertise
moves that did not exist.

The outline is one flat plane per level running `rim_ripple.gdshader` — a crisp
line just outside the board plus a lighter crest that swells outward from it and
fades. It needs a plane because a ripple needs somewhere to travel; four thin
bars have nowhere to go. Distance is Chebyshev (`max` of the axes) so the rings
come out square and follow the board instead of bulging into circles. Turn
`ripple_strength` down if it pulls too much attention.

`BoardVisual::_process()` → `_animate_rims()` only eases one number per level
between hidden, resting and hovered; the ripple itself runs on `TIME` in the
shader. That `_process` existing is load-bearing — it had been deleted once when
the glass shader took over level 2's shimmer, and the rims silently stopped
animating.

**Picking is deliberately two-pass.** `main.gd::_pick()` queries squares (layer
1) and pieces (layer 2) first, and only consults the rim layer (4) when that
comes back empty. The rim colliders are intentionally fat — a thin hover target
is a bad hover target — and a single combined query let one sit in front of a
legal destination square and swallow the click. A rim must never take a click
away from the board; a test asserts exactly that against four edge squares.

Hovering a rim holds it brighter and shows a small bordered tooltip at the
cursor. It is a HUD element rather than a `Label3D` so it stays crisp, sits on
top, and carries a background plate — unbacked text over stars and glass is
unreadable. Clicking a rim does nothing at all: it is an indicator, not a
control, and must not discard a selection.

## Particles

Two systems, both deliberately near the edge of perception. They read far more
strongly in motion than in a screenshot, so judge them in play before tuning.

**`vertical_beam.gd` — the vertical-move column.** A destination highlight on
another board is easy to miss, so the selected piece gets a column on its own
square for each direction it can travel, and the same column trails the piece
during the move itself (the vertical-move polish the art doc asks for in §5).

Slow green vertical streaks, and nothing else. They use `BILLBOARD_FIXED_Y` so a
tall quad stays upright while turning to face the camera, which is what makes
them read as lines from any angle. An earlier version put a dense haze of tiny
pale motes underneath for body; it read as noise rather than as a beam, so the
lines carry it alone.

There are two beam nodes, `beam_up` and `beam_down`, because a piece standing on
level 2 can go both ways at once and a single shared column would have to pick a
winner. `main.gd::_update_beam()` walks the piece's legal moves and lights one
column per available direction; boundary levels naturally get only one, since
nothing rises off level 3 or drops out of level 1.

`show_at()` is idempotent, and that is load-bearing rather than tidiness.
Re-seeding a `GPUParticles3D` restarts its whole loop, which reads as a visible
stutter; the beam is refreshed from `_redraw_highlights()`, which runs every time
the hover square changes, so asking for a column that is already running has to
cost nothing. `_update_beam()` works out the wanted state and applies it, instead
of hiding both columns and rebuilding — the hide-then-immediately-show pattern
was exactly what made the beam churn under the cursor. A test asserts the
re-seed counter stays flat across a sweep of hover events.

Louder or quieter: `MOTE_AMOUNT` / `STREAK_AMOUNT` and the peak alpha passed to
`_ramp()` in each process material.

**`lattice_drift.gd` — the ambient connection between boards.** Every particle
spawns on a lattice point of level 1 or level 3 (a square corner or an edge
midpoint, 225 of them per board) and drifts slowly toward the middle board, so
the three levels quietly read as one structure with the same grid running
through them. Godot's `EMISSION_SHAPE_POINTS` does the snapping: hand it a
texture of positions and every spawn lands on one of them.

Tuned to stay out of the way — `AMOUNT` is 10 in flight at once across 225
possible columns, at `SPEED` 0.75 units/second, which works out to roughly one
drifting past a second, each barely above the background. Raising `AMOUNT` much
past this starts to feel like weather. It switches off entirely in the focused
single-level view, where it has nothing to say.

## The main menu

`scenes/menu.tscn` is the boot scene. It stands in the game's own world — the
same sky shader, the same lights and a real `BoardVisual` with no pieces on it,
on a slow orbit — rather than in front of a picture of one, so the menu can
never show a board the game no longer builds.

### What it is built on

The whole thing is a centred column: title, five choices, Quit. It is deliberately
the shape every game main menu has (Jakob's law) rather than the two-pane app
layout it started as. `menu.gd`'s header comment maps every non-obvious decision
to the rule it came from; the short version:

	Mandel 1, control      Escape is always one step back, there is a real back
						   stack, and nothing destructive happens without asking.
	Mandel 2, memory       The Play screen ends with a sentence describing the
						   game you are about to start, so nothing has to be
						   carried from one screen to another.
	Mandel 3, consistency  One row idiom, one primary-button idiom, one "not
						   built yet" idiom — the same on all seven screens.
	Shneiderman 2          The menu is fully keyboard-operable, and the
						   accelerators are printed next to what they trigger.
	Shneiderman 3          Feedback lands at the control that caused it — "Saved"
						   beside the row, not only in a corner.
	Shneiderman 4          Play is a beginning, a middle, and an end.
	Shneiderman 5, 6       Quit and Reset confirm; Settings can undo its last
						   change specifically, not only reset everything.
	Fitts                  Primary action is the biggest target; rows are
						   full-width so only vertical travel costs anything;
						   the difficulty slider has two large steppers because
						   a slider handle is a poor target.
	Hick                   Five choices on the title screen. Difficulty controls
						   do not appear until you choose to play the computer.
	Von Restorff           Exactly one filled, coloured button per screen.
	Tesler                 The opponent's complexity is absorbed by a sane
						   default and one sentence of plain English.

Two of these pull against each other and the conflict is resolved rather than
split. Serial position says the last item in a list is memorable and easy to
hit, which is a bad property for something irreversible; Jakob says Quit belongs
at the bottom because that is where people look. Jakob wins — but Quit is
printed quietly, at a third the height of the primary, separated by a rule, and
it asks first.

### Honesty

Every entry the menu offers is declared once in `App.FEATURES` as `BUILT`,
`PARTIAL` or `PLANNED` with a plain-language note, and the menu renders itself
from that table. A feature graduating is one line there plus the code that makes
it true; without that the menu becomes a second, quietly drifting claim about
what the game does.

Unbuilt features are shown and marked, not hidden — but they moved off the front
page, because a title screen is a decision and a decision with fifteen answers
is a worse one. They live under **More** and in the "not built yet" group of
Settings: dimmed, chipped `SOON` or `PARTIAL`, and still pressable, because a
disabled control that swallows the click is the one interaction in an interface
with no feedback attached at all. Pressing one says what is missing and which
doc section it comes from. Colour follows the art doc rather than inventing a
new language: the red family marks what you cannot reach, the pale green hint
colour marks what half works, and the valid-move green is the accent on the one
primary action per screen.

### Settings

They live in `user://settings.cfg` and are deliberately few, because only these
are actually read:

	fullscreen             the same two modes F11 toggles in game
	ui_scale               the menu's own text size; the HUD has its own sizes
	default_view           opening camera view, applied through the HUD's buttons
	move_shadow_default    ditto for the move-shadow toggle
	undo_after_final_move  holds the turn open at the move cap — see below
	player_one/two         names shown in the turn indicator and pass screen
	opponent               "human" or "computer"
	ai_difficulty, ai_seat how hard it plays, and which side it plays

Game setup (opponent, difficulty, sides, names) lives on the Play screen;
preferences live in Settings. Nothing appears in both places — one setting with
two homes is the same drift problem in miniature.

A stored value whose type does not match its default is ignored on load, so a
hand-edited or stale settings file cannot boot the game into a state the rest of
the code does not expect, and a blank name falls back rather than rendering an
empty label (Postel's law, both times). `undo_after_final_move` is the switch for
interpretation 4 below: off, the turn auto-ends at the cap and takes undo with
it; on, `_after_animation()` leaves the turn open and `End turn` closes it.

### Tests

**A test entry script must not name a class whose script touches the `App`
autoload.** A script passed to `godot --script` is compiled before the autoload
list is registered, so `App` does not resolve there — and naming a class pulls
that class's script into the same too-early compile. `tests/test_menu.gd` had
`var menu: MainMenu`, which dragged in `menu.gd`, which calls
`App.get_setting()`; the file failed to compile, the Menu node loaded as a bare
`CanvasLayer` with no script, and the suite ran **zero** assertions while still
exiting 0. It now holds the menu as an untyped `Node` and reaches the autoload
as `root.get_node("App")` from inside `_process()`, where the tree is live.

That costs static checking on those references and buys back forty assertions.
Scripts loaded later — `main.gd`, `menu.gd` themselves — compile after
registration and can keep using `App` normally; only the entry script is
affected. `tests/test_scene.gd` reads `VIEW_CHOICES` off the HUD instance for
the same reason.

`tests/test_menu.gd` asserts the feature table stays well-formed and settings
survive a round trip through disk — and then asserts the interaction design,
because that is the part that rots without anyone noticing. A back stack quietly
stops covering a new screen; a confirm gets dropped from a destructive action in
a refactor; a screen is added and nothing ever gives it keyboard focus. None of
that crashes and none of it shows up in a screenshot, so the rules are asserted:
one screen visible at a time, every screen naming a focusable control to land
on, Quit confirming with the safe answer holding focus, back landing exactly one
level up, the title screen never growing past five choices, and undo restoring
the previous value without a no-op change eating it.

## The computer opponent

`ai_player.gd`. It clones the `GameState`, searches on the clone through the
same `get_legal_moves()` / `apply_move()` a click goes through, and carries no
second copy of the rules — so it cannot drift from them. The price is that
every search node costs a `to_dict()` / `load_dict()` round trip, which is what
the node and time budgets are sized around.

The unit of planning is a whole turn, not a move: three moves, one per piece,
no two ending on the same level. Full enumeration is hopeless — with the glass
board open a side can have 200+ legal moves, so three moves is eight million
sequences. Instead it opens one branch per candidate first move and fills each
one in with a narrowing beam, then re-ranks the finished branches by what you
could do about them.

That last step is where the strength is. There is no check in this variant and
capturing either king wins on the spot, so "don't leave a king takeable" is not
something move generation enforces — it is something a player has to see. The
reply search is what sees it, and switching it off is most of what makes the
low difficulties beatable.

    difficulty      1    2    3    4    5    6    7    8    9   10
    first moves     1    2    3    4    5    6    7    8    9   10
    moves planned   1    1    2    2    3    3    3    3    3    3
    replies checked 0    0    1    1    2    2    3    3    3    3
    random move   60%  42%  28%  18%  11%   6%   3%   1%    -    -

Levels 1 and 2 count material and nothing else, and never look at your reply —
they will take a free bishop that costs them a king, which is exactly what a
beginner does. From level 5 up every branch it generates gets the reply check;
at 3 and 4 only its favourite two or three do, and a branch it never checked is
never played rather than being ranked on the fantasy that you do nothing back.
Above level 3 a blunder roll is not allowed to throw away a move that wins the
game; at 1 through 3 it can, and does.

The slider in the menu prints `AiPlayer.describe()` under itself, which names
what that notch changes in words. A difficulty dial whose only feedback is its
own number is indistinguishable from one wired to nothing.

Everything above is in one table, `AiPlayer.TABLE`, and `tests/test_ai.gd`
asserts it is monotonic in every column and that no two adjacent levels search
identically. The same suite plays a position where a free bishop costs a king
and checks that the levels without a reply search take it and the levels with
one decline — if the slider were not wired to the search, that test fails.

Against the computer there is no pass screen: nothing changes hands, so the
board stays up and a "Computer is thinking" line appears instead. The search is
well under its budget on the opening position; the pauses between its moves are
for legibility, since three moves landing at once is impossible to follow.

## Not built yet

Mobile input, async remote play and the Supabase backend, and the final art
pass. `GameState.to_dict()` / `load_dict()` already round-trip the whole game
through JSON, which is the payload an async turn submission would send.
