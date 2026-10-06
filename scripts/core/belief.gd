class_name Belief
extends RefCounted
## 信念矩阵：三份 N×N（主文档 §18.2、§18.5）。
##
## 语义：B[i][j] = i 猜测「j 对 i」的态度（i 的信念，不是真值矩阵）。
## 平铺同 Relations：[i][j] 存于 i * N + j。
## 读写一律走访问器，不用裸下标。

var _b_affinity: PackedFloat32Array
var _b_hostility: PackedFloat32Array
var _b_trust: PackedFloat32Array

var _n: int = 0


func _init(n: int) -> void:
	_n = maxi(n, 0)
	_b_affinity.resize(_n * _n)
	_b_hostility.resize(_n * _n)
	_b_trust.resize(_n * _n)


## 节点数（矩阵边长）。
func size() -> int:
	return _n


## i 猜测「j 对我的好感」；越界或自反返回 0。
func b_affinity(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _b_affinity[i * _n + j]


func b_hostility(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _b_hostility[i * _n + j]


func b_trust(i: int, j: int) -> float:
	if i == j or not _in_bounds(i, j):
		return 0.0
	return _b_trust[i * _n + j]


## 写入点统一钳制到 [0,100]；越界与自反忽略。
func set_b_affinity(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_b_affinity[i * _n + j] = clampf(value, 0.0, 100.0)


func set_b_hostility(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_b_hostility[i * _n + j] = clampf(value, 0.0, 100.0)


func set_b_trust(i: int, j: int, value: float) -> void:
	if i == j or not _in_bounds(i, j):
		return
	_b_trust[i * _n + j] = clampf(value, 0.0, 100.0)


func _in_bounds(i: int, j: int) -> bool:
	return i >= 0 and i < _n and j >= 0 and j < _n
