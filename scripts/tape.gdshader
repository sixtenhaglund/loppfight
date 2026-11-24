shader_type spatial;
// Clear sticky tape: see-through, shiny, a bit yellow, with wrinkles and more visible edges.
// It uses the same movement code as the paper, so it bends and opens with the point it's stuck on.
render_mode cull_disabled, blend_mix, specular_schlick_ggx;

#include "res://scripts/paper_common.gdshaderinc"

uniform sampler2D wrinkle : filter_linear_mipmap, repeat_enable;

void vertex() {
	deform(VERTEX, NORMAL, COLOR.a, TIME, MODEL_MATRIX);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);           // 0 in the middle, 1 at the edges
	float w = texture(wrinkle, UV * vec2(2.0, 0.6)).r;
	ALBEDO = vec3(0.97, 0.95, 0.86);
	ALPHA = 0.22 + 0.3 * smoothstep(0.82, 1.0, across) + 0.12 * w;   // edges and wrinkles catch light
	ROUGHNESS = 0.08 + 0.2 * w;
	SPECULAR = 0.8;
}
