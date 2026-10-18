extends SceneTree
## 实例化生产漫画，检查时钟 hold、翻页、跳过与不同横屏尺寸。

const COMIC := preload("res://tools/opening_comic_bake_view.gd")
const OUTPUT := "res://tools/out/opening_comic_baked"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1920, 1080)
	var core := SimCore.new(20261018, 16, ConfigLoader.new().load_all())
	var clock := SimulationClock.new()
	root.add_child(clock)
	assert(clock.bind_core(core))
	var comic := COMIC.new()
	comic.seen_path = "user://comic_capture_test.dat"
	root.add_child(comic)
	comic.start(clock)
	assert(clock._paused_by.has(&"opening_comic"))
	await _save("page_01_first_panel")
	for page in 4:
		while comic.state.revealed < 4:
			comic.advance()
		assert(comic.state.page == page)
		await create_timer(0.5).timeout
		await _save("page_%02d_1920" % (page + 1))
		root.size = Vector2i(1280, 720)
		await _save("page_%02d_1280" % (page + 1))
		root.size = Vector2i(1920, 1080)
		comic.advance()
	assert(not comic.visible)
	assert(not clock._paused_by.has(&"opening_comic"))
	comic.start(clock)
	comic.skip()
	assert(not clock._paused_by.has(&"opening_comic"))
	assert(FileAccess.file_exists(comic.seen_path))
	DirAccess.remove_absolute(comic.seen_path)
	print("Opening comic UI: four pages, clock hold/release and skip passed")
	quit()


func _save(label: String) -> void:
	for frame in 4:
		await process_frame
	RenderingServer.force_draw()
	var rendered := root.get_texture().get_image()
	var error := rendered.save_png(OUTPUT + "/" + label + ".png")
	if label.ends_with("_1920"):
		var page_name := label.trim_suffix("_1920")
		assert(
			(
				rendered.save_webp(
					"res://assets/illustrations/opening_comic/" + page_name + ".webp", false
				)
				== OK
			)
		)
	assert(error == OK)
	print("saved ", label)
