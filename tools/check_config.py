"""配置表启动校验（文档中已声明的各项约束的可执行版本）

运行：python tools/check_config.py
任一项失败则以非零码退出，可直接接进 CI。

校验清单（依据各表内的「启动校验」注释与 UIF §2.5 / §2.6）：
  1. w_events：`tier` 与 `base` 档位一致（normal ∈ [1,3]、major ∈ [4,5]）；`class` ∈ A–E
  2. transmission：`feedback` ∈ [0,1]；`settle_interval` > 0
  3. decay：`decay_a_*` / `decay_h` / `retain_s` ∈ (0,1]；`decay_a_interact` ≥ `decay_a_no_interact`
  4. behavior_thresholds：阈值键格式（行为名不得自带轴后缀，否则查表键会重复拼接）
  5. behavior_probs：概率类 ∈ [0,1]
  6. phases：课间 + 上课 tick 合计 = 480；`player_control` = 1 当且仅当 `kind` = break
  7. status_tags：`days` ≥ 1
  8. behaviors：`duration ≥ 0`、`|payoff| ∈ [1,5]`、**按 |payoff| 分组后平均耗时呈上升趋势**（效果越强耗时越长）
  9. social_event_triggers：metric / op / value 不得含日期类记号（不变式 1）
 10. 配置键存在性：`core_sim.py` 引用的阈值键必须真的在 behavior_thresholds.csv 里
 11. 闲聊空间几何 / 场景拾取层（2026-10-16 接替已删的玩家交互配置）：
     `rules/chat_space.csv`（学生闲聊的范围 / 容差 / 采样步长）与 `ui/pick_layers.csv`
     （点选学生的物理层）的必需键与值域
"""

import csv
import os
import re
import sys
import math
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()
AXES_WORDS = ("affinity", "hostility", "stress")
DATE_WORDS = ("day", "week", "month", "term_", "第", "天", "周", "month")

FAILED = []
PASSED = [0]


def load(rel, key=None):
    with open(os.path.join(DATA, rel), encoding="utf-8") as f:
        rows = [r for r in f if not r.startswith("#")]
    return list(csv.DictReader(rows))


def params(rel):
    return {r["param"]: float(r["value"]) for r in load(rel)}


def check(name, cond, detail=""):
    print("  %s %s%s" % ("✓" if cond else "✗", name, ("  ← " + str(detail)) if (not cond and detail) else ""))
    if cond:
        PASSED[0] += 1
    else:
        FAILED.append(name)


print("=== 1. w_events：档位与分类 ===")
for r in load("balance/w_events.csv"):
    base = float(r["base"])
    tier = r["tier"]
    lo, hi = (1, 3) if tier == "normal" else (4, 5)
    check("%s: %s 档 base=%s ∈ [%d,%d]" % (r["event_id"], tier, r["base"], lo, hi), lo <= abs(base) <= hi)
    check("%s: class ∈ A–E" % r["event_id"], r.get("class", "") in ("A", "B", "C", "D", "E"))

print("=== 2. transmission ===")
tp = params("rules/transmission.csv")
check("feedback ∈ [0,1]", 0.0 <= tp["feedback"] <= 1.0, tp["feedback"])
check("settle_interval > 0", tp["settle_interval"] > 0, tp["settle_interval"])

print("=== 3. decay ===")
dc = params("rules/decay.csv")
for k in ("decay_a_no_interact", "decay_a_interact", "decay_h", "retain_s"):
    check("%s ∈ (0,1]" % k, 0.0 < dc[k] <= 1.0, dc[k])
check("decay_a_interact ≥ decay_a_no_interact", dc["decay_a_interact"] >= dc["decay_a_no_interact"])

print("=== 4. behavior_thresholds ===")
rows = load("rules/behavior_thresholds.csv")
for r in rows:
    bad = [w for w in AXES_WORDS if any(r["behavior"].endswith("_" + w) for w in AXES_WORDS)]
    check("%s: 行为名不得自带轴后缀（会与 metric 重复拼接）" % r["behavior"], not bad, r["behavior"])
print("=== 5. behavior_probs ===")
# 本表混有两类行：① 行为概率（行为名与 behaviors.csv 一致）→ 必须在 [0,1]；
#                  ② 数值参数（涓流值 / 减压幅度 / 发生概率上限等）→ 只要求是有限数。
# （曾把 sleep_relief=8.0 当概率校验而误报，故按"是否为行为名"分流。）
KNOWN_B = {r["behavior"] for r in load("rules/behaviors.csv")}
for r in load("rules/behavior_probs.csv"):
    v = float(r["base_p"])
    if r["behavior"] in KNOWN_B:
        check("%s 概率 ∈ [0,1]" % r["behavior"], 0.0 <= v <= 1.0, v)
    else:
        check("%s 是有限数值参数" % r["behavior"], abs(v) < 10000, v)

print("=== 7. phases ===")
ph = load("rules/phases.csv")
total = sum(int(r["tick_count"]) for r in ph if r["kind"] in ("break", "class"))
check("课间 + 上课 tick 合计 = 480", total == 480, total)
for r in ph:
    check("%s: player_control = 1 当且仅当 kind = break" % r["phase_id"],
          (r["player_control"] == "1") == (r["kind"] == "break"))

print("=== 8. status_tags ===")
for r in load("rules/status_tags.csv"):
    check("%s: days ≥ 1" % r["tag_id"], int(float(r["days"])) >= 1)
    check("%s: spread_ratio ∈ [0,1]" % r["tag_id"], 0.0 <= float(r.get("spread_ratio", 0)) <= 1.0)
    check("%s: spread_max ≥ 0" % r["tag_id"], int(float(r.get("spread_max", 0))) >= 0)

print("=== 9. behaviors：耗时与收益的单调性 ===")
bh = load("rules/behaviors.csv")
for r in bh:
    check("%s: duration ≥ 0" % r["behavior"], int(float(r["duration"])) >= 0)
    check(
        "%s: |payoff| ∈ [0,5]（负值 = 损害方向；**0 = 只读行为**，无数值收益）" % r["behavior"],
        0 <= abs(float(r["payoff"])) <= 5,
    )
# 法则：收益越大耗时越长 —— 这是**趋势**，不是逐档严格单调。
#   · 排除「整段占用」特例（duration ≥ 100，如睡觉）：它占用整个课间，不参与普通比较
#   · 允许 20% 波动（设计上同类收益的行为耗时不必相同）
by_payoff = {}
for r in bh:
    d = int(float(r["duration"]))
    if d >= 100:
        continue
    if abs(float(r["payoff"])) == 0:
        #   · 排除「只读行为」（payoff = 0，如观察）：它不产生数值收益，谈不上「收益-耗时」
        continue
    by_payoff.setdefault(abs(float(r["payoff"])), []).append(d)
avgs = [(k, sum(v) / len(v)) for k, v in sorted(by_payoff.items())]
for (k1, a1), (k2, a2) in zip(avgs, avgs[1:]):
    check("收益 %.0f → %.0f：平均耗时呈上升趋势（%.1f → %.1f）" % (k1, k2, a1, a2),
          a2 >= a1 * 0.8, "允许 20%% 波动")

print("=== 10. social_event_triggers：禁日期记号 ===")
for r in load("rules/social_event_triggers.csv"):
    blob = (r["metric"] + " " + r["op"] + " " + r["value"]).lower()
    hit = [w for w in DATE_WORDS if w in blob]
    check("%s / %s: 无日期类记号" % (r["trigger_rule"], r["metric"]), not hit, hit)

print("=== 11. 配置键存在性（防 .get 静默回落）===")
# 教训（本会话第 5 类「回执≠真相」，同类错误已发生 **两次**）：
#   `thresholds_lookup` 的键是 f"{behavior}_{metric}"。曾把整串 `humiliate_min_bystanders`
#   写进 behavior 列 → 键变成 `humiliate_min_bystanders_bystanders`，
#   代码 `th.get("humiliate_min_bystanders", 3.0)` **静默回落到默认 3.0** →
#   §10.23 的羞辱判据**恒真**，而一切「看起来在跑」；同类错误在 `conformity_see_window` 上又复发一次。
#   ∴ 本项把「代码引用的阈值键」与「表里实际存在的键」做集合比对。
#   ⚠️ 缺键应当**报错**，而不是悄悄用默认值 —— 这就是本项存在的理由。
_tkeys = set()
for _r in load("rules/behavior_thresholds.csv"):
    _tkeys.add(_r["behavior"] + "_" + _r["metric"])
_srcp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "core_sim.py")
_src = open(_srcp, encoding="utf-8").read()
_want = set()
for _line in _src.split("\n"):
    for _pre in ('th["', 'th.get("', 'thresholds_lookup.get("'):
        _i = 0
        while True:
            _i = _line.find(_pre, _i)
            if _i < 0:
                break
            _rest = _line[_i + len(_pre):]
            _end = _rest.find('"')
            if _end > 0:
                _want.add(_rest[:_end])
            _i += len(_pre)
_missing = sorted(k for k in _want if k not in _tkeys)
check("代码引用的阈值键全部存在于 behavior_thresholds.csv", not _missing,
      ("缺失: %s" % _missing) if _missing else "全部存在（%d 个键）" % len(_want))

print("=== 8. 时间组件配置（time_presentation / time_runtime / phases 一致性）===")
_pres_rows = load("rules/time_presentation.csv")
_runtime = {r["key"]: r["value"] for r in load("rules/time_runtime.csv")}
_phases_rows = load("rules/phases.csv")
_pres_by_phase = {r["phase_id"]: r for r in _pres_rows}
check("term_days 为正整数",
      _runtime.get("term_days", "").isdigit() and int(_runtime.get("term_days", "0")) > 0,
      _runtime.get("term_days"))
check("max_ticks_per_frame 为正整数",
      _runtime.get("max_ticks_per_frame", "").isdigit() and int(_runtime.get("max_ticks_per_frame", "0")) > 0,
      _runtime.get("max_ticks_per_frame"))
try:
    _report_hold = float(_runtime.get("report_hold_seconds", ""))
    _report_hold_ok = math.isfinite(_report_hold) and _report_hold >= 0.0
except ValueError:
    _report_hold_ok = False
check("report_hold_seconds 为非负有限数（0 = 立即自动进入次日）",
      _report_hold_ok, _runtime.get("report_hold_seconds"))
check("time_presentation 与 phases 相位一一对应",
      set(_pres_by_phase) == {r["phase_id"] for r in _phases_rows},
      "pres=%s phases=%s" % (sorted(_pres_by_phase), sorted(r["phase_id"] for r in _phases_rows)))
for _r in _phases_rows:
    _row = _pres_by_phase.get(_r["phase_id"])
    if _row is None:
        continue
    _seconds = float(_row["real_duration_seconds"])
    if _r["kind"] == "settle":
        check("%s: 结算相位实时时长为 0" % _r["phase_id"], _seconds == 0.0, _seconds)
    else:
        check("%s: 活动相位实时时长为正" % _r["phase_id"], _seconds > 0.0, _seconds)
        check("%s: 活动相位 tick_count 为正" % _r["phase_id"], int(_r["tick_count"]) > 0, _r["tick_count"])

print("=== 12. 闲聊空间几何 / 场景拾取层 ===")
# 依据：主文档 §10.5（交互范围）、§8.7（加入闲聊）。
# 2026-10-16：原 rules/player_interaction.csv 随玩家子系统删除 —— 学生自主闲聊仍需要的几何参数
#            迁到 rules/chat_space.csv；点选学生的物理层留在 UI 配置 ui/pick_layers.csv。
_cs_rows = load("rules/chat_space.csv")
_cs = {r["param"]: r["value"] for r in _cs_rows}
_cs_required = ["chat_range_m", "seated_tolerance_m", "seated_chat_range_m", "range_step_m"]
check("chat_space 必需键齐全", all(k in _cs for k in _cs_required),
      "缺失: %s" % sorted(set(_cs_required) - set(_cs)))
if all(k in _cs for k in _cs_required):
    check("chat_range_m 为正", float(_cs["chat_range_m"]) > 0, _cs["chat_range_m"])
    check("座位聊天容差为正且小于通用范围",
          0 < float(_cs["seated_tolerance_m"]) < float(_cs["chat_range_m"]),
          _cs["seated_tolerance_m"])
    check("前后座位聊天上限不小于通用范围",
          float(_cs["seated_chat_range_m"]) >= float(_cs["chat_range_m"]),
          _cs["seated_chat_range_m"])
    check("range_step_m 为正", float(_cs["range_step_m"]) > 0, _cs["range_step_m"])
_pl_rows = load("ui/pick_layers.csv")
_pl = {r["param"]: r["value"] for r in _pl_rows}
check("pick_layers 必需键齐全",
      all(k in _pl for k in ("actor_pick_layer", "world_pick_blocker_layer")))
if all(k in _pl for k in ("actor_pick_layer", "world_pick_blocker_layer")):
    check("拾取层掩码为正且与遮挡层不同",
          int(_pl["actor_pick_layer"]) > 0
          and int(_pl["world_pick_blocker_layer"]) > 0
          and _pl["actor_pick_layer"] != _pl["world_pick_blocker_layer"],
          "%s / %s" % (_pl["actor_pick_layer"], _pl["world_pick_blocker_layer"]))

_particles = json.loads(read(os.path.join(DATA, "ui", "behavior_particles.json")))
_ps = _particles["settings"]
_positive_particle_keys = (
    "interval_seconds", "lifetime_seconds", "max_per_actor", "font_size", "halo_radius_pixels",
    "halo_segments", "head_lift_m", "fallback_height_m", "spread_m", "side_speed_m",
    "rise_speed_m", "gravity_m", "reference_height_pixels", "minimum_view_scale",
    "maximum_view_scale",
)
check("符号粒子：尺寸、寿命、密度和运动参数为有限正数",
      all(math.isfinite(float(_ps.get(k, 0))) and float(_ps.get(k, 0)) > 0
          for k in _positive_particle_keys))
check("符号粒子：透明度、缩放和淡出起点合法",
      0 <= _ps["halo_alpha"] <= 1 and 0 <= _ps["minimum_scale"] < 1
      and 0 <= _ps["fade_start"] < 1
      and _ps["minimum_view_scale"] <= _ps["maximum_view_scale"])
check("符号粒子：容量和圆形分段为整数",
      all(int(_ps[k]) == _ps[k] for k in ("max_per_actor", "halo_segments")))
_particle_kinds = {"chat", "study", "listen_music", "eat_snack", "read_book"}
check("符号粒子：六种公开行为样式齐全", set(_particles["styles"]) == _particle_kinds)
check("符号粒子：各样式符号与颜色有效",
      all(s["symbols"] and all(isinstance(v, str) and v for v in s["symbols"])
          and s["colors"] and all(re.fullmatch(r"[0-9a-fA-F]{6}", c) for c in s["colors"])
          for s in _particles["styles"].values()))

_style_rows = load("ui/chat_feedback_style.csv")
with open(os.path.join(DATA, "ui/activity_ring_palette.json"), encoding="utf-8") as _file:
    _ring_palette = json.load(_file)
_ring_colors = [_ring_palette["personal"]] + _ring_palette["groups"]
check("活动圈配色为不透明六位十六进制 RGB",
      all(re.fullmatch(r"#[0-9a-fA-F]{6}", c) for c in _ring_colors))
check("活动圈配色覆盖最大 12 组且与个人圈互异",
      len(_ring_palette["groups"]) >= 12 and
      len({c.lower() for c in _ring_colors}) == len(_ring_colors))
_style = {r["param"]: r["value"] for r in _style_rows}
_style_required = [
    "pen_windup_seconds",
    "pen_spin_seconds",
    "pen_settle_seconds",
    "pen_result_seconds",
    "menu_width_px",
    "menu_margin_px",
    "bubble_follow_height_m",
    "progress_bar_height_px",
    "ring_radius_m",
    "ring_fill_alpha",
    "ring_blend_radius_m",
    "toast_seconds",
    "emotion_positive_affinity_delta",
    "emotion_negative_hostility_delta",
    "emotion_crying_stress_delta",
    "emotion_high_stress",
]
check("chat_feedback_style 必需键齐全", all(k in _style for k in _style_required),
      "缺失: %s" % sorted(set(_style_required) - set(_style)))
if all(k in _style for k in _style_required):
    _pen_total = sum(float(_style[k]) for k in
                     ("pen_windup_seconds", "pen_spin_seconds", "pen_settle_seconds",
                      "pen_result_seconds"))
    check("转笔四段合计为正", _pen_total > 0, _pen_total)
    check("呈现尺寸 / 时长参数为正",
          all(float(_style[k]) > 0 for k in
              ("pen_windup_seconds", "pen_spin_seconds", "pen_settle_seconds",
               "pen_result_seconds", "menu_width_px", "menu_margin_px",
               "bubble_follow_height_m", "progress_bar_height_px", "toast_seconds")))
    check("圈半径为正、填充透明度在 [0,1]、融合宽度非负",
          float(_style["ring_radius_m"]) > 0 and 0.0 <= float(_style["ring_fill_alpha"]) <= 1.0,
          "%s / %s / %s"
          % (
              _style["ring_radius_m"],
              _style["ring_fill_alpha"],
              _style["ring_blend_radius_m"],
          ))

_scripts = []
for _root_dir, _dirs, _files in os.walk(os.path.join(ROOT, "scripts")):
    for _f in _files:
        if _f.endswith(".gd"):
            _scripts.append(read(os.path.join(_root_dir, _f)))
_src_all = "\n".join(_scripts)
_dead = [k for k in list(_cs) + list(_pl) + list(_style) if ('"%s"' % k) not in _src_all]
check("新表的每个键都有脚本消费者（防「写了没人读」）", not _dead, "未被引用的键: %s" % _dead)
_used = set()
for _pat in (re.compile(r'params\.get\("([a-z_]+)"'), re.compile(r'\.get\("([a-z_]+)"\s*,')):
    for _m in _pat.finditer(_src_all):
        _used.add(_m.group(1))
_ghost = sorted(k for k in _used
                if k.startswith(("chat_range", "seated_", "range_step", "actor_pick_layer",
                                 "world_pick_blocker_layer", "pen_", "menu_",
                                 "bubble_", "ring_", "toast_", "emotion_", "progress_bar"))
                and k not in _cs and k not in _pl and k not in _style)
check("脚本 params.get 的键都在新表里（防 .get 静默回落）", not _ghost, "无对应表项: %s" % _ghost)

# 13. movement（导航口径）：数值集中 + 烘焙参数可校验
#     桌椅阻挡盒必须高于 agent_max_climb —— 否则 Recast 会把桌顶面与地面判为连通，
#     人物"沿导航走上桌子"，而且**没有任何报错**（静默失效）。
_mv = params("rules/movement.csv")
_want_mv = ("meters_per_tick", "player_radius", "nav_cell_size", "nav_agent_height",
            "nav_max_climb", "nav_blocker_height")
_missing_mv = sorted(k for k in _want_mv if _mv.get(k, 0.0) <= 0.0)
check("movement：导航参数齐全且为正", not _missing_mv, "缺失 / 非正: %s" % _missing_mv)
check("movement.nav_max_climb < nav_blocker_height",
      _mv.get("nav_max_climb", 0.0) < _mv.get("nav_blocker_height", 0.0),
      "%s / %s" % (_mv.get("nav_max_climb"), _mv.get("nav_blocker_height")))
check("movement.nav_blocker_height ≥ 桌面实际高度 0.74",
      _mv.get("nav_blocker_height", 0.0) >= 0.74, _mv.get("nav_blocker_height"))
check("movement.nav_cell_size ≤ player_radius",
      _mv.get("nav_cell_size", 0.0) <= _mv.get("player_radius", 0.0),
      "%s / %s" % (_mv.get("nav_cell_size"), _mv.get("player_radius")))

_time_flow = params("rules/time_flow.csv")
check("时间流速：正常倍率必须为 1", _time_flow.get("normal_scale", 0.0) == 1.0,
      _time_flow.get("normal_scale"))
check("时间流速：行动倍率有限且不小于正常倍率",
      math.isfinite(_time_flow.get("player_action_scale", 0.0))
      and _time_flow.get("player_action_scale", 0.0) >= _time_flow.get("normal_scale", 1.0),
      _time_flow.get("player_action_scale"))

# 14. 学业系统（§17.1）：成绩轴初始化常量 + 涓流分段表（2026-10-16：分布改由 rules/psyche.csv 给出）
_kp = params("rules/kernel_params.csv")
_ps = params("rules/psyche.csv")
_grade_keys = ("grade_init_min", "grade_init_max")
check("psyche：开局成绩分布常量齐全", all(k in _ps for k in _grade_keys),
      "缺失: %s" % sorted(set(_grade_keys) - set(_ps)))
if all(k in _ps for k in _grade_keys):
    check("grade_init_min ≤ grade_init_max", _ps["grade_init_min"] <= _ps["grade_init_max"],
          "%s / %s" % (_ps["grade_init_min"], _ps["grade_init_max"]))
    check("开局成绩区间 ⊆ [0, grade_max]",
          0 <= _ps["grade_init_min"] and _ps["grade_init_max"] <= _kp["grade_max"],
          "%s / %s" % (_ps["grade_init_min"], _ps["grade_init_max"]))
    check("开局成绩均值 = (min+max)/2",
          abs((_ps["grade_init_min"] + _ps["grade_init_max"]) / 2.0 - 300.0) <= 1.0,
          (float(_ps["grade_init_min"]) + float(_ps["grade_init_max"])) / 2.0)
check("psych：压力 / 动力范围与阈值合法",
      0 <= _ps["stress_init_min"] <= _ps["stress_init_max"] <= _ps["stat_max"]
      and _ps["stat_min"] == 0 and _ps["stat_max"] == 100
      and _ps["vitality_play_threshold"] < _ps["vitality_study_threshold"]
      and _ps["breakdown_exit_stress"] < _ps["breakdown_enter_stress"])
check("psyche：跨天继承与联动标志存在",
      all(k in _ps for k in ("carry_stress_cut", "carry_vitality_cut", "vitality_equals_stress")))
_grows = load("rules/grade_table.csv")
_guppers = [float(r["band_upper"]) for r in _grows]
_gtpp = [float(r["ticks_per_point"]) for r in _grows]
check("grade_table：band_upper 严格递增",
      all(a < b for a, b in zip(_guppers, _guppers[1:])), _guppers)
check("grade_table：ticks_per_point 递增",
      all(a <= b for a, b in zip(_gtpp, _gtpp[1:])), _gtpp)
check("grade_table：末档上界 = grade_max",
      bool(_guppers) and _guppers[-1] == _kp.get("grade_max"),
      "末档 %s vs grade_max %s" % (_guppers[-1] if _guppers else "无", _kp.get("grade_max")))
check("grade_table：上界与 ticks 均为正",
      all(u > 0 and t > 0 for u, t in zip(_guppers, _gtpp)))
_exam_rows = load("rules/exam.csv")
_exam = {r["param"]: r["value"] for r in _exam_rows}
_exam_days = sorted(int(float(v)) for k, v in _exam.items() if k.startswith("exam_day_"))
_term_days = int(float({r["key"]: r["value"] for r in load("rules/time_runtime.csv")}["term_days"]))
check("exam：周考日落在学期内且递增无重复",
      bool(_exam_days) and _exam_days == sorted(set(_exam_days))
      and _exam_days[0] > 0 and _exam_days[-1] < _term_days
      and _term_days not in _exam_days,
      _exam_days)
check("exam：噪声与扣分非负",
      float(_exam.get("exam_noise_sigma", -1)) >= 0 and float(_exam.get("stress_exam_penalty", -1)) >= 0)
check("exam：特等奖名次至少为 1", int(float(_exam.get("top_prize_rank", 0))) >= 1)
check("exam：进步奖门槛为正", float(_exam.get("progress_prize_delta", 0)) > 0)

print("\n=== 结论 ===")
_leisure = params("rules/leisure.csv")
# 2026-10-16（D02）：减压不再逐活动配 —— 统一「每 10 秒 −5 压力」（rules/activities.csv 的 relief_per_unit），
# 因此本表只校验活动时长与噪声；玩手机（phone）为本轮新增活动。
for prefix in ("music", "snack", "book", "phone"):
    check("P0-3 %s：时长为正" % prefix,
          math.isfinite(_leisure.get(prefix + "_duration", 0)) and _leisure.get(prefix + "_duration", 0) > 0)
    check("P0-3 %s：时长为整数、噪声非负" % prefix,
          _leisure[prefix + "_duration"] == int(_leisure[prefix + "_duration"])
          and math.isfinite(_leisure.get(prefix + "_noise", -1)) and _leisure.get(prefix + "_noise", -1) >= 0)
_acts_cfg = params("rules/activities.csv")
check("D02：每 10 秒减压为正", _acts_cfg.get("relief_per_unit", 0) > 0)
check("D02：单位时长与学习结算时长为正整数",
      _acts_cfg.get("unit_seconds", 0) > 0 and _acts_cfg.get("study_settle_seconds", 0) > 0
      and _acts_cfg.get("play_settle_seconds", 0) > 0)
check("D02：学习收益为正、游戏收益为负",
      _acts_cfg.get("study_gain", 0) > 0 and _acts_cfg.get("play_gain", 0) < 0)
_seed_books = load("characters/seeds.csv")
check("P0-3：课外书种子仅 0/1", all(r.get("book") in ("0", "1") for r in _seed_books))
_roster = {r["key"]: r["value"] for r in load("rules/roster.csv")}
_npc_count = int(float(_roster.get("npc_count", 0)))
check("P0-3：一局 NPC 数 = 角色池人数（16 人一一对应）",
      _npc_count > 0 and _npc_count == len(_seed_books), "%s vs 池 %d" % (_npc_count, len(_seed_books)))
_quota = _leisure.get("book_count", -1)
_available = sum(r.get("book") == "1" for r in _seed_books)
check("P0-3：持书配额可抽足（book_count 单值）",
      0 <= _quota <= _npc_count and int(_quota) == _quota and _quota <= _available
      and _npc_count - _quota <= len(_seed_books) - _available,
      "book_count=%s，持书者 %d" % (_quota, _available))
_seat_rel = params("rules/seat_relations.csv")
check("D04：座位基础好感增量为有限数",
      math.isfinite(_seat_rel.get("orthogonal_h", 0)) and math.isfinite(_seat_rel.get("far_h", 0)))
check("D04：对角邻座不加好感", _seat_rel.get("diagonal_h", -1) == 0)
check("D04：学习者对娱乐邻座的敌对增量为正且有限",
      math.isfinite(_seat_rel.get("study_play_hostility", 0))
      and _seat_rel.get("study_play_hostility", 0) > 0)
check("D04：睡觉视同学习标志仅 0/1", _seat_rel.get("sleep_as_study") in (0, 1))
_lprobs = {r["behavior"]: float(r["base_p"]) for r in load("rules/behavior_probs.csv")}
check("P0-3：四种行为概率存在且在 [0,1]", all(0 <= _lprobs.get(k, -1) <= 1 for k in ("music_p", "snack_p", "book_p", "phone_p")))
# P0-2/P3：巡查与没收参数定义；运行该校验仍遵从用户指令。
_teacher = params("rules/teacher.csv")
for _key in ("visit_check_first", "visit_check_second", "stay_ticks", "confiscate_books_per_catch"):
    _value = _teacher.get(_key, 0)
    check("老师：%s 正整数" % _key, math.isfinite(_value) and _value > 0 and int(_value) == _value)
for _key in ("visit_p", "suppress_behavior_mult", "volume_target_mult"):
    _value = _teacher.get(_key, -1)
    check("老师：%s 在 [0,1]" % _key, math.isfinite(_value) and 0 <= _value <= 1)
check("老师：巡查点按先后顺序且在课间内", 0 < _teacher["visit_check_first"] < _teacher["visit_check_second"]
      <= min(int(row["tick_count"]) for row in ph if row["kind"] == "break"))
check("老师：没收只收正在读的一本", _teacher["confiscate_books_per_catch"] == 1)


for key in ("study_speed_interval_seconds", "study_speed_step"):
    check("时间流速：学习提速参数 " + key + " 为有限正数",
          math.isfinite(_time_flow.get(key, 0.0)) and _time_flow.get(key, 0.0) > 0.0)
print("  通过 %d 项，失败 %d 项" % (PASSED[0], len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
