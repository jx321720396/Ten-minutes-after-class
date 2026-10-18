extends PanelContainer
## 白底黑边漫画气泡；尾巴覆盖框线并指向说话人。

var tail_anchor := 0.5
var tail_width := 32.0
var tail_depth := 42.0
var tail_lean := -28.0
var fill := Color.WHITE
var ink := Color.BLACK
var border := 2.0


func _draw() -> void:
	var center := size.x * tail_anchor
	var tip := Vector2(center + tail_lean, -tail_depth)
	var polygon := PackedVector2Array(
		[
			Vector2(center - tail_width * 0.5, border * 2.0),
			tip,
			Vector2(center + tail_width * 0.5, border * 2.0),
		]
	)
	draw_colored_polygon(polygon, fill)
	draw_polyline(
		PackedVector2Array(
			[Vector2(center - tail_width * 0.5, 0), tip, Vector2(center + tail_width * 0.5, 0)]
		),
		ink,
		border,
		true
	)
