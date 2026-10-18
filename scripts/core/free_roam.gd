class_name FreeRoam
extends RefCounted
## 自由状态的课间走动与「先加入好感最高者」（主文档 §5.1.1 / §9.1.5，2026-10-19 用户裁定）。
##
## 状态、活动与关系仍归 SimCore 所有；这里只做判定与转调，不新增可存档的玩法字段
## （唯一新增的 `_best_join_phase` 只是「本段是否已尝试过」的临时标记）。

const STUDY_KEY := "vitality_study_threshold"
const PLAY_KEY := "vitality_play_threshold"


## 段首判定之后的中途切换：自由状态一旦动力跨线，就进入学习／游戏状态并**锁定**。
## 锁定后即使动力回到 30–60 也不退出（下个课间重新判定），对齐用户 2026-10-19 裁定。
static func refresh_states(c: SimCore) -> void:
	if c._phase != "break" or c._is_exam_only_day():
		return
	if c._phase_state.size() < c._n:
		return
	var hi := float(c._psyche[STUDY_KEY])
	var lo := float(c._psyche[PLAY_KEY])
	for i in range(c._n):
		if c._broken[i] or c._sleeping[i]:
			continue
		if str(c._phase_state[i]) != "free":
			continue
		if c._vitality[i] > hi:
			c._phase_state[i] = "study"
		elif c._vitality[i] < lo:
			c._phase_state[i] = "play"


## 自由状态优先加入「自己好感最高的人」正在做的事；每课间只尝试一次。
## 好感最高者不可用（睡觉／崩溃／办公室）或没在做什么时，改为加入「身边（前后左右）正在做的事」；
## 都不成立就交回自主决策（回座位做自己的事）。这两种情况都不消耗本段机会。
static func try_join_best(c: SimCore, i: int) -> bool:
	var phase_key := c._day * 10 + c._phase_index
	if c._best_join_phase.size() <= i:
		return false
	if c._best_join_phase[i] == phase_key:
		return false
	var j := c._find_partner(i, "join")
	if j >= 0:
		var akind := str(c._join_activity_of(j)[0])
		if akind != "idle" and akind != "play":
			c._best_join_phase[i] = phase_key
			return c._propose_activity(i, j, akind)
	var near := _neighbor_doing(c, i)
	if near < 0:
		return false
	c._best_join_phase[i] = phase_key
	return c._propose_activity(i, near, str(c._join_activity_of(near)[0]))


## 前后左右（正交邻座）里正在做可加入活动、且好感最高的人；没有返回 -1。
static func _neighbor_doing(c: SimCore, i: int) -> int:
	var best := -1
	var best_a := 0.0
	var has_best := false
	for k in c._neighbor_idx[i]:
		var j := int(k)
		if j == i or c._broken[j] or c._sleeping[j] or not c.is_present(j):
			continue
		if str(c._seat_relation_between(i, j)) != "orthogonal":
			continue
		var akind := str(c._join_activity_of(j)[0])
		if akind == "idle" or akind == "play":
			continue
		var a := float(c.affinity(i, j))
		if not has_best or a > best_a:
			best = j
			best_a = a
			has_best = true
	return best


## 共享的个人娱乐（2026-10-19 用户裁定）：听歌、看课外书可以加入，仍走 §9.1.2 投票。
static func is_shared(kind: String) -> bool:
	return kind == "listen_music" or kind == "read_book"


## 加入共享娱乐：加入者执行同款娱乐并与发起者同步结束。
## 看书免物品（2026-10-19）：加入者不必自带书，与发起者看同一本。
static func join_shared_leisure(c: SimCore, i: int, anchor: int, akind: String) -> bool:
	var vote: Dictionary = c._vote_accept([anchor], i)
	if not bool(vote["ok"]):
		c._reject_join(i, anchor, [anchor], akind, vote["yes"], vote["no"])
		return false
	c._leave_solo_activity(i)
	if not c._start_leisure(i, akind, true):
		return false
	c._busy_until[i] = c._busy_until[anchor]
	c._busy_phase[i] = c._busy_phase[anchor]
	c._joined_tick[i] = c._global_tick
	c._stats["join_accepts"] = int(c._stats.get("join_accepts", 0)) + 1
	c._log_join_event(i, [anchor], "joined", akind, vote["yes"], vote["no"], {"anchor": anchor})
	return true
