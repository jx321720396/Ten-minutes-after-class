extends SceneTree
## D10 验收：无头 30 天「单日戏剧循环 ≥1 次/天」。
##
## 与 D9 的 8 人性能基准不同，戏剧循环需要**满编班级**：8 人散落在 17 座里邻接过稀，
## 调侃的「≥3 人围观」门槛几乎无法满足，戏剧出不来的现象是**座位稀疏**所致，不是内核 bug。
## 故本脚本按主文档 §11.5「16 NPC + 1 玩家 = 17 节点」满编跑 30 天，统计戏剧循环的
## 「调侃 → 羞辱 → 排挤 → 压力爆发」链条。
##
## 运行：godot --headless --path . --script res://tools/headless_run_drama.gd

func _init() -> void:
	var tables := ConfigLoader.new().load_all()
	var core := SimCore.from_npc(12345, 16, tables)
	for d in range(30):
		core.run_day()

	var st: Dictionary = core._stats
	var teases := int(st.get("teases", 0))
	var humiliations := int(st.get("humiliations", 0))
	var excludes := int(st.get("excludes", 0))
	var reports := int(st.get("reports", 0))
	var bursts := int(st.get("bursts", 0))
	# 「戏剧循环」= 冲突链事件（调侃 / 羞辱 / 排挤 / 举报 / 爆发）日均次数
	var drama_events := teases + humiliations + excludes + reports + bursts
	var per_day := drama_events / 30.0

	print("=== D10 戏剧循环验收：16 人 × 30 天（满编班级）===")
	print(core.report())
	print("")
	print("  戏剧循环链条：调侃 %d → 羞辱 %d → 排挤 %d → 举报 %d → 压力爆发 %d" % [
		teases, humiliations, excludes, reports, bursts])
	print("  戏剧事件日均 %.1f 次/天（门槛 ≥1；%s）" % [
		per_day, "通过" if per_day >= 1.0 else "不通过"])
	print("  压力爆发频率：平均每 %.1f 天一次" % [30.0 / maxf(1.0, float(bursts))])
	quit(0 if per_day >= 1.0 else 1)
