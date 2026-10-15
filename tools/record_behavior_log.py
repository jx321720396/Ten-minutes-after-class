#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""行为记录器：跑 Python 内核，逐条记录「谁在什么时候做了什么」，聊天按人数分类。

用途：离线诊断 —— 观察一局里所有发生的行为，尤其把聊天按人数（2 人 / 3 人 / …）
分开记录，而不是笼统记一个「聊天」。

设计原则（与 export_ticks.py 同源）：
  · **不复制内核逻辑** —— 只 hook 行为方法，在调用前后做只读快照 + 纯 Python 数据结构记录；
  · **不消耗内核 RNG** —— 记录过程不掷骰、不改矩阵，保同种子逐 tick 可复现；
  · 聊天人数靠「会话追踪器」重建：把每场 do_chat / do_chat_join 成功连出的 (i, j)
    视为一条连线，共享成员即并入同一场，到期收尾时记下该场最终人数（通用，支持 2/3/4… 人）。

用法：
    python tools/record_behavior_log.py --days 3 --seed 12345
    python tools/record_behavior_log.py --days 30 --seed 12345 --npc 16
    python tools/record_behavior_log.py --days 1 --seed 12345 --print-all   # 全部事件以文本打印

输出：
    · JSONL 事件流：tools/out/behavior_log_seed<seed>_npc<npc>_<days>d.jsonl
    · 汇总摘要：stdout + tools/out/behavior_log_..._summary.txt
"""

from __future__ import print_function

import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Windows 下 Python 默认 stdout 为 GBK，终端（Git Bash）是 UTF-8 —— 统一成 UTF-8 避免乱码。
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        try:
            _stream.reconfigure(encoding="utf-8")
        except Exception:
            pass

import core_sim  # noqa: E402  同目录内核原型

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

LEISURE_CN = {"listen_music": "听音乐", "eat_snack": "吃零食", "read_book": "看书"}
TEASE_CN = {"laugh": "玩笑", "taunt": "嘲讽", "awkward": "尴尬"}
NOTE_TONE_CN = {1: "好话", -1: "坏话"}


def name_of(sim, i):
    """节点 -> 显示名；玩家（末位）没有种子行，用固定名。"""
    if i is None:
        return None
    if i == sim.N - 1:
        return "玩家"
    return sim.chars[i]["alias"]


def names(sim, ids):
    return [name_of(sim, i) for i in ids]


class ChatSessionTracker:
    """重建「同一场聊天」的成员集合（通用，支持任意人数）。

    内核没有显式群组字段，聊天成员只能从「谁在同一时间窗口内被同一场
    do_chat / do_chat_join 联系起来」重建 —— 与内核 `_record_book_gift_chat`
    的「合并共享成员的同场闲聊」同一口径。凡连线共享成员就并入同一场；
    到期（end_tick <= now）即收尾，记下该场最终人数。不消耗 RNG、不写回矩阵。
    """

    def __init__(self):
        self._sessions = {}   # sid -> {"members": set, "end_tick": int}
        self._next = 1
        self.finished = []    # 每场结束时的成员（升序列表），用于按人数统计

    def add(self, members, end_tick):
        ms = set(int(m) for m in members if m is not None)
        if len(ms) < 2:
            return
        sids = [sid for sid, s in self._sessions.items() if ms & s["members"]]
        if sids:
            main = min(sids)
            merged = set(ms)
            for sid in sids:
                merged |= self._sessions[sid]["members"]
            self._sessions[main]["members"] = merged
            self._sessions[main]["end_tick"] = max(self._sessions[main]["end_tick"], end_tick)
            for sid in sids:
                if sid != main:
                    self._sessions.pop(sid, None)
        else:
            sid = self._next
            self._next += 1
            self._sessions[sid] = {"members": ms, "end_tick": int(end_tick)}

    def expire(self, now):
        due = [sid for sid, s in self._sessions.items() if s["end_tick"] <= now]
        for sid in sorted(due):
            self.finished.append(sorted(self._sessions.pop(sid)["members"]))

    def active(self):
        return {sid: {"members": sorted(s["members"]), "end_tick": s["end_tick"]}
                for sid, s in self._sessions.items()}


class Recorder:
    """hook 内核行为方法，把每次行为调用落成一条事件。"""

    def __init__(self, sim):
        self.sim = sim
        self.events = []
        self.sessions = ChatSessionTracker()
        self._join_depth = 0            # 是否正处在 do_chat_join 内部（用于去重）
        self._teacher_seen = 0          # 已采集的 teacher.events 条数
        self._book_gift_seen = 0        # 已采集的 book_gift_events 条数
        self._free_join_study = 0       # 跟随「学习」的次数（学习是默认态，逐节点不可见）

    # ------------------------------------------------------------- 基础设施
    def emit(self, kind, **fields):
        s = self.sim
        ev = {
            "tick": s.global_tick,
            "day": s.day,
            "phase": s.phase,
            "tick_in_phase": s.tick_in_phase,
            "kind": kind,
        }
        ev.update(fields)
        self.events.append(ev)

    def _wrap(self, name, handler):
        """通用包裹：handler(before_or_None, result, *args, **kwargs) 在调用后执行。"""
        orig = getattr(self.sim, name)

        def wrapped(*args, **kwargs):
            before = handler("before", None, None, *args, **kwargs)
            result = orig(*args, **kwargs)
            handler("after", before, result, *args, **kwargs)
            return result

        setattr(self.sim, name, wrapped)

    def wrap_all(self):
        s = self.sim
        self._wrap("do_chat", self._on_chat)
        self._wrap("do_chat_join", self._on_chat_join)
        self._wrap("do_report", self._on_report)
        self._wrap("do_tease", self._on_tease)
        self._wrap("do_exclude", self._on_exclude)
        self._wrap("do_roughhouse", self._on_roughhouse)
        self._wrap("do_comfort", self._on_comfort)
        self._wrap("do_apologize", self._on_apologize)
        self._wrap("do_study", self._on_study)
        self._wrap("do_sleep", self._on_sleep)
        self._wrap("do_observe", self._on_observe)
        self._wrap("do_pass_note", self._on_pass_note)
        self._wrap("start_leisure", self._on_leisure)
        self._wrap("free_join", self._on_free_join)
        self._wrap("roll_sleep", self._on_roll_sleep)
        self._wrap("try_burst", self._on_try_burst)
        self._wrap("tick", self._on_tick)

    # ------------------------------------------------------------- 各行为
    def _on_chat(self, phase, before, result, i, j):
        if phase == "before":
            # 先清过期会话再登记，与内核 _settle_book_gifts 的「到期即移除」同口径：
            # 只合并「时间上重叠且共享成员」的聊天，避免把跨时间的同一个人误并成多人。
            self.sessions.expire(self.sim.global_tick)
            return self.sim.stats.get("chats", 0)
        s = self.sim
        # 目标=玩家时被邀请系统拦截（`@invitation_behavior`）：函数体没跑、没占用、
        # stats["chats"] 不变 —— 那不是一场真正发生的聊天，不能记会话、不能记发起。
        if s.stats.get("chats", 0) <= before:
            return None
        # 会话结束 = 自然到期（busy_until）与「被铃声打断」（相位末）取更早者。
        # 内核 check_interrupt 在相位末把未完成的占用清零，故聊天不会跨相位存活；
        # 若直接取 busy_until，会把「上一段被打断的人又在下一段开新聊天」误并成多人。
        end = min(max(s.busy_until[i], s.busy_until[j]), self._phase_end_tick())
        # do_chat_join 成功后会内部再调 do_chat —— 那次只登记会话，不再另记「发起」事件。
        if self._join_depth == 0:
            self.emit("chat", actor=i, target=j,
                      actor_name=name_of(s, i), target_name=name_of(s, j),
                      action="start")
        self.sessions.add([i, j], end)

    def _on_chat_join(self, phase, before, result, i, j, roll=None):
        if phase == "before":
            self._join_depth += 1   # 进入 do_chat_join：其内部 do_chat 只登记会话、不另记「发起」
            return (self.sim.stats.get("join_accepts", 0),
                    self.sim.stats.get("join_rejects", 0))
        self._join_depth -= 1
        s = self.sim
        acc_before, rej_before = before
        accepted = s.stats.get("join_accepts", 0) > acc_before
        rejected = s.stats.get("join_rejects", 0) > rej_before
        if accepted:
            outcome = "accepted"
        elif rejected:
            outcome = "rejected"
        else:
            # 目标=玩家：被邀请系统拦截，等待玩家选择，尚未有结果。
            outcome = "player_pending"
        self.emit("chat_join", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j),
                  outcome=outcome)

    def _on_report(self, phase, before, result, i, j):
        if phase == "before":
            return None
        s = self.sim
        self.emit("report", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j))

    def _on_tease(self, phase, before, result, i, j, audience):
        if phase == "before":
            return self._tease_tier(i, j)
        s = self.sim
        self.emit("tease", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j),
                  audience=names(s, audience), audience_size=len(audience),
                  tier=before, tier_cn=TEASE_CN.get(before, before))

    def _on_exclude(self, phase, before, result, i, j, crowd):
        if phase == "before":
            return None
        s = self.sim
        self.emit("exclude", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j),
                  crowd=names(s, crowd), crowd_size=len(crowd))

    def _on_roughhouse(self, phase, before, result, i, j, bystanders):
        if phase == "before":
            return None
        s = self.sim
        self.emit("roughhouse", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j),
                  bystanders=names(s, bystanders), bystander_size=len(bystanders))

    def _on_comfort(self, phase, before, result, i, j):
        if phase == "before":
            return None
        s = self.sim
        self.emit("comfort", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j))

    def _on_apologize(self, phase, before, result, i, j):
        if phase == "before":
            return (self.sim.stats.get("apologizes", 0),
                    self.sim.stats.get("apologize_rejects", 0))
        s = self.sim
        acc_before, rej_before = before
        accepted = s.stats.get("apologizes", 0) > acc_before
        rejected = s.stats.get("apologize_rejects", 0) > rej_before
        self.emit("apologize", actor=i, target=j,
                  actor_name=name_of(s, i), target_name=name_of(s, j),
                  outcome="accepted" if accepted else ("rejected" if rejected else "n/a"))

    def _on_study(self, phase, before, result, i):
        if phase == "before":
            return None
        self.emit("study", actor=i, actor_name=name_of(self.sim, i))

    def _on_sleep(self, phase, before, result, i):
        if phase == "before":
            return None
        self.emit("sleep", actor=i, actor_name=name_of(self.sim, i), source="player")

    def _on_observe(self, phase, before, result, me, j):
        if phase == "before":
            return None
        s = self.sim
        self.emit("observe", actor=me, target=j,
                  actor_name=name_of(s, me), target_name=name_of(s, j))

    def _on_pass_note(self, phase, before, result, i, j):
        if phase == "before":
            return None
        s = self.sim
        note = s.notes[-1] if s.notes else None
        fields = {"actor": i, "target": j,
                  "actor_name": name_of(s, i), "target_name": name_of(s, j)}
        if note:
            fields.update({
                "note_id": note["id"],
                "about": name_of(s, note["target"]),          # 被说者 X
                "tone": "positive" if note["tone"] > 0 else "negative",
                "tone_cn": NOTE_TONE_CN.get(note["tone"], str(note["tone"])),
                "template": note["tpl"],
            })
        self.emit("pass_note", **fields)

    def _on_leisure(self, phase, before, result, i, kind):
        if phase == "before":
            return None
        self.emit("leisure", actor=i, actor_name=name_of(self.sim, i),
                  leisure_kind=kind, leisure_cn=LEISURE_CN.get(kind, kind),
                  started=bool(result))

    def _on_free_join(self, phase, before, result):
        if phase == "before":
            return list(self.sim.sleeping)
        s = self.sim
        before_sleep = before
        for i in range(s.N):
            if s.sleeping[i] and not before_sleep[i]:
                self.emit("free_join", actor=i, actor_name=name_of(s, i), followed="sleep")

    def _on_roll_sleep(self, phase, before, result):
        if phase == "before":
            return list(self.sim.sleeping)
        s = self.sim
        before_sleep = before
        for i in range(s.N):
            if s.sleeping[i] and not before_sleep[i]:
                self.emit("sleep", actor=i, actor_name=name_of(s, i), source="npc_random")

    def _on_try_burst(self, phase, before, result):
        if phase == "before":
            return list(self.sim.knot_days)
        s = self.sim
        before_knot = before
        for i in range(s.N):
            if s.knot_days[i] > before_knot[i]:
                self.emit("burst", actor=i, actor_name=name_of(s, i),
                          stress=round(s.Stress[i], 1), knot_days=s.knot_days[i])

    def _on_tick(self, phase, before, result):
        if phase == "before":
            return None
        s = self.sim
        # 会话到期收尾（记录该场聊天最终人数）
        self.sessions.expire(s.global_tick)
        # 老师巡查事件增量
        te = s.teacher.events
        while self._teacher_seen < len(te):
            self.emit("teacher", **self._teacher_fields(te[self._teacher_seen]))
            self._teacher_seen += 1
        # 赠书事件增量
        bg = s.book_gift_events
        while self._book_gift_seen < len(bg):
            ev = bg[self._book_gift_seen]
            self._book_gift_seen += 1
            self.emit("book_gift", donor=ev["donor"], recipient=ev["recipient"],
                      donor_name=name_of(s, ev["donor"]),
                      recipient_name=name_of(s, ev["recipient"]),
                      books=ev["books"], first=ev["first"])

    # ------------------------------------------------------------- 判定（只读）
    def _phase_end_tick(self):
        """当前相位最后一个 tick（铃声打断点）。

        `tick_in_phase` 在 tick() 之后才自增，行为调用发生时它等于「本段已完成的 tick 数」，
        故 `dur - tick_in_phase` 是本段剩余 tick（含当前 tick），最后一个 tick = 当前 + 剩余 − 1。
        """
        s = self.sim
        dur = s.day_phases[s.phase_index][1]
        return s.global_tick + (dur - s.tick_in_phase) - 1

    def _tease_tier(self, i, j):
        th = self.sim.thresholds_lookup
        a, h = self.sim.A[i][j], self.sim.H[i][j]
        if a >= th["tease_laugh_affinity"] and h < th["tease_laugh_hostility"]:
            return "laugh"
        if h >= th["tease_taunt_hostility"] or a < th["tease_taunt_affinity"]:
            return "taunt"
        return "awkward"

    def _teacher_fields(self, ev):
        out = {"event": ev.get("kind")}
        if "i" in ev:
            out["actor"] = ev["i"]
            out["actor_name"] = name_of(self.sim, ev["i"])
        for k in ("amount", "books", "confiscated_books"):
            if k in ev:
                out[k] = ev[k]
        return out


# ------------------------------------------------------------- 人类可读行
def human_line(ev):
    """把一条事件转成一行中文描述。"""
    t = "D%-2d %-5s t=%-4d" % (ev["day"], ev["phase"], ev["tick"])
    k = ev["kind"]
    a = ev.get("actor_name", "?")
    j = ev.get("target_name", "")
    if k == "chat":
        return "%s  %s 发起闲聊 与 %s" % (t, a, j)
    if k == "chat_join":
        o = {"accepted": "接受", "rejected": "被拒"}.get(ev["outcome"], "等待玩家回应")
        return "%s  %s 搭话 %s —— %s" % (t, a, j, o)
    if k == "tease":
        return "%s  %s 当众调侃 %s（%s，围观 %d 人：%s）" % (
            t, a, j, ev["tier_cn"], ev["audience_size"], "、".join(ev["audience"]))
    if k == "report":
        return "%s  %s 举报 %s" % (t, a, j)
    if k == "exclude":
        return "%s  %s 排挤 %s（%d 人：%s）" % (t, a, j, ev["crowd_size"], "、".join(ev["crowd"]))
    if k == "roughhouse":
        return "%s  %s 与 %s 追逐打闹（吵到 %s）" % (t, a, j, "、".join(ev["bystanders"]))
    if k == "comfort":
        return "%s  %s 安慰 %s" % (t, a, j)
    if k == "apologize":
        return "%s  %s 向 %s 道歉 —— %s" % (t, a, j,
                                            "接受" if ev["outcome"] == "accepted" else "被拒")
    if k == "study":
        return "%s  %s 坐下学习" % (t, a)
    if k == "sleep":
        return "%s  %s 睡觉（%s）" % (t, a, ev.get("source", ""))
    if k == "observe":
        return "%s  %s 观察 %s" % (t, a, j)
    if k == "pass_note":
        return "%s  %s 传纸条给 %s（说 %s 的%s，模板%d）" % (
            t, a, j, ev.get("about"), ev.get("tone_cn"), ev.get("template", 0))
    if k == "leisure":
        return "%s  %s %s" % (t, a, ev.get("leisure_cn", ev.get("leisure_kind")))
    if k == "free_join":
        return "%s  %s 从众跟随：%s" % (t, a, ev.get("followed"))
    if k == "teacher":
        e = ev.get("event")
        if e == "teacher_arrived":
            return "%s  【老师】进班巡查" % t
        if e == "teacher_left":
            return "%s  【老师】离开" % t
        if e == "teacher_caught":
            return "%s  【老师】抓到 %s 违纪" % (t, ev.get("actor_name"))
        if e == "book_confiscated":
            return "%s  【老师】没收 %s 的书 %d 本" % (t, ev.get("actor_name"), ev.get("amount", 0))
        if e == "book_confiscation_exempted":
            return "%s  【老师】免罚 %s（用免罚券）" % (t, ev.get("actor_name"))
        return "%s  【老师】%s" % (t, e)
    if k == "burst":
        return "%s  %s 压力爆发（压力 %.1f，心结 %d 天）" % (
            t, a, ev.get("stress", 0), ev.get("knot_days", 0))
    if k == "book_gift":
        return "%s  %s 把书赠给 %s（现 %d 本%s）" % (
            t, ev.get("donor_name"), ev.get("recipient_name"), ev.get("books", 0),
            "，第一本" if ev.get("first") else "")
    return "%s  %s  %s" % (t, a, k)


def summarize(sim, rec):
    """按行为类型 + 聊天人数做汇总。"""
    cnt = collections.Counter(e["kind"] for e in rec.events)
    lines = []
    add = lines.append

    add("=== 行为汇总（seed=%d，天数=%d，节点=%d）===" % (sim.seed, sim.day - 1, sim.N))
    add("")
    add("总行为事件：%d 条" % len(rec.events))
    add("")

    # 聊天按人数（会话追踪器）
    size_cnt = collections.Counter(len(m) for m in rec.sessions.finished)
    chat_total = sum(size_cnt.values())
    add("—— 聊天（按人数分开）——")
    if chat_total == 0:
        add("  （本局没有形成任何一场聊天）")
    for size in sorted(size_cnt):
        add("  %d 人聊天：%d 场" % (size, size_cnt[size]))
    join_accepts = sum(1 for e in rec.events
                       if e["kind"] == "chat_join" and e["outcome"] == "accepted")
    join_rejects = sum(1 for e in rec.events
                       if e["kind"] == "chat_join" and e["outcome"] == "rejected")
    join_pending = sum(1 for e in rec.events
                       if e["kind"] == "chat_join" and e["outcome"] == "player_pending")
    add("  其中（发起方式）：")
    add("    发起闲聊（chat）        ：%d 次" % cnt["chat"])
    add("    搭话（chat_join）总次数 ：%d 次" % cnt.get("chat_join", 0))
    add("      ├ 接受：%d 次" % join_accepts)
    add("      ├ 被拒：%d 次" % join_rejects)
    add("      └ 等待玩家回应：%d 次" % join_pending)
    add("")

    add("—— 其余行为（按类型）——")
    for k in sorted(cnt):
        if k in ("chat", "chat_join"):
            continue
        add("  %-14s：%d 次" % (k, cnt[k]))
    add("")

    # 细分：调侃档位 / 道歉结果
    tease_tiers = collections.Counter(
        e["tier"] for e in rec.events if e["kind"] == "tease")
    if tease_tiers:
        add("—— 调侃档位 ——")
        for tier in ("laugh", "taunt", "awkward"):
            if tease_tiers.get(tier):
                add("  %-6s（%s）：%d 次" % (tier, TEASE_CN[tier], tease_tiers[tier]))
        add("")

    return "\n".join(lines)


def run(seed, npc, days):
    sim = core_sim.Sim(seed=seed, npc_count=npc)
    rec = Recorder(sim)
    rec.wrap_all()
    for _ in range(days):
        sim.run_day()
    rec.sessions.expire(10 ** 9)   # 收尾所有（含模拟结束时仍在进行的聊天）
    return sim, rec


def main(argv=None):
    p = argparse.ArgumentParser(description="行为记录器：跑内核，逐条记录行为，聊天按人数分类")
    p.add_argument("--days", type=int, default=3)
    p.add_argument("--seed", type=int, default=12345)
    p.add_argument("--npc", type=int, default=16)
    p.add_argument("--out", default=None, help="JSONL 输出（默认 tools/out/behavior_log_*.jsonl）")
    p.add_argument("--print-all", action="store_true", help="把全部事件以文本打印到 stdout")
    args = p.parse_args(argv)

    out = args.out or os.path.join(
        OUT_DIR, "behavior_log_seed%d_npc%d_%dd.jsonl" % (args.seed, args.npc, args.days))

    sim, rec = run(args.seed, args.npc, args.days)

    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        for ev in rec.events:
            f.write(json.dumps(ev, ensure_ascii=False, sort_keys=True) + "\n")

    summary = summarize(sim, rec)
    print(summary)
    print("事件流：%s（%d 条）" % (out, len(rec.events)))
    print("")

    if args.print_all:
        print("=== 全部事件（按发生顺序）===")
        for ev in rec.events:
            print("  " + human_line(ev))
    else:
        print("=== 事件样例（前 40 条）===")
        for ev in rec.events[:40]:
            print("  " + human_line(ev))
        if len(rec.events) > 40:
            print("  … 共 %d 条，用 --print-all 看全部" % len(rec.events))

    # 摘要落盘
    summary_path = out.rsplit(".", 1)[0] + "_summary.txt"
    with open(summary_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(summary + "\n")
        f.write("事件流：%s（%d 条）\n" % (out, len(rec.events)))
        f.write("\n=== 全部事件 ===\n")
        for ev in rec.events:
            f.write(human_line(ev) + "\n")
    print("")
    print("摘要已写入：%s" % summary_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
