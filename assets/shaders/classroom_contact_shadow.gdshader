shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, world_vertex_coords;

uniform vec4 shadow_color : source_color;
uniform float softness;
uniform float floor_height;

void vertex() {
	// 人物走路会上下起伏；阴影始终投在地板上。
	VERTEX.y = floor_height;
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float opacity = 1.0 - smoothstep(softness, 1.0, radius);
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * opacity;
}
