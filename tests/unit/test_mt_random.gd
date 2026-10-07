extends GutTest
## MT19937 位级移植：与 CPython random.Random(12345) 黄金值对拍。
##
## 黄金值来源：tools/_verify_mt.gd（已与 Python 逐位核对通过）。
## 覆盖 random() / getrandbits(32/53) / shuffle() 四条关键路径。

const G32 := [
	1789368711, 3146859322, 43676229, 3522623596,
	3544234957, 3448207591, 1282648386, 3672791226,
]

const G53 := [
	6599442377972103, 7387476936782405, 7231418505673677, 7702402357766466,
]

const G01 := [
	0.41661987254534116, 0.010169169457068361, 0.8252065092537432,
	0.2986398551995928, 0.3684116894884757, 0.19366134904507426,
	0.5660081687288613, 0.1616878239293682, 0.12426688428353017,
	0.4329362680099159,
]

const GSHUF := [
	14, 15, 12, 3, 22, 16, 7, 21, 10, 2, 18, 4, 19, 17, 1,
	20, 5, 23, 8, 6, 11, 9, 0, 13,
]


func test_getrandbits_32() -> void:
	var rng := MtRandom.new(12345)
	for i in range(G32.size()):
		assert_eq(rng.getrandbits(32), G32[i], "getrandbits(32)[%d]" % i)


func test_random_float() -> void:
	var rng := MtRandom.new(12345)
	for i in range(G01.size()):
		assert_almost_eq(rng.random(), G01[i], 0.000000000001, "random()[%d]" % i)


func test_getrandbits_53() -> void:
	var rng := MtRandom.new(12345)
	for i in range(G53.size()):
		assert_eq(rng.getrandbits(53), G53[i], "getrandbits(53)[%d]" % i)


func test_shuffle_matches_cpython() -> void:
	var seq: Array = []
	for i in range(24):
		seq.append(i)
	MtRandom.new(12345).shuffle(seq)
	for i in range(GSHUF.size()):
		assert_eq(seq[i], GSHUF[i], "shuffle 结果 [%d]" % i)
