extends GutTest
## Relations 数据模型单测：平铺访问器、钳制、越界/自反安全、有向独立。


func test_allocates_size() -> void:
	var r := Relations.new(5)
	assert_eq(r.size(), 5, "边长应为 5")


func test_default_zero() -> void:
	var r := Relations.new(3)
	assert_eq(r.affinity(0, 1), 0.0, "初始应为 0")


func test_set_and_get_roundtrip() -> void:
	var r := Relations.new(3)
	r.set_affinity(0, 1, 70.0)
	assert_eq(r.affinity(0, 1), 70.0, "写入后读回应一致")


func test_clamp_upper() -> void:
	var r := Relations.new(3)
	r.set_affinity(0, 1, 150.0)
	assert_eq(r.affinity(0, 1), 100.0, "写入应钳制到 100")


func test_clamp_lower() -> void:
	var r := Relations.new(3)
	r.set_affinity(0, 1, -10.0)
	assert_eq(r.affinity(0, 1), 0.0, "写入应钳制到 0")


func test_self_reflexive_is_zero_and_not_writable() -> void:
	var r := Relations.new(3)
	r.set_affinity(1, 1, 80.0)
	assert_eq(r.affinity(1, 1), 0.0, "对角线恒为 0，写入不生效")


func test_out_of_bounds_returns_zero() -> void:
	var r := Relations.new(3)
	assert_eq(r.affinity(-1, 0), 0.0, "负索引返回 0")
	assert_eq(r.affinity(3, 0), 0.0, "发起者越界返回 0")
	assert_eq(r.affinity(0, 3), 0.0, "对象越界返回 0")


func test_directed_independence() -> void:
	var r := Relations.new(3)
	r.set_affinity(0, 1, 70.0)
	assert_eq(r.affinity(1, 0), 0.0, "有向：A[1][0] 不受 A[0][1] 影响")


func test_three_axes_independent() -> void:
	var r := Relations.new(3)
	r.set_affinity(0, 1, 60.0)
	r.set_hostility(0, 1, 20.0)
	r.set_trust(0, 1, 40.0)
	assert_eq(r.affinity(0, 1), 60.0, "好感轴")
	assert_eq(r.hostility(0, 1), 20.0, "敌对轴")
	assert_eq(r.trust(0, 1), 40.0, "信任轴")
