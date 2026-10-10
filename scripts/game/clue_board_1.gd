extends Control

@onready var drawing_surface: Control = $DrawingSurface
@onready var chalk: TextureRect = $Chalk
@onready var eraser: TextureRect = $Eraser
@onready var palette: Control = $ColorPalette
@onready var tool_tray: Control = $ToolTray
@onready var chalk_pick: TextureRect = $ToolTray/ChalkPick
@onready var eraser_pick: Panel = $ToolTray/EraserPick
@onready var markers_root: Control = get_node_or_null("Markers")
@onready var avatar_column: Control = $AvatarColumn
@onready var avatar_list: Control = $AvatarColumn/AvatarList
@onready var board_avatars: Node2D = $BoardAvatars

var lines: Array = []
var current_line: PackedVector2Array = PackedVector2Array()
var is_drawing := false
var is_eraser_mode := false
var is_erasing := false
var current_color := Color(0.95, 0.95, 0.92, 1)
var eraser_radius := 30.0
var drag_start_distance := 12.0
var dragged_marker: ColorRect = null
var drag_source: Sprite2D = null
var drag_ghost: Sprite2D = null
var drag_press := Vector2.ZERO
var _rest: Dictionary = {}
var _pop_lift := 28.0
var _pop_scale := 1.22


func _ready():
	drawing_surface.z_index = 0
	board_avatars.z_index = 1
	chalk.z_index = 5
	eraser.z_index = 5
	drawing_surface.draw.connect(_on_draw)
	palette.z_index = 4
	tool_tray.z_index = 4
	_cache_rest(palette)
	_cache_rest(tool_tray)
	chalk_pick.gui_input.connect(_on_chalk_pick_input)
	eraser_pick.gui_input.connect(_on_eraser_pick_input)
	for child in palette.get_children():
		var swatch := child as Panel
		if swatch:
			swatch.gui_input.connect(_on_swatch_input.bind(swatch))
	var first := palette.get_child(0) as Panel
	if first:
		_select_chalk_color(_swatch_color(first))


func _cache_rest(root_node: Node) -> void:
	for child in root_node.get_children():
		var control := child as Control
		if control:
			_rest[control] = Rect2(control.position, control.size)


func _on_chalk_pick_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_chalk_color(current_color)


func _on_eraser_pick_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_eraser()


func _place_chalk_cursor(pos: Vector2) -> void:
	chalk.position = pos - Vector2(chalk.size.x * 0.05, chalk.size.y * 0.99)


func _place_eraser_cursor(pos: Vector2) -> void:
	eraser.position = pos - eraser.size * 0.5


func _select_eraser() -> void:
	is_eraser_mode = true
	is_erasing = false
	chalk.visible = false
	eraser.visible = false
	_mark_selected_swatch(current_color)
	_mark_selected_tool()


func _on_swatch_input(event: InputEvent, swatch: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_chalk_color(_swatch_color(swatch))


func _swatch_color(swatch: Panel) -> Color:
	var style := swatch.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return current_color
	return style.bg_color


func _mark_selected_swatch(color: Color) -> void:
	for child in palette.get_children():
		var swatch := child as Panel
		if swatch == null:
			continue
		var style := swatch.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		var selected := not is_eraser_mode and style.bg_color.is_equal_approx(color)
		_set_pop(swatch, selected)


func _set_pop(node: Control, selected: bool) -> void:
	var rest: Rect2 = _rest[node]
	var grow := _pop_scale if selected else 1.0
	var new_size := rest.size * grow
	var center := rest.get_center()
	if selected:
		center.y -= _pop_lift
	if node.has_meta("pop_tween"):
		var old: Tween = node.get_meta("pop_tween")
		if old != null and old.is_valid():
			old.kill()
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(node, "position", center - new_size * 0.5, 0.14)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(node, "size", new_size, 0.14).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	node.set_meta("pop_tween", tween)
	node.z_index = 2 if selected else 0


func _mark_selected_tool() -> void:
	_set_pop(chalk_pick, not is_eraser_mode)
	_set_pop(eraser_pick, is_eraser_mode)


func _tint_chalk_pick(color: Color) -> void:
	chalk_pick.modulate = color


func _select_chalk_color(color: Color) -> void:
	current_color = color
	chalk.modulate = color
	_tint_chalk_pick(color)
	is_eraser_mode = false
	is_erasing = false
	eraser.visible = false
	_mark_selected_swatch(color)
	_mark_selected_tool()


func _get_marker_at(pos: Vector2) -> ColorRect:
	if markers_root == null:
		return null
	for child in markers_root.get_children():
		var marker := child as ColorRect
		if marker and marker.get_rect().has_point(pos):
			return marker
	return null


func _hits_control(node: Control, pos: Vector2) -> bool:
	if node.get_global_rect().has_point(pos):
		return true
	for child in node.get_children():
		var control := child as Control
		if control and control.get_global_rect().has_point(pos):
			return true
	return false


func _is_on_ui(pos: Vector2) -> bool:
	if _hits_control(palette, pos) or _hits_control(tool_tray, pos):
		return true
	if avatar_column.get_global_rect().has_point(pos):
		return true
	return false


func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var head := _head_in_column(event.position)
				if head:
					drag_source = head
					drag_press = event.position
					return
				dragged_marker = _get_marker_at(event.position)
				if dragged_marker:
					return
				if _is_on_ui(event.position):
					return
				is_drawing = true
				if is_eraser_mode:
					is_erasing = true
					eraser.visible = true
					_place_eraser_cursor(event.position)
					_erase_at(event.position)
				else:
					current_line = PackedVector2Array()
					current_line.append(event.position)
					chalk.visible = true
					_place_chalk_cursor(event.position)
			else:
				_finish_avatar_drag(event.position)
				dragged_marker = null
				is_drawing = false
				is_erasing = false
				chalk.visible = false
				eraser.visible = false
				drawing_surface.queue_redraw()
	elif event is InputEventMouseMotion:
		if drag_source:
			_update_avatar_drag(event.position)
			return
		if dragged_marker:
			dragged_marker.position = event.position - dragged_marker.size / 2.0
		elif is_drawing:
			if is_eraser_mode:
				_place_eraser_cursor(event.position)
				if is_erasing:
					_erase_at(event.position)
			else:
				current_line.append(event.position)
				_place_chalk_cursor(event.position)
			drawing_surface.queue_redraw()


func _head_in_column(pos: Vector2) -> Sprite2D:
	var column_rect := avatar_column.get_global_rect()
	if not column_rect.has_point(pos):
		return null
	for slot in avatar_list.get_children():
		var slot_control := slot as Control
		if slot_control == null:
			continue
		var visible_rect := slot_control.get_global_rect().intersection(column_rect)
		if not visible_rect.has_point(pos):
			continue
		for child in slot_control.get_children():
			if child is Sprite2D:
				return child
	return null


func _board_avatar_rect(sprite: Sprite2D) -> Rect2:
	var size := sprite.texture.get_size() * sprite.scale
	return Rect2(sprite.position - size * 0.5, size)


func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(
		clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y)
	)
	return closest.distance_to(center) <= radius


func _segment_hits_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq <= 0.001:
		return a.distance_to(center) <= radius
	var t := clampf((center - a).dot(ab) / length_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(center) <= radius


func _to_local_point(pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * pos


func _update_avatar_drag(pos: Vector2) -> void:
	if drag_ghost == null:
		if pos.distance_to(drag_press) < drag_start_distance:
			return
		drag_ghost = drag_source.duplicate() as Sprite2D
		drag_ghost.z_index = 20
		add_child(drag_ghost)
	drag_ghost.position = _to_local_point(pos)


func _finish_avatar_drag(pos: Vector2) -> void:
	if drag_ghost:
		var on_column := avatar_column.get_global_rect().has_point(pos)
		var on_chrome := _hits_control(palette, pos) or _hits_control(tool_tray, pos)
		if on_column or on_chrome:
			drag_ghost.queue_free()
		else:
			var drop_at := _to_local_point(pos)
			drag_ghost.reparent(board_avatars)
			drag_ghost.position = drop_at
			drag_ghost.z_index = 1
	drag_source = null
	drag_ghost = null


func _erase_at(pos: Vector2) -> void:
	var local_pos := _to_local_point(pos)
	for child in board_avatars.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		if _circle_hits_rect(local_pos, eraser_radius, _board_avatar_rect(sprite)):
			sprite.queue_free()
	var kept: Array = []
	for line in lines:
		var pts: PackedVector2Array = line.points
		var run := PackedVector2Array()
		for i in pts.size():
			var inside := pts[i].distance_to(pos) <= eraser_radius
			var segment_cut := false
			if i > 0:
				segment_cut = _segment_hits_circle(pts[i - 1], pts[i], pos, eraser_radius)
			if inside or segment_cut:
				if run.size() >= 2:
					kept.append({"points": run, "color": line.color})
				run = PackedVector2Array()
				if not inside:
					run.append(pts[i])
			else:
				run.append(pts[i])
		if run.size() >= 2:
			kept.append({"points": run, "color": line.color})
	lines = kept
	drawing_surface.queue_redraw()


func _on_draw():
	for line in lines:
		if line.points.size() >= 2:
			drawing_surface.draw_polyline(line.points, line.color, 3.0)
	if current_line.size() >= 2:
		drawing_surface.draw_polyline(current_line, current_color, 3.0)
	if not is_drawing and current_line.size() >= 2:
		lines.append({"points": current_line, "color": current_color})
		current_line = PackedVector2Array()
