extends SceneTree
func _init() -> void:
	var vals: Array[float] = [
		1.05, 1.15, 1.25, 1.35, 1.45, 1.55, 1.65, 1.75, 1.85, 1.95,
		2.05, 2.15, 2.25, 2.35, 2.45, 2.55, 2.65, 2.75, 2.85, 2.95,
	]
	for v in vals:
		var s: String = "%.1f" % v
		var r_twoprod: float = _r1_twoprod(v)
		var r_snapped: float = snapped(v, 0.1)
		print("v=", "%.17f" % v, "  fmt=", s, "  twoprod=", "%.17f" % r_twoprod, "  snapped=", "%.17f" % r_snapped)
	quit(0)

func _r1_twoprod(v: float) -> float:
	var y: float = v * 10.0
	var flr: float = floor(y)
	var frac: float = y - flr
	if frac > 0.5:
		return (flr + 1.0) / 10.0
	if frac < 0.5:
		return flr / 10.0
	var err: float = _mul10_err(v, y)
	if err > 0.0:
		return (flr + 1.0) / 10.0
	if err < 0.0:
		return flr / 10.0
	if fmod(flr, 2.0) == 0.0:
		return flr / 10.0
	return (flr + 1.0) / 10.0

func _mul10_err(v: float, p: float) -> float:
	var split_c := 134217729.0
	var t := split_c * v
	var a_hi := t - (t - v)
	var a_lo := v - a_hi
	return (a_hi * 10.0 - p) + a_lo * 10.0
