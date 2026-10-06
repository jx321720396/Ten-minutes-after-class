class_name ActorState
extends RefCounted
## 个体属性（长度 N，主文档 §18.2）。
##
## 平铺：opacity / stress 是长度 N 的向量；mbti 是 4×N（dim 0=E、1=N、2=F、3=P），
## mbti[dim][i] 存于 _mbti[dim * N + i]。
## 读写一律走访问器；§18.2 的 `var opacity` / `var stress` 与 §4.1 的
## 访问器 `opacity(i)` / `stress(i)` 同名，故底层数组私有化。

const MBTI_DIMS: int = 4

var _opacity: PackedFloat32Array
var _stress: PackedFloat32Array
var _mbti: PackedFloat32Array

var _n: int = 0


func _init(n: int) -> void:
	_n = maxi(n, 0)
	_opacity.resize(_n)
	_stress.resize(_n)
	_mbti.resize(MBTI_DIMS * _n)


## 个体数量。
func size() -> int:
	return _n


## i 的透明度；越界返回 0。
func opacity(i: int) -> float:
	if not _in_bounds(i):
		return 0.0
	return _opacity[i]


## i 的压力；越界返回 0。
func stress(i: int) -> float:
	if not _in_bounds(i):
		return 0.0
	return _stress[i]


## i 的 MBTI 维度值（dim：0=E、1=N、2=F、3=P）；越界返回 0。
func mbti(i: int, dim: int) -> float:
	if not _in_bounds(i) or dim < 0 or dim >= MBTI_DIMS:
		return 0.0
	return _mbti[dim * _n + i]


## 写入点统一钳制到 [0,100]；越界忽略。
func set_opacity(i: int, value: float) -> void:
	if not _in_bounds(i):
		return
	_opacity[i] = clampf(value, 0.0, 100.0)


func set_stress(i: int, value: float) -> void:
	if not _in_bounds(i):
		return
	_stress[i] = clampf(value, 0.0, 100.0)


func set_mbti(i: int, dim: int, value: float) -> void:
	if not _in_bounds(i) or dim < 0 or dim >= MBTI_DIMS:
		return
	_mbti[dim * _n + i] = clampf(value, 0.0, 100.0)


func _in_bounds(i: int) -> bool:
	return i >= 0 and i < _n
