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
uniform float web = 0.0;           // 1 = simple web renderer: matte paper, almost no bumps

varying vec2 extra;                // x = ambient occlusion (crevices), y = marker amount

vec3 rot3(vec3 v, vec3 ax, float a) {
	return v * cos(a) + cross(ax, v) * sin(a) + ax * dot(ax, v) * (1.0 - cos(a));
}

void vertex() {
	extra = UV2;
	// COLOR.a = how far out along the point: the base stays put, beyond the fold it curves around
	float ang = length(bend_rot);
	if (ang > 0.0001) {
		float s = smoothstep(fold_start, 1.0, clamp(COLOR.a, 0.0, 1.0));
		vec3 ax = bend_rot / ang;
		VERTEX = pivot + rot3(VERTEX - pivot, ax, ang * s);
		NORMAL = rot3(NORMAL, ax, ang * s);
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
	BACKLIGHT = col * 0.35 * ao;
#endif
}
