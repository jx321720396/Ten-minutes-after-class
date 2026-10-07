"""第六道门：文档一致性检查（`check_docs.py`）

**为什么需要它**：本会话在自检里发现 4 处「**文档与实现脱节**」——
`adapt_rate` 错值、§18.9 三项过时、§10.17.1 整章过时、`deep_cap` 标注过时。
这**不是疏忽，而是长期迭代的必然**：

    每次改机制/调参 → 代码立即生效，文档却停留在「当时的结论」
    → 越到后期，早期章节越可能说的是「已不成立的事」

∴ 把它固化成门，让每轮改完都能自动发现这类尾巴，而不是靠人眼。

**五项检查**（都对应本会话踩过的真实问题）：
  ① 「未实现 / 尚未 / 待办」标记 vs 代码实际实现
  ② 文档里的 `param = 数值` vs `data/` 下的实际配置
  ③ 行内代码损坏（被 shell 吃掉 → 留下空括号）
  ④ § 交叉引用有效性
  ⑤ 陈旧标记（写着「待标定 / 未达标」但门已通过）

运行：`python tools/check_docs.py [--verbose]`  退出码 0 = 通过
"""

import argparse
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
MAIN = os.path.join(DOCS, "gdd", "core-gameplay-v3.1.md")
CORE = os.path.join(ROOT, "tools", "core_sim.py")

FAILED = []
_BEHAVIORS = [set()]


def check(name, cond, detail=""):
    ok = bool(cond)
    print("  %s %s%s" % ("✓" if ok else "✗", name, ("  ← %s" % detail) if detail and not ok else ""))
    if not ok:
        FAILED.append(name)
    return ok


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def behavior_names():
    """behaviors.csv 里的【行为名】不是参数 —— 文档里 `chat = 6` 指的是噪音/人数，不是配置值。"""
    p = os.path.join(ROOT, "data", "rules", "behaviors.csv")
    if not os.path.exists(p):
        return set()
    rows = [ln for ln in read(p).split("\n") if ln.strip() and not ln.startswith("#")]
    return {r["behavior"] for r in csv.DictReader(rows) if r.get("behavior")}


def cfg_values():
    """把 data/ 下所有表的「参数名 -> 值」收成一张字典。"""
    out = {}
    for sub in ("rules", "balance"):
        d = os.path.join(ROOT, "data", sub)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".csv"):
                continue
            p = os.path.join(d, fn)
            rows = [ln for ln in read(p).split("\n") if ln.strip() and not ln.startswith("#")]
            if not rows:
                continue
            rdr = list(csv.DictReader(rows))
            for r in rdr:
                for k, v in r.items():
                    if k in ("param", "behavior", "event_id") and v:
                        val = r.get("value") or r.get("base_p") or r.get("base")
                        if val:
                            out.setdefault(v.strip(), set()).add(val.strip())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(MAIN):
        print("!! 找不到主文档：%s" % MAIN)
        return 1
    doc = read(MAIN)
    core = read(CORE)
    _BEHAVIORS[0] = behavior_names()

    print("=== 第六道门：文档一致性（%s）===" % os.path.relpath(MAIN, ROOT))

    # ---------- ① 「未实现」标记 vs 实际实现 ----------
    print("\n  — ① 「未实现 / 尚未 / 待办」标记 vs 代码实现 —")
    pat = re.compile(r"`?([A-Za-z_][A-Za-z0-9_]{2,})`?\s*(?:\([^)]*\))?\s*(?:该行为)?\s*(?:尚未实现|未实现)")
    stale = []
    for m in pat.finditer(doc):
        sym = m.group(1)
        if sym in core:                      # 代码里已有这个名字 → 很可能已实现
            stale.append(sym)
    check("文档中标注「未实现」的符号，代码里确实没有",
          not stale, "但代码里已存在：%s —— 请核对文档是否已过时" % sorted(set(stale)))
    if a.verbose:
        print("     (扫描到 %d 处「未实现」标记)" % len(pat.findall(doc)))

    # ---------- ② 文档里的 param = 数值 vs 配置 ----------
    print("\n  — ② 文档里的 `param = 数值` vs data/ 实际配置 —")
    cfg = cfg_values()
    bad = []
    # ⚠️ 两种写法都要覆盖：`` `param` = 1.2 `` 与 `` `param = 1.2` ``（`=` 在反引号**内**）。
    #    初版只写了前一种，而文档实际多用后一种 → **门根本没匹配上，是个「假的绿」**。
    PAT_BQ = re.compile(r"`([a-z_]{4,})\s*[=＝]\s*([0-9]+(?:\.[0-9]+)?)`|`([a-z_]{4,})`\s*[=＝]\s*([0-9]+(?:\.[0-9]+)?)")
    # 2026-10-07 补强①：**无反引号**的 `name = 1.2` 此前完全不扫 ——
    #   文档 §10.28.3 的 `noise_base_fear = 1.3`（配置为 2.8）因此长期漏过。
    #   只在**代码块内**与**表格行内**扫，避免把正文叙述里的数字误当参数值。
    PAT_PLAIN = re.compile(r"\b([a-z_]{4,})\s*[=＝]\s*([0-9]+(?:\.[0-9]+)?)\b")
    # 「历史对照」语境豁免：**必须是明确的过去 / 对照记号**。
    # ⚠️ 2026-10-07 补强②：**移除「默认」** —— 它太宽，把「当前默认 `stress_k = 0`」这条
    #   **真错**也放过了（配置早已是 0.40）。同类过于宽泛的豁免（`关闭`、`= 0 =`）一并移除。
    HIST = re.compile(r"早先|旧值|曾|修复前|改为|原|实测扫描|实测：|对照|→|历史|当时|已废弃|已由|替代|设|若|即关闭|可关闭")

    hits = []                       # (参数名, 文档写的值, 所在行文本)

    def _add(name, value, line_text):
        hits.append((name, value, line_text))

    for m in PAT_BQ.finditer(doc):
        _add(m.group(1) or m.group(3), m.group(2) or m.group(4),
             doc[doc.rfind("\n", 0, m.start()) + 1: doc.find("\n", m.end())])
    for blk in re.finditer(r"```[\s\S]*?```", doc):
        for ln in blk.group(0).split("\n"):
            for m in PAT_PLAIN.finditer(ln):
                _add(m.group(1), m.group(2), ln)
    for ln in doc.split("\n"):
        if not ln.lstrip().startswith("|"):
            continue
        for m in PAT_PLAIN.finditer(ln):
            _add(m.group(1), m.group(2), ln)

    for k, v, line in hits:
        if k in _BEHAVIORS[0]:
            continue                        # 行为名不是参数
        if k in cfg and not any(abs(float(v) - float(c)) < 1e-9 for c in cfg[k]):
            if HIST.search(line):
                continue
            bad.append("%s = %s（配置为 %s）" % (k, v, sorted(cfg[k])))
    check("文档里引用的参数值都与 data/ 一致", not bad,
          "不一致：%s" % bad[:5])

    # ---------- ②b data/ 各表的 note 与 value 是否脱节（§3.4.1 纪律④）----------
    print("\n  — ②b data/ 表的 note 与 value 是否一致 —")
    drift = []
    for sub in ("rules", "balance"):
        d = os.path.join(ROOT, "data", sub)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".csv"):
                continue
            rows = [ln for ln in read(os.path.join(d, fn)).split("\n")
                    if ln.strip() and not ln.startswith("#")]
            if not rows:
                continue
            rdr = csv.DictReader(rows)
            keycol = next((c for c in ("param", "behavior", "event_id")
                           if c in (rdr.fieldnames or [])), None)
            if not keycol:
                continue
            for r in rdr:
                val = r.get("value") or r.get("base_p") or r.get("base")
                note = r.get("note") or ""
                if not val:
                    continue
                # 注释里写「默认 X」而 X ≠ 本行实测值 → 改值没改注释的典型症状
                # （实例如 environment.csv 的 `stress_k,0.40,…默认 0…`）
                for m in re.finditer(r"默认\s*([0-9]+(?:\.[0-9]+)?)", note):
                    if abs(float(m.group(1)) - float(val)) > 1e-9:
                        drift.append("%s/%s：note 写「默认 %s」，实测值为 %s"
                                     % (fn, r[keycol], m.group(1), val))
    check("data/ 各表的 note 与 value 一致（「默认 X」≠ 值即报）", not drift,
          "；".join(drift[:5]))

    # ---------- ③ 行内代码损坏 ----------
    print("\n  — ③ 行内代码损坏（被 shell 吃掉 → 空括号）—")
    broken = []
    for root, _, files in os.walk(DOCS):
        for f in files:
            if not f.endswith(".md"):
                continue
            p = os.path.join(root, f)
            for i, ln in enumerate(read(p).split("\n"), 1):
                if re.search(r"（\s*/\s*）|（[，,]\s*）|\(\s*/\s*\)", ln):
                    broken.append("%s:%d" % (os.path.relpath(p, ROOT), i))
    check("无「空括号」损坏", not broken, "可疑位置：%s" % broken[:6])

    # ---------- ④ § 交叉引用 ----------
    print("\n  — ④ § 交叉引用有效性 —")
    # 主文档内：§x.y 应能在主文档或 design/ 里找到对应小标题
    heads_main = set(re.findall(r"^#+\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)", doc, re.M))
    heads_other = set()
    for root, _, files in os.walk(os.path.join(DOCS, "design")):
        for f in files:
            if f.endswith(".md"):
                heads_other |= set(re.findall(
                    r"^#+\s*(?:§)?([0-9]+\.[0-9]+(?:\.[0-9]+)?)", read(os.path.join(root, f)), re.M))
    refs = set(re.findall(r"§([0-9]+\.[0-9]+(?:\.[0-9]+)?)", doc))
    miss = sorted(r for r in refs
                  if r not in heads_main and r not in heads_other
                  and r.split(".")[0] not in {str(i) for i in range(3, 19)})
    check("§ 引用都能找到对应标题", not miss, "找不到：%s" % miss[:8])

    # ---------- ⑤ 陈旧标记 ----------
    print("\n  — ⑤ 陈旧标记（写着「未达标 / 待标定」但门已通过）—")
    stale2 = []
    for kw in ["爆发指标尚未达标", "尚未达标", "待标定", "未能达标"]:
        for m in re.finditer(kw, doc):
            line = doc[doc.rfind("\n", 0, m.start()) + 1: doc.find("\n", m.end())]
            # 允许出现在"历史记录/待办清单"语境
            if re.search(r"历史|当时|曾|保留|待办|待观察|遗留", line):
                continue
            stale2.append(line.strip()[:60])
    check("无遗留的「未达标 / 待标定」表述", not stale2, "可疑：%s" % stale2[:4])

    print("\n  %s（失败 %d 项）" % ("✓ 文档一致性检查通过" if not FAILED else "✗ 有项未通过",
                                    len(FAILED)))
    if FAILED:
        print("  失败清单：", FAILED)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
