class_name Relations
extends RefCounted
## 关系矩阵：N×N 有向，0–100（主文档 §18.2）。
##
## 平铺：矩阵元素 [i][j] 存于 PackedFloat32Array 的 i * N + j；
## i 是「发起者」、j 是「对象」，即「i 对 j」的态度（有向，A[i][j] ≠ A[j][i]）。
## 读写一律走访问器，不用裸下标，避免把 A[i][j] 误读成 A[j][i]。
##
## 说明：§18.2 伪码里的 `var affinity` 与 §4.1 的访问器 `affinity(i,j)` 在 GDScript
## 里同名冲突，故底层数组改为私有 `_affinity`，公开访问器保留 `affinity(i,j)`。

var _affinity: PackedFloat32Array
var _hostility: PackedFloat32Array
var _trust: PackedFloat32Array

var _n: int = 0


func _init(n: int) -> void:
	_n = maxi(n, 0)
	_affinity.resize(_n * _n)
	_hostility.resize(_n * _n)
	_trust.resize(_n * _n)


## 节点数（矩阵边长）。
func size() -> int:
	return _n


## i 对 j 的好感；越界或自反（i == j）返回 0。
func affinity(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _affinity[i * _n + j]


func hostility(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _hostility[i * _n + j]


func trust(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _trust[i * _n + j]


## 写入点统一钳制到 [0,100]；越界与自反（i == j）忽略不写。
func set_affinity(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_affinity[i * _n + j] = clampf(value, 0.0, 100.0)


func set_hostility(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_hostility[i * _n + j] = clampf(value, 0.0, 100.0)


func set_trust(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_trust[i * _n + j] = clampf(value, 0.0, 100.0)


func _in_bounds(i: int, j: int) -> bool:
	return i >= 0 and i < _n and j >= 0 and j < _n
