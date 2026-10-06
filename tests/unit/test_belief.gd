extends GutTest
## Belief 数据模型单测：三份 N×N 平铺、钳制、越界/自反安全。


func test_allocates_size() -> void:
	var b := Belief.new(4)
	assert_eq(b.size(), 4, "边长应为 4")


func test_roundtrip() -> void:
	var b := Belief.new(4)
	b.set_b_affinity(0, 1, 45.0)
	b.set_b_hostility(1, 0, 30.0)
	b.set_b_trust(2, 3, 60.0)
	assert_eq(b.b_affinity(0, 1), 45.0, "b_affinity 读回")
	assert_eq(b.b_hostility(1, 0), 30.0, "b_hostility 读回")
	assert_eq(b.b_trust(2, 3), 60.0, "b_trust 读回")


func test_clamp() -> void:
	var b := Belief.new(3)
	b.set_b_affinity(0, 1, 120.0)
	assert_eq(b.b_affinity(0, 1), 100.0, "写入应钳制到 100")


func test_self_reflexive_is_zero() -> void:
	var b := Belief.new(3)
	b.set_b_affinity(0, 0, 50.0)
	assert_eq(b.b_affinity(0, 0), 0.0, "对角线恒为 0")


func test_out_of_bounds_returns_zero() -> void:
	var b := Belief.new(3)
	assert_eq(b.b_affinity(-1, 0), 0.0, "负索引返回 0")
	assert_eq(b.b_trust(3, 0), 0.0, "发起者越界返回 0")
	assert_eq(b.b_hostility(0, 3), 0.0, "对象越界返回 0")
