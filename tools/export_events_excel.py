"""生成事件总表 Excel（基于代码实装）"""
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

wb = Workbook()

# ── 样式 ──
header_font = Font(bold=True, size=11, color="FFFFFF")
header_fill = PatternFill("solid", fgColor="4472C4")
section_fill = PatternFill("solid", fgColor="D9E2F3")
section_font = Font(bold=True, size=11)
thin_border = Border(
    left=Side(style="thin"),
    right=Side(style="thin"),
    top=Side(style="thin"),
    bottom=Side(style="thin"),
)
wrap_align = Alignment(wrap_text=True, vertical="top")


def style_header(ws, row, cols):
    for c in range(1, cols + 1):
        cell = ws.cell(row=row, column=c)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = thin_border


def style_section(ws, row, cols):
    for c in range(1, cols + 1):
        cell = ws.cell(row=row, column=c)
        cell.font = section_font
        cell.fill = section_fill
        cell.border = thin_border


def style_data(ws, row, cols):
    for c in range(1, cols + 1):
        cell = ws.cell(row=row, column=c)
        cell.alignment = wrap_align
        cell.border = thin_border


# ══════════════════════════════════════════════════════════════
# Sheet 1: 行为组件事件总表
# ══════════════════════════════════════════════════════════════
ws1 = wb.active
ws1.title = "行为组件事件"
headers1 = ["行为ID", "中文名", "触发概率", "前置条件", "判定公式", "耗时(tick)", "噪音", "流程", "加点（接受/正面）", "加点（拒绝/负面）"]
ws1.append(headers1)
style_header(ws1, 1, len(headers1))

data1 = [
    ["chat", "闲聊（含加入）",
     "base_p=0.06/tick\n相邻×1.5\n压力≥70时×0.5", "双方空闲、同空间；加入另需 A(i,j)≥30、我压力<80（软门槛）",
     "发起无判定；加入：score=A[j][i]+外向度修正，p=σ((score−43)/10)，对方压力≥12 压制 score；加入尝试 10 tick",
     30, 2,
     "① 双方标记 in_conversation\n② 互相占用时间槽（加入：全体成员与结束点对齐）\n③ 双向施加 topic_affinity/trust/stress\n④ 双向 observe 亲和\n⑤ 登记/并入活动会话",
     "双向: affinity+3, trust+3, stress−2", "加入被拒: affinity−3, hostility+3, stress+2 + observe"],

    ["tease", "当众调侃", "base_p=0.09/tick", "需≥3人围观(共同邻居)",
     "笑场档: A(i,j)≥55 且 H(i,j)<25\n嘲讽档: H(i,j)≥40 或 A(i,j)<25", 30, 3,
     "【笑场】双方+success_affinity, 围观者对j+affinity, 目标stress−2\n【嘲讽】目标+hostility/stress, 围观者站队判定\n  围观者A(k,j)≥55→站被调侃者\n  围观者H(k,j)≥40→附和嘲讽\n  围观者≥4人→升级羞辱(mark_hurt, 写深层敌意)",
     "笑场: 双方affinity+2, 目标stress−2", "嘲讽: 目标hostility+3, stress+3\n羞辱额外: hostility+4(深层)"],

    ["report", "举报", "base_p=0.10 × sigmoid(z)\n每段课间对有把柄候选掷骰",
     "H(i,j)≥40(sigmoid拐点)\nscale≥8\nwitness_window≤7天\n好友惩罚: A/100×1.5压低z\n信任惩罚: T/100×1.0压低z",
     "sigmoid: H(i,j)拐点40, scale=8", 40, 1,
     "① 目标获得 report_stress + report_hostility(对举报者)\n② mark_hurt(i,j) 记录伤害\n③ 举报者 hostility 降低",
     "目标: stress+5(major), hostility+5(major)", "—"],

    ["roughhouse", "追逐打闹", "base_p=0.05/tick", "发起者外向度E≥45\n旁观者人数≥2", "—", 50, 5,
     "① 双方互相+roughhouse_affinity\n② 所有旁观者对双方+roughhouse_hostility",
     "参与者双向: affinity+2", "旁观者: hostility+3(对参与者)"],

    ["exclude", "排挤", "base_p=0.06/tick", "近30天内有敌对行为\ncooldown≥7天\n≥3人集体(≥2人有重大敌对)", "—", 40, 1,
     "① 目标对发起者+exclude_stress+exclude_affinity\n② 目标对所有crowd成员−affinity\n③ 发起者对目标−affinity\n④ crowd成员各自对目标−affinity\n(双向好感下降)",
     "—", "目标: stress+5(major)\n双向: affinity−4(major)"],

    ["comfort", "安慰", "base_p=0.35/tick\n(高概率因命中条件极窄)",
     "目标stress≥70\n好感门槛: E≥50→≥50, E=0→≥70\n(线性插值)",
     "好感门槛 = 50 + (50−E)/50 × 20", 50, 1,
     "① 发起者付 comfort_cost_stress\n② 目标: stress−5, affinity+4, trust+5",
     "目标: stress−5(major), affinity+4(major), trust+5(major)", "发起者成本: stress+2"],


    ["apologize", "道歉和解", "base_p=0.05/tick",
     "真值H(i,j)≥30\n信念B_H(i,j)≥30\n(决策侧不得读对方真值)",
     "score = A[j][i] + F_j/100×20 − H[j][i]×0.5\np = sigmoid((score−40)/12)\nno_modulation=true(跳过关系调制)", 50, 1,
     "【接受】① 发起者付cost → ② 双向hostility−3(只消表层), affinity+3, trust+2, stress−3\n【拒绝】① 发起者付cost → ② hostility+2, stress+4(major), trust−3",
     "双向: hostility−3, affinity+3, trust+2, stress−3", "hostility+2, stress+4(major), trust−3\n(发起成本: stress+3)"],
]

for row_data in data1:
    ws1.append(row_data)
    style_data(ws1, ws1.max_row, len(headers1))

ws1.column_dimensions["A"].width = 14
ws1.column_dimensions["B"].width = 14
ws1.column_dimensions["C"].width = 22
ws1.column_dimensions["D"].width = 30
ws1.column_dimensions["E"].width = 30
ws1.column_dimensions["F"].width = 10
ws1.column_dimensions["G"].width = 8
ws1.column_dimensions["H"].width = 45
ws1.column_dimensions["I"].width = 35
ws1.column_dimensions["J"].width = 35

# ══════════════════════════════════════════════════════════════
# Sheet 2: 隐式行为
# ══════════════════════════════════════════════════════════════
ws2 = wb.create_sheet("隐式行为(sim_core)")
headers2 = ["行为ID", "中文名", "触发概率", "前置条件", "耗时(tick)", "流程", "加点"]
ws2.append(headers2)
style_header(ws2, 1, len(headers2))

data2 = [
    ["stress_burst", "压力爆发",
     "p = 0.5 × (stress−70)/(100−70)\n每日结算判定一次",
     "stress ≥ 70(进入高压区)", "—",
     "① stress骤降40\n② 生成heart_knot标签, 天数=3×(1+severity)\n③ 传染: 按|A−H|排序取关系最鲜明者\n   (spread_ratio=25%, spread_max=2)\n   severity放大天数和传染数",
     "即时: stress−40\n心结期: 每天stress+5, 持续3+天"],

    ["sleep", "睡觉",
     "base_p=0.03\nstress≥70时×1.5",
     "—", 100,
     "不参与任何交互\n课间结束时一次性stress−3",
     "stress−3"],

    ["study", "学习",
     "默认兜底行为\n无主行为且未走动时自动进入",
     "—", 0,
     "每天2次结算(上课段)\n每次stress+1",
     "stress+1/次"],

    ["move", "走动",
     "base_p=0.05\n每课间段开始判定一次",
     "—", 15,
     "位置更新, 产生噪音",
     "—"],

    ["pass_note", "传纸条",
     "base_p=0.0\n(闲聊触发后按判定改写, 无独立概率)",
     "闲聊中触发改写", 10,
     "闲聊的不可被加入版本(无声)",
     "同chat加点"],

    ["observe", "观察",
     "—",
     "玩家独有；靠近单人或活动圈", "≥ 10",
     "只读信息，零副作用\n单人 2 真值 + 1 信念（O ≥ 50 再多 1）\n群体对圈内每人各 1+1",
     "—"],

    ["share_secret", "秘密交换",
     "—",
     "双方信任≥60", 60,
     "守密超5tick→形成secret_alliance标签\n泄密→信任崩塌",
     "守密: 双方每日trust+1(7天)\n泄密: stress+5, trust−5, hostility+4"],
]

for row_data in data2:
    ws2.append(row_data)
    style_data(ws2, ws2.max_row, len(headers2))

ws2.column_dimensions["A"].width = 16
ws2.column_dimensions["B"].width = 14
ws2.column_dimensions["C"].width = 28
ws2.column_dimensions["D"].width = 28
ws2.column_dimensions["E"].width = 10
ws2.column_dimensions["F"].width = 45
ws2.column_dimensions["G"].width = 35

# ══════════════════════════════════════════════════════════════
# Sheet 3: 事件权重表 (w_events.csv 完整数据)
# ══════════════════════════════════════════════════════════════
ws3 = wb.create_sheet("事件权重表(w_events)")
headers3 = ["event_id", "axis", "base", "w_E", "w_S", "w_F", "w_J", "tier", "class", "note"]
ws3.append(headers3)
style_header(ws3, 1, len(headers3))

w_events = [
    ["tease_stress", "stress", 3, -0.3, 0, 0.5, 0, "normal", "E", "被当众调侃"],
    ["tease_hostility", "hostility", 3, 0, 0, 0.4, 0.2, "normal", "E", "被当众调侃"],
    ["tease_affinity", "affinity", -2, 0, 0, 0.3, 0, "normal", "E", "被当众调侃"],
    ["reject_stress", "stress", 2, 0.2, 0, 0.3, 0, "normal", "C", "被拒绝搭话"],
    ["reject_hostility", "hostility", 3, 0, 0, 0.2, 0.3, "normal", "C", "被拒绝搭话"],
    ["reject_affinity", "affinity", -3, 0, 0, 0.2, 0, "normal", "C", "被拒绝搭话"],
    ["report_stress", "stress", 5, 0, 0, 0.3, -0.4, "major", "B", "被举报"],
    ["report_hostility", "hostility", 5, 0, 0, 0.2, -0.3, "major", "B", "被举报"],
    ["comfort_target_stress", "stress", -5, 0.2, 0, 0.4, 0, "major", "A", "安慰:目标压力↓"],
    ["comfort_target_affinity", "affinity", 4, 0, 0, 0.3, 0, "major", "A", "安慰:目标好感↑"],
    ["comfort_target_trust", "trust", 5, 0, 0, 0.5, 0, "major", "A", "安慰:目标信任↑"],
    ["roughhouse_affinity", "affinity", 2, 0.3, 0, 0.2, 0, "normal", "A", "追逐打闹:参与者互好感↑"],
    ["conformity_hostility", "hostility", 3, 0, 0, 0.4, 0, "normal", "B", "从众:跟着敌视"],
    ["noise_hostility", "hostility", 3, 0, 0, 0.3, 0, "normal", "B", "音量:怕吵者敌视邻居"],
    ["roughhouse_hostility", "hostility", 3, 0.3, 0, 0, -0.3, "normal", "B", "追逐打闹:旁观者讨厌参与者"],
    ["exclude_stress", "stress", 5, 0, 0, 0.4, 0.2, "major", "B", "被排挤:压力↑"],
    ["exclude_affinity", "affinity", -4, 0, 0, 0.2, 0.3, "major", "B", "排挤:双向好感↓"],
    ["leak_stress", "stress", 5, 0, 0, 0.4, 0.2, "major", "B", "秘密泄露:压力↑"],
    ["leak_trust", "trust", -5, 0, 0, 0.3, 0.2, "major", "B", "秘密泄露:信任↓"],
    ["humiliate_hostility", "hostility", 4, -0.2, 0, 0.3, 0.2, "major", "B", "当众羞辱:写深层敌对"],
    ["leak_hostility", "hostility", 4, 0, 0, 0.2, 0, "major", "B", "秘密泄露:敌对↑"],
    ["tease_laugh_stress", "stress", -2, 0, 0, 0.3, 0, "normal", "E", "被逗笑(调侃正面)"],
    ["tease_success_affinity", "affinity", 2, 0, 0, 0.3, 0, "normal", "E", "调侃成功:双方+围观者"],
    ["topic_trust", "trust", 3, 0, 0.3, 0.2, 0, "normal", "A", "话题共鸣"],
    ["topic_affinity", "affinity", 3, 0.2, 0.2, 0, 0, "normal", "A", "话题共鸣"],
    ["topic_stress", "stress", -2, 0.3, 0, 0.2, 0, "normal", "A", "话题共鸣"],
    ["comfort_cost_stress", "stress", 2, 0.2, 0, 0.3, 0, "normal", "A", "安慰发起成本"],
    ["apologize_cost_stress", "stress", 3, 0, 0, 0.3, 0, "normal", "E", "道歉发起成本"],
    ["apologize_ok_hostility", "hostility", -3, 0, 0, 0.3, 0.2, "normal", "E", "道歉被接受:只消表层敌对"],
    ["apologize_ok_affinity", "affinity", 3, 0, 0, 0.3, 0, "normal", "E", "道歉被接受:好感回升(双向)"],
    ["apologize_ok_trust", "trust", 2, 0, 0, 0.2, 0, "normal", "E", "道歉被接受:信任回升(双向)"],
    ["apologize_ok_stress", "stress", -3, 0, 0, 0.3, 0, "normal", "E", "道歉被接受:双方松口气"],
    ["apologize_no_hostility", "hostility", 2, 0, 0, 0.3, 0.2, "normal", "E", "道歉被拒:敌对继续"],
    ["apologize_no_stress", "stress", 4, 0, 0, 0.4, 0.2, "major", "E", "道歉被拒:重大档"],
    ["apologize_no_trust", "trust", -3, 0, 0, 0.2, 0, "normal", "E", "道歉被拒:信任受损"],
]

for row_data in w_events:
    ws3.append(row_data)
    style_data(ws3, ws3.max_row, len(headers3))

ws3.column_dimensions["A"].width = 28
ws3.column_dimensions["B"].width = 10
ws3.column_dimensions["C"].width = 8
ws3.column_dimensions["D"].width = 8
ws3.column_dimensions["E"].width = 8
ws3.column_dimensions["F"].width = 8
ws3.column_dimensions["G"].width = 8
ws3.column_dimensions["H"].width = 10
ws3.column_dimensions["I"].width = 8
ws3.column_dimensions["J"].width = 28

# ══════════════════════════════════════════════════════════════
# Sheet 4: 状态标签
# ══════════════════════════════════════════════════════════════
ws4 = wb.create_sheet("状态标签")
headers4 = ["tag_id", "中文名", "持续天数", "每日stress", "每日trust", "触发条件", "spread_ratio", "spread_max", "说明"]
ws4.append(headers4)
style_header(ws4, 1, len(headers4))

tags = [
    ["heart_knot", "心结", 3, 5, 0, "压力爆发(stress≥90)", 0.25, 2, "崩溃有回声(3天, 每天+5); 传染给关系最鲜明者"],
    ["secret_alliance", "秘密同盟", 7, 0, 1, "守密超过5tick", 0, 0, "双方每日信任+1(7天为稳定上限)"],
]

for row_data in tags:
    ws4.append(row_data)
    style_data(ws4, ws4.max_row, len(headers4))

ws4.column_dimensions["A"].width = 18
ws4.column_dimensions["B"].width = 12
ws4.column_dimensions["C"].width = 10
ws4.column_dimensions["D"].width = 10
ws4.column_dimensions["E"].width = 10
ws4.column_dimensions["F"].width = 24
ws4.column_dimensions["G"].width = 12
ws4.column_dimensions["H"].width = 12
ws4.column_dimensions["I"].width = 40

# ══════════════════════════════════════════════════════════════
# Sheet 5: 阈值条件速查
# ══════════════════════════════════════════════════════════════
ws5 = wb.create_sheet("阈值条件速查")
headers5 = ["行为", "指标", "运算符", "阈值", "说明"]
ws5.append(headers5)
style_header(ws5, 1, len(headers5))

thresholds = [
    ["report", "hostility", ">=", 40, "举报: 敌对累积到阈值"],
    ["report", "scale", ">=", 8, "举报 sigmoid 坡度"],
    ["report", "witness_window", "<=", 7, "把柄有效期(天)"],
    ["report", "affinity_penalty", ">=", 1.5, "好友惩罚系数"],
    ["report", "trust_penalty", ">=", 1.0, "信任惩罚系数"],
    ["burst", "stress", ">=", 70, "压力爆发入口"],
    ["apologize_trigger", "hostility", ">=", 30, "道歉可发起最低敌对"],
    ["comfort_trigger", "target_stress", ">=", 70, "安慰目标压力门槛"],
    ["tease_laugh", "affinity", ">=", 55, "玩笑档: 好感下限"],
    ["tease_laugh", "hostility", "<", 25, "玩笑档: 敌对上限"],
    ["tease_taunt", "hostility", ">=", 40, "嘲讽档: 敌对下限"],
    ["tease_taunt", "affinity", "<", 25, "嘲讽档: 低好感触发"],
    ["chat", "join_affinity", ">=", 43, "搭话接纳 sigmoid 拐点"],
    ["chat", "join_scale", ">=", 10, "sigmoid 坡度"],
    ["chat", "join_stress_penalty", ">=", 12, "对方压力压制"],
    ["chat", "join_gate_affinity", ">=", 30, "决策侧软门槛"],
    ["chat", "join_gate_stress", ">=", 80, "决策侧软门槛"],
    ["humiliate", "bystanders", ">=", 4, "围观者≥4人升级羞辱"],
    ["tease_stand", "affinity", ">=", 55, "围观者站被调侃者"],
    ["tease_sneer", "hostility", ">=", 40, "围观者附和嘲讽"],
    ["roughhouse", "affinity", ">=", 45, "发起者外向度门槛"],
    ["roughhouse", "count", ">=", 2, "旁观者人数门槛"],
    ["exclude", "window", "<=", 30, "近期敌对窗口(天)"],
    ["exclude", "cooldown", ">=", 7, "同目标冷却(天)"],
    ["exclude", "count", ">=", 2, "集体人数门槛"],
    ["comfort_trigger", "affinity", ">=", 50, "安慰好感门槛(E≥50)"],
    ["comfort_trigger", "introvert_affinity", ">=", 70, "安慰好感门槛(E=0)"],
    ["apologize", "accept_scale", ">=", 12, "sigmoid 坡度"],
    ["apologize", "calm_bonus", ">=", 20, "对方随和系数"],
    ["apologize", "hostility_penalty", ">=", 0.5, "敌对压制系数"],
]

for row_data in thresholds:
    ws5.append(row_data)
    style_data(ws5, ws5.max_row, len(headers5))

ws5.column_dimensions["A"].width = 20
ws5.column_dimensions["B"].width = 20
ws5.column_dimensions["C"].width = 10
ws5.column_dimensions["D"].width = 10
ws5.column_dimensions["E"].width = 35

# ── 保存 ──
output_path = "D:/下课十分钟/tools/事件总表_代码实装.xlsx"
wb.save(output_path)
print(f"Excel saved: {output_path}")
