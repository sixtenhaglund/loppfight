shader_type spatial;
// Paper: printed lines + marker colour + fibres, darker on the inside of the lopp,
// light shining through thin paper (only where the renderer supports it).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fiber_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform float inside_dark = 0.6;   // how dark the inside (back side) of the paper is
// ---- a lopp point bending (floppy paper + permanent folds) ----
uniform vec3 bend_rot = vec3(0.0);   // rotation axis * angle
uniform vec3 pivot = vec3(0.0);      // the spot along the point where it bends
uniform float fold_start = 0.25;     // 0 = bends from the base, 1 = only the tip
// ---- a torn-off piece: curled and flapping in the air ----
uniform float curl = 0.0;
uniform float flutter = 0.0;
uniform vec3 piece_n = vec3(0.0, 1.0, 0.0);
uniform vec3 piece_axis = vec3(1.0, 0.0, 0.0);
uniform float phase = 0.0;
// ---- jaws + desk ----
uniform float jaw = 0.0;             // jaw opening angle for this point
uniform float hinge_z0 = -0.5;       // depth of the back fold line in the middle (the back tip)
uniform float hinge_z1 = -0.05;      // ... and out at the sides
uniform float floor_y = -1000.0;     // desk height: paper can lie on it but never go through
uniform vec4 desk = vec4(-15.0, 15.0, -8.0, 8.0);   // desk edges (x min, x max, z min, z max)
uniform float web = 0.0;           // 1 = simple web renderer: matte paper, almost no bumps

varying vec2 extra;                // x = ambient occlusion (crevices), y = marker amount

vec3 rot3(vec3 v, vec3 ax, float a) {
	return v * cos(a) + cross(ax, v) * sin(a) + ax * dot(ax, v) * (1.0 - cos(a));
}

void vertex() {
	// UV2.x = darkness + 2 * (hinge weight * 50), so unpack both
	float hw_i = floor(UV2.x / 2.0);
	extra = vec2(UV2.x - hw_i * 2.0, UV2.y);
	float hinge = hw_i / 50.0;
	// COLOR.a = how far out along the point: the base stays put, beyond the fold it curves around
	float ang = length(bend_rot);
	if (ang > 0.0001) {
		float s = smoothstep(fold_start, 1.0, clamp(COLOR.a, 0.0, 1.0));
		vec3 ax = bend_rot / ang;
		VERTEX = pivot + rot3(VERTEX - pivot, ax, ang * s);
		NORMAL = rot3(NORMAL, ax, ang * s);
	}
	// the jaws open by BENDING the paper: the middle fold stays put, paper further away turns more
	// (the fold line runs from the back tip out to the side corners, so its depth depends on x)
	if (jaw != 0.0) {
		vec3 xa = vec3(1.0, 0.0, 0.0);
		float hz = mix(hinge_z0, hinge_z1, clamp(abs(VERTEX.x), 0.0, 1.0));
		float hd = length(vec2(VERTEX.y, VERTEX.z - hz));
		float a = jaw * smoothstep(0.03, 0.45, hd);
		vec3 piv = vec3(0.0, 0.0, hz);
		VERTEX = piv + rot3(VERTEX - piv, xa, a);
		NORMAL = rot3(NORMAL, xa, a);
	}
	// torn pieces: curl like a scrap of paper, ripple while flying
	if (curl != 0.0 || flutter != 0.0) {
		vec3 bx = normalize(cross(piece_n, piece_axis));
		float a = dot(VERTEX, piece_axis);
		float b = dot(VERTEX, bx);
		float h = curl * a * a + flutter * (sin(a * 7.0 + TIME * 15.0 + phase) + 0.6 * sin(b * 5.0 + TIME * 11.0));
		float dh = 2.0 * curl * a + flutter * 7.0 * cos(a * 7.0 + TIME * 15.0 + phase);
		VERTEX += piece_n * h;
		float side = sign(dot(NORMAL, piece_n));
		NORMAL = normalize(NORMAL - piece_axis * dh * side);
	}
	// lie on the desk, never through it
	if (floor_y > -999.0) {
		vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
		if (wp.y < floor_y && wp.x > desk.x && wp.x < desk.y && wp.z > desk.z && wp.z < desk.w) {
			wp.y = floor_y;
			VERTEX = (inverse(MODEL_MATRIX) * wp).xyz;
		}
	}
}

void fragment() {
	vec3 paper = texture(paper_tex, UV).rgb;
	paper *= 0.93 + 0.07 * texture(mottle, UV * 0.7).r;
	// marker strokes: stretched noise = streaks where the pen went back and forth
	float streak = texture(mottle, UV * vec2(5.0, 0.35)).r;
	float m = clamp(extra.y * (0.78 + 0.35 * streak), 0.0, 1.0);
	vec3 col = mix(paper, paper * COLOR.rgb, m);
	float ao = extra.x;
	if (!FRONT_FACING) {
		// back side of the paper: only a little marker bleeds through
		col = mix(paper, paper * COLOR.rgb, m * 0.22);
		// inside a finger pocket: the deeper you look into the point, the less light gets there
		ao *= inside_dark * mix(1.0, 0.35, COLOR.a);
	}
	ALBEDO = col * ao;
	ROUGHNESS = mix(mix(0.93, 0.7, m), 1.0, web);
	SPECULAR = mix(0.3, 0.06, web);
	NORMAL_MAP = texture(fiber_normal, UV * 2.0).rgb;
	NORMAL_MAP_DEPTH = mix(0.5, 0.08, web);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	BACKLIGHT = col * 0.55 * ao;   // thin paper: light shines through
#endif
}
