extends GutTest

## ESC / 返回音（sys_ui_cancel，2026-10-20）：
## · 页面消费 ui_cancel → 播 UiCancel；
## · 没有任何页面处理（如主菜单）→ 保持静音。

const CONFIRM_DIALOG := preload("res://scenes/ui/confirm_dialog.tscn")


class _CancelConsumer:
	extends Control
	var taken := false

	func _unhandled_input(event: InputEvent) -> void:
		if visible and event.is_action_pressed("ui_cancel"):
			taken = true
			get_viewport().set_input_as_handled()


func _cancel_player() -> AudioStreamPlayer:
	return SFX.get_node_or_null(^"UiCancel") as AudioStreamPlayer


func _press_cancel() -> void:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	await get_tree().process_frame


## 整包测试的帧间隔可能超过素材时长（80 ms），只看 playing 会偶发假失败；
## 同时接受「已经播完（finished 已发出）」视为响过。
func _press_cancel_and_check_sound(player: AudioStreamPlayer, message: String) -> void:
	var finished := [false]
	var on_finished := func() -> void: finished[0] = true
	player.finished.connect(on_finished)
	await _press_cancel()
	var heard := player.playing or bool(finished[0])
	if player.finished.is_connected(on_finished):
		player.finished.disconnect(on_finished)
	assert_true(heard, message)


func test_consumed_cancel_plays_sound() -> void:
	var player := _cancel_player()
	assert_not_null(player, "sfx.tscn 应包含 UiCancel 播放器")
	assert_same(player.stream, SFX.get_node(^"ButtonClick").stream, "返回音应沿用普通按钮点击音")
	player.stop()
	var consumer := _CancelConsumer.new()
	add_child_autofree(consumer)
	await _press_cancel_and_check_sound(player, "页面消费返回后应播放 ui_cancel")
	assert_true(consumer.taken, "构造的页面应消费 ui_cancel")


func test_real_dialog_escape_plays_sound() -> void:
	var player := _cancel_player()
	player.stop()
	var dialog: Control = CONFIRM_DIALOG.instantiate()
	add_child_autofree(dialog)
	dialog.open(false)
	watch_signals(dialog)
	await _press_cancel_and_check_sound(player, "真实页面消费 ESC 后应播放 ui_cancel")
	assert_signal_emitted(dialog, "cancelled", "真实页面的 ESC 分支被走到")


func test_unconsumed_cancel_stays_silent() -> void:
	var player := _cancel_player()
	player.stop()
	var consumer := _CancelConsumer.new()
	consumer.visible = false
	add_child_autofree(consumer)
	await _press_cancel()
	assert_false(consumer.taken, "隐藏的页面不消费 ui_cancel")
	assert_false(player.playing, "没有页面处理返回时不播")
