shader_type spatial;
// Paper: printed lines + marker colour + your own drawing + fibres, glue shine, darker on the inside,
// light shining through thin paper (only where the renderer supports it).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://scripts/paper_common.gdshaderinc"

uniform sampler2D paper_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fiber_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_tex : source_color, hint_default_transparent, filter_linear;   // what you drew
uniform float inside_dark = 0.6;   // how dark the inside (back side) of the paper is
uniform float web = 0.0;           // 1 = simple web renderer: matte paper, almost no bumps

varying vec2 extra;                // x = ambient occlusion (crevices), y = marker amount
varying vec3 custom;               // xy = where this spot is in your drawing, z = glue

void vertex() {
	// UV2.x = darkness (+ an old packed value in steps of 2), UV2.y = marker
	extra = vec2(UV2.x - floor(UV2.x / 2.0) * 2.0, UV2.y);
	custom = CUSTOM0.xyz;
	// COLOR.a = how far out along the point
	deform(VERTEX, NORMAL, COLOR.a, TIME, MODEL_MATRIX);
}

void fragment() {
	vec3 paper = texture(paper_tex, UV).rgb;
	paper *= 0.93 + 0.07 * texture(mottle, UV * 0.7).r;
	// marker strokes: stretched noise = streaks where the pen went back and forth
	float streak = texture(mottle, UV * vec2(5.0, 0.35)).r;
	float m = clamp(extra.y * (0.78 + 0.35 * streak), 0.0, 1.0);
	vec3 col = mix(paper, paper * COLOR.rgb, m);
	vec4 drawn = texture(paint_tex, custom.xy);
	float glue = custom.z;
	float ao = extra.x;
	if (FRONT_FACING) {
		col = mix(col, paper * drawn.rgb, drawn.a * (0.85 + 0.15 * streak));   // your marker drawing
	} else {
		// back side of the paper: only a little marker bleeds through
		col = mix(paper, paper * COLOR.rgb, m * 0.22);
		col = mix(col, paper * drawn.rgb, drawn.a * 0.2);
		// inside a finger pocket: the deeper you look into the point, the less light gets there
		ao *= inside_dark * mix(1.0, 0.35, COLOR.a);
	}
	col *= mix(vec3(1.0), vec3(0.96, 0.93, 0.82), glue);   // dried glue: a little yellow
	ALBEDO = col * ao;
	ROUGHNESS = mix(mix(mix(0.93, 0.7, m), 1.0, web), 0.25, glue);   // dried glue is shiny
	SPECULAR = mix(mix(0.3, 0.06, web), 0.6, glue);
	NORMAL_MAP = texture(fiber_normal, UV * 2.0).rgb;
	NORMAL_MAP_DEPTH = mix(mix(0.5, 0.08, web), 0.15, glue);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	BACKLIGHT = col * 0.55 * ao;   // thin paper: light shines through
#endif
}
