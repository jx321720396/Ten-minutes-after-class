extends Node
## 安卓返回键适配（2026-10-18）：
##   · 子页面 / 弹层：把返回键翻译成一次 `ui_cancel`，沿用各页面已有的 Esc 关闭逻辑，
##     即“返回到上一个页面”（设置 / 百科 / 背包 / 档案 / 推理板 / 暂停菜单 / 办公室 …）；
##   · 主界面（没有任何页面消费返回）：连续两次返回退出，第一次给一行提示。
## 前提：project.godot 的 `application/config/quit_on_go_back=false`，
##       否则系统会在引擎层直接退出，收不到本通知。

const DOUBLE_BACK_MSEC := 2000
const TOAST_SECONDS := 2.0
const TOAST_TEXT := "再按一次返回键退出"
const TOAST_LAYER := 200
const Fonts = preload("res://scripts/ui/game_fonts.gd")

var _last_back_msec := -1000000
var _toast: PanelContainer
var _toast_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_toast()
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_requested()


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left = maxf(0.0, _toast_left - delta)
	_toast.modulate.a = clampf(_toast_left / 0.35, 0.0, 1.0)
	if _toast_left <= 0.0:
		_toast.visible = false
		set_process(false)


func _on_back_requested() -> void:
	if _dispatch_cancel():
		_last_back_msec = -1000000
		_hide_toast()
		return
	var now := Time.get_ticks_msec()
	if now - _last_back_msec <= DOUBLE_BACK_MSEC:
		get_tree().quit()
		return
	_last_back_msec = now
	_show_toast()


## 返回 true = 当前页面消费了这次返回（关掉弹层 / 打开暂停菜单等）。
## 用 push_input 同步派发，之后能立即读到 Viewport 的 handled 状态。
func _dispatch_cancel() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	viewport.push_input(event)
	return viewport.is_input_handled()


func _show_toast() -> void:
	if _toast == null:
		return
	_toast_left = TOAST_SECONDS
	_toast.modulate.a = 1.0
	_toast.visible = true
	set_process(true)


func _hide_toast() -> void:
	_toast_left = 0.0
	if _toast != null:
		_toast.visible = false
	set_process(false)


## 底部居中的一行提示；不拦截任何输入。
func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BackToastLayer"
	layer.layer = TOAST_LAYER
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_toast = PanelContainer.new()
	_toast.name = "BackToast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -132.0
	_toast.offset_bottom = -84.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.06, 0.86)
	style.set_corner_radius_all(18)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_toast.add_theme_stylebox_override("panel", style)
	root.add_child(_toast)

	var label := Label.new()
	label.text = TOAST_TEXT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Fonts.regular())
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88, 1.0))
	_toast.add_child(label)
	_toast.visible = false
