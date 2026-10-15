shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D atlas_texture : source_color, filter_linear;
uniform float region_top;
uniform float region_height;
uniform float fade_top = 0.0;
uniform float fade_bottom = 0.0;

void fragment() {
	vec4 color = texture(atlas_texture, UV);
	float y = (UV.y - region_top) / region_height;
	float coverage = 1.0;
	if (fade_top > 0.0) {
		coverage *= smoothstep(0.0, fade_top, y);
	}
	if (fade_bottom > 0.0) {
		coverage *= smoothstep(0.0, fade_bottom, 1.0 - y);
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * coverage;
}
