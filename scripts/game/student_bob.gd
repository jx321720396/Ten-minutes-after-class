extends Node2D
## 2D 教室原型：让每个学生都有肉眼可见的动作（上下浮动 + 轻微左右摆动）。
##
## 挂法：挂在一个“学生”节点（Node2D）上，人物本体放在它的子节点里
## （单张立绘 → Sprite2D；序列帧/图集 → AnimatedSprite2D）。
## 幅度 / 周期 / 相位集中在下面的导出参数里，可以在 Inspector 里逐个微调。
## 换序列帧素材后：把子节点换成 AnimatedSprite2D，做一个名为 idle 的动画，本脚本会自动播放它。

@export_group("动作参数")
## 上下浮动幅度（像素）
@export var bob_pixels: float = 3.5
## 左右摆动幅度（±度）
@export var tilt_degrees: float = 2.0
## 一个完整起伏的周期（秒）
@export var period_seconds: float = 1.0
## 随机相位（0 ~ 2π），用来错开每个人的节奏，避免全班同步
@export var phase: float = 0.0
## 若子节点是 AnimatedSprite2D，则播放这个动画名
@export var idle_animation: StringName = &"idle"

var _base_position: Vector2 = Vector2.ZERO
var _time: float = 0.0


func _ready() -> void:
	_base_position = position
	_time = phase
	if period_seconds <= 0.01:
		period_seconds = 1.0
	var animated := _find_animated_sprite(self)
	if (
		animated != null
		and animated.sprite_frames != null
		and animated.sprite_frames.has_animation(idle_animation)
	):
		animated.play(idle_animation)


func _process(delta: float) -> void:
	_time += delta
	var omega: float = TAU / period_seconds
	# 上下浮动与左右摆动用不同频率（0.5 倍），看起来才不像机械同步
	position = _base_position + Vector2(0.0, sin(_time * omega) * bob_pixels)
	rotation = deg_to_rad(tilt_degrees) * sin(_time * omega * 0.5 + phase)


func _find_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return child
		var found := _find_animated_sprite(child)
		if found != null:
			return found
	return null
