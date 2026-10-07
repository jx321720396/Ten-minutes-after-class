class_name MtRandom
extends RefCounted
## MT19937 —— CPython `random.Random` 的位级精确移植。
##
## 用途：内核随机数必须「同种子可复现」，且要与 Python 参考 `tools/core_sim.py`
## 逐 tick 对拍（硬闸门：同种子关键指标误差 ≤1%，见 `tools/export_ticks.py`）。
## Godot 自带的 `RandomNumberGenerator` 是 PCG32，与 Python 的 Mersenne Twister
## 算法不同，无法对拍 —— 故此处按 CPython `_randommodule.c` 逐位移植。
##
## 仅实现内核用到的子集：random / getrandbits / randbelow / choice / choices /
## sample / shuffle。所有常数均为 MT19937 算法结构常量（非游戏规则），
## 已列入 tests/invariants/check_magic_numbers.py 白名单。

const _N := 624
const _M := 397
const _MATRIX_A := 0x9908b0df
const _UPPER_MASK := 0x80000000
const _LOWER_MASK := 0x7fffffff
const _TEMPER_B := 0x9d2c5680
const _TEMPER_C := 0xefc60000
const _MULT_INIT_GEN := 1812433253
const _INIT_BY_ARRAY_SEED := 19650218
const _MULT_INIT_A := 1664525
const _MULT_INIT_B := 1566083941
const _MASK32 := 0xffffffff

var _mt := PackedInt64Array()
var _mti := _N


func _init(seed: int) -> void:
	_mt.resize(_N)
	_seed_by_array([seed])


## [0,1) 均匀浮点（CPython `random.random`，每次消费两个 32-bit 字）。
func random() -> float:
	var a := _uint32() >> 5
	var b := _uint32() >> 6
	return (a * 67108864.0 + b) * (1.0 / 9007199254740992.0)


## k 个随机位组成的非负整数（CPython `getrandbits`）。
func getrandbits(k: int) -> int:
	if k <= 32:
		return _uint32() >> (32 - k)
	var words: int = (k - 1) / 32 + 1
	var result := 0
	var remaining := k
	for i in range(words):
		var r := _uint32()
		if remaining < 32:
			r >>= (32 - remaining)
		result |= r << (32 * i)
		remaining -= 32
	return result


## [0, n) 均匀整数（CPython `_randbelow`，拒绝采样）。
func randbelow(n: int) -> int:
	var k := _bit_length(n)
	var r := getrandbits(k)
	while r >= n:
		r = getrandbits(k)
	return r


## 从序列等概率取一个元素（CPython `choice`）。
func choice(seq: Array):
	var n := seq.size()
	if n == 0:
		return null
	return seq[randbelow(n)]


## 加权抽样 k 个（含放回，CPython `choices`，累积权重 + bisect_right）。
func choices(population: Array, weights: Array, k: int) -> Array:
	var n := population.size()
	if n == 0 or k <= 0:
		return []
	var cum: Array = []
	var acc := 0.0
	for w in weights:
		acc += float(w)
		cum.append(acc)
	var total := acc
	var out: Array = []
	for _i in range(k):
		var x := random() * total
		out.append(population[clampi(_bisect_right(cum, x), 0, n - 1)])
	return out


## 无放回抽样 k 个（CPython `sample`；本局节点数 ≤16，恒走 pool-swap 路径）。
func sample(population: Array, k: int) -> Array:
	var n := population.size()
	if k > n:
		k = n
	if k < 0:
		k = 0
	var pool := population.duplicate()
	var result: Array = []
	for i in range(k):
		var j := randbelow(n - i)
		result.append(pool[j])
		pool[j] = pool[n - i - 1]
	return result


## 原地洗牌（CPython `shuffle`，反向 Fisher–Yates）。
func shuffle(seq: Array) -> void:
	for i in range(seq.size() - 1, 0, -1):
		var j := randbelow(i + 1)
		var tmp = seq[i]
		seq[i] = seq[j]
		seq[j] = tmp


# ------------------------------------------------------------------ 内部实现
## CPython `init_genrand`。
func _seed_genrand(s: int) -> void:
	_mt[0] = s & _MASK32
	for i in range(1, _N):
		var prev := _mt[i - 1]
		_mt[i] = (_MULT_INIT_GEN * (prev ^ (prev >> 30)) + i) & _MASK32


## CPython `init_by_array`（int 种子走 `init_by_array([seed])`）。
func _seed_by_array(init_key: Array) -> void:
	_seed_genrand(_INIT_BY_ARRAY_SEED)
	var key_len := init_key.size()
	var i := 1
	var j := 0
	var k := maxi(_N, key_len)
	while k > 0:
		var prev := _mt[i - 1]
		var t := (_mt[i] ^ ((prev ^ (prev >> 30)) * _MULT_INIT_A)) + int(init_key[j]) + j
		_mt[i] = t & _MASK32
		i += 1
		j += 1
		if i >= _N:
			_mt[0] = _mt[_N - 1]
			i = 1
		if j >= key_len:
			j = 0
		k -= 1
	k = _N - 1
	while k > 0:
		var prev := _mt[i - 1]
		var t := (_mt[i] ^ ((prev ^ (prev >> 30)) * _MULT_INIT_B)) - i
		_mt[i] = t & _MASK32
		i += 1
		if i >= _N:
			_mt[0] = _mt[_N - 1]
			i = 1
		k -= 1
	_mt[0] = _UPPER_MASK


## CPython `genrand_uint32`（含 tempering）。
func _uint32() -> int:
	if _mti >= _N:
		var kk := 0
		while kk < _N - _M:
			var y := (_mt[kk] & _UPPER_MASK) | (_mt[kk + 1] & _LOWER_MASK)
			_mt[kk] = _mt[kk + _M] ^ (y >> 1) ^ (_MATRIX_A if (y & 1) == 1 else 0)
			kk += 1
		while kk < _N - 1:
			var y := (_mt[kk] & _UPPER_MASK) | (_mt[kk + 1] & _LOWER_MASK)
			_mt[kk] = _mt[kk + (_M - _N)] ^ (y >> 1) ^ (_MATRIX_A if (y & 1) == 1 else 0)
			kk += 1
		var y := (_mt[_N - 1] & _UPPER_MASK) | (_mt[0] & _LOWER_MASK)
		_mt[_N - 1] = _mt[_M - 1] ^ (y >> 1) ^ (_MATRIX_A if (y & 1) == 1 else 0)
		_mti = 0
	var out := _mt[_mti]
	_mti += 1
	out ^= out >> 11
	out ^= (out << 7) & _TEMPER_B
	out ^= (out << 15) & _TEMPER_C
	out ^= out >> 18
	return out & _MASK32


## 非负整数的二进制位数（等价 Python `int.bit_length`）。
func _bit_length(n: int) -> int:
	var count := 0
	while n > 0:
		count += 1
		n >>= 1
	return count


func _bisect_right(cum: Array, x: float) -> int:
	var lo := 0
	var hi := cum.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if float(cum[mid]) <= x:
			lo = mid + 1
		else:
			hi = mid
	return lo
