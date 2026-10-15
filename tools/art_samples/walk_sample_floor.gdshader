shader_type spatial;
render_mode unshaded;
uniform float tile_size = 0.5;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = world_position.xz / tile_size;
	float checker = mod(floor(cell.x) + floor(cell.y), 2.0);
	vec2 edge = abs(fract(cell) - 0.5);
	float line = smoothstep(0.488, 0.497, max(edge.x, edge.y));
	vec3 base = mix(vec3(0.89, 0.86, 0.78), vec3(0.92, 0.89, 0.82), checker);
	ALBEDO = mix(base, vec3(0.76, 0.73, 0.65), line * 0.45);
}
