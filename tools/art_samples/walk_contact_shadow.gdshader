shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float strength = 0.19;

void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	ALBEDO = vec3(0.34, 0.30, 0.23);
	ALPHA = (1.0 - smoothstep(0.0, 1.0, radius)) * strength;
}
