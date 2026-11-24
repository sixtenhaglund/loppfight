shader_type spatial;
// Paper: printed lines + marker colour + fibres, darker on the inside of the lopp,
// light shining through thin paper (only where the renderer supports it).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fiber_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform float inside_dark = 0.6;   // how dark the inside (back side) of the paper is
uniform float web = 0.0;           // 1 = simple web renderer: matte paper, almost no bumps

varying vec2 extra;                // x = ambient occlusion (crevices), y = marker amount

void vertex() {
	extra = UV2;
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
