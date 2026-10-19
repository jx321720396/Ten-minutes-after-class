extends GutTest
## 声量输入的按住路径（2026-10-19）：不依赖麦克风，可在无头测试里跑。
## 麦克风路径需要真机/输入设备，只在设置与办公室集成测试里覆盖「不可用时按平常」。

const VOICE_INPUT = preload("res://scripts/game/voice_input.gd")


func _make_input() -> Node:
	var input: Node = VOICE_INPUT.new()
	add_child_autofree(input)
	var rules := VoiceRules.new()
	rules.configure_table(ConfigLoader.new().get_table("rules/voice"))
	input.configure(rules)
	return input


func test_hold_full_window_reaches_shout() -> void:
	var input := _make_input()
	watch_signals(input)
	assert_true(input.begin_window(true), "按住模式不需要麦克风")
	input._process(0.3)  # 提示结束，下一帧开始蓄力
	input._process(5.0)
	assert_signal_emitted(input, "tier_locked", "满 5 秒锁定档位")
	assert_eq(input.current_tier(), 4, "满窗 → 吼")


func test_single_spike_does_not_flip_live_tier() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	for _i in range(10):
		input._process_mic_sample(40.0, 0.016)
	var before: int = int(input.live_tier())
	input._process_mic_sample(95.0, 0.016)
	assert_eq(input.live_tier(), before, "单帧尖峰不抬档")
	assert_true(input.current_intensity() < 60.0, "平滑后不跟随尖峰")


func test_sustained_high_reaches_shout() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	for _i in range(80):
		input._process_mic_sample(95.0, 0.016)
	assert_eq(input.live_tier(), 4, "持续大声 → 吼")
	assert_true(input.current_intensity() > 90.0, "平滑值接近目标")


func test_recent_loud_stretch_reaches_shout() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	for _i in range(125):
		input._process_mic_sample(40.0, 0.016)
	for _i in range(125):
		input._process_mic_sample(95.0, 0.016)
	assert_eq(input.live_tier(), 4, "最近 2.5 秒持续大声 → 吼（整窗均值只能到提高）")


func test_finish_uses_window_average_not_last() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	for _i in range(60):
		input._process_mic_sample(40.0, 0.016)
	for _i in range(5):
		input._process_mic_sample(95.0, 0.016)
	input._finish_mic()
	assert_eq(input.current_tier(), 2, "取最近窗口平均，不取最后一刻的高音")


func test_hold_tap_is_whisper() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	input._process(0.3)
	input._process(0.1)
	input.end_hold()
	assert_eq(input.current_tier(), 1, "轻点 → 轻声")


func test_hold_mid_window_is_normal() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	input._process(0.3)
	input._process(2.5)
	input.end_hold()
	assert_eq(input.current_tier(), 2, "约 2.5 秒 → 平常")


func test_finish_now_uses_collected_charge() -> void:
	var input := _make_input()
	assert_true(input.begin_window(true))
	input._process(0.3)
	input._process(4.5)
	input.finish_now()
	assert_eq(input.current_tier(), 4, "提前结束按已蓄力档位结算")
	assert_false(input.is_active())
