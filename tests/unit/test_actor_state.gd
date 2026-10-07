extends GutTest
## ActorState 数据模型单测：向量访问器、mbti 4×N 平铺、钳制、越界安全。


func test_allocates_size() -> void:
	var s := ActorState.new(5)
	assert_eq(s.size(), 5, "个体数量应为 5")


func test_opacity_stress_roundtrip() -> void:
	var s := ActorState.new(3)
	s.set_opacity(0, 40.0)
	s.set_stress(0, 55.0)
	assert_eq(s.opacity(0), 40.0, "透明度读回")
	assert_eq(s.stress(0), 55.0, "压力读回")


func test_clamp() -> void:
	var s := ActorState.new(3)
	s.set_opacity(0, 200.0)
	s.set_stress(1, -5.0)
	assert_eq(s.opacity(0), 100.0, "透明度钳制上限")
	assert_eq(s.stress(1), 0.0, "压力钳制下限")


func test_out_of_bounds_returns_zero() -> void:
	var s := ActorState.new(3)
	assert_eq(s.opacity(-1), 0.0, "负索引返回 0")
	assert_eq(s.stress(3), 0.0, "越界返回 0")


func test_mbti_flattening() -> void:
	var s := ActorState.new(3)
	s.set_mbti(0, 0, 80.0)  # E
	s.set_mbti(0, 2, 65.0)  # F
	assert_eq(s.mbti(0, 0), 80.0, "E 维读回")
	assert_eq(s.mbti(0, 2), 65.0, "F 维读回")
	assert_eq(s.mbti(0, 1), 0.0, "N 维未被写入")
	assert_eq(s.mbti(0, 3), 0.0, "P 维未被写入")


func test_mbti_no_cross_talk() -> void:
	var s := ActorState.new(3)
	s.set_mbti(1, 2, 90.0)
	assert_eq(s.mbti(0, 2), 0.0, "角色 0 的 F 维不受角色 1 影响")


func test_mbti_invalid_dim() -> void:
	var s := ActorState.new(3)
	assert_eq(s.mbti(0, 4), 0.0, "dim 越界返回 0")
	s.set_mbti(0, -1, 50.0)
	assert_eq(s.mbti(0, 3), 0.0, "非法 dim 写入不生效")
