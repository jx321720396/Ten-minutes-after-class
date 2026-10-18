extends SceneTree
## 使用正式 UI 和项目头像截图；不写玩家存档。

const OUTPUT := "res://tools/out/student_roster"
var _viewport: SubViewport


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(1280, 720)
	root.add_child(_viewport)
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var roster = load("res://scripts/ui/student_roster.gd").new()
	_viewport.add_child(roster)
	roster.open(core, "profile")
	await _save("profile_1280")
	roster.set_mode("seats")
	roster.select_student(0)
	roster.select_student(1)
	await _save("seats_1280")
	_viewport.size = Vector2i(1600, 720)
	await _save("seats_wide")
	roster.hide()
	var profile = load("res://scenes/ui/npc_profile.tscn").instantiate()
	_viewport.add_child(profile)
	profile.bind_sources(core, null, null)
	profile.open_profile(0)
	await _save("detail_wide")
	profile.close()
	var encyclopedia = load("res://scenes/ui/encyclopedia.tscn").instantiate()
	_viewport.add_child(encyclopedia)
	await _save("encyclopedia_wide")
	encyclopedia.hide()
	var settings = load("res://scenes/ui/settings_menu.tscn").instantiate()
	_viewport.add_child(settings)
	await _save("settings_wide")
	settings.hide()
	var board = load("res://scenes/ui/clue_board.tscn").instantiate()
	_viewport.add_child(board)
	await _save("board_wide")
	board.hide()
	var overview = load("res://scripts/ui/class_overview_card.gd").new()
	_viewport.add_child(overview)
	await process_frame
	overview._open_details()
	await _save("overview_wide")
	overview.get("_details").hide()
	overview.hide()
	var risk = load("res://scripts/ui/attention_card.gd").new()
	_viewport.add_child(risk)
	risk._open_details("all")
	await _save("risk_wide")
	risk.close_details()
	risk.hide()
	var backpack = load("res://scenes/ui/backpack_panel.tscn").instantiate()
	_viewport.add_child(backpack)
	backpack.open_item()
	await _save("backpack_wide")
	quit()


func _save(filename: String) -> void:
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png(OUTPUT + "/" + filename + ".png")
