shader_type canvas_item;
render_mode unshaded;

// Purely decorative deterministic grain. No gameplay RNG and no texture download.
void fragment() {
	vec2 p = floor(UV * vec2(1640.0, 940.0));
	float grain = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
	float fibre = sin(p.x * 0.63 + sin(p.y * 0.13)) * 0.5 + 0.5;
	COLOR = vec4(vec3(0.42, 0.32, 0.17), grain * 0.045 + fibre * 0.014);
}
