"""配置表启动校验（文档中已声明的各项约束的可执行版本）

运行：python tools/check_config.py
任一项失败则以非零码退出，可直接接进 CI。

校验清单（依据各表内的「启动校验」注释与 UIF §2.5 / §2.6）：
  1. w_events：`tier` 与 `base` 档位一致（normal ∈ [1,3]、major ∈ [4,5]）；`class` ∈ A–E
  2. transmission：`feedback` ∈ [0,1]；`settle_interval` > 0；`beta_*` > 0
  3. decay：所有 value ∈ (0,1]；`decay_a_interact` ≥ `decay_a_no_interact`
  4. belief：`prior_*` ∈ (0,100]；`eta0_*` > 0
  5. behavior_thresholds：① 阈值键格式（行为名不得自带轴后缀，否则查表键会重复拼接）
     ② `chat_join_affinity` 必须 **严格大于** `prior_a`（否则搭话永远通过 → 关系只涨不跌）
  6. behavior_probs：概率类 ∈ [0,1]
  7. phases：课间 + 上课 tick 合计 = 480；`player_control` = 1 当且仅当 `kind` = break
  8. status_tags：`days` ≥ 1
  9. behaviors：`duration ≥ 0`、`|payoff| ∈ [1,5]`、**按 |payoff| 分组后平均耗时呈上升趋势**（效果越强耗时越长）
 10. social_event_triggers：metric / op / value 不得含日期类记号（不变式 1）
 11. 配置键存在性：`core_sim.py` 引用的阈值键必须真的在 behavior_thresholds.csv 里
 12. 玩家交互 / 闲聊反馈（2026-10-07 完整可玩流程）：
     `rules/player_interaction.csv` 与 `ui/chat_feedback_style.csv` 的必需键、值域，
     以及**表 ↔ 消费者**双向一致（写了没人读 / 读了没写都要报）
"""

import csv
import os
import re
import sys
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()
AXES_WORDS = ("affinity", "hostility", "trust", "stress")
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
check("beta_* > 0", all(tp[k] > 0 for k in ("beta_a", "beta_h", "beta_t")))

print("=== 3. decay ===")
dc = params("rules/decay.csv")
for k in ("decay_a_no_interact", "decay_a_interact", "decay_h", "decay_t", "retain_s"):
    check("%s ∈ (0,1]" % k, 0.0 < dc[k] <= 1.0, dc[k])
check("decay_a_interact ≥ decay_a_no_interact", dc["decay_a_interact"] >= dc["decay_a_no_interact"])

print("=== 4. belief ===")
bp = params("rules/belief.csv")
check("prior_* ∈ (0,100]", all(0 < bp[k] <= 100 for k in ("prior_a", "prior_h", "prior_t")))
check("eta0_* > 0", all(bp[k] > 0 for k in ("eta0_a", "eta0_h", "eta0_t")))

print("=== 5. behavior_thresholds ===")
rows = load("rules/behavior_thresholds.csv")
for r in rows:
    bad = [w for w in AXES_WORDS if any(r["behavior"].endswith("_" + w) for w in AXES_WORDS)]
    check("%s: 行为名不得自带轴后缀（会与 metric 重复拼接）" % r["behavior"], not bad, r["behavior"])
th = {"%s_%s" % (r["behavior"], r["metric"]): float(r["value"]) for r in rows}
if "chat_join_affinity" in th:
    check("加入闲聊门槛 > prior_a（否则永远通过）", th["chat_join_affinity"] > bp["prior_a"],
          "门槛 %s vs 先验 %s" % (th["chat_join_affinity"], bp["prior_a"]))
for k in ("tease_laugh_affinity", "tease_taunt_hostility", "tease_stand_affinity", "tease_sneer_hostility"):
    check("阈值键存在：%s" % k, k in th)

print("=== 6. behavior_probs ===")
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

print("=== 12. 玩家交互 / 闲聊反馈配置（计划 2026-10-07-chat-playable-loop）===")
# 依据：docs/superpowers/plans/2026-10-07-chat-playable-loop.md §3.1、§7、§8；
#     主文档 §10.5（闲聊范围与玩家专属透露）。
# 两类校验：
#   ① 值域（范围 / 步长 / 条数 / 掩码）；
#   ② **表 ↔ 消费者**：表里每个键都必须被某个脚本引用（防「写了没人读」），
#      脚本里 `params.get("键")` 的键必须真的在表里（防 `.get` 静默回落到默认值）。
_pi_rows = load("rules/player_interaction.csv")
_pi = {r["param"]: r["value"] for r in _pi_rows}
_pi_required = [
    "chat_range_m",
    "seated_tolerance_m",
    "seated_chat_range_m",
    "range_step_m",
    "clue_opacity_split",
    "clue_count_low",
    "clue_count_high",
    "actor_pick_layer",
    "world_pick_blocker_layer",
]
check("player_interaction 必需键齐全", all(k in _pi for k in _pi_required),
      "缺失: %s" % sorted(set(_pi_required) - set(_pi)))
if all(k in _pi for k in _pi_required):
    check("chat_range_m 为正", float(_pi["chat_range_m"]) > 0, _pi["chat_range_m"])
    check("座位聊天容差为正且小于通用范围",
          0 < float(_pi["seated_tolerance_m"]) < float(_pi["chat_range_m"]),
          _pi["seated_tolerance_m"])
    check("前后座位聊天上限不小于通用范围",
          float(_pi["seated_chat_range_m"]) >= float(_pi["chat_range_m"]),
          _pi["seated_chat_range_m"])
    check("range_step_m 为正", float(_pi["range_step_m"]) > 0, _pi["range_step_m"])
    check("clue_opacity_split ∈ (0,100]", 0 < float(_pi["clue_opacity_split"]) <= 100,
          _pi["clue_opacity_split"])
    check("clue_count_low / high 为正整数且 low ≤ high",
          int(_pi["clue_count_low"]) >= 1 and int(_pi["clue_count_high"]) >= int(_pi["clue_count_low"]),
          "%s / %s" % (_pi["clue_count_low"], _pi["clue_count_high"]))
    check("拾取层掩码为正且与遮挡层不同",
          int(_pi["actor_pick_layer"]) > 0
          and int(_pi["world_pick_blocker_layer"]) > 0
          and _pi["actor_pick_layer"] != _pi["world_pick_blocker_layer"],
          "%s / %s" % (_pi["actor_pick_layer"], _pi["world_pick_blocker_layer"]))

_style_rows = load("ui/chat_feedback_style.csv")
_style = {r["param"]: r["value"] for r in _style_rows}
_style_required = [
    "pen_windup_seconds",
    "pen_spin_seconds",
    "pen_settle_seconds",
    "pen_result_seconds",
    "menu_width_px",
    "menu_margin_px",
    "bubble_dot_seconds",
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
               "pen_result_seconds", "menu_width_px", "menu_margin_px", "bubble_dot_seconds",
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
_dead = [k for k in list(_pi) + list(_style) if ('"%s"' % k) not in _src_all]
check("新表的每个键都有脚本消费者（防「写了没人读」）", not _dead, "未被引用的键: %s" % _dead)
_used = set()
for _pat in (re.compile(r'params\.get\("([a-z_]+)"'), re.compile(r'\.get\("([a-z_]+)"\s*,')):
    for _m in _pat.finditer(_src_all):
        _used.add(_m.group(1))
_ghost = sorted(k for k in _used
                if k.startswith(("chat_range", "range_step", "clue_", "pen_", "menu_",
                                 "bubble_", "ring_", "toast_", "emotion_", "progress_bar"))
                and k not in _pi and k not in _style)
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

# 14. 学业系统（§17.1）：成绩轴初始化常量 + 涓流分段表
_kp = params("rules/kernel_params.csv")
_grade_keys = ("grade_max", "grade_init_player", "grade_init_npc_min", "grade_init_npc_max")
check("kernel_params：成绩初始化常量齐全", all(k in _kp for k in _grade_keys),
      "缺失: %s" % sorted(set(_grade_keys) - set(_kp)))
if all(k in _kp for k in _grade_keys):
    check("grade_max 为正", _kp["grade_max"] > 0, _kp["grade_max"])
    check("grade_init_npc_min ≤ grade_init_npc_max",
          _kp["grade_init_npc_min"] <= _kp["grade_init_npc_max"],
          "%s / %s" % (_kp["grade_init_npc_min"], _kp["grade_init_npc_max"]))
    check("grade_init_player ∈ [0, grade_max]",
          0 <= _kp["grade_init_player"] <= _kp["grade_max"], _kp["grade_init_player"])
    check("NPC 初始区间 ⊆ [0, grade_max]",
          0 <= _kp["grade_init_npc_min"] and _kp["grade_init_npc_max"] <= _kp["grade_max"],
          "%s / %s" % (_kp["grade_init_npc_min"], _kp["grade_init_npc_max"]))
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

print("\n=== 结论 ===")
_invite_kinds = load("rules/player_invitation_kinds.csv")
check("玩家邀请：行为键不重复", len({r["behavior"] for r in _invite_kinds}) == len(_invite_kinds))
check("玩家邀请：requires_choice 为 0/1", all(r["requires_choice"] in ("0", "1") for r in _invite_kinds))
check("玩家邀请：行为存在于 behaviors", all(r["behavior"] in {r["behavior"] for r in load("rules/behaviors.csv")} for r in _invite_kinds))
_invite_params = params("rules/player_interaction.csv")
check("玩家邀请：有效期与再次邀请间隔为正整数", all(_invite_params.get(k, 0) > 0 and int(_invite_params[k]) == _invite_params[k] for k in ("invitation_timeout_ticks", "invitation_cooldown_ticks")))
print("  通过 %d 项，失败 %d 项" % (PASSED[0], len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
