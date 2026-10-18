extends Control
## 将整页插画按配置的斜切区域采样，避免矩形遮罩破坏漫画边缘。

var texture: Texture2D
var vertices := PackedVector2Array()
var uv := PackedVector2Array()


func _draw() -> void:
	if texture != null and vertices.size() >= 3:
		draw_polygon(vertices, PackedColorArray([Color.WHITE]), uv, texture)
