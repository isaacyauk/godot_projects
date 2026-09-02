## The fixed five-colour palette from the art doc §2, plus the tint/shade ramps
## that give each colour a small family instead of one flat value.
##
## One documented exception: the move shadow adds a sixth hue. See SHADOW_MOVE
## below for why none of the five could carry that meaning.
##
## Nothing outside this file should hard-code a colour.
class_name Palette

const OFF_BLACK := Color("2d2d2d")  ## one player's pieces
const OFF_WHITE := Color("f8f8f8")  ## the other player's pieces
const RED := Color("b40000")        ## invalid-move family
const NAVY := Color("033561")       ## environment family
const GREEN := Color("36c339")      ## valid-move family

# --- environment ---------------------------------------------------------

const SPACE_DEEP := Color("010a17")           ## zenith of the night-sky gradient
const SPACE_HORIZON := Color("042141")        ## horizon of the night-sky gradient
const STAR_TINT := Color("6fa8d8")

# --- move feedback -------------------------------------------------------

const MOVE_QUIET := Color("1f7a21")           ## GREEN darkened — a quiet legal move
const MOVE_CAPTURE := Color("36c339")         ## GREEN base — a capture is louder
const MOVE_SELECTED := Color("8fe491")        ## GREEN lightened — the picked-up piece
const MOVE_HOVER := Color("6bd76d")
const INVALID := Color("b40000")              ## RED base — rejection flash
const INVALID_SOFT := Color("d94c4c")         ## RED lightened — warnings, restricted markers

## Move shadow: the projection onto the two boards the piece is NOT on.
##
## Violet, and this is the one place the five-colour palette gets a sixth. Every
## other colour on the board already carries a meaning that would be wrong here:
## green says "you may click this", red says "you may not", blue is level 2's
## glass, and the greys are the boards themselves — a grey shadow on a grey
## board reads as a lighting artefact rather than a marker. A shadow is not a
## move state at all, so it gets a hue no move state uses. Violet also stays
## separable from green under the common forms of colour blindness, which the
## green-versus-anything alternatives do not.
##
## Still deliberately dim: a shadow must never look clickable.
const SHADOW_MOVE := Color("2f2359")          ## a destination, projected
const SHADOW_PIECE := Color("6247b0")         ## the piece itself, projected

# --- boards --------------------------------------------------------------
#
# Level 2 must be readable at a glance because its rules are wholesale
# different (art doc §3), so it is the one board made of a different material:
# a translucent glass pane with luminous edges. Levels 1 and 3 share the
# traditional checker but differ in value and finish — level 1 reads matte and
# darker, level 3 glossy and lighter — which is how the two armies' matte and
# glossy material variant is echoed by the board they start on.

# Levels 1 and 3 only — level 2 is glass and uses the GLASS_* values below.
# Its entries here are placeholders so the arrays stay indexable by level.
const BOARD_LIGHT := [Color("9c9ca4"), Color("1b5480"), Color("e6e6ea")]
const BOARD_DARK := [Color("34343c"), Color("0d3a63"), Color("6d6d7a")]
const BOARD_FRAME := [Color("1d1d24"), Color("092c4d"), Color("42424e")]
const BOARD_ROUGHNESS := [0.9, 0.5, 0.18]   ## matte L1, mid L2, glossy L3

# --- level 2, the glass pane ---------------------------------------------
#
# Alpha, not value, carries the checker here: the pane has to stay see-through
# or it stops reading as glass. The rim and edge glow are what actually define
# the board against the night sky.

# --- particles ------------------------------------------------------------

## The slow vertical lines in the column, from the valid-move green family.
const BEAM_STREAK := Color("6bd76d")
## The ambient drift running the board lattice between levels.
const LATTICE_DRIFT := Color(0.9, 0.95, 1.0)

# --- per-board availability rim -------------------------------------------

## The outline around a board that can still take a move this turn. Same green
## family as a legal destination, because it means the same thing.
const LEVEL_RIM := Color(0.29, 0.79, 0.31)
## The crest of the outward ripple — a lighter tint of the same green.
const LEVEL_RIPPLE := Color(0.65, 0.95, 0.66)
## The hover label. Deliberately quiet: it is an explanation, not an alert.
const LEVEL_HINT := Color(0.79, 0.94, 0.81)

const GLASS_LIGHT := Color(0.36, 0.62, 0.86, 0.15)
const GLASS_DARK := Color(0.09, 0.27, 0.47, 0.2)
const GLASS_EDGE := Color(0.52, 0.82, 1.0, 0.55)
const GLASS_RIM := Color(0.62, 0.87, 1.0, 0.75)


static func piece_albedo(owner_id: int) -> Color:
	return OFF_WHITE if owner_id == 0 else OFF_BLACK


## The material variant that separates a player's level-1 army from their
## level-3 army (art doc §4): army 0 matte, army 1 glossy.
static func piece_roughness(army: int) -> float:
	return 0.8 if army == 0 else 0.15


static func piece_metallic(army: int) -> float:
	return 0.0 if army == 0 else 0.45
