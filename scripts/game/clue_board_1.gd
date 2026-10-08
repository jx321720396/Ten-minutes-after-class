extends Control

@onready var drawing_surface: Control = $DrawingSurface
@onready var chalk: TextureRect = $Chalk
@onready var eraser: TextureRect = $Eraser
@onready var palette: Control = $ColorPalette
@onready var tool_toggle: Button = $ToolToggle
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

var palette_colors := [
	Color(0.95, 0.95, 0.92, 1),
	Color(1, 0.95, 0.3, 1),
	Color(1, 0.4, 0.55, 1),
	Color(0.3, 0.85, 1, 1),
	Color(0.4, 1, 0.4, 1),
]


func _ready():
	drawing_surface.draw.connect(_on_draw)
	tool_toggle.pressed.connect(_on_tool_toggle)
	for i in palette.get_child_count():
		var swatch := palette.get_child(i) as ColorRect
		if swatch:
			swatch.gui_input.connect(_on_swatch_input.bind(palette_colors[i]))


func _on_tool_toggle():
	is_eraser_mode = not is_eraser_mode
	if is_eraser_mode:
		tool_toggle.text = "橡皮擦"
		chalk.visible = false
	else:
		tool_toggle.text = "粉笔"
		eraser.visible = false


func _on_swatch_input(event: InputEvent, color: Color):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		current_color = color
		chalk.modulate = color


func _get_marker_at(pos: Vector2) -> ColorRect:
	if markers_root == null:
		return null
	for child in markers_root.get_children():
		var marker := child as ColorRect
		if marker and marker.get_rect().has_point(pos):
			return marker
	return null


func _is_on_ui(pos: Vector2) -> bool:
	if palette.get_global_rect().has_point(pos):
		return true
	if tool_toggle.get_global_rect().has_point(pos):
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
				if _is_on_ui(event.position) or _is_on_board_avatar(event.position):
					return
				is_drawing = true
				if is_eraser_mode:
					is_erasing = true
					eraser.visible = true
					eraser.position = event.position - Vector2(40, 30)
					_erase_at(event.position)
				else:
					current_line = PackedVector2Array()
					current_line.append(event.position)
					chalk.visible = true
					chalk.position = event.position - Vector2(60, 15)
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
				eraser.position = event.position - Vector2(40, 30)
				if is_erasing:
					_erase_at(event.position)
			else:
				current_line.append(event.position)
				chalk.position = event.position - Vector2(60, 15)
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


func _is_on_board_avatar(pos: Vector2) -> bool:
	var local_pos := _to_local_point(pos)
	for child in board_avatars.get_children():
		var sprite := child as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var size := sprite.texture.get_size() * sprite.scale
		var rect := Rect2(sprite.position - size * 0.5, size)
		if rect.has_point(local_pos):
			return true
	return false


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
		var on_chrome := palette.get_global_rect().has_point(pos) or tool_toggle.get_global_rect().has_point(pos)
		if on_column or on_chrome:
			drag_ghost.queue_free()
		else:
			var drop_at := _to_local_point(pos)
			drag_ghost.reparent(board_avatars)
			drag_ghost.position = drop_at
			drag_ghost.z_index = 1
	drag_source = null
	drag_ghost = null


func _erase_at(pos: Vector2):
	var i := lines.size() - 1
	while i >= 0:
		var line = lines[i]
		var pts: PackedVector2Array = line.points
		var keep := PackedVector2Array()
		for pt in pts:
			if pt.distance_to(pos) > eraser_radius:
				keep.append(pt)
		if keep.size() < 2:
			lines.remove_at(i)
		else:
			line.points = keep
		i -= 1
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
