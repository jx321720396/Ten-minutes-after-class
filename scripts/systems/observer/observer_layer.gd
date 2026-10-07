class_name ObserverLayer
extends RefCounted
## 观察层（§11）：**只读**、**按透明度过滤**、**每个角色一份视角**的标签器。
##
## 为什么是「透明度的下属」（用户判断 + §7.4）：
##   「只读」只保证标签不干扰模拟；但若直接读真值矩阵，它对玩家就是上帝视角。
##   低透明度角色的「藏」会在标签层被绕过。故凡是涉及感知的读取，都要经透明度过滤，
##   而标签器的输出正是「玩家感知到的班级结构」。
##
## 于是：低透明度的人，关系看不透 → 标签器不会把他归进任何簇。
## 规格：docs/design/信念矩阵.md §11；阈值 §11.1 复用系统已有阈值（亲近 A≥60），不另定。
##
## 与 Python 参考 `tools/core_sim.py` 的 `ObserverLayer` 逐字一致（只读：不写任何矩阵）。

var _core


func _init(core) -> void:
	_core = core


# ---------- ① 可见性档位（§11.1 / §11.3：由「被观测者」的透明度决定）----------
## 返回 'clear' / 'blurry' / 'sealed'。由被观测者 O[target] 决定，与 viewer 无关。
func visibility(_viewer: int, target: int) -> String:
	var o: float = _core.opacity(target)
	if o >= 50.0:
		return "clear"
	if o >= 20.0:
		return "blurry"
	return "sealed"


# ---------- ② 该 viewer 能看见的关系矩阵 ----------
## viewer 眼中的 axis 关系矩阵（null = 看不见）。
##   clear  → 真值；blurry → 只知「有没有变化」不给方向，取中性基准；sealed → null。
func seen_matrix(viewer: int, axis: String = "affinity") -> Array:
	var n: int = _core.node_count()
	var base := 50.0 if axis != "hostility" else 0.0
	var out: Array = []
	for _k in range(n):
		out.append(_null_row(n))
	for k in range(n):
		var vis := visibility(viewer, k)
		for m in range(n):
			if k == m:
				continue
			if vis == "clear":
				out[k][m] = _src(axis, k, m)
			elif vis == "blurry":
				out[k][m] = base
	return out


func _null_row(n: int) -> Array:
	var row: Array = []
	for _i in range(n):
		row.append(null)
	return row


func _src(axis: String, k: int, m: int) -> float:
	if axis == "affinity":
		return _core.affinity(k, m)
	if axis == "hostility":
		return _core.hostility(k, m)
	return _core.trust(k, m)


# ---------- ③ 簇标签（每个角色一份视角）----------
## viewer 眼中的小团体：§11.1 强连接阈值 A≥60 取连通分量（≥3 人成簇）。
## 绝对阈值 A≥60 是基线；再加一条相对判据：这条边要比「双方各自的多数关系」都更亲近
## （75 分位），否则好感均值偏高时 60 不构成「强」连接、会连成一个巨簇。
func cluster_tags(viewer: int) -> Array:
	var n: int = _core.node_count()
	var seen := seen_matrix(viewer, "affinity")
	var TH_A := 60.0
	# 每个人可观测关系的分位基准（只统计他看得见的部分；不足 3 条 = 哨兵，无法成强连接边）
	var pct := {}
	for i in range(n):
		var vals: Array = []
		for v in seen[i]:
			if v != null:
				vals.append(v)
		vals.sort()
		if vals.size() >= 3:
			pct[i] = vals[int(vals.size() * 0.75)]
	# 无向强连接图：双方都看得见 + 都过绝对阈值 + 都比各自 75 分位更高
	var adj := {}
	for i in range(n):
		adj[i] = {}
	for i in range(n):
		for j in range(i + 1, n):
			var a1 = seen[i][j]
			var a2 = seen[j][i]
			if (
				a1 != null
				and a2 != null
				and float(a1) >= TH_A
				and float(a2) >= TH_A
				and pct.has(i)
				and pct.has(j)
				and float(a1) >= float(pct[i])
				and float(a2) >= float(pct[j])
			):
				adj[i][j] = true
				adj[j][i] = true
	# 连通分量
	var seen_set := {}
	var clusters: Array = []
	for i in range(n):
		if seen_set.has(i):
			continue
		var stack: Array = [i]
		var comp: Array = []
		while not stack.is_empty():
			var x: int = stack.pop_back()
			if seen_set.has(x):
				continue
			seen_set[x] = true
			comp.append(x)
			for nb in adj[x]:
				if not seen_set.has(nb):
					stack.append(nb)
		if comp.size() >= 3:
			comp.sort()
			clusters.append(comp)
	clusters.sort_custom(
		func(a, b):
			if a.size() != b.size():
				return a.size() > b.size()
			return int(a[0]) < int(b[0])
	)
	return clusters


# ---------- ④ 孤立标签 ----------
## viewer 眼中的「被孤立者」：他人→他显著低，而他→他人接近正常（§10.26.3）。
func isolated_tags(viewer: int) -> Array:
	var n: int = _core.node_count()
	var seen := seen_matrix(viewer, "affinity")
	var recv := {}
	var give := {}
	for j in range(n):
		var r: Array = []
		var g: Array = []
		for k in range(n):
			if k != j and seen[k][j] != null:
				r.append(seen[k][j])
			if k != j and seen[j][k] != null:
				g.append(seen[j][k])
		if r.size() >= 3 and g.size() >= 3:
			recv[j] = _avg(r)
			give[j] = _avg(g)
	if recv.is_empty():
		return []
	var avg := _avg(recv.values())
	var out: Array = []
	for j in recv:
		if float(recv[j]) < avg - 15.0 and float(give[j]) > float(recv[j]) + 15.0:
			out.append(j)
	out.sort_custom(func(a, b): return float(recv[int(a)]) < float(recv[int(b)]))
	return out


# ---------- 汇总：一份「某人眼中的班级格局」----------
func view(viewer: int) -> Dictionary:
	return {
		"viewer": viewer,
		"clusters": cluster_tags(viewer),
		"isolated": isolated_tags(viewer),
	}


func _avg(vals: Array) -> float:
	var total := 0.0
	for v in vals:
		total += float(v)
	return total / vals.size()
