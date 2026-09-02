// Night-sky backdrop: a vertical blue gradient with soft procedural stars and
// a faint pale nebula. Replaces the ProceduralSkyMaterial from the first pass.
//
// Everything is a uniform so the look can be dialled in from the inspector
// (select WorldEnvironment -> Environment -> Sky -> Sky Material). Stars are
// generated from a hash rather than a texture, so there is no asset to ship and
// no visible tiling.
shader_type sky;

group_uniforms Gradient;
// Colours run bottom (brightest) to top (deepest), matching how a real night
// sky lightens toward the horizon.
uniform vec3 zenith_color : source_color = vec3(0.005, 0.039, 0.09);
uniform vec3 horizon_color : source_color = vec3(0.016, 0.129, 0.255);
// The gradient is spread over this slice of EYEDIR.y rather than the whole
// sphere. The camera looks down at the stack, so only a narrow band is ever on
// screen — stretching the ramp across the full sphere makes it read as flat.
uniform float gradient_low : hint_range(-1.0, 1.0) = -0.85;
uniform float gradient_high : hint_range(-1.0, 1.0) = 0.15;

group_uniforms Stars;
uniform vec3 star_color : source_color = vec3(0.933, 0.965, 1.0);
// Small field: many faint pinpricks.
uniform float small_density : hint_range(4.0, 140.0) = 58.0;
uniform float small_size : hint_range(0.005, 0.3) = 0.05;
uniform float small_coverage : hint_range(0.0, 0.4) = 0.14;
// Large field: fewer, brighter, softer — the ones that read first.
uniform float large_density : hint_range(2.0, 60.0) = 24.0;
uniform float large_size : hint_range(0.005, 0.4) = 0.1;
uniform float large_coverage : hint_range(0.0, 0.4) = 0.065;
uniform float star_brightness : hint_range(0.0, 3.0) = 1.0;
uniform float star_bloom : hint_range(0.0, 1.0) = 0.26;

group_uniforms Nebula;
uniform vec3 nebula_color : source_color = vec3(0.78, 0.87, 1.0);
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.14;
uniform vec3 nebula_direction = vec3(-0.6, -0.3, -0.72);
uniform float nebula_spread : hint_range(0.05, 1.5) = 0.42;


vec3 hash3(vec2 p) {
	vec3 q = vec3(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3)),
		dot(p, vec2(419.2, 371.9))
	);
	return fract(sin(q) * 43758.5453123);
}


// Projects a direction onto the face of a cube, giving a roughly uniform 2D
// grid over the whole sphere. Cheaper than spherical coordinates and, unlike
// them, it does not bunch stars up at the poles.
// Returns (u, v, face index).
vec3 cube_face(vec3 d) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) {
		return vec3(d.z / a.x, d.y / a.x, d.x > 0.0 ? 0.0 : 1.0);
	}
	if (a.y >= a.z) {
		return vec3(d.x / a.y, d.z / a.y, d.y > 0.0 ? 2.0 : 3.0);
	}
	return vec3(d.x / a.z, d.y / a.z, d.z > 0.0 ? 4.0 : 5.0);
}


// One star field. `coverage` is the fraction of grid cells that hold a star.
float star_field(vec3 dir, float density, float size, float coverage) {
	vec3 face = cube_face(dir);
	vec2 grid = face.xy * density;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float total = 0.0;

	// Sample the neighbouring cells too, so a star sitting near a cell edge is
	// not clipped in half.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec3 h = hash3(cell + offset + vec2(face.z * 41.0, face.z * 17.0));
			if (h.z > coverage) {
				continue;
			}
			vec2 centre = offset + vec2(h.x, h.y);
			float dist = length(local - centre);
			float radius = size * (0.5 + 1.1 * fract(h.z * 137.0));
			float core = smoothstep(radius, radius * 0.2, dist);
			// A wider, much fainter halo gives the soft out-of-focus look
			// rather than a hard pixel dot.
			float halo = smoothstep(radius * 3.0, 0.0, dist) * star_bloom;
			total += (core + halo) * (0.45 + 0.55 * fract(h.z * 71.0));
		}
	}
	return clamp(total, 0.0, 1.4);
}


// A soft directional patch, used for the faint pale cloud. Built from three
// overlapping lobes so it reads as irregular rather than as a circle.
float nebula(vec3 dir) {
	vec3 c = normalize(nebula_direction);
	float d = 1.0 - dot(dir, c);
	float a = exp(-d / (nebula_spread * nebula_spread));
	float b = exp(-(1.0 - dot(dir, normalize(c + vec3(0.22, 0.14, -0.1)))) / (nebula_spread * nebula_spread * 0.45));
	float e = exp(-(1.0 - dot(dir, normalize(c + vec3(-0.15, 0.2, 0.12)))) / (nebula_spread * nebula_spread * 0.3));
	return clamp(a * 0.5 + b * 0.35 + e * 0.35, 0.0, 1.0);
}


void sky() {
	vec3 dir = normalize(EYEDIR);

	// EYEDIR.y is -1 straight down, +1 straight up.
	float t = smoothstep(gradient_low, gradient_high, dir.y);
	vec3 col = mix(horizon_color, zenith_color, t);

	col += nebula_color * nebula(dir) * nebula_strength;

	float s = star_field(dir, small_density, small_size, small_coverage)
		+ star_field(dir, large_density, large_size, large_coverage) * 1.25;
	col += star_color * s * star_brightness;

	COLOR = col;
}
