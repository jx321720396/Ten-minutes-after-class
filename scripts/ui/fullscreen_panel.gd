extends RefCounted
## 在统一逻辑画布中铺满屏幕；保留容器排版和既有节点路径。


static func fit(center: Control, panel: Control, base: Vector2) -> void:
	var viewport := center.get_viewport_rect().size
	var factor := minf(viewport.x / base.x, viewport.y / base.y)
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	center.scale = Vector2.ONE * factor
	panel.custom_minimum_size = viewport / factor
	panel.size = viewport / factor
	center.size = viewport / factor
	# 旧居中卡片的最小尺寸在本帧末失效后，再解除 CenterContainer 的旧尺寸钳制。
	center.set_deferred("size", viewport / factor)
