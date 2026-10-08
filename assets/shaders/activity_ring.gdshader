// 活动圈着色器：一块横置平面，片元用 SDF 求「成员圆 ∪ 连接胶囊」的并集。
//
// 依据：docs/superpowers/plans/2026-10-07-activity-foot-rings.md、
//      docs/superpowers/plans/2026-10-07-chat-playable-loop.md §8.2。
//
// 为什么用 SDF 而不是逐个画圆：两人（或多人）融合时必须**一块连续区域、无内部双边框**；
// 逐个圆叠加会在交界处留下两条边。这里整场活动只用一个 quad、一次并集求值。
//
// 单位一律是米；members / link_* 都是**相对 quad 中心**的局部 XZ 坐标。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec4 ring_color : source_color = vec4(0.24, 0.60, 0.44, 0.42);
// 区域填充透明度（0 = 只描边，个人圈用）
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.28;
// 描边宽度（米）
uniform float line_width : hint_range(0.0, 0.3) = 0.04;
// 每个成员圆的半径（米）
uniform float radius : hint_range(0.05, 1.5) = 0.30;
// 这块 quad 的尺寸（米），用于把 UV 换算成局部坐标
uniform vec2 quad_size = vec2(1.0, 1.0);
// 成员圆（最多 8 个：一场课间闲聊不会更多）
uniform vec2 members[8];
uniform int member_count : hint_range(0, 8) = 0;
// 连接胶囊的端点对（最多 8 条边）
uniform vec2 link_a[8];
uniform vec2 link_b[8];
uniform int link_count : hint_range(0, 8) = 0;

varying vec2 ring_pos;

void vertex() {
	ring_pos = (UV - vec2(0.5)) * quad_size;
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

void fragment() {
	float d = 1e9;
	for (int i = 0; i < 8; i++) {
		if (i >= member_count) {
			break;
		}
		d = min(d, length(ring_pos - members[i]) - radius);
	}
	for (int i = 0; i < 8; i++) {
		if (i >= link_count) {
			break;
		}
		d = min(d, sd_capsule(ring_pos, link_a[i], link_b[i], radius));
	}
	if (d > 10.0) {
		ALPHA = 0.0;
		discard;
	}
	float inside = 1.0 - smoothstep(0.0, 0.02, d);
	float border = 1.0 - smoothstep(0.0, 0.02, abs(d) - line_width);
	float a = max(inside * fill_alpha, border * ring_color.a);
	if (a <= 0.004) {
		discard;
	}
	ALBEDO = ring_color.rgb;
	ALPHA = a;
}
