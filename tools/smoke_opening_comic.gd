extends SceneTree
## 从真实新局状态进入教室，验证老师漫画接线与触摸不重复翻页。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("GameState")
	game.start_game(20261018, 16)
	game.tutorial_pending = true
	var room := load("res://scenes/game/classroom3D.tscn").instantiate() as Node
	root.add_child(room)
	for frame in 240:
		await process_frame
		if room.has_node("OpeningComic"):
			break
	var comic := room.get_node_or_null("OpeningComic")
	if comic == null or not comic.visible:
		print("FAIL: new game did not open comic")
		quit(1)
		return
	comic.seen_path = "user://comic_smoke_test.dat"
	var clock := room.get_node("Clock")
	assert(clock.is_held_by(&"opening_comic"))
	assert(not room.get_node("TutorialOverlay").visible)
	var touch := InputEventScreenTouch.new()
	touch.pressed = false
	comic._on_page_input(touch)
	assert(comic.state.page == 0 and comic.state.revealed == 2)
	var emulated := InputEventMouseButton.new()
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = false
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	comic._on_page_input(emulated)
	assert(comic.state.page == 0, "touch emulation must not also turn page")
	assert(comic.state.revealed == 2, "emulated mouse must not reveal another panel")
	comic._on_page_input(touch)
	assert(comic.state.page == 0 and comic.state.revealed == 3)
	comic._on_page_input(touch)
	assert(comic.state.page == 0 and comic.state.revealed == 4)
	comic._on_page_input(touch)
	assert(comic.state.page == 1)
	comic.skip()
	assert(not clock.is_held_by(&"opening_comic"))
	DirAccess.remove_absolute(comic.seen_path)
	print("Opening comic: real new game, touch, no double-turn, skip/release passed")
	quit()
