extends RefCounted
## 考试与结束界面只读模型。考分取已结算记录，不重新考试、不消费随机数。


func archive_record(core: Variant, data: Dictionary) -> Dictionary:
	var record: Dictionary = core.term_record().duplicate(true)
	# 辞退也是本局终点；仅修正副本中的终止标记和旧学生版姓名。
	record.finished = true
	record.ended_day = data.day
	for student in data.students:
		record.names[int(student.index)] = str(student.name)
	record["teacher_outcome"] = data.duplicate(true)
	return record


func build(core: Variant, time: Dictionary) -> Dictionary:
	var day := int(time.get("ended_day", 0))
	var finished := str(time.get("mode", "")) == SimulationClock.MODE_FINISHED
	var has_exam: bool = core._exam.is_exam_day(day) and not core.exam_report(day).is_empty()
	if not finished and not has_exam:
		return {}
	var risk: Dictionary = core._risk_snapshot()
	var students: Array = []
	var dropouts: Array = []
	var total := 0.0
	for i in core.node_count():
		var score: float = core._exam.last_score_of(i) if has_exam else core.grade(i)
		total += score
		students.append({"index": i, "name": core.alias(i), "score": score})
		if core._is_dropped_out(i):
			dropouts.append(
				{
					"name": core.alias(i),
					"breakdowns": int(risk.breakdowns[i]),
					"risk": str(risk.triggered_kind[i])
				}
			)
	var kind := "exam" if has_exam and not finished else "end"
	if not dropouts.is_empty():
		kind = "dropout"
	elif has_exam and not core._exam.passed_of(day):
		kind = "academic"
	return {
		"kind": kind,
		"day": day,
		"count": students.size(),
		"students": students,
		"dropouts": dropouts,
		"mean": total / students.size() if not students.is_empty() else 0.0,
		"target": core._exam.target_mean(),
		"can_continue": kind == "exam" and not finished,
		"finished": finished,
		"reason": str(time.get("failure_reason", ""))
	}
