extends Node2D
## 无字对话气泡组件（纯代码自绘，不依赖美术素材）。
##
## 用法：把本节点（或 speech_bubble.tscn 实例）作为"人物节点"的子节点挂上，
## 需要时调用 show_bubble()，气泡即在人物头顶弹出 → 由大变小 → 淡出消失。
## 人物节点自身可继续做浮动（student_bob.gd），气泡作为子节点会跟着走。
##
## 锚点约定：本节点的 (0,0) 即人物原点，气泡底部（尾巴尖）落在 head_offset 处。

enum BubbleMode { MODE_SHRINK, MODE_POP }  # SHRINK=直接由大变小；POP=先弹入再缩回

@export_group("外观")
## 气泡底部（尾巴尖）相对人物原点的位置，按立绘把气泡抬到头顶
@export var head_offset := Vector2(0.0, -46.0)
## 气泡主体宽高（像素）
@export var bubble_size := Vector2(110.0, 56.0)
## 圆角半径
@export var corner_radius := 18.0
## 尖尾巴高度
@export var tail_height := 14.0
@export var fill_color := Color(1.0, 1.0, 1.0, 0.95)
@export var outline_color := Color(0.1, 0.1, 0.1, 0.3)
@export var outline_width := 2.0
## true 时在气泡里画三个点，做出"无声发言/在想"的效果
@export var show_ellipsis := false

@export_group("动画")
@export var mode: BubbleMode = BubbleMode.MODE_SHRINK
## 消失时轻微上浮的像素
@export var rise_pixels := 8.0
## 弹出后停留时长（秒）
@export var hold_seconds := 1.2
## 由大变小消失的时长（秒）
@export var shrink_seconds := 0.45
## 起始（或 POP 峰值）缩放
@export var pop_scale := 1.3
## POP 模式弹入时长（秒）
@export var pop_seconds := 0.16

var _base_pos := Vector2.ZERO
var _playing := false


func _ready() -> void:
	_base_pos = position
	visible = false
	scale = Vector2.ZERO


## 播放一次气泡。若正在播放则忽略本次调用，避免连点抖动。
func show_bubble() -> void:
	if _playing:
		return
	_playing = true
	visible = true
	position = _base_pos
	modulate.a = 1.0

	var tw := create_tween()
	match mode:
		BubbleMode.MODE_POP:
			scale = Vector2.ONE * pop_scale
			tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "scale", Vector2.ONE, pop_seconds)
			tw.tween_interval(hold_seconds)
		BubbleMode.MODE_SHRINK:
			scale = Vector2.ONE * pop_scale
			tw.tween_interval(hold_seconds)

	# 停留后：轻微上浮 + 由大变小 + 淡出，三者并行
	tw.parallel().tween_property(self, "position:y", _base_pos.y - rise_pixels, shrink_seconds)
	tw.parallel().tween_property(self, "scale", Vector2.ZERO, shrink_seconds)
	tw.parallel().tween_property(self, "modulate:a", 0.0, shrink_seconds)
	tw.tween_callback(_finish)


func _finish() -> void:
	_playing = false
	visible = false
	scale = Vector2.ZERO


## —— 气泡绘制（局部坐标，整体相对 head_offset）——
func _draw() -> void:
	var o := head_offset
	var w := bubble_size.x
	var h := bubble_size.y
	var t := tail_height

	# 主体：圆角矩形，底边位于 head_offset
	var rect := Rect2(o.x - w * 0.5, o.y - h - t, w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill_color
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	sb.border_color = outline_color
	sb.set_border_width_all(outline_width)
	draw_style_box(sb, rect)

	# 尖尾巴：三角形，底部中点指向 head_offset
	var poly := PackedVector2Array([
		Vector2(o.x - t * 0.6, o.y - t),
		Vector2(o.x + t * 0.6, o.y - t),
		o,
	])
	draw_colored_polygon(poly, fill_color)

	# 可选：三个省略点
	if show_ellipsis:
		var dot_y := o.y - h * 0.5 - t
		for i in 3:
			draw_circle(Vector2(o.x - 12.0 + i * 12.0, dot_y), 3.0, Color(0.3, 0.3, 0.3, 0.8))
