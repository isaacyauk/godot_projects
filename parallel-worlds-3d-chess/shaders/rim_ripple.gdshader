// The availability outline around a board that can still take a move this turn.
//
// A crisp line sitting just outside the board's edge, plus a soft lighter-green
// band that swells outward from it and fades — a slow ripple rather than a
// blink. It is drawn on one flat plane per level and shaped by distance from
// the centre, which is what lets the ripple actually travel; four thin bars
// have nowhere to travel to.
//
// Chebyshev distance (max of the axes) rather than length(), so the rings come
// out square and follow the board instead of bulging into circles.
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

uniform vec3 rim_color : source_color = vec3(0.29, 0.79, 0.31);
// The ripple crest, lighter than the line it comes from.
uniform vec3 ripple_color : source_color = vec3(0.65, 0.95, 0.66);

uniform float plane_size = 12.0;      // must match the PlaneMesh
uniform float board_half = 4.14;      // where the line sits, in world units
uniform float line_width : hint_range(0.01, 0.5) = 0.07;

uniform float ripple_reach : hint_range(0.1, 6.0) = 2.1;
uniform float ripple_speed : hint_range(0.02, 2.0) = 0.26;
uniform float ripple_width : hint_range(0.05, 2.0) = 0.5;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.34;

// 0 hides it, 1 is the resting state, above 1 is the hovered state. Driven from
// BoardVisual so it can ease between them instead of snapping.
uniform float intensity : hint_range(0.0, 3.0) = 1.0;


void fragment() {
	vec2 p = (UV - vec2(0.5)) * plane_size;
	float d = max(abs(p.x), abs(p.y));

	float line = smoothstep(line_width, 0.0, abs(d - board_half));

	// One crest in flight at a time, born at the line and fading as it goes.
	float phase = fract(TIME * ripple_speed);
	float front = board_half + phase * ripple_reach;
	float crest = smoothstep(ripple_width, 0.0, abs(d - front)) * (1.0 - phase);
	crest *= step(board_half, d);      // never wash back over the board itself

	float a = clamp(line + crest * ripple_strength, 0.0, 1.0) * intensity;
	ALBEDO = mix(rim_color, ripple_color, clamp(crest, 0.0, 1.0));
	ALPHA = a;
}
