extends SceneTree

var failures := 0


func _initialize() -> void:
	var script := load("res://scripts/ui/opening_comic_state.gd")
	if script == null:
		print("FAIL: opening comic state is missing")
		quit(1)
		return
	var state = script.new()
	state.start(4, 4, 2.0)
	_check(state.revealed == 1, "first panel visible")
	state.advance_time(1.9)
	_check(state.revealed == 1, "wait full interval")
	state.advance_time(0.11)
	_check(state.revealed == 2, "auto reveal after two seconds")
	state.advance_time(20.0)
	_check(state.revealed == 4 and state.page == 0, "never auto turn page")
	state.tap()
	_check(state.page == 1 and state.revealed == 1, "tap turns complete page")
	state.tap()
	_check(state.page == 1 and state.revealed == 2, "tap reveals exactly one panel")
	state.advance_time(1.9)
	_check(state.revealed == 2, "tap resets auto reveal timer")
	state.advance_time(20.0)
	state.tap()
	state.advance_time(20.0)
	state.tap()
	state.advance_time(20.0)
	_check(not state.finished, "last page must be acknowledged")
	state.tap()
	_check(state.finished, "last acknowledgement finishes")
	state.start(4, 4, 2.0)
	state.skip()
	state.advance_time(20.0)
	_check(state.finished and state.page == 0, "skip stops playback")
	print("Opening comic state: ", 10 - failures, "/10 passed")
	quit(1 if failures else 0)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", label)
