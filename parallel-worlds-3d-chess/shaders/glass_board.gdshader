// Level 2's squares. The middle board is the one with wholesale different
// rules, so it is the one board made of a different material rather than a
// different colour: a translucent pane with luminous edges. You can see the
// stars and the board below through it, which is also what "any piece can pass
// through this level" means mechanically.
//
// Unshaded on purpose — a glass plate should not pick up the key light like the
// solid boards do.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

// Faint checker fill. Alpha is what carries the light/dark difference here,
// not value, so the plate stays readable as glass.
uniform vec4 fill_color : source_color = vec4(0.10, 0.28, 0.48, 0.16);
// The glowing rim around each square. Alpha above 1.0 in the glow multiplier
// is deliberate: it pushes the edges into the bloom pass.
uniform vec4 edge_color : source_color = vec4(0.52, 0.82, 1.0, 0.6);
uniform float edge_width : hint_range(0.0, 0.5) = 0.07;
uniform float edge_glow : hint_range(0.0, 4.0) = 1.9;
uniform float shimmer_speed : hint_range(0.0, 4.0) = 0.9;
uniform float shimmer_depth : hint_range(0.0, 0.5) = 0.14;

// Set by BoardVisual when this square is a legal destination or the selected
// square. amount 0 means "not highlighted" and the glass shows through.
uniform vec4 highlight_color : source_color = vec4(0.0);
uniform float highlight_amount : hint_range(0.0, 1.0) = 0.0;


void fragment() {
	// Distance to the nearest edge of the quad, in UV space.
	vec2 d = min(UV, vec2(1.0) - UV);
	float edge = 1.0 - smoothstep(0.0, edge_width, min(d.x, d.y));

	// Offset the shimmer by world position so the grid breathes unevenly
	// instead of pulsing as one flat sheet.
	float phase = NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.z;
	float pulse = 1.0 - shimmer_depth + shimmer_depth * sin(TIME * shimmer_speed + phase);

	vec3 col = mix(fill_color.rgb, edge_color.rgb * edge_glow, edge);
	float alpha = mix(fill_color.a, edge_color.a, edge);

	col = mix(col, highlight_color.rgb, highlight_amount);
	alpha = mix(alpha, max(alpha, highlight_color.a), highlight_amount);

	ALBEDO = col * pulse;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
