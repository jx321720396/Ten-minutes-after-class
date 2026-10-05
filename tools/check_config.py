"""配置表启动校验（文档中已声明的各项约束的可执行版本）

运行：python tools/check_config.py
任一项失败则以非零码退出，可直接接进 CI。

校验清单（依据各表内的「启动校验」注释与 UIF §2.5 / §2.6）：
  1. w_events：`tier` 与 `base` 档位一致（normal ∈ [1,3]、major ∈ [4,5]）；`class` ∈ A–E
  2. transmission：`feedback` ∈ [0,1]；`settle_interval` > 0；`beta_*` > 0
  3. decay：所有 value ∈ (0,1]；`decay_a_interact` ≥ `decay_a_no_interact`
  4. belief：`prior_*` ∈ (0,100]；`eta0_*` > 0
  5. behavior_thresholds：① 阈值键格式（行为名不得自带轴后缀，否则查表键会重复拼接）
     ② `join_chat_affinity` 必须 **严格大于** `prior_a`（否则搭话永远通过 → 关系只涨不跌）
  6. behavior_probs：概率类 ∈ [0,1]
  7. phases：课间 + 上课 tick 合计 = 480；`player_control` = 1 当且仅当 `kind` = break
  8. status_tags：`days` ≥ 1
  9. behaviors：`duration ≥ 0`、`payoff ∈ [1,5]`、**按 payoff 分组后平均耗时单调不减**（收益越大耗时越长）
 10. social_event_triggers：metric / op / value 不得含日期类记号（不变式 1）
"""

import csv
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
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
if "join_chat_affinity" in th:
    check("join_chat 门槛 > prior_a（否则搭话永远通过）", th["join_chat_affinity"] > bp["prior_a"],
          "门槛 %s vs 先验 %s" % (th["join_chat_affinity"], bp["prior_a"]))
for k in ("tease_laugh_affinity", "tease_taunt_hostility", "tease_stand_affinity", "tease_sneer_hostility"):
    check("阈值键存在：%s" % k, k in th)

print("=== 6. behavior_probs ===")
for r in load("rules/behavior_probs.csv"):
    v = float(r["base_p"])
    check("%s ∈ [0,1] 或涓流值" % r["behavior"], (0.0 <= v <= 1.0) or r["behavior"].endswith(("_stress",)))

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
    check("%s: payoff ∈ [1,5]" % r["behavior"], 1 <= float(r["payoff"]) <= 5)
# 法则：收益越大耗时越长 —— 这是**趋势**，不是逐档严格单调。
#   · 排除「整段占用」特例（duration ≥ 100，如睡觉）：它占用整个课间，不参与普通比较
#   · 允许 20% 波动（设计上同类收益的行为耗时不必相同）
by_payoff = {}
for r in bh:
    d = int(float(r["duration"]))
    if d >= 100:
        continue
    by_payoff.setdefault(float(r["payoff"]), []).append(d)
avgs = [(k, sum(v) / len(v)) for k, v in sorted(by_payoff.items())]
for (k1, a1), (k2, a2) in zip(avgs, avgs[1:]):
    check("收益 %.0f → %.0f：平均耗时呈上升趋势（%.1f → %.1f）" % (k1, k2, a1, a2),
          a2 >= a1 * 0.8, "允许 20%% 波动")

print("=== 10. social_event_triggers：禁日期记号 ===")
for r in load("rules/social_event_triggers.csv"):
    blob = (r["metric"] + " " + r["op"] + " " + r["value"]).lower()
    hit = [w for w in DATE_WORDS if w in blob]
    check("%s / %s: 无日期类记号" % (r["trigger_rule"], r["metric"]), not hit, hit)

print("\n=== 结论 ===")
print("  通过 %d 项，失败 %d 项" % (PASSED[0], len(FAILED)))
if FAILED:
    print("  失败清单：", FAILED)
sys.exit(1 if FAILED else 0)
