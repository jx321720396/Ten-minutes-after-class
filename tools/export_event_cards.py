# -*- coding: utf-8 -*-
"""生成《行为事件表》（标准格式 + 现状预填 + 待填写列）。

用法：
    python tools/export_event_cards.py

输出：
    docs/design/行为事件表.xlsx

现状来源（2026-10-09 仓库快照，只读参考，数值一律以 data/ 为准）：
    · data/rules/behaviors.csv            行为主表（kind / duration / payoff / noise / join_mode）
    · data/balance/w_events.csv           事件权重表（每条效果的轴 / 档位 / 性格敏感度）
    · data/rules/behavior_probs.csv       环境类行为的每 tick 概率与涓流
    · data/rules/behavior_thresholds.csv  阈值类与判定侧门槛
    · data/rules/player_interaction.csv   玩家交互几何与线索参数
    · data/rules/movement.csv             移动速度与几何容差
    · data/rules/seats.csv                座位表（4x4 + 讲桌旁）
    · data/rules/phases.csv               相位定义（时长 / 启用规则 / 玩家权限）
    · data/rules/time_flow.csv            世界倍率（玩家占用 3x）
    · data/rules/time_runtime.csv         学期长度等运行时参数
    · docs/gdd/v4/ 拆分版主文档（§8 人物行为 = 08 / §9 人物设计 = 09 / §10 玩家操作 = 10 / §11 社会事件 = 11 / §14 工程规范 = 14）
    · scripts/systems/behaviors/*.gd      行为组件（结算点与顺序）
    · scripts/core/sim_core.gd            内核入口与占用 / 会话 / 涓流

本脚本只写文档产物，不改任何玩法代码与配置。
"""

import csv
import os

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "design", "行为事件表.xlsx")

# ── 样式 ──
HEADER_FONT = Font(bold=True, size=11, color="FFFFFF")
HEADER_FILL = PatternFill("solid", fgColor="4472C4")
TITLE_FONT = Font(bold=True, size=14)
NOTE_FONT = Font(size=9, color="7F7F7F")
SECTION_FONT = Font(bold=True, size=11)
SECTION_FILL = PatternFill("solid", fgColor="D9E2F3")
LEAD_FILL = PatternFill("solid", fgColor="F2F2F2")
FILL_IN = PatternFill("solid", fgColor="FFF7E0")
LABEL_FILL = PatternFill("solid", fgColor="EDEDED")
BORDER = Border(
    left=Side(style="thin"),
    right=Side(style="thin"),
    top=Side(style="thin"),
    bottom=Side(style="thin"),
)
WRAP = Alignment(wrap_text=True, vertical="top")
CENTER = Alignment(horizontal="center", vertical="center")


def load_table(rel_path):
    """读 data/ 下的 csv：跳过 # 注释行，返回 (表头, 行字典列表)。"""
    path = os.path.join(ROOT, rel_path)
    if not os.path.exists(path):
        return [], []
    with open(path, "r", encoding="utf-8") as fh:
        lines = [
            line.rstrip("\r\n")
            for line in fh
            if line.strip() and not line.lstrip().startswith("#")
        ]
    reader = csv.DictReader(lines)
    return reader.fieldnames or [], [dict(row) for row in reader]


def new_sheet(wb, title, widths):
    ws = wb.create_sheet(title)
    for index, width in enumerate(widths):
        ws.column_dimensions[chr(ord("A") + index)].width = width
    return ws


def write_header_row(ws, row, headers):
    for col, text in enumerate(headers, start=1):
        cell = ws.cell(row=row, column=col, value=text)
        cell.font = HEADER_FONT
        cell.fill = HEADER_FILL
        cell.alignment = CENTER
        cell.border = BORDER


def write_row(ws, row, values, fills=None, bold=False):
    for col, text in enumerate(values, start=1):
        cell = ws.cell(row=row, column=col, value=text)
        cell.alignment = WRAP
        cell.border = BORDER
        if bold:
            cell.font = Font(bold=True)
        if fills and col in fills:
            cell.fill = fills[col]


def write_block_title(ws, row, text, cols):
    cell = ws.cell(row=row, column=1, value=text)
    cell.font = SECTION_FONT
    cell.fill = SECTION_FILL
    cell.border = BORDER
    for col in range(2, cols + 1):
        side = ws.cell(row=row, column=col)
        side.fill = SECTION_FILL
        side.border = BORDER


# ══════════════════════════════════════════════════════════════════════
# 标准字段清单：所有事件卡共用同一套维度（缺失字段填「（未记录）」）
# ══════════════════════════════════════════════════════════════════════
SECTIONS = [
    ("① 标识", [
        "行为 ID", "事件名", "层级类型", "数值分类（A–E）", "定义版本／状态",
        "规则来源", "实现位置",
    ]),
    ("② 类型与用途", ["kind", "行为用途", "收益档 payoff"]),
    ("③ 发起与参与", [
        "发起方式", "允许阶段", "发起者", "目标", "人数范围", "加入／退出规则（join_mode）",
    ]),
    ("④ 前置条件与位置", [
        "状态条件", "允许区域／交互点", "姿态要求", "距离／遮挡／相邻规则",
        "执行中需持续满足的条件", "条件不满足时",
    ]),
    ("⑤ 判定与确认", [
        "决策侧（做不做）", "判定侧（成不成）", "玩家确认", "判定读值（信念／真值）",
        "拒绝／超时分支",
    ]),
    ("⑥ 时间与资源", [
        "duration（tick）", "接近／准备耗时", "执行结束条件", "时间不够时", "时间倍率",
        "资源／次数／冷却",
    ]),
    ("⑦ 移动与占用", ["移动模式", "占用对象", "允许并发行为", "噪音 noise"]),
    ("⑧ 加减点", [
        "效果清单（w_events）", "方向与对象", "计算方式", "结算时机", "结算次数",
        "中断后处理",
    ]),
    ("⑨ 信息反馈", ["玩家获得的信息", "可见范围", "来源／可靠程度", "提示／日志／动画"]),
    ("⑩ 具体流程", [
        "请求", "校验", "接近", "准备", "确认／判定", "执行", "结算与反馈", "释放占用",
    ]),
    ("⑪ 取消与中断", [
        "无法开始", "拒绝／超时", "玩家取消", "目标离开", "外部事件打断", "阶段结束",
    ]),
    ("⑫ 收尾与清理", ["释放移动锁", "释放占用／会话", "资源预留与返还", "倍率覆盖"]),
    ("⑬ 验收", [
        "正常路径", "失败与边界路径", "重复请求／通知去重", "同种子可复现", "检验一",
    ]),
]

# 所有事件共用的现状（事件卡未单独填写时使用）
DEFAULTS = {
    "同种子可复现": (
        "是：随机数一律走带种子的 RNG（内核 _rng / context.random()），无全局隐式随机。",
        "§14.7",
    ),
    "检验一": (
        "是：规则是 f(性格四维, 透明度, 当前状态/关系) 的纯函数，不按角色名 / 角色 ID / 天数分支。",
        "§9.11；AGENTS.md 硬性约束 1",
    ),
    "中断后处理": (
        "现状：效果在行为执行点一次性施加，已结算部分不因中断回滚；无「按有效进度结算」。",
        "scripts/systems/behaviors/*.gd",
    ),
    "倍率覆盖": (
        "现状：行为本身不申请正常速度锁（request_normal_speed 只由特殊事件调用）。",
        "time_flow.gd",
    ),
}


def F(field, current, source=""):
    return (field, current, source)


# ══════════════════════════════════════════════════════════════════════
# 事件卡数据：现状全部取自 2026-10-09 仓库快照
# ══════════════════════════════════════════════════════════════════════
EVENTS = [
    {
        "id": "study",
        "name": "学习",
        "status": "已实现（默认状态）",
        "ov": {
            "实现状态": "已实现（默认状态；Godot 内核 _doing_study ＋ 上课段 study_together）",
            "位置姿态（现状）": "无要求：任何位置、任何姿态都算学习",
            "时间倍率（现状）": "1×（不算占用，不触发玩家三倍速）",
            "触发／门槛（现状）": "自动：无主行为且未走动即进入（study=1.0）",
            "主要效果": "study_stress(+1/次, 每天 2 次)、alone_stress(−2/次)",
        },
        "hints": {
            "允许区域／交互点": "候选 A（现状）：不限位置，任何地方都算学习。候选 B：必须在「允许学习的座位/书桌交互点」（座位归属按 seats.csv 判定）才算学习。",
            "姿态要求": "候选 A（现状）：无姿态要求。候选 B：必须已坐下；站姿或正在走动不计入学习。",
            "执行中需持续满足的条件": "候选 A（现状）：只要不忙、未走动即为学习，不校验位置。候选 B：持续满足「在允许座位 + 已坐下 + 未移动 + 未参加其他活动」；离开座位或开始走路即退出学习。",
            "条件不满足时": "候选 A（现状）：无此分支（不忙即学习）。候选 B：退出学习态——成绩累积（§17.1.2）停止，且不再享受老师巡查的学习豁免（§17.2.3）。",
            "执行": "口径 A 下「不忙即学习」直接驱动成绩累加器 study_acc；口径 B 下累加仅在座位 + 坐姿条件成立时进行（§17.1.2）。",
            "时间倍率": "注意：现行默认学习不触发玩家三倍速（TimeFlow 只在玩家 is_busy 时用 3×）。若口径 B 把学习变成「主动任务」，需同时裁定它是否算占用、是否三倍速。",
        },
        "notes": {
            "允许区域／交互点": "该口径连锁影响三处：成绩累积、老师巡查豁免名单、压力涓流 study_stress —— 请一并确认。",
            "姿态要求": "口径 B 需要内核有「姿态」事实；若暂无，须先补内核状态（表现层姿态不得代替，§8.8 注记同一原则）。",
        },
        "f": [
            F("层级类型", "默认状态（kind=default）：非行为、不进 current_act", "behaviors.csv"),
            F("数值分类（A–E）", "A 纯增益型（共同学习）＋涓流压力", "§8.16"),
            F("定义版本／状态", "已实现（Python 内核与 Godot 内核均按默认状态处理）",
              "sim_core.gd `_doing_study`"),
            F("规则来源", "主文档 §8.15、§10.2、§2.3；behaviors.csv study 行；behavior_probs.csv study / study_stress",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/core/sim_core.gd `_doing_study`；phases.csv 上课段 active_rules=study_together|rumor|stress_drip|transmission；无独立行为组件",
              "scripts / data"),
            F("行为用途", "兜底状态：不占时间槽，占满所有不忙时间；本作不设「什么都不做」", "§10.2 duration 语义"),
            F("发起方式", "自动（无主行为、未走动、未睡觉即进入）；玩家不选即学习", "behavior_probs.csv study=1.0"),
            F("允许阶段", "全部相位；上课段以 study_together 继续跑", "phases.csv"),
            F("发起者", "每个角色各自进入（含玩家）", ""),
            F("目标", "无（共同学习的目标是相邻座位，不是人）", "§8.15.5"),
            F("人数范围", "1；共同学习按「相邻两人都在学习」成对结算", "§2.3、§8.15.5"),
            F("状态条件", "清醒、不忙（tick ≥ busy_until）、未走动、未参加其他活动", "§8.15.4、§8.21.3"),
            F("允许区域／交互点", "未限定：现状任何位置都可算学习（无座位／书桌要求）",
              "代码现状；2026-10-09 指出需改"),
            F("姿态要求", "无（不要求坐姿、不要求坐在自己座位）", "代码现状"),
            F("距离／遮挡／相邻规则", "共同学习只认座位邻接（8 邻域；seats.csv 4x4 + 讲桌旁）", "seats.csv、§9.1"),
            F("决策侧（做不做）", "无需：不做任何主行为即为学习", "behavior_probs.csv study=1.0"),
            F("判定侧（成不成）", "无需", ""),
            F("玩家确认", "不需要", ""),
            F("duration（tick）", "0（不占用时间槽；不等于零时间收益）", "behaviors.csv duration=0"),
            F("执行结束条件", "出现主行为／走动／睡觉／相位切换", "§8.15.4"),
            F("时间倍率", "现状 1×：TimeFlow 只在「玩家可控 ＋ 玩家 is_busy」时用 player_action_scale=3；默认学习不算占用，故不加速",
              "time_flow.gd refresh()、time_flow.csv"),
            F("移动模式", "原地（不校验是否在座位）", ""),
            F("允许并发行为", "窃听（已关闭、未启用）", "§8.9"),
            F("噪音 noise", "1（注意：behaviors.csv 表头注释称「安静行为一律为 0」，此处现值 1，需核对）",
              "behaviors.csv noise=1"),
            F("效果清单（w_events）", "study_stress（压力 +1/次）；alone_stress（独处 −2/次）；共同学习走 §2.3 上课发酵",
              "behavior_probs.csv"),
            F("方向与对象", "本人 → 自身压力 +1；独处时 自身压力 −2", "behavior_probs.csv"),
            F("计算方式", "涓流结算（每天 2 次），非每 tick", "behavior_probs.csv study_stress 注释"),
            F("结算时机", "涓流结算点（每天 2 次）", "behavior_probs.csv"),
            F("结算次数", "每天 2 次，与行为次数无关", "behavior_probs.csv"),
            F("玩家获得的信息", "无", ""),
            F("可见范围", "无", ""),
            F("来源／可靠程度", "无", ""),
            F("提示／日志／动画", "底部状态提示显示当前活动与剩余时间", "§10.1"),
            F("请求", "无请求：不忙即在学习", ""),
            F("校验", "仅在共同学习时做座位邻接校验", "§8.15.5"),
            F("接近", "无（现状不要求先走到座位）", ""),
            F("准备", "无", ""),
            F("确认／判定", "无", ""),
            F("执行", "持续累计有效学习时间（现状不校验位置，等价于「不忙就是在学」）", "代码现状"),
            F("结算与反馈", "每天 2 次涓流压力 +1", "behavior_probs.csv"),
            F("释放占用", "无占用可释放", ""),
            F("无法开始", "无", ""),
            F("玩家取消", "发起任何主行为即结束学习", "§8.15.4"),
            F("目标离开", "不适用", ""),
            F("外部事件打断", "相位切换后进入上课段，学习继续（study_together）", "phases.csv"),
            F("释放移动锁", "无（学习不锁移动）", ""),
            F("释放占用／会话", "无", ""),
            F("资源预留与返还", "无", ""),
            F("正常路径", "不忙即学习，每天 2 次压力 +1；相邻双方都在学则跑共同学习", "behavior_probs.csv、§2.3"),
            F("失败与边界路径", "位置／姿态条件未实现，无法验证「坐着才算学」；这是本次要改的点",
              "2026-10-09 指出"),
        ],
    },
    {
        "id": "eavesdrop",
        "name": "窃听",
        "status": "未启用（不在任何版本排期）",
        "ov": {
            "实现状态": "未启用：behavior_probs eavesdrop=0.0，§14.9 明确不纳入任何版本",
            "位置姿态（现状）": "未定义（规格留存）",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "原值 1.0 语义为「未做主行为即必触发」，已置 0 关闭",
            "主要效果": "（无现行效果行）",
        },
        "f": [
            F("层级类型", "附加行为（kind=passive，不占时间槽）", "behaviors.csv"),
            F("数值分类（A–E）", "D 信任／透明度驱动型（规格）", "§8.16"),
            F("定义版本／状态", "未启用：§8.9 ⛔ 本节规格仅留存，重启前须先补流言记忆模型", "§8.9、§14.9"),
            F("规则来源", "主文档 §8.9；behaviors.csv eavesdrop 行；behavior_probs.csv eavesdrop",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "无实现（上游缺「流言记忆」与「范围判定」两个结构）", "§8.9"),
            F("行为用途", "捕获自身范围内所有人的闲聊内容，把流言存入记忆（规格）", "§8.9"),
            F("发起方式", "被动：本课间未进行任何主行为时生效（规格）", "§8.9"),
            F("允许阶段", "课间（规格）", "§8.9"),
            F("发起者", "自己（规格）", ""),
            F("目标", "范围内正在闲聊的人（规格）", ""),
            F("人数范围", "1 → 多人（规格）", ""),
            F("状态条件", "未有主行为、清醒、未移动（规格）", "§8.9"),
            F("允许区域／交互点", "未定义（缺范围判定结构）", "§8.9"),
            F("决策侧（做不做）", "规格：无判定，未做主行为即生效；现值 0.0 = 关闭", "behavior_probs.csv"),
            F("判定侧（成不成）", "规格：无", ""),
            F("duration（tick）", "0（并行行为，不占时间槽）", "behaviors.csv"),
            F("时间倍率", "1×", ""),
            F("移动模式", "原地（规格）", ""),
            F("占用对象", "无", ""),
            F("允许并发行为", "不做任何主行为时生效（规格）", "§8.9"),
            F("效果清单（w_events）", "（无现行效果行）", "w_events.csv"),
            F("玩家获得的信息", "规格：可能听到别人的流言", "§8.9"),
            F("提示／日志／动画", "无", ""),
            F("请求", "无（被动生效）", ""),
            F("执行", "规格：捕获范围内闲聊内容", "§8.9"),
            F("无法开始", "概率为 0.0，永不开始", "behavior_probs.csv"),
            F("正常路径", "无（未启用）", "§14.9"),
            F("失败与边界路径", "若按原值 1.0 接线，会让全班无条件互相窃听", "behavior_probs.csv 注释"),
        ],
    },
    {
        "id": "rumor",
        "name": "流言",
        "status": "部分实现（即时染色已通；记忆／纸条／遗忘未落地）",
        "ov": {
            "实现状态": "部分实现：rumor_behavior.gd 已通即时染色；§8.9 指出流言记忆模型尚未落地",
            "位置姿态（现状）": "无要求（现状不校验距离与姿态）",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "rumor_p=0.03 / tick；方向判定 H(i,j) > A(i,j) → 负面",
            "主要效果": "rumor_hostility(H+3)、rumor_stress(stress+3)、tease_hostility(H+3)",
        },
        "f": [
            F("层级类型", "附加行为（kind=env，环境类固定概率 × 修正）", "behaviors.csv"),
            F("数值分类（A–E）", "B 纯损害型（负面染色）", "§8.16"),
            F("定义版本／状态", "部分实现：即时染色已通；记忆携带、纸条传递、三个课间遗忘未落地", "§8.1、§8.9"),
            F("规则来源", "主文档 §8.1、§8.6；behaviors.csv rumor 行；behavior_probs.csv rumor_p",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/rumor_behavior.gd；内核入口 `_do_rumor`",
              "scripts/core/sim_core.gd"),
            F("行为用途", "把关于某人的闲话散出去：即时改变听到者对传播者的敌对，并让全场二手观测",
              "rumor_behavior.gd"),
            F("发起方式", "NPC 自主（环境类概率）；玩家主动（菜单「传流言」）", "§10.2.2"),
            F("允许阶段", "课间；上课段 active_rules 含 rumor（上课仍跑流言）", "phases.csv"),
            F("发起者", "掌握话的人（i）", ""),
            F("目标", "被说的对象（j）", ""),
            F("人数范围", "2（传播者＋对象）；旁观者只做二手观测", "rumor_behavior.gd"),
            F("状态条件", "规格要求「手中含流言」；现状未接流言记忆，故未校验持有", "§8.1、§8.9"),
            F("允许区域／交互点", "未限定（现状不校验距离与遮挡）", "rumor_behavior.gd"),
            F("姿态要求", "无", ""),
            F("决策侧（做不做）", "环境类：p = base_p(0.03) × 修正", "behavior_probs.csv"),
            F("判定侧（成不成）", "方向判定：H(i,j) > A(i,j) → 负面（当前实现口径）", "rumor_behavior.gd"),
            F("判定读值（信念／真值）", "读真值 H(i,j) / A(i,j)", "rumor_behavior.gd"),
            F("duration（tick）", "10（一句话的量）", "behaviors.csv"),
            F("时间倍率", "1×（玩家占用时按全局 3×）", "time_flow.csv"),
            F("占用对象", "发起者与目标（occupy 由内核入口处理）", "sim_core.gd"),
            F("噪音 noise", "1（低声，但计入环境音量）", "behaviors.csv"),
            F("效果清单（w_events）", "rumor_hostility、rumor_stress，负面时另加 tease_hostility",
              "w_events.csv"),
            F("方向与对象", "j → i 的敌对 +3；负面时 i → j 的敌对 +3 与 i 自身压力 +3", "rumor_behavior.gd"),
            F("结算时机", "执行点一次性施加（apply_event 在 set_in_conversation 之后立即调用）",
              "rumor_behavior.gd"),
            F("结算次数", "每次执行每有向边 1 次；旁观者 observe 走观察层，不重复加点", "rumor_behavior.gd"),
            F("玩家获得的信息", "规格：听到关于某人的话（带可靠程度与来源）", "§7.4"),
            F("可见范围", "全场其他节点二手观测 j 的敌对（observe，带噪声）", "rumor_behavior.gd"),
            F("来源／可靠程度", "二手，可能失真（观察层噪声）", "§7.4、§9.11"),
            F("提示／日志／动画", "event_happened(kind=rumor)", "rumor_behavior.gd"),
            F("请求", "无显式请求阶段（概率命中即执行）", ""),
            F("校验", "现状仅有占用与相位校验", "sim_core.gd"),
            F("执行", "施加 rumor_hostility；负面时再施加 rumor_stress 与 tease_hostility；全场 observe",
              "rumor_behavior.gd"),
            F("结算与反馈", "同执行阶段（一次性）；emit event_happened", "rumor_behavior.gd"),
            F("释放占用", "占用随 busy_until 自然到期", "sim_core.gd"),
            F("无法开始", "概率未命中、或发起者忙／在睡", "behavior_probs.csv"),
            F("正常路径", "每 tick 3% 命中，负面分支同时给双方敌对", "behavior_probs.csv"),
            F("失败与边界路径", "同一人重复被传、流言条目去重、记忆三课间遗忘：现状均未实现", "§8.1"),
        ],
    },
    {
        "id": "join_chat",
        "name": "搭话／加入闲聊",
        "status": "已实现（兼容别名；玩法已并入 chat）",
        "ov": {
            "实现状态": "已实现：旧路径保留为兼容别名，玩家侧新入口是 chat + mode=join",
            "位置姿态（现状）": "需在闲聊范围内、双方停止移动（can_chat_in_space）",
            "时间倍率（现状）": "1×（成功接上一场 chat 后按 chat 占用算）",
            "触发／门槛（现状）": "决策侧软门槛 A(i,j)≥30 / 压力 <80；判定 p=sigmoid((A[j][i]+外向加成−43)/10)",
            "主要效果": "成功＝按 chat 结算；被拒＝reject_affinity(−3)/reject_hostility(+3)/reject_stress(+2)",
        },
        "f": [
            F("层级类型", "意向类（kind=intent，门槛 → 意向评分 → softmax）", "behaviors.csv"),
            F("数值分类（A–E）", "C 信念驱动型（决策读信念、判定读真值）", "§8.16"),
            F("定义版本／状态", "已实现；§8.7：不再是独立玩法，只是 chat 的加入方式，配置与旧路径暂留兼容",
              "§8.7、§8.21"),
            F("规则来源", "主文档 §8.5、§8.7、§8.21；behaviors.csv join_chat 行；behavior_thresholds.csv join_chat.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/join_chat_behavior.gd（旧路径 ＋ options.mode=group 群聊编排）",
              "scripts/core/sim_core.gd `_do_join_chat`"),
            F("行为用途", "请求加入他人正在进行的闲聊（成功即并入同一会话，不另开一场）",
              "chat_behavior.gd、join_chat_behavior.gd"),
            F("发起方式", "NPC 自主选择／玩家菜单「加入」；玩家侧标识 kind=chat、mode=join", "§8.5"),
            F("允许阶段", "课间（player_control=1）", "phases.csv"),
            F("发起者", "请求加入者（i）", ""),
            F("目标", "原会话中的一位成员（j），成员表由内核给出", "join_chat_behavior.gd"),
            F("人数范围", "≥2；群聊编排下与全体原成员各建一条新关系边", "join_chat_behavior.gd"),
            F("状态条件", "i 空闲、未睡觉、未移动；原闲聊会话有效", "can_chat_in_space"),
            F("允许区域／交互点", "双方须在闲聊范围内（普通 1.2 m；同列前后相邻座位 1.8 m）",
              "player_interaction.csv"),
            F("姿态要求", "现状不要求坐姿；但要求双方停止移动（is_moving=false）", "behavior_context.gd"),
            F("距离／遮挡／相邻规则", "chat_range_m=1.2 / seated_chat_range_m=1.8 / seated_tolerance_m=0.1 / range_step_m=0.1",
              "player_interaction.csv"),
            F("执行中需持续满足的条件", "会话有效、双方仍在占用期内（会话结束点后延不缩短）", "join_chat_behavior.gd"),
            F("条件不满足时", "直接 return，不结算、不占用（不进入拒绝分支）", "join_chat_behavior.gd"),
            F("决策侧（做不做）", "软门槛：我对他好感 ≥30、我压力 <80（gate_scale=8、gate_weight=4）",
              "behavior_thresholds.csv"),
            F("判定侧（成不成）", "p = sigmoid((A[j][i] + E_j/100×? − 43)/10)，对方压力 ≥12 时压制 score",
              "behavior_thresholds.csv join_chat.*"),
            F("玩家确认", "NPC 请求加入含玩家的会话：先显示接受／拒绝邀请，玩家接受后不再掷接受骰",
              "§10.1、player_invitation_kinds.csv"),
            F("判定读值（信念／真值）", "判定读真值 A[j][i]；决策侧读信念与自身状态", "§4.4、§8.16 C 类"),
            F("拒绝／超时分支", "拒绝：请求者获 reject_affinity/hostility/stress 三轴反噬 ＋ observe；邀请超时 12 tick 不自动接受",
              "join_chat_behavior.gd、player_interaction.csv"),
            F("duration（tick）", "10（加入尝试本身；成功后的持续聊天按 chat 的 30 tick 计）", "behaviors.csv"),
            F("执行结束条件", "成功＝并入原会话，结束点取 max(原 end_tick, 当前 tick+chat.duration)",
              "join_chat_behavior.gd"),
            F("时间倍率", "1×（走路与接近不加速；玩家进入占用后按全局 3×）", "time_flow.csv"),
            F("占用对象", "旧路径：i、j；群聊：全体成员与共同结束点对齐", "join_chat_behavior.gd"),
            F("允许并发行为", "无（会话期间不得另发行为）", ""),
            F("噪音 noise", "2（与 chat 同档）", "behaviors.csv"),
            F("效果清单（w_events）", "成功走 topic_affinity/topic_trust/topic_stress；被拒走 reject_affinity/reject_hostility/reject_stress",
              "w_events.csv"),
            F("方向与对象", "成功：新成员与每位原成员各建双向 topic_affinity/topic_trust；减压只对发起者一次；被拒：i→各原成员敌对 +3、i→j 好感 −3、i 自身压力 +2",
              "join_chat_behavior.gd"),
            F("结算次数", "每条新关系边 1 次；原成员之间不重算；压力不按人数重复扣", "join_chat_behavior.gd"),
            F("玩家获得的信息", "接受后与闲聊同源；拒绝只给出发起方反馈", "§8.5"),
            F("可见范围", "绿圈 / 红圈由表现层按加入判定结果绘制（内核只给判定）", "§8.21.4"),
            F("提示／日志／动画", "event_happened(kind=chat, mode=join, accepted, session_id)", "join_chat_behavior.gd"),
            F("请求", "玩家点「加入」或 NPC 命中概率", "§8.5"),
            F("校验", "can_chat_in_space：双方未移动且在闲聊范围内", "behavior_context.gd"),
            F("确认／判定", "一次判定（加入只有一次接受判定，roll 由调用方预掷一次）", "join_chat_behavior.gd"),
            F("执行", "接受 → 与每位原成员结算新边、并入会话、全体占用对齐；拒绝 → 三轴反噬且不占用请求者",
              "join_chat_behavior.gd"),
            F("结算与反馈", "同执行阶段；表现层只收一条加入结果，不因多边弹多次反馈", "join_chat_behavior.gd"),
            F("释放占用", "拒绝不占用请求者；接受随共同结束点释放", "join_chat_behavior.gd"),
            F("无法开始", "范围/移动校验失败、原会话失效、请求者忙或睡觉", "behavior_context.gd"),
            F("拒绝／超时", "拒绝＝reject 三轴；邀请超时（12 tick）＝失效，不算主动拒绝、无处罚", "player_interaction.csv"),
            F("玩家取消", "现状：加入失败不阻止玩家移动或另发交互", "join_chat_behavior.gd"),
            F("目标离开", "范围校验在下一次交互前重新判定", "behavior_context.gd"),
            F("外部事件打断", "相位切换／上课归位前先完成到期活动、中断未完成聊天", "§8.4"),
            F("阶段结束", "随 busy_until 与会话结束点结束", "sim_core.gd"),
            F("释放移动锁", "拒绝不锁移动；接受期间参与会话占用", "join_chat_behavior.gd"),
            F("释放占用／会话", "会话只登记一次（begin_or_join），结束点只后延不缩短", "join_chat_behavior.gd"),
            F("正常路径", "范围内、空闲、通过判定 → 并入原会话，共享结束点", "join_chat_behavior.gd"),
            F("失败与边界路径", "被拒不得占用请求者；多人加入不得让减压重复结算", "join_chat_behavior.gd 注释"),
            F("重复请求／通知去重", "同一场活动只登记一次；表现层一条反馈对应一次判定", "join_chat_behavior.gd"),
        ],
    },
    {
        "id": "pass_note",
        "name": "传纸条",
        "status": "已合并（不再是独立行为）",
        "ov": {
            "实现状态": "已合并入流言：配置行保留（join_mode=accept），无独立组件",
            "位置姿态（现状）": "同闲聊范围（作为闲聊的私密传递方式）",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "无独立基础概率（pass_note=0.0）：闲聊触发后按判定改写",
            "主要效果": "同 chat 加点；不可被窃听、不可被搭话",
        },
        "f": [
            F("层级类型", "附加行为（kind=env）；2026-10-06 定稿后已并入流言／闲聊的传递方式", "behaviors.csv"),
            F("数值分类（A–E）", "B 纯损害型（传递负面流言）／随内容而定", "§8.16"),
            F("定义版本／状态", "已合并：不再是独立行为，不再单独占行为槽、不再单独出现在行为表",
              "§8.6"),
            F("规则来源", "主文档 §8.6、§8.1；behaviors.csv pass_note 行；behavior_probs.csv pass_note",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "无独立组件（配置行保留）", "scripts/systems/behaviors/"),
            F("行为用途", "把流言／闲聊内容以纸条私密传递：不可被窃听、不可被搭话", "§8.6"),
            F("发起方式", "规格：闲聊中改用纸条（触发时走 §8.1 传播流程）", "§8.6"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "传递者", ""),
            F("目标", "接收者", ""),
            F("人数范围", "2", "§8.6"),
            F("状态条件", "规格：处于闲聊中", "§8.6"),
            F("允许区域／交互点", "同闲聊范围", "§8.6"),
            F("决策侧（做不做）", "无独立概率（pass_note=0.0）：由闲聊触发后按判定改写", "behavior_probs.csv"),
            F("判定侧（成不成）", "沿用接受判定（join_mode=accept）", "behaviors.csv"),
            F("duration（tick）", "10", "behaviors.csv"),
            F("时间倍率", "1×", ""),
            F("允许并发行为", "规格：不可被窃听、不可被搭话", "§8.6"),
            F("噪音 noise", "1", "behaviors.csv"),
            F("效果清单（w_events）", "随携带的流言内容而定（复用 rumor_* / topic_*）", "w_events.csv"),
            F("玩家获得的信息", "纸条内容只有收件人可见", "§8.6"),
            F("提示／日志／动画", "无独立通知（现状）", ""),
            F("无法开始", "prob=0.0 时永不独立触发", "behavior_probs.csv"),
            F("正常路径", "作为闲聊／流言的私密传递方式生效", "§8.6"),
            F("失败与边界路径", "现状无独立实现，无法验证「不被窃听」", "§8.6"),
        ],
    },
    {
        "id": "move",
        "name": "走动",
        "status": "部分实现（玩家移动已落地；NPC do_move 未进内核对时间）",
        "ov": {
            "实现状态": "部分实现：玩家 WASD / 点地移动已通；NPC do_move 未进内核，行为占用互通",
            "位置姿态（现状）": "站姿走动；沿导航网格折线，不直线兜底",
            "时间倍率（现状）": "1×（走路保持正常速度）",
            "触发／门槛（现状）": "move=0.20，段首与 50 秒后各判一次；外向 E 修正（永不为 0）",
            "主要效果": "走动本身不改任何数值（噪音与位置变化）",
        },
        "f": [
            F("层级类型", "状态层（kind=env；§8.4 明确「状态层，非行为」）", "behaviors.csv、§8.4"),
            F("数值分类（A–E）", "不适用：不改 A/H/T/Stress", "§10 分层总则"),
            F("定义版本／状态", "部分实现：玩家移动与占用互斥已通；NPC 移动耗时仍只用于表现层归位",
              "§8.4 注记"),
            F("规则来源", "主文档 §8.4、§8.2；behaviors.csv move 行；behavior_probs.csv move；movement.csv",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/game/player_controller.gd（玩家）、actor_walker.gd、nav_ready.gd；内核 set_position / set_moving / is_moving",
              "scripts"),
            F("行为用途", "改变临时位置（互动距离与活动圈以 position 为准），段末回座位", "§8.4"),
            F("发起方式", "NPC：段首与 50 秒后各判定一次；玩家：WASD 或点地面（无概率判定）", "§8.4.2 / §8.4.5"),
            F("允许阶段", "课间（上课段归位）", "phases.csv、§8.4.6"),
            F("发起者", "走动的角色", ""),
            F("目标", "空闲站立点（加权抽取）", "§8.4.3"),
            F("人数范围", "1", ""),
            F("加入／退出规则（join_mode）", "free：跟着走由 free_join 处理", "behaviors.csv、§8.21.2"),
            F("状态条件", "清醒、未在移动、未被行为占用（睡觉者跳过本批）", "§8.4.2"),
            F("允许区域／交互点", "教室内空闲站立点（stand_points.csv）；玩家走导航网格",
              "stand_points.csv、classroom_nav.tres"),
            F("姿态要求", "站姿行走", "§8.4"),
            F("距离／遮挡／相邻规则", "权重 = 1 + Σ A[i][j]/100 − Σ H[i][j]/200（下限 0.1）；想加入的活动圈 ×1.5",
              "§8.4.3"),
            F("条件不满足时", "路径不可达则停在原地（不直线兜底）", "§8.4 注记"),
            F("决策侧（做不做）", "p = 0.20 × 外向修正（E≥50：×(1+(E−50)/100)；E<50：×(1−(50−E)/200)）；不套用高压减半",
              "behavior_probs.csv、§8.4.2"),
            F("判定侧（成不成）", "无需（玩家侧无概率）", "§8.4.5"),
            F("玩家确认", "不需要（玩家自主移动）", ""),
            F("duration（tick）", "按距离：ceil(路径长度 / meters_per_tick)；速度 0.8 m/tick。behaviors.csv 现值 15 仅代表表现层归位时限",
              "movement.csv、§10.2"),
            F("接近／准备耗时", "移动本身即接近阶段", "§8.4.4"),
            F("执行结束条件", "到达目标点或段末归位", "§8.4.6"),
            F("时间倍率", "1×：走路保持正常速度，玩家占用型行为期间才 3×", "time_flow.csv、§2.2"),
            F("移动模式", "按导航路线行走；玩家 WASD 连续移动＋点地吸附站立点（半径 1.0 m）",
              "movement.csv、§8.4.5"),
            F("占用对象", "路程占用时间；移动中不能发起或接受新聊天", "§8.4"),
            F("允许并发行为", "无（移动期间不能发起／接受新交互）", "§8.4.4"),
            F("噪音 noise", "1", "behaviors.csv"),
            F("效果清单（w_events）", "无（走动不产生数值变化）", "§8.4.4"),
            F("方向与对象", "无", ""),
            F("结算时机", "无结算", ""),
            F("中断后处理", "被上课铃打断按 interrupt 规则结算压力（走动不豁免）", "§8.4.6"),
            F("玩家获得的信息", "无（位置变化本身可见）", ""),
            F("可见范围", "位置是公开可见的", "§8.4.1"),
            F("提示／日志／动画", "导航路径与行走动画由表现层负责", "actor_walker.gd"),
            F("请求", "NPC：批次判定命中；玩家：按键／点击", "§8.4.2/§8.4.5"),
            F("校验", "可通行路线（网格 A*，绕开桌椅）＋占用互斥", "movement.csv、§8.4.5"),
            F("接近", "沿路线行走，速度 0.8 m/tick", "movement.csv"),
            F("执行", "位置更新（临时位置 position）", "§8.4.4"),
            F("结算与反馈", "无数值结算", ""),
            F("释放占用", "到达后释放移动状态；段末全体归位", "§8.4.6"),
            F("无法开始", "睡觉、正在移动、被占用、路径不可达", "§8.4.2"),
            F("玩家取消", "按下 WASD 立刻取消自动行走，松键后不恢复旧路线", "§8.4.5"),
            F("外部事件打断", "上课铃 → 归位 ＋ 压力结算", "§8.4.6"),
            F("正常路径", "段首／50 秒后判定，命中者离座到站立点", "§8.4.2"),
            F("失败与边界路径", "路径不可达停在原地；跨桌椅不得直线穿越", "§8.4 注记"),
        ],
    },
    {
        "id": "ask_help",
        "name": "求助",
        "status": "已实现（Python 内核 do_ask_help ＋ Godot 组件）",
        "ov": {
            "实现状态": "已实现：ask_help_behavior.gd；未实装「被亏欠」状态与部分性格倍率",
            "位置姿态（现状）": "走到目标处（接近阶段未强制）；不校验姿态",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "ask_help_p=0.04；好感门槛三段 30/50/20；判定 p=sigmoid((A[j][i]+E_j/100×10−40)/12)",
            "主要效果": "成功：求助者 A+3/stress−2、帮忙者 A+2/T+3；被拒：stress+3/H+3/T−3；成本 stress+2",
        },
        "f": [
            F("层级类型", "意向类（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "C 信念驱动型（决策读信念、判定读真值）", "§8.16"),
            F("定义版本／状态", "已实现（2026-10-07，Python 内核 `do_ask_help`；Godot 侧 ask_help_behavior.gd）",
              "§8.10"),
            F("规则来源", "主文档 §8.10；behaviors.csv ask_help 行；behavior_probs.csv ask_help_p；behavior_thresholds.csv ask_help.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/ask_help_behavior.gd；内核入口 `_do_ask_help`",
              "scripts/core/sim_core.gd"),
            F("行为用途", "开口求人帮个忙；关系的常规建立方式之一", "§8.10"),
            F("发起方式", "NPC 自主（概率命中且过门槛）；玩家菜单「求助」", "§10.2.1"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "求助者（i）", ""),
            F("目标", "被求助者（j）", ""),
            F("人数范围", "2", ""),
            F("状态条件", "i 空闲、未睡觉、未移动；j 可交互（未睡觉）", "sim_core `_player_action_error`"),
            F("允许区域／交互点", "现状：未做距离校验（不比照闲聊范围）", "代码现状"),
            F("姿态要求", "无", ""),
            F("执行中需持续满足的条件", "占用期内不得另发行为", "context.occupy"),
            F("条件不满足时", "不执行（玩家侧返回 player_busy / target_unavailable）", "sim_core.gd"),
            F("决策侧（做不做）", "好感门槛三段插值：E=50→30、E=0→50、E=100→20；p = ask_help_p(0.04) 命中后发起",
              "behavior_thresholds.csv"),
            F("判定侧（成不成）", "score = A[j][i] + E_j/100×extrovert_bonus(10)；p = sigmoid((score−40)/12)",
              "ask_help_behavior.gd"),
            F("玩家确认", "NPC 向玩家求助时先弹接受／拒绝邀请；玩家接受后不再掷接受骰", "§10.1"),
            F("判定读值（信念／真值）", "判定读真值 A[j][i]；决策侧目标选择读信念", "§4.4"),
            F("拒绝／超时分支", "被拒走 ask_help_no_* 三轴；邀请超时 12 tick 不自动接受、无处罚", "player_interaction.csv"),
            F("duration（tick）", "20（一次动作档）", "behaviors.csv"),
            F("接近／准备耗时", "现状：无独立接近计时（走动另算）", "§8.4"),
            F("执行结束条件", "判定完成即结束", "ask_help_behavior.gd"),
            F("时间不够时", "现状：不截断（行为开始时即设定 busy_until）", "sim_core.gd `_occupy`"),
            F("时间倍率", "1×（玩家占用期间按全局 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无（仅受时间预算约束）", "§10.2"),
            F("占用对象", "i、j（安静占用 quiet=false）", "ask_help_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "1", "behaviors.csv"),
            F("效果清单（w_events）", "ask_help_cost_stress、ask_help_ok_asker_affinity/stress、ask_help_ok_helper_affinity/trust、ask_help_no_stress/hostility/trust",
              "w_events.csv"),
            F("方向与对象", "成本：i 自身压力 +2（不论结果）；成功：i→j 好感 +3、i 压力 −2、j→i 好感 +2、j→i 信任 +3；被拒：i 压力 +3、i→j 敌对 +3、i→j 信任 −3",
              "ask_help_behavior.gd"),
            F("结算时机", "执行点一次性施加（成本先于判定；结果判定后立即施加）", "ask_help_behavior.gd"),
            F("结算次数", "每次执行每有向边 1 次", "ask_help_behavior.gd"),
            F("玩家获得的信息", "玩家展示侧的成功率必须从信念重算（§8.22.3）", "§8.22.3"),
            F("可见范围", "双方可见，无旁观者信息", "§8.10"),
            F("提示／日志／动画", "event_happened(kind=ask_help, accepted)", "ask_help_behavior.gd"),
            F("请求", "玩家点击／NPC 概率命中", "§10.2.1"),
            F("校验", "公共门槛：相位权限、目标可交互、自己空闲", "sim_core `_player_action_error`"),
            F("确认／判定", "单次 sigmoid 判定；玩家作为目标时为接受邀请", "ask_help_behavior.gd"),
            F("执行", "先付成本 → 判定 → 施加成功或拒绝侧效果", "ask_help_behavior.gd"),
            F("结算与反馈", "同执行阶段（一次性，无 tick 累计）", ""),
            F("释放占用", "随 busy_until 到期释放", "sim_core.gd"),
            F("无法开始", "好感未达门槛、概率未命中、相位不允许、目标在睡", "behavior_thresholds.csv"),
            F("拒绝／超时", "被拒三轴反噬；邀请超时不算拒绝、无处罚", "§8.10、player_interaction.csv"),
            F("玩家取消", "现状：玩家发起后不提供中途取消（占用至 busy_until）", "sim_core.gd"),
            F("目标离开", "现状：执行点一次性结算，不重查距离", "ask_help_behavior.gd"),
            F("外部事件打断", "相位切换按 interrupt 规则结算压力", "behavior_probs.csv interrupted_stress"),
            F("释放占用／会话", "随 busy_until", "sim_core.gd"),
            F("正常路径", "过门槛 → 判定通过 → 双向好感/信任上升、求助者减压", "ask_help_behavior.gd"),
            F("失败与边界路径", "被拒不得漏结算成本；「被亏欠」状态与性格倍率未实装", "§8.10 ⚠️"),
        ],
    },
    {
        "id": "ask_about",
        "name": "打听",
        "status": "已实现（玩家独有）",
        "ov": {
            "实现状态": "已实现（玩家独有）：菜单项 ask_about；内核 player_action 通道",
            "位置姿态（现状）": "走到目标处；不校验姿态",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "任何时候可发起（玩家独有）；透露度 = 他对你的信任",
            "主要效果": "（无 w_events 效果行）只产出情报，不改关系矩阵",
        },
        "f": [
            F("层级类型", "意向类（kind=intent）；§10.3 列为玩家独有 3 项能力之一", "behaviors.csv、§10.3"),
            F("数值分类（A–E）", "D 信任／透明度驱动型（透露度读信任）", "§8.16"),
            F("定义版本／状态", "已实现（玩家菜单）；NPC 无此行为", "§10.2.1、§10.3"),
            F("规则来源", "主文档 §10.3、§7.3；behaviors.csv ask_about 行（20 tick / 收益档 3）",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/core/sim_core.gd player_action 通道；scripts/game/player_interaction_controller.gd",
              "scripts"),
            F("行为用途", "向某人打听另一个人的事；透露度由他对你的信任决定", "§10.3"),
            F("发起方式", "仅玩家主动（NPC 不做）", "§10.3"),
            F("允许阶段", "课间（上课段只能看情报日志与推理板）", "§10.4"),
            F("发起者", "玩家", ""),
            F("目标", "被打听者（j）；被问及的是第三人（k）", ""),
            F("人数范围", "2（玩家 + 被问者）", ""),
            F("加入／退出规则（join_mode）", "none（不可加入）", "behaviors.csv"),
            F("状态条件", "玩家空闲、未睡觉、未移动；目标可交互（未睡觉）", "sim_core `_player_action_error`"),
            F("允许区域／交互点", "现状：未做距离校验", "代码现状"),
            F("决策侧（做不做）", "玩家选择（跳过决策侧）", "§10.1"),
            F("判定侧（成不成）", "无判定（不掷骰）", "§10.3"),
            F("判定读值（信念／真值）", "透露度读他对玩家的信任（真实值）", "§10.3、§7.3"),
            F("duration（tick）", "20（一次课间动作）", "behaviors.csv"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无（时间预算约束）", "§10.2"),
            F("占用对象", "玩家与目标", "sim_core.gd"),
            F("噪音 noise", "1", "behaviors.csv"),
            F("效果清单（w_events）", "无（只产出情报，不改关系矩阵）", "w_events.csv"),
            F("方向与对象", "无", ""),
            F("玩家获得的信息", "关于第三人的关系情报，条数与内容由信任度决定", "§7.3"),
            F("可见范围", "只有玩家看到", "§10.3"),
            F("来源／可靠程度", "人物主观说法（可能是错的）", "§7.4"),
            F("提示／日志／动画", "情报日志（intel_log）", "§10.3"),
            F("请求", "玩家点菜单「打听」", "§10.2.1"),
            F("校验", "公共门槛：相位、目标可交互、自己空闲", "sim_core.gd"),
            F("执行", "按信任度产出情报条目", "§7.3"),
            F("结算与反馈", "只交付信息，不改矩阵", "§10.3"),
            F("释放占用", "随 busy_until 释放", "sim_core.gd"),
            F("无法开始", "相位不允许、目标在睡、玩家忙", "sim_core.gd"),
            F("正常路径", "信任越高，透露越多", "§7.3"),
            F("失败与边界路径", "现状无失败分支（无判定）", ""),
        ],
    },
    {
        "id": "inform",
        "name": "告密",
        "status": "部分实现（规格已定，无独立组件）",
        "ov": {
            "实现状态": "部分实现：behaviors.csv 有配置行，scripts/systems/behaviors 无独立组件",
            "位置姿态（现状）": "规格：A 走向 B 的位置；B 本课间不移动",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "规格：A 记忆中含对 B 的流言且通过告密判定（无独立概率行）",
            "主要效果": "（无独立 w_events 行）规格：双向好感上升，并按倾向影响对班级其余人的好恶",
        },
        "f": [
            F("层级类型", "意向类（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "D 信任／透明度驱动型（规格）", "§8.16"),
            F("定义版本／状态", "部分实现：配置与规格在，独立行为组件未落地", "§8.3、scripts/systems/behaviors/"),
            F("规则来源", "主文档 §8.3；behaviors.csv inform 行", "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "无独立组件（配置行保留）", "scripts/systems/behaviors/"),
            F("行为用途", "把掌握的流言单独告诉当事人（不可被窃听）", "§8.3"),
            F("发起方式", "规格：NPC 自主／玩家菜单「告密」", "§10.2.2"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "掌握流言者（A）", ""),
            F("目标", "流言当事人（B）", ""),
            F("人数范围", "2", "§8.3"),
            F("状态条件", "规格：A 记忆中含对 B 的流言（依赖流言记忆模型，尚未落地）", "§8.3、§8.9"),
            F("允许区域／交互点", "规格：A 走到 B 的位置；B 本课间不移动", "§8.3"),
            F("姿态要求", "无", ""),
            F("执行中需持续满足的条件", "规格：B 本课间保持不动", "§8.3"),
            F("决策侧（做不做）", "规格：通过「对 B 的告密判定」（无独立概率行）", "§8.3"),
            F("判定侧（成不成）", "规格：告密判定（未定义公式）", "§8.3"),
            F("duration（tick）", "20（一次动作档）", "behaviors.csv"),
            F("时间倍率", "1×", ""),
            F("占用对象", "规格：B 本课间不移动（占用目标）", "§8.3"),
            F("噪音 noise", "1（低声，无法被窃听）", "behaviors.csv"),
            F("效果清单（w_events）", "无独立效果行", "w_events.csv"),
            F("方向与对象", "规格：A 与 B 互相好感上升；按流言倾向增加 A、B 对班级其余人的好感或敌对", "§8.3"),
            F("结算时机", "规格：未定义", ""),
            F("玩家获得的信息", "规格：B 得知流言内容并存入记忆，课间结束后立刻删除", "§8.3"),
            F("来源／可靠程度", "一手转述，可能带偏差", "§7.4"),
            F("提示／日志／动画", "无（未实现）", ""),
            F("无法开始", "规格：无流言可告时不可发起", "§8.3"),
            F("正常路径", "规格：走到 B 处低声告知", "§8.3"),
            F("失败与边界路径", "现状无实现，无法验证不被窃听与记忆删除", "§8.9"),
        ],
    },
    {
        "id": "chat",
        "name": "闲聊",
        "status": "已实现（统一入口 kind=chat, mode=start/join）",
        "ov": {
            "实现状态": "已实现：统一入口 preview/commit_player_interaction；组件 chat_behavior.gd",
            "位置姿态（现状）": "坐或站均可，但要求双方停止移动且在闲聊范围内",
            "时间倍率（现状）": "1×；玩家进入占用后 3×",
            "触发／门槛（现状）": "chat=0.06/tick（相邻×1.5、自己压力≥70 时×0.5）",
            "主要效果": "topic_affinity(A+3)、topic_trust(T+3)、topic_stress(stress−2)；被拒走 reject_*",
        },
        "f": [
            F("层级类型", "主行为（kind=env，环境类）", "behaviors.csv"),
            F("数值分类（A–E）", "A 纯增益型（话题共鸣）", "§8.16"),
            F("定义版本／状态", "已实现：2026-10-07 与原「搭话」合并，2026-10-08 玩家统一入口落地", "§8.5、§8.7"),
            F("规则来源", "主文档 §8.5、§8.7、§8.15.5；behaviors.csv chat 行；behavior_probs.csv chat；player_interaction.csv",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/chat_behavior.gd；scripts/core/player_interactions.gd；内核 `_do_chat`",
              "scripts/core/sim_core.gd"),
            F("行为用途", "找人说两句：涨好感与信任、降压力，并可能透露／传播信息", "§8.5"),
            F("发起方式", "NPC 自主（每 tick 概率）；玩家菜单「闲聊」（发起或加入）", "§8.5"),
            F("允许阶段", "课间（player_control=1）", "phases.csv"),
            F("发起者", "发起者（i）", ""),
            F("目标", "对象（j）", ""),
            F("人数范围", "≥2（多人加入沿用同一会话，不另建重叠聊天）", "§8.5、join_chat_behavior.gd"),
            F("状态条件", "双方清醒、空闲、未移动；对方不在睡（睡着者不作为交互对象）", "§8.8"),
            F("允许区域／交互点", "普通范围 1.2 m；双方都在座位入口时仅同列前后相邻 1.8 m；连线不得穿桌椅",
              "player_interaction.csv"),
            F("姿态要求", "坐着或站着均可；执行期间必须保持位置（不套用学习／睡觉的坐姿条件）", "§8.5"),
            F("距离／遮挡／相邻规则", "chat_range_m=1.2 / seated_chat_range_m=1.8 / seated_tolerance_m=0.1 / range_step_m=0.1",
              "player_interaction.csv"),
            F("执行中需持续满足的条件", "现状：开始后不再逐 tick 重查范围（只查 in_conversation 与占用）",
              "chat_behavior.gd"),
            F("条件不满足时", "can_chat_in_space 失败则直接 return（不结算、不占用）", "chat_behavior.gd"),
            F("决策侧（做不做）", "环境类：p = 0.06 × 修正（相邻 ×1.5；自己压力 ≥70 时 ×0.5）", "behavior_probs.csv"),
            F("判定侧（成不成）", "发起新聊天无判定；加入既有聊天走 join_chat 判定", "§8.5"),
            F("玩家确认", "NPC 邀请玩家：先弹接受／拒绝；玩家接受后不再掷接受骰", "§10.1"),
            F("判定读值（信念／真值）", "加入判定读真值 A[j][i]；玩家展示侧从信念重算成功率", "§4.4、§8.22.3"),
            F("拒绝／超时分支", "加入被拒走 reject_* 三轴；邀请超时 12 tick 失效、无处罚", "player_interaction.csv"),
            F("duration（tick）", "30（主行为，要聊一会儿）", "behaviors.csv"),
            F("接近／准备耗时", "无独立计时；走动按距离另算（0.8 m/tick）", "§8.4.4、movement.csv"),
            F("执行结束条件", "busy_until 到期；多人会话结束点取 max(各自占用)", "chat_behavior.gd"),
            F("时间不够时", "现状：不截断（开始时即定 busy_until）", "sim_core.gd"),
            F("时间倍率", "1×；玩家正式进入占用后 3×（接近过程不加速）", "time_flow.csv、§2.2"),
            F("资源／次数／冷却", "无（时间预算约束）", "§10.2"),
            F("移动模式", "原地（执行期间不得离座漫游）", "§8.5"),
            F("占用对象", "发起者与目标（占用时间槽）；会话由 _sessions 登记", "chat_behavior.gd"),
            F("允许并发行为", "无；睡着者不参与、不作为对象", "§8.8"),
            F("噪音 noise", "2（2 人无事，8 人就吵）", "behaviors.csv"),
            F("效果清单（w_events）", "topic_affinity、topic_trust、topic_stress（双向好感/信任，减压只对发起者）",
              "chat_behavior.gd"),
            F("方向与对象", "i→j 与 j→i 各 +3 好感、+3 信任；i 自身压力 −2（现状只对发起者一方）",
              "chat_behavior.gd"),
            F("计算方式", "公共统一影响公式（E × 性格调制 × 关系调制 M）", "§4.1"),
            F("结算时机", "执行开始时一次性施加（chat_behavior 在登记会话前即调用 apply_event）",
              "chat_behavior.gd"),
            F("结算次数", "每次执行每有向边 1 次；群聊新成员只与自己的新边结算", "join_chat_behavior.gd"),
            F("玩家获得的信息", "玩家主动闲聊时对象顺带透露关系情报：O<50 一条、O≥50 两条", "§8.5、player_interaction.csv"),
            F("可见范围", "闲聊内容可被范围内未处于闲聊的同学听到（窃听规格，当前未启用）", "§8.5"),
            F("来源／可靠程度", "人物主观说法，可能是错的", "§7.4"),
            F("提示／日志／动画", "脚下融合圈、活动圈上色、event_happened(kind=chat)", "§8.21.4"),
            F("请求", "玩家点击／NPC 概率命中", "§8.5"),
            F("校验", "can_chat_in_space：双方未移动且在范围内（含桌椅阻挡）", "behavior_context.gd"),
            F("接近", "若不在范围内，需先走动接近（玩家点地面或 WASD）", "§8.5"),
            F("准备", "现状无独立准备阶段（坐下／站定不校验）", "§8.5 建议项"),
            F("确认／判定", "发起无需判定；加入需接受判定", "§8.5"),
            F("执行", "标记 in_conversation、占用双方、施加 topic_* 事件、双方 observe、登记会话",
              "chat_behavior.gd"),
            F("结算与反馈", "同执行阶段（开始时结算）；自然完成才交付情报", "§8.5"),
            F("释放占用", "随共同结束点释放；中断时释放会话与占用", "§8.4、chat_behavior.gd"),
            F("无法开始", "不在范围、任一在睡／忙／移动、连线穿桌椅", "behavior_context.gd"),
            F("拒绝／超时", "加入被拒＝三轴反噬；邀请超时不自动接受", "player_interaction.csv"),
            F("玩家取消", "现状：占用期内不提供中途取消（走完 busy_until）", "sim_core.gd"),
            F("目标离开", "现状：不逐 tick 重查范围，会话持续到结束点", "chat_behavior.gd"),
            F("外部事件打断", "上课铃先完成到期活动、中断未完成聊天，再执行归位", "§8.4"),
            F("阶段结束", "随 busy_until 到期结束", "sim_core.gd"),
            F("释放移动锁", "接受并进入执行时锁定参与者移动；结束或中断时释放", "§8.5 建议项"),
            F("释放占用／会话", "会话只登记一次；结束点只后延不缩短", "chat_behavior.gd"),
            F("正常路径", "范围内发起 → 双向好感/信任 +3、发起者压力 −2 → 会话登记", "chat_behavior.gd"),
            F("失败与边界路径", "加入被拒不得污染原会话；重叠聊天不得另开一场", "join_chat_behavior.gd"),
            F("重复请求／通知去重", "群聊一次判定一条反馈；新边各结算一次，旧边不重算", "join_chat_behavior.gd"),
        ],
    },
    {
        "id": "tease",
        "name": "当众调侃",
        "status": "已实现（tease_behavior.gd）",
        "ov": {
            "实现状态": "已实现：tease_behavior.gd；羞辱档写深层敌对（mark_hurt）",
            "位置姿态（现状）": "需 ≥3 人围观（共同邻居）；不校验姿态与距离",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "tease_p=0.09/tick；发起双轨 A≥40 或 H≥25 或 A<25；围观 ≥3",
            "主要效果": "笑场 tease_success_affinity(A+2)/tease_laugh_stress(−2)；嘲讽 tease_hostility(H+3)/tease_stress(+3)；羞辱 humiliate_hostility(H+4 深层)",
        },
        "f": [
            F("层级类型", "主行为（kind=intent，意向类）", "behaviors.csv"),
            F("数值分类（A–E）", "E 混合判定型（读 A + H，结果方向可变）", "§8.16"),
            F("定义版本／状态", "已实现；发起门槛 2026-10-05 修为双轨（原 A≥40 使嘲讽档永不可达）", "§8.12、§8.17.2"),
            F("规则来源", "主文档 §8.12、§8.16、§7.4；behaviors.csv tease 行；behavior_probs.csv tease_p；behavior_thresholds.csv tease_* / humiliate_*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/tease_behavior.gd；内核 `_do_tease`（audience 由调用方给出）",
              "scripts/core/sim_core.gd"),
            F("行为用途", "当着大家的面开某人玩笑；嘲弄是敌对的第一发声（B 类种子的主要来源）", "§8.12、§8.17.2"),
            F("发起方式", "NPC 自主（概率命中且过围观门槛）；玩家菜单「当众调侃」", "§10.2.1"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "调侃者（i）", ""),
            F("目标", "被调侃者（j）", ""),
            F("人数范围", "≥4（发起者＋目标＋≥3 名共同邻居围观）；羞辱档要求围观 ≥4", "§8.12、§9.4"),
            F("加入／退出规则（join_mode）", "accept（加入需对方判定）", "behaviors.csv、§8.21.2"),
            F("状态条件", "i 空闲、未睡、未移动；目标清醒且可交互（睡着者不作为对象）", "§8.8"),
            F("允许区域／交互点", "现状：不校验距离；围观者 = 双方的共同邻居（几何上界 4 人）", "§9.4"),
            F("姿态要求", "无", ""),
            F("执行中需持续满足的条件", "占用期内不得另发行为", "context.occupy"),
            F("条件不满足时", "不执行（围观人数不足时调用方不发起）", "§8.12"),
            F("决策侧（做不做）", "发起条件（任一）：好意调侃 A(i,j) ≥40；挑衅式 H(i,j) ≥25 或 A(i,j) <25；且周围 ≥3 人围观；tease_p=0.09 命中",
              "§8.12、behavior_thresholds.csv"),
            F("判定侧（成不成）", "方向由绝对阈值分档（见「执行」）；现状为确定性分档，不再单独掷骰",
              "tease_behavior.gd"),
            F("玩家确认", "NPC 向玩家发起时先弹接受／拒绝邀请", "§10.1"),
            F("判定读值（信念／真值）", "读真值 A(i,j) / H(i,j)；围观者立场读 A(k,j) / H(k,j)", "tease_behavior.gd"),
            F("拒绝／超时分支", "邀请超时 12 tick 失效、不自动接受；被调侃者是 NPC 时无拒绝分支（方向已定档）",
              "player_interaction.csv"),
            F("duration（tick）", "30（主行为）", "behaviors.csv"),
            F("执行结束条件", "判定与分档结算完成即结束", "tease_behavior.gd"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无", ""),
            F("占用对象", "i、j（占用时间槽；围观者不占用）", "tease_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "3（哄笑会明显抬高音量）", "behaviors.csv"),
            F("效果清单（w_events）", "笑场：tease_success_affinity、tease_laugh_stress；嘲讽：tease_hostility、tease_stress、tease_affinity；羞辱：humiliate_hostility",
              "w_events.csv"),
            F("方向与对象", "笑场：i↔j 好感 +2、每位围观者 k→j 好感 +2、j 自身压力 −2；嘲讽：j→i 敌对 +3、j 自身压力 +3，围观者 A(k,j)≥55 则 k→i 敌对 +3，否则 H(k,j)≥40 则 k→j 好感 −2；羞辱：j→i 敌对 +4（写深层，mark_hurt）",
              "tease_behavior.gd"),
            F("计算方式", "公共统一影响公式；羞辱档为 major（写深层敌对）", "§4.1、§9.3"),
            F("结算时机", "执行点一次性施加（分档判定后立即施加）", "tease_behavior.gd"),
            F("结算次数", "笑场/嘲讽每有向边 1 次；围观者各自 1 次；羞辱额外 1 次", "tease_behavior.gd"),
            F("中断后处理", "已结算部分不回滚（现状无完成时结算）", "tease_behavior.gd"),
            F("玩家获得的信息", "被调侃者与围观者各自可见（公开行为）", "§9.4.1"),
            F("可见范围", "围观者与本人可见；公开行为留下的痕迹可被目击（举报把柄来源）", "§7.6、§8.2"),
            F("来源／可靠程度", "一手目击", "§8.2"),
            F("提示／日志／动画", "event_happened(kind=tease)；statistics: teases / tease_fail / humiliations",
              "tease_behavior.gd"),
            F("请求", "NPC 概率命中或玩家点击", "§8.12"),
            F("校验", "围观人数、目标可交互、相位权限、自己空闲", "sim_core.gd"),
            F("确认／判定", "绝对阈值分档：玩笑 A(i,j)≥55 且 H(i,j)<25；嘲讽 H(i,j)≥40 或 A(i,j)<25；其余为尴尬档（不结算）",
              "behavior_thresholds.csv"),
            F("执行", "按档位施加对应效果；羞辱档额外 mark_hurt", "tease_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 到期释放", "sim_core.gd"),
            F("无法开始", "围观不足 3 人、发起条件不满足、概率未命中、目标在睡", "§8.12"),
            F("拒绝／超时", "邀请超时失效、无处罚", "player_interaction.csv"),
            F("玩家取消", "现状：占用期内不提供取消", "sim_core.gd"),
            F("目标离开", "现状：执行点一次性结算，不重查", "tease_behavior.gd"),
            F("外部事件打断", "相位切换按 interrupt 规则结算压力", "behavior_probs.csv"),
            F("释放占用／会话", "随 busy_until", "sim_core.gd"),
            F("正常路径", "过围观门槛 → 分档 → 施加对应效果（敌对种子或关系升温）", "tease_behavior.gd"),
            F("失败与边界路径", "尴尬档必须不结算（现状：无 else 分支，效果自然为 0）", "tease_behavior.gd"),
            F("重复请求／通知去重", "一次调侃一条反馈；围观者效果不重复施加", "tease_behavior.gd"),
        ],
    },
    {
        "id": "report",
        "name": "举报",
        "status": "已实现（report_behavior.gd ＋ 内核掷骰）",
        "ov": {
            "实现状态": "已实现：report_behavior.gd；举报者敌对回落 `_reduce_reporter_hostility`",
            "位置姿态（现状）": "本课间举报者离场（同走动到室外）",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "report_p=0.10 × σ(z)；H≥40 拐点、scale=8、witness_window≤7 天、好友/信任惩罚",
            "主要效果": "report_stress(stress+5, major)、report_hostility(H+5, major)；举报者敌对回落",
        },
        "f": [
            F("层级类型", "主行为（kind=threshold，阈值类）", "behaviors.csv"),
            F("数值分类（A–E）", "B 纯损害型", "§8.16"),
            F("定义版本／状态", "已实现", "§8.2"),
            F("规则来源", "主文档 §8.2；behaviors.csv report 行；behavior_probs.csv report_p / phone_expose_p；behavior_thresholds.csv report.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/report_behavior.gd；内核 `_roll_reports`、`_reduce_reporter_hostility`",
              "scripts/core/sim_core.gd"),
            F("行为用途", "跑去老师那儿告状：大幅抬高被举报者压力，并可能生成负面流言", "§8.2"),
            F("发起方式", "NPC 自主（每段课间对有把柄候选掷骰一次）；玩家菜单「举报」", "§10.2.2"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "举报者（i）", ""),
            F("目标", "被举报者（j）", ""),
            F("人数范围", "2", "§8.2"),
            F("加入／退出规则（join_mode）", "none（不可加入）", "behaviors.csv、§8.21.2"),
            F("状态条件", "i 空闲、未睡；载体条件：最近 witness_window 天内目击过 j 的标签行为痕迹", "§8.2.1"),
            F("允许区域／交互点", "举报时离场（不在教室内）；不影响其他角色的几何", "§8.2.2"),
            F("姿态要求", "无", ""),
            F("条件不满足时", "无把柄则不掷骰", "§8.2.1"),
            F("决策侧（做不做）", "z = (H[i][j] − 40)/8 − 1.5×A[i][j]/100 − 1.0×T[i][j]/100；p = report_p(0.10) × σ(z)（好友几乎不举报，但永不为 0）",
              "behavior_thresholds.csv"),
            F("判定侧（成不成）", "同一条 sigmoid（阈值类不分两段式判定）", "§8.16"),
            F("判定读值（信念／真值）", "读真值 H[i][j] / A[i][j] / T[i][j]", "§8.2.1"),
            F("duration（tick）", "40（重大事件，得跑一趟）", "behaviors.csv"),
            F("执行结束条件", "本课间离场后结束", "§8.2.2"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("占用对象", "i（离场）；j 为效果对象", "§8.2.2"),
            F("允许并发行为", "无（本课间不再参与其他交互）", "§8.2.2"),
            F("噪音 noise", "1（私下进行）", "behaviors.csv"),
            F("效果清单（w_events）", "report_stress、report_hostility（均为 major）", "w_events.csv"),
            F("方向与对象", "j 自身压力 +5；j→i 敌对 +5；同时 mark_hurt(i,j) 记录伤害；i→j 敌对回落",
              "report_behavior.gd"),
            F("结算时机", "执行点一次性施加（举报后果立即写入）", "report_behavior.gd"),
            F("结算次数", "每段课间每个候选最多 1 次", "§8.2"),
            F("中断后处理", "现状：已结算不回滚", "report_behavior.gd"),
            F("玩家获得的信息", "玩家侧无专属情报（举报本身是他人行为）", ""),
            F("可见范围", "举报者离场可见；把柄来自公开痕迹", "§8.2.2"),
            F("来源／可靠程度", "一手目击（不追溯流言源头）", "§8.2.1"),
            F("提示／日志／动画", "event_happened(kind=report)", "report_behavior.gd"),
            F("请求", "每段课间对有把柄候选掷骰", "behavior_probs.csv report_p"),
            F("校验", "把柄窗口、相位权限、目标可交互", "behavior_thresholds.csv"),
            F("执行", "施加 report_stress / report_hostility、mark_hurt、举报者敌对回落", "report_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 释放；离场状态随相位结束恢复", "sim_core.gd"),
            F("无法开始", "无把柄、概率未命中、自己忙或睡", "§8.2.1"),
            F("正常路径", "敌对累积跨过阈值 → 段内掷骰命中 → 被举报者压力与敌对大幅上升", "behavior_thresholds.csv"),
            F("失败与边界路径", "好友惩罚与信任惩罚压低 z 但不归零；举报后流言生成（现状为即时染色）", "§8.2"),
        ],
    },
    {
        "id": "comfort",
        "name": "安慰",
        "status": "已实现（Python 内核 do_comfort ＋ Godot 组件）",
        "ov": {
            "实现状态": "已实现；未实装爆发期 ×1.5 共情判定与性格倍率",
            "位置姿态（现状）": "凑过去（接近阶段未强制）；不校验姿态",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "comfort_p=0.35；目标压力≥70；好感门槛 E≥50→50、E=0→70",
            "主要效果": "目标 stress−5/affinity+4/trust+5（均 major）；发起成本 stress+2",
        },
        "f": [
            F("层级类型", "主行为（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "A 纯增益型（对目标轴）", "§8.16"),
            F("定义版本／状态", "已实现（2026-10-07，Python 内核 `do_comfort`；Godot 侧 comfort_behavior.gd）", "§8.13"),
            F("规则来源", "主文档 §8.13；behaviors.csv comfort 行；behavior_probs.csv comfort_p；behavior_thresholds.csv comfort_trigger.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/comfort_behavior.gd；内核 `_do_comfort`", "scripts/core/sim_core.gd"),
            F("行为用途", "看谁难受了去说句好话：深度关系的主要建立方式（窄条件、稀有）", "§8.13"),
            F("发起方式", "NPC 自主（机会来临时高概率行动）；玩家菜单「安慰」", "§10.2.1"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "安慰者（i）", ""),
            F("目标", "高压者（j）", ""),
            F("人数范围", "2", "§8.13"),
            F("加入／退出规则（join_mode）", "accept", "behaviors.csv"),
            F("状态条件", "i 空闲、未睡、未移动；j 可交互（未睡）", "§8.8"),
            F("允许区域／交互点", "现状：未做距离校验（规格要求「够近」）", "§8.13 ⚠️"),
            F("姿态要求", "无", ""),
            F("条件不满足时", "不发起", "behavior_thresholds.csv"),
            F("决策侧（做不做）", "门槛：目标压力 ≥70 且我对目标好感 ≥50（E<50 时线性抬高至 70）；comfort_p=0.35 命中",
              "behavior_thresholds.csv"),
            F("判定侧（成不成）", "现状：无成败判定（只有发起成本 ＋ 立即效果）；规格中的共情判定未实装",
              "comfort_behavior.gd"),
            F("玩家确认", "NPC 向玩家发起安慰时先弹接受／拒绝邀请", "§10.1"),
            F("判定读值（信念／真值）", "决策侧读信念（我以为他的压力/他对我的态度）；效果写目标真值轴", "§4.4"),
            F("拒绝／超时分支", "邀请超时 12 tick 失效；玩家拒绝不产生额外惩罚", "player_interaction.csv"),
            F("duration（tick）", "50（深度沟通）", "behaviors.csv"),
            F("执行结束条件", "效果施加完成即结束", "comfort_behavior.gd"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无", ""),
            F("占用对象", "i、j", "comfort_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "1（低声交谈）", "behaviors.csv"),
            F("效果清单（w_events）", "comfort_cost_stress；comfort_target_stress / comfort_target_affinity / comfort_target_trust（均 major）",
              "w_events.csv"),
            F("方向与对象", "i 自身压力 +2（成本，不论结果）；j 压力 −5、j→i 好感 +4、j→i 信任 +5",
              "comfort_behavior.gd"),
            F("计算方式", "公共统一影响公式；目标效果为 major（不做关系调制）", "§4.1、§8.16 边界 2"),
            F("结算时机", "执行点一次性施加（成本与目标效果同一时点）", "comfort_behavior.gd"),
            F("结算次数", "每次执行 1 组", "comfort_behavior.gd"),
            F("中断后处理", "现状：已结算不回滚", "comfort_behavior.gd"),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "双方可见（低声，不构成公开事件）", "§8.13"),
            F("提示／日志／动画", "event_happened(kind=comfort)；statistics: comforts", "comfort_behavior.gd"),
            F("请求", "NPC 概率命中或玩家点击", "§8.13"),
            F("校验", "门槛（压力＋好感）、相位权限、目标可交互", "behavior_thresholds.csv"),
            F("确认／判定", "现状无判定（规格：爆发期需共情判定，未实装）", "§8.13 ⚠️"),
            F("执行", "施加成本与目标三轴效果", "comfort_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 释放", "sim_core.gd"),
            F("无法开始", "目标压力未达 70、好感未过门槛、概率未命中", "behavior_thresholds.csv"),
            F("正常路径", "救援时刻：双向好感与信任向上跃升，目标压力回落", "§8.13"),
            F("失败与边界路径", "爆发期（压力 ≥90）的 ×1.5 与共情判定未实装；性格倍率超出 M 钳位", "§8.13 ⚠️"),
        ],
    },
    {
        "id": "apologize",
        "name": "道歉 / 和解",
        "status": "已实现（Python 内核 do_apologize ＋ Godot 组件）",
        "ov": {
            "实现状态": "已实现；效果一律 no_modulation；未实装透明度临时 +10 与性格倍率",
            "位置姿态（现状）": "走向对方；不校验姿态与距离",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "apologize_p=0.05；真值 H(i,j)≥30 且信念 B_H(i,j)≥30",
            "主要效果": "接受：双向 H−3(表层)/A+3/T+2/stress−3；拒绝：H+2/stress+4(major)/T−3；成本 stress+3",
        },
        "f": [
            F("层级类型", "主行为（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "E 混合判定型", "§8.16"),
            F("定义版本／状态", "已实现；2026-10-07 两处裁决：接受侧敌对由 −5 降为 −3（只消表层）、效果不做关系调制",
              "§8.11"),
            F("规则来源", "主文档 §8.11、§9.3；behaviors.csv apologize 行；behavior_probs.csv apologize_p；behavior_thresholds.csv apologize*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/apologize_behavior.gd；内核 `_do_apologize`", "scripts/core/sim_core.gd"),
            F("行为用途", "跟闹翻的人把话说开：修复表层敌对（心结 H_deep 不消）", "§8.11、§9.3"),
            F("发起方式", "NPC 自主（窄条件：我恨他且以为他也恨我）；玩家菜单「道歉／和解」", "§10.2.1"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "道歉者（i）", ""),
            F("目标", "对象（j）", ""),
            F("人数范围", "2", "§8.11"),
            F("加入／退出规则（join_mode）", "none（不可加入）", "behaviors.csv"),
            F("状态条件", "i 空闲、未睡、未移动；j 可交互", "§8.8"),
            F("允许区域／交互点", "现状：未做距离校验", "代码现状"),
            F("姿态要求", "无", ""),
            F("条件不满足时", "不发起", "§8.11"),
            F("决策侧（做不做）", "真值 H[i][j] ≥30 且信念 B_H[i][j] ≥30（决策侧不得读 H[j][i]）；apologize_p=0.05 命中",
              "§8.11、§14.7"),
            F("判定侧（成不成）", "score = A[j][i] + F_j/100×20 − H[j][i]×0.5；p = sigmoid((score−40)/12)",
              "apologize_behavior.gd"),
            F("玩家确认", "NPC 向玩家道歉时先弹接受／拒绝邀请", "§10.1"),
            F("判定读值（信念／真值）", "决策读信念 B_H；判定读真值 A[j][i]、H[j][i]", "§4.4"),
            F("拒绝／超时分支", "拒绝走 apologize_no_* 三轴；邀请超时 12 tick 失效、无处罚", "player_interaction.csv"),
            F("duration（tick）", "50（深度沟通）", "behaviors.csv"),
            F("执行结束条件", "判定与结算完成即结束", "apologize_behavior.gd"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无", ""),
            F("占用对象", "i、j", "apologize_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "1（低声）", "behaviors.csv"),
            F("效果清单（w_events）", "apologize_cost_stress；接受侧 apologize_ok_hostility/affinity/trust/stress；拒绝侧 apologize_no_hostility/stress/trust",
              "w_events.csv"),
            F("方向与对象", "成本：i 自身压力 +3；接受：双向 H −3（只消表层）、A +3、T +2、双方压力 −3；拒绝：i→j H +2、i 压力 +4、i→j T −3",
              "apologize_behavior.gd"),
            F("计算方式", "公共统一影响公式，但**一律 no_modulation=True**（修复类行为与 M 调制结构性冲突）",
              "§8.11 分歧③"),
            F("结算时机", "执行点一次性施加（成本先施加，判定后施加对应侧效果）", "apologize_behavior.gd"),
            F("结算次数", "接受/拒绝每有向边各 1 次", "apologize_behavior.gd"),
            F("中断后处理", "现状：已结算不回滚", ""),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "双方可见（私下修复）", "§8.11"),
            F("提示／日志／动画", "event_happened(kind=apologize, accepted)", "apologize_behavior.gd"),
            F("请求", "NPC 概率命中或玩家点击", "§8.11"),
            F("校验", "门槛（真值＋信念双向）、相位权限、目标可交互", "§8.11"),
            F("确认／判定", "单次 sigmoid 判定（玩家作为目标时为接受邀请）", "apologize_behavior.gd"),
            F("执行", "施加成本 → 判定 → 接受或拒绝侧效果", "apologize_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 释放", "sim_core.gd"),
            F("无法开始", "H 未达 30、信念未达 30、概率未命中", "§8.11"),
            F("正常路径", "冲突升级后出现：表层敌对回落、好感与信任回升", "§8.11"),
            F("失败与边界路径", "「双方敌对 ≥30」在当前标定下几乎不可达（30 天 H 上限 19–24）——这是敌对积累通道问题，不是道歉门槛问题",
              "§8.11 分歧②、§8.17"),
        ],
    },
    {
        "id": "share_secret",
        "name": "秘密交换",
        "status": "未实装（规格与配置在，无独立组件）",
        "ov": {
            "实现状态": "未实装：behaviors.csv 与 status_tags.csv 有定义，scripts/systems/behaviors 无组件",
            "位置姿态（现状）": "规格：私下交谈（未定义几何）",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "双方信任 ≥60（规格；无独立概率行）",
            "主要效果": "泄密 leak_stress(+5)/leak_trust(−5)/leak_hostility(+4)；守密 → secret_alliance（每天 trust+1，7 天）",
        },
        "f": [
            F("层级类型", "主行为（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "D 信任／透明度驱动型", "§8.16"),
            F("定义版本／状态", "未实装：配置行与状态标签已定义，行为组件未落地", "§8.14、scripts/systems/behaviors/"),
            F("规则来源", "主文档 §8.14；behaviors.csv share_secret 行；status_tags.csv secret_alliance",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "无独立组件（配置保留）", "scripts/systems/behaviors/"),
            F("行为用途", "说个秘密给他，换他守口如瓶；守密成同盟，泄密则信任崩塌", "§8.14"),
            F("发起方式", "规格：一方主动发起；玩家菜单「秘密交换」", "§10.2.2"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "发起者（i）", ""),
            F("目标", "受托者（j）", ""),
            F("人数范围", "2", "§8.14"),
            F("加入／退出规则（join_mode）", "accept", "behaviors.csv"),
            F("状态条件", "规格：双方信任 ≥60", "§8.14"),
            F("允许区域／交互点", "规格未定义（未实现）", ""),
            F("姿态要求", "未定义", ""),
            F("条件不满足时", "不发起", "§8.14"),
            F("决策侧（做不做）", "门槛：双方信任 ≥60（无独立概率行）", "§8.14、behaviors.csv"),
            F("判定侧（成不成）", "规格未定义（现状无实现）", ""),
            F("判定读值（信念／真值）", "规格：读信任 T", "§8.14"),
            F("duration（tick）", "60（收益最大、耗时最长）", "behaviors.csv"),
            F("执行结束条件", "规格：守密超过 5 tick → 进入秘密同盟", "§8.14、status_tags.csv"),
            F("时间倍率", "1×", ""),
            F("占用对象", "规格：双方；目标进入「守密」状态", "§8.14"),
            F("噪音 noise", "1（低声，且不能被窃听）", "behaviors.csv"),
            F("效果清单（w_events）", "leak_stress、leak_trust、leak_hostility（泄密侧）；secret_alliance 为状态标签（每日 trust +1）",
              "w_events.csv、status_tags.csv"),
            F("方向与对象", "泄密：发起者对其信任 −5、敌对 +4、压力 +5；泄密者获「泄密者」标签（3 天）；守密超 5 tick：双方每日信任 +1",
              "§8.14"),
            F("结算时机", "规格：泄密即时结算；同盟走每日涓流结算点", "§8.14"),
            F("结算次数", "秘密同盟每日 1 次，持续 7 天（稳定上限）", "status_tags.csv"),
            F("玩家获得的信息", "规格：知道对方是否守密", "§8.14"),
            F("可见范围", "只有双方（不可被窃听）", "§8.14"),
            F("提示／日志／动画", "无（未实现）", ""),
            F("无法开始", "信任未达 60", "§8.14"),
            F("正常路径", "规格：守密 → 秘密同盟（信任涓流上升）", "§8.14"),
            F("失败与边界路径", "泄密侧后果已定档但未实装；「守密超过 5 tick」的计时口径未定义", "§8.14"),
        ],
    },
    {
        "id": "roughhouse",
        "name": "追逐打闹",
        "status": "已实现（roughhouse_behavior.gd）",
        "ov": {
            "实现状态": "已实现：roughhouse_behavior.gd；旁观者只取邻座（§9.1.3）",
            "位置姿态（现状）": "不校验姿态；旁观者由座位邻接给出",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "roughhouse_p=0.05/tick；发起者 E≥45；旁观者 ≥2",
            "主要效果": "参与者双向 roughhouse_affinity(A+2)；旁观者 roughhouse_hostility(H+3)",
        },
        "f": [
            F("层级类型", "主行为（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "A 纯增益型（参与者）＋ B 纯损害型（旁观者）", "§8.16"),
            F("定义版本／状态", "已实现（2026-10-05 起为敌对种子的第一版实验；2026-10-07 旁观者固定为邻座）",
              "§8.17.1、§9.1.3"),
            F("规则来源", "主文档 §8.17.1、§9.1.3；behaviors.csv roughhouse 行；behavior_probs.csv roughhouse_p；behavior_thresholds.csv roughhouse.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/roughhouse_behavior.gd；内核 `_do_roughhouse`",
              "scripts/core/sim_core.gd"),
            F("行为用途", "一群人疯玩一场：参与者互相好感上升，被吵到的旁观者对参与者敌对上升（敌对种子）",
              "§8.17.1"),
            F("发起方式", "NPC 自主（概率命中）；玩家菜单「追逐打闹」", "§10.2.2"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "发起者（i）", ""),
            F("目标", "另一位参与者（j）", ""),
            F("人数范围", "≥4（2 名参与者 ＋ ≥2 名旁观者）", "§8.17.1"),
            F("加入／退出规则（join_mode）", "accept", "behaviors.csv"),
            F("状态条件", "i 空闲、未睡、未移动；旁观者在场且未睡", "§8.8"),
            F("允许区域／交互点", "现状：不校验距离；旁观者 = 邻座（座位邻接）", "§9.1.3"),
            F("姿态要求", "无", ""),
            F("条件不满足时", "不发起", "behavior_thresholds.csv"),
            F("决策侧（做不做）", "发起者外向度 E ≥45（用 E 维代替「热闹型」）；旁观者人数 ≥2；roughhouse_p=0.05 命中",
              "behavior_thresholds.csv"),
            F("判定侧（成不成）", "无判定", "roughhouse_behavior.gd"),
            F("玩家确认", "NPC 向玩家发起时先弹接受／拒绝邀请", "§10.1"),
            F("判定读值（信念／真值）", "读真值（参与者互加好感、旁观者加敌对）", "roughhouse_behavior.gd"),
            F("duration（tick）", "50（群体活动）", "behaviors.csv"),
            F("执行结束条件", "效果施加完成即结束", "roughhouse_behavior.gd"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("占用对象", "i、j（旁观者不占用）", "roughhouse_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "5（最大的噪音源）", "behaviors.csv"),
            F("效果清单（w_events）", "roughhouse_affinity（参与者）；roughhouse_hostility（旁观者）", "w_events.csv"),
            F("方向与对象", "i→j 与 j→i 好感 +2；每位旁观者 k→i 与 k→j 敌对 +3", "roughhouse_behavior.gd"),
            F("计算方式", "公共统一影响公式（常规档）", "§4.1"),
            F("结算时机", "执行点一次性施加", "roughhouse_behavior.gd"),
            F("结算次数", "每有向边 1 次；旁观者对 2 名参与者各 1 次", "roughhouse_behavior.gd"),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "活动圈可见（§8.21.4）；噪音计入环境层音量", "§8.21.4、§8.18"),
            F("提示／日志／动画", "event_happened(kind=roughhouse)；statistics: roughhouse", "roughhouse_behavior.gd"),
            F("请求", "NPC 概率命中或玩家点击", "§8.17.1"),
            F("校验", "外向门槛、旁观者人数、相位权限", "behavior_thresholds.csv"),
            F("执行", "施加参与者互好感 ＋ 旁观者敌对", "roughhouse_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 释放", "sim_core.gd"),
            F("无法开始", "外向不足、旁观者不足、概率未命中", "behavior_thresholds.csv"),
            F("正常路径", "参与者关系升温、旁观者敌对种子落点", "§8.17.1"),
            F("失败与边界路径", "单次幅度不宜加压（实测加压无效，瓶颈是通路），提高单次幅度未采用", "§8.17.1 第 4 点"),
        ],
    },
    {
        "id": "exclude",
        "name": "排挤",
        "status": "已实现（exclude_behavior.gd；判据 2026-10-07 修订）",
        "ov": {
            "实现状态": "已实现：exclude_behavior.gd；判据视角已从受害者移到施害者（§9.6）",
            "位置姿态（现状）": "不校验位置与姿态；crowd 由判据给出",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "exclude_p=0.06；近 30 天内有敌对行为、cooldown≥7 天、≥2 人重大敌对（≥3 人集体）",
            "主要效果": "目标 exclude_stress(+5 major)；双向 exclude_affinity(−4 major)",
        },
        "f": [
            F("层级类型", "主行为（kind=intent）", "behaviors.csv"),
            F("数值分类（A–E）", "B 纯损害型（群体驱逐）", "§8.16"),
            F("定义版本／状态", "已实现；判据方向 2026-10-07 修订（原判据方向反了）", "§9.6"),
            F("规则来源", "主文档 §9.6、§9.7、§9.5；behaviors.csv exclude 行；behavior_probs.csv exclude_p；behavior_thresholds.csv exclude.*",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/systems/behaviors/exclude_behavior.gd；内核 `_do_exclude`", "scripts/core/sim_core.gd"),
            F("行为用途", "带着一群人孤立某个人：关系真变差（双向疏远），造成观察层的「孤立」标签",
              "§9.6、§9.7"),
            F("发起方式", "NPC 自主（判据命中）；玩家菜单「排挤」", "§10.2.2"),
            F("允许阶段", "课间", "phases.csv"),
            F("发起者", "发起者（i）＋ crowd 群体", "exclude_behavior.gd"),
            F("目标", "被排挤者（j）", ""),
            F("人数范围", "≥3（集体驱逐）", "behavior_thresholds.csv"),
            F("加入／退出规则（join_mode）", "none（不可加入）", "behaviors.csv"),
            F("状态条件", "i 空闲、未睡；目标可交互", "§8.8"),
            F("允许区域／交互点", "现状：不校验距离（群体驱逐按关系而非几何）", "exclude_behavior.gd"),
            F("姿态要求", "无", ""),
            F("条件不满足时", "不发起", "behavior_thresholds.csv"),
            F("决策侧（做不做）", "window ≤30 天内有敌对行为、cooldown ≥7 天、≥2 人做过重大敌对（构成「集体」）；exclude_p=0.06 命中",
              "behavior_thresholds.csv、§9.6"),
            F("判定侧（成不成）", "无判定", "exclude_behavior.gd"),
            F("判定读值（信念／真值）", "读真值敌对（施害者视角）", "§9.6.2"),
            F("duration（tick）", "40（群体驱逐）", "behaviors.csv"),
            F("执行结束条件", "效果施加完成即结束", "exclude_behavior.gd"),
            F("时间倍率", "1×（玩家占用期间 3×）", "time_flow.csv"),
            F("占用对象", "i、j（crowd 成员不占用）", "exclude_behavior.gd"),
            F("允许并发行为", "无", ""),
            F("噪音 noise", "1", "behaviors.csv"),
            F("效果清单（w_events）", "exclude_stress、exclude_affinity（双向，均 major）；从众侧 conformity_hostility",
              "w_events.csv"),
            F("方向与对象", "j 自身压力 +5；j→i 好感 −4；j→每位 crowd 成员好感 −4；i→j 好感 −4；每位 crowd 成员→j 好感 −4",
              "exclude_behavior.gd"),
            F("计算方式", "公共统一影响公式；major 档不做关系调制", "§4.1、§8.16 边界 2"),
            F("结算时机", "执行点一次性施加", "exclude_behavior.gd"),
            F("结算次数", "目标与每位参与者之间各 1 次（有向关系边）", "exclude_behavior.gd"),
            F("玩家获得的信息", "无专属情报（孤立标签是观察层产物，不回写矩阵）", "§9.7.4"),
            F("可见范围", "公开行为，观众可见", "§9.4.1"),
            F("提示／日志／动画", "event_happened(kind=exclude)；statistics: excludes", "exclude_behavior.gd"),
            F("请求", "判据命中后发起", "§9.6"),
            F("校验", "窗口、冷却、集体人数、相位权限", "behavior_thresholds.csv"),
            F("执行", "施加目标压力、双向好感下降", "exclude_behavior.gd"),
            F("结算与反馈", "同执行阶段", ""),
            F("释放占用", "随 busy_until 释放", "sim_core.gd"),
            F("无法开始", "集体人数不足、冷却未过、无近期敌对行为", "behavior_thresholds.csv"),
            F("正常路径", "群体驱逐成立：目标压力大涨、双向疏远、孤立标签出现", "§9.6、§9.7.3"),
            F("失败与边界路径", "同一目标 7 天内不重复驱逐（孤立是状态，不是反复的动作）", "behavior_thresholds.csv"),
        ],
    },
    {
        "id": "sleep",
        "name": "睡觉",
        "status": "已实现（段粒度判定；内核 _roll_sleep / _settle_sleep）",
        "ov": {
            "实现状态": "已实现（2026-10-05）：按段判定，睡着者不被任何人交互",
            "位置姿态（现状）": "不校验座位与姿态（规格建议：自己座位 ＋ 趴桌）",
            "时间倍率（现状）": "1×（玩家占用时 3×）",
            "触发／门槛（现状）": "sleep=0.03（压力≥70 时×1.5）；每段课间判定一次，非每 tick",
            "主要效果": "课间结束一次性 stress−3（sleep_relief）；期间不参与任何交互",
        },
        "f": [
            F("层级类型", "状态层（kind=env；§8.8 明确「状态层，非行为」）", "behaviors.csv、§8.8"),
            F("数值分类（A–E）", "不适用（只改压力与占用）", "§10 分层总则"),
            F("定义版本／状态", "已实现：2026-10-05 改按段粒度判定（早期误写在每 tick 决策里，导致 96% 课间都在睡）",
              "§8.8 注记"),
            F("规则来源", "主文档 §8.8、§10.2.3；behaviors.csv sleep 行；behavior_probs.csv sleep / sleep_relief",
              "docs/gdd/v4/（08 人物行为 / 09 人物设计）"),
            F("实现位置", "scripts/core/sim_core.gd `_roll_sleep` / `_settle_sleep`", "scripts/core/sim_core.gd"),
            F("行为用途", "用社交机会换压力缓解：本次课间不参与任何活动，课间结束减压", "§8.8"),
            F("发起方式", "NPC 概率触发；玩家菜单「睡觉」（玩家自己选择）", "§8.8、§10.1"),
            F("允许阶段", "课间（段粒度判定）", "phases.csv"),
            F("发起者", "睡觉者自己", ""),
            F("目标", "无", ""),
            F("人数范围", "1", ""),
            F("加入／退出规则（join_mode）", "free（可跟随）", "behaviors.csv"),
            F("状态条件", "清醒、空闲（未被行为占用）", "§8.8"),
            F("允许区域／交互点", "现状不要求座位（规格建议：自己的座位／书桌交互点）", "用户 2026-10-09 建议"),
            F("姿态要求", "现状无（规格建议：坐下并进入趴桌睡姿）", "用户 2026-10-09 建议"),
            F("执行中需持续满足的条件", "整个课间段保持睡眠（现状不重查位置）", "§8.8"),
            F("条件不满足时", "不进入睡眠判定", "§8.8"),
            F("决策侧（做不做）", "p = 0.03（自己压力 ≥70 时 ×1.5）；每段课间判定一次", "behavior_probs.csv"),
            F("判定侧（成不成）", "无第二段判定", "sim_core.gd"),
            F("玩家确认", "玩家自己选择是否睡觉（不替他随机）", "§10.1"),
            F("判定读值（信念／真值）", "读自身压力真值", "behavior_probs.csv"),
            F("duration（tick）", "100（整段占用；§10.2 的耗时-收益单调性特例）", "behaviors.csv"),
            F("执行结束条件", "课间段结束（现状：固定 100 tick 与「段末结束」的区分待定）", "§8.8"),
            F("时间倍率", "1×；玩家正式进入睡眠占用后 3×（醒来或中断即清理）", "time_flow.csv"),
            F("占用对象", "自己（整段占用；不作为任何交互的目标）", "§8.8.3"),
            F("允许并发行为", "无（本次课间不参与任何活动）", "§8.8.2"),
            F("噪音 noise", "1（behaviors.csv 现值；表头注释称安静行为应为 0，需核对）", "behaviors.csv"),
            F("效果清单（w_events）", "sleep_relief（课间结束一次性 stress −3）；无其他事件行", "behavior_probs.csv"),
            F("方向与对象", "自身压力 −3（段末一次性）", "behavior_probs.csv"),
            F("结算时机", "课间段结束（一次性，非每 tick）", "sim_core.gd `_settle_sleep`"),
            F("结算次数", "每段课间 1 次", "behavior_probs.csv"),
            F("中断后处理", "规格待定：提前醒来是否获部分减压，草案不额外规定", "§8.8 建议项"),
            F("玩家获得的信息", "无（睡眠期间错过全部观测）", "§8.8.4"),
            F("可见范围", "睡眠状态公开可见", "§8.8.3"),
            F("提示／日志／动画", "表现层姿态（趴桌）不得代替内核睡眠状态", "§8.8 建议项"),
            F("请求", "段粒度概率判定命中", "behavior_probs.csv"),
            F("校验", "清醒、空闲；规格建议再加座位与姿态校验", "§8.8"),
            F("准备", "规格建议：先走到座位、坐下、进入趴桌睡姿（接近阶段保持正常速度）", "用户 2026-10-09 建议"),
            F("执行", "整段睡眠，不参与任何交互", "§8.8.2"),
            F("结算与反馈", "段末一次性减压", "sim_core.gd"),
            F("释放占用", "段末释放", "sim_core.gd"),
            F("无法开始", "不空闲、已占用", "§8.8"),
            F("玩家取消", "现状：玩家进入睡眠后整段占用，无中途醒来接口", "sim_core.gd"),
            F("目标离开", "不适用", ""),
            F("外部事件打断", "相位切换即结束睡眠并结算", "sim_core.gd"),
            F("阶段结束", "段末结算减压", "sim_core.gd"),
            F("释放移动锁", "睡眠期间禁止移动与交互", "§8.8.3"),
            F("释放占用／会话", "段末释放，并从相邻类判定对象中移出", "§8.8.3"),
            F("正常路径", "概率命中 → 整段睡眠 → 段末压力 −3", "sim_core.gd"),
            F("失败与边界路径", "睡着者不得作为任何交互对象（含共同学习的相邻判定）", "§8.8.3"),
            F("重复请求／通知去重", "段粒度判定：同段不重复掷骰", "§8.8 注记"),
        ],
    },
    {
        "id": "teacher_patrol",
        "name": "老师巡查",
        "status": "未开工（P0 规格完成 2026-10-09）",
        "new": True,
        "table": {
            "kind": "世界实体（非行为条目）", "duration": "stay_ticks=30",
            "payoff": "不适用（压力 base 3）", "noise": "不适用", "join_mode": "不适用",
        },
        "ov": {
            "实现状态": "未开工（P0-2 规格完成）：老师实体与巡查逻辑均未实现",
            "位置姿态（现状）": "世界实体在办公室↔教室之间移动；无姿态概念",
            "时间倍率（现状）": "1×",
            "触发／门槛（现状）": "课间 tick=25 / 65 两个判定点，各以 visit_p=0.25 独立掷骰；至多 1 次/课间",
            "主要效果": "teacher_visit_stress（全班 stress +3，待落 w_events）；在场期间 调侃/打闹/排挤 ×0.3、音量目标 ×0.5",
        },
        "f": [
            F("层级类型", "世界实体层：非社交节点、非行为——不占 N 名额、不进 A/H/T/B 矩阵、不参与传导与信念更新",
              "§17.2.1"),
            F("数值分类（A–E）", "不适用：只经统一影响公式施加压力，不读 A/H/T",
              "§17.2.1、§17.2.3"),
            F("定义版本／状态", "未开工（P0-2：规格完成，实现未开工）", "§17.0、§17.2"),
            F("规则来源", "v4/17 §17.2；`data/rules/teacher.csv`（待建）；`w_events.teacher_visit_stress`（待建）",
              "docs/gdd/v4/17-P0功能细分规格.md"),
            F("实现位置", "（无实现）内核需新增非节点实体与巡查状态机；表现层画讲台状态",
              "§17.5 实现顺序"),
            F("kind", "世界实体（不是 behaviors.csv 条目，不受 duration/payoff 单调性表约束）", "§17.2.1"),
            F("行为用途", "老师课间进来一趟：给全班加压、压低音量与吵闹行为，制造「被逮风险感」", "§17.2.3"),
            F("收益档 payoff", "不适用；到场压力用 w_events base=3（常规档）", "§17.2.5"),
            F("发起方式", "系统条件触发：每课间两个判定点独立掷骰；「不杀回马枪」——已来过则第二点跳过",
              "§17.2.2"),
            F("允许阶段", "课间；上课段老师默认在教室（教学状态），不触发巡查与加压逻辑", "§17.2.2"),
            F("发起者", "老师（世界实体，无 MBTI、无节点四维）", "§17.2.1"),
            F("目标", "在场的全体角色（含玩家）", "§17.2.3"),
            F("人数范围", "全体在教室者", "§17.2.3"),
            F("加入／退出规则（join_mode）", "不适用（不是可加入活动）", "§17.2.1"),
            F("状态条件", "本课间尚未巡查过；当前相位为课间", "§17.2.2"),
            F("允许区域／交互点", "办公室 ↔ 教室；进教室即全场生效，不分距离", "§17.2.1、§17.2.3"),
            F("姿态要求", "不适用", ""),
            F("距离／遮挡／相邻规则", "不适用（到场即全场事件）", "§17.2.3"),
            F("执行中需持续满足的条件", "在场期间保持「巡查中」状态，直至 stay_ticks 到期", "§17.2.2"),
            F("条件不满足时", "本判定点跳过（不重掷、不延后）", "§17.2.2"),
            F("决策侧（做不做）", "两个判定点各以 visit_p=0.25 独立掷骰；单课间至少来一次 ≈43.75%",
              "§17.2.2"),
            F("判定侧（成不成）", "无（到场即生效，不做接受判定）", "§17.2.3"),
            F("玩家确认", "不需要：玩家无讨价还价入口，同在教室即受同一套限制", "§17.2.4"),
            F("判定读值（信念／真值）", "无（纯状态量输入，符合铁律）", "§17.2.4"),
            F("拒绝／超时分支", "不适用", ""),
            F("duration（tick）", "停留 stay_ticks=30（约半段课间）；判定点 tick=25 与 tick=65",
              "§17.2.2、§17.2.5"),
            F("接近／准备耗时", "无（相位过渡直接切换位置）", "§17.2.2"),
            F("执行结束条件", "stay_ticks 到期回办公室；上课铃响立即回教室（上课优先于巡查）", "§17.2.2"),
            F("时间不够时", "在 stay 未到期时被上课铃截断，不补完剩余 stay_ticks", "§17.2.2"),
            F("时间倍率", "1×（不参与玩家倍率判定）", "§17.2"),
            F("资源／次数／冷却", "每课间至多 1 次到场", "§17.2.2"),
            F("移动模式", "世界实体沿办公室↔教室移动（不进社交移动体系）", "§17.2.1"),
            F("占用对象", "不占用任何角色，也不被任何角色占用", "§17.2.1"),
            F("允许并发行为", "与一切行为并发（以状态修正方式生效）", "§17.2.3"),
            F("噪音 noise", "不适用", ""),
            F("效果清单（w_events）", "teacher_visit_stress（axis=stress，base=3，tier=normal，待落表）；音量与行为抑制由 teacher.csv 参数承担",
              "§17.2.5"),
            F("方向与对象", "每人 → 自身压力 +3；**豁免：睡觉、学习（默认状态）、出门的玩家**；听音乐/吃零食/看书不豁免",
              "§17.2.3"),
            F("计算方式", "统一影响公式（性格修正经 w 系数：敏感者 1.2 / 迟钝 0.15 锚定）", "§17.2.5"),
            F("结算时机", "**到场瞬间一次性结算**（事件类）；在场期间为持续状态修正", "§17.2.3"),
            F("结算次数", "每课间至多 1 次到场结算", "§17.2.2"),
            F("中断后处理", "上课铃打断：立即回教室，不补完停留、不重复加压", "§17.2.2"),
            F("玩家获得的信息", "老师位置可见（讲台状态由可视化呈现）", "§17.2.4"),
            F("可见范围", "全场可见；老师位置属环境事实", "§17.2.4"),
            F("来源／可靠程度", "一手目击（不是流言）", "§17.2.4"),
            F("提示／日志／动画", "讲台状态表现；观察层只读输出，不回写矩阵", "§17.2.4"),
            F("请求", "无请求阶段：判定点掷骰命中即到场", "§17.2.2"),
            F("校验", "本课间未巡查过 + 相位为课间", "§17.2.2"),
            F("接近", "无", ""),
            F("准备", "无", ""),
            F("确认／判定", "掷骰（visit_p=0.25），命中即进教室", "§17.2.2"),
            F("执行", "到场（全场压力结算）→ 在场期间状态修正（调侃/打闹/排挤 ×0.3、音量目标 ×0.5）",
              "§17.2.3"),
            F("结算与反馈", "到场瞬间一次性 +3（豁免名单内的人不结算）", "§17.2.3"),
            F("释放占用", "无角色占用可释放；stay 到期或相位切换时重置实体位置", "§17.2.2"),
            F("无法开始", "本课间已来过；或当前是上课段", "§17.2.2"),
            F("拒绝／超时", "不适用", ""),
            F("玩家取消", "玩家不可取消（外部环境事件）", "§12.1 语义（v4 §10.1）"),
            F("目标离开", "不适用（到场即全场）", ""),
            F("外部事件打断", "上课铃 → 立即回教室（上课优先于巡查）", "§17.2.2"),
            F("阶段结束", "stay 到期回办公室", "§17.2.2"),
            F("释放移动锁", "不涉及玩家移动锁", ""),
            F("释放占用／会话", "无占用", ""),
            F("资源预留与返还", "无", ""),
            F("倍率覆盖", "无（不申请正常速度锁）", ""),
            F("正常路径", "判定命中 → 到场（全班 +3）→ 停留 30 tick 压场 → 回办公室", "§17.2.2–§17.2.3"),
            F("失败与边界路径", "同一课间不得到场 2 次；豁免名单必须精确（睡觉/学习/出门不结算）",
              "§17.2.2、§17.2.3"),
            F("重复请求／通知去重", "到场结算每课间最多 1 次", "§17.2.2"),
            F("验收标准", "批量统计到场率 ≈43.75%/课间（±抽样噪声）；任意课间到场次数 ≤1；同种子可复现",
              "§17.5 验收 3"),
        ],
    },
    {
        "id": "listen_music",
        "name": "听音乐",
        "status": "未开工（P0 规格完成 2026-10-09）",
        "new": True,
        "table": {
            "kind": "主行为（状态层动作，与睡觉同构）", "duration": "30",
            "payoff": "不适用（减压 −2.0）", "noise": "0（耳机）", "join_mode": "待定（规格未定义）",
        },
        "ov": {
            "实现状态": "未开工（P0-3 第一批减压动作）",
            "位置姿态（现状）": "规格未定义（未开工）",
            "时间倍率（现状）": "1×（玩家占用期间按全局 3×）",
            "触发／门槛（现状）": "NPC 触发概率 music_p=0.02（标定起点）；玩家默认可用",
            "主要效果": "动作结束时 stress −2.0（leisure.csv music_relief，待建）",
        },
        "f": [
            F("层级类型", "主行为（占时段、期间不发起/接受交互）—— 与睡觉同构的状态层动作", "§17.3.1"),
            F("数值分类（A–E）", "不适用：只改自身压力，不读 A/H/T", "§17.3.1"),
            F("定义版本／状态", "未开工（P0-3 第一批减压动作，规格完成）", "§17.0、§17.3.1"),
            F("规则来源", "v4/17 §17.3.1、§17.3.2；`data/rules/leisure.csv`（待建）；`behavior_probs.music_p`（待建）",
              "docs/gdd/v4/17-P0功能细分规格.md"),
            F("实现位置", "（无实现）内核行为组件 + 菜单项", "§17.5"),
            F("kind", "主行为（状态层动作）；待落 behaviors.csv", "§17.3.1"),
            F("行为用途", "戴耳机听一会儿歌：短时段减压、但保留课间其余时间的社交机会", "§17.3.1"),
            F("收益档 payoff", "不适用（减压走 leisure.csv，不进 w_events）", "§17.3.5"),
            F("发起方式", "NPC 走既有「门槛 → 意向 → 采样」路径（music_p=0.02）；玩家菜单项", "§17.3.1"),
            F("允许阶段", "课间", "§17.3.1"),
            F("发起者", "自己", ""),
            F("目标", "无", ""),
            F("人数范围", "1", "§17.3.1"),
            F("加入／退出规则（join_mode）", "待定（规格未定义；与睡觉同为状态层动作，倾向 free）", "§17.3.1"),
            F("状态条件", "清醒、空闲、未移动、未处于其他占用", "§17.3.1"),
            F("允许区域／交互点", "规格未定义（待定：是否要求座位）", "用户 2026-10-09 待裁定项"),
            F("姿态要求", "规格未定义（待定）", ""),
            F("距离／遮挡／相邻规则", "不适用", ""),
            F("执行中需持续满足的条件", "占用期内不得发起/接受交互", "§17.3.1"),
            F("条件不满足时", "不发起", "§17.3.1"),
            F("决策侧（做不做）", "NPC：music_p=0.02（标定起点，进 behavior_probs.csv）；玩家：主动选择",
              "§17.3.5"),
            F("判定侧（成不成）", "无判定", "§17.3.1"),
            F("玩家确认", "玩家自己选择；NPC 对玩家无邀请语义", "§10.1（v4）"),
            F("判定读值（信念／真值）", "无", ""),
            F("拒绝／超时分支", "不适用", ""),
            F("duration（tick）", "30（music_duration）", "§17.3.5"),
            F("接近／准备耗时", "规格未定义", ""),
            F("执行结束条件", "占用时长走完（动作结束）", "§17.3.1"),
            F("时间不够时", "被相位切换打断：按「行为被打断 +0.5」结算压力代价，**减压不结算**",
              "§17.3.1 结算时机"),
            F("时间倍率", "1×（玩家占用期间按全局 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "无（耳机为常物，P0 不做门控）", "§17.3.2"),
            F("移动模式", "原地", "§17.3.1"),
            F("占用对象", "自己（期间不发起/接受交互）", "§17.3.1"),
            F("允许并发行为", "无", "§17.3.1"),
            F("噪音 noise", "0（耳机，不抬高环境音量）", "§17.3.1"),
            F("效果清单（w_events）", "不进 w_events：减压值在 `leisure.csv music_relief=2.0`（待建）",
              "§17.3.5"),
            F("方向与对象", "自身压力 −2.0（动作结束时一次性）", "§17.3.1"),
            F("计算方式", "参数直减（不走 UIF/关系调制）", "§17.3.1"),
            F("结算时机", "**动作结束时一次性结算**（P0 引入的第二类结算时机；现行实现是开始即结算）",
              "§17.3.1 结算时机"),
            F("结算次数", "每次动作 1 次", "§17.3.1"),
            F("中断后处理", "被打断 → 减压不结算，只付 +0.5 打断代价（没做完不回血）", "§17.3.1"),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "动作本身公开可见（环境音量不变）", "§17.3.1"),
            F("来源／可靠程度", "不适用", ""),
            F("提示／日志／动画", "待定（表现层：耳机姿态）", "§17.3.1"),
            F("请求", "NPC 概率命中 / 玩家点击菜单", "§17.3.1"),
            F("校验", "空闲、清醒、相位为课间", "§17.3.1"),
            F("接近", "规格未定义", ""),
            F("准备", "规格未定义", ""),
            F("确认／判定", "无判定", ""),
            F("执行", "占用 30 tick，期间不参与交互", "§17.3.1"),
            F("结算与反馈", "动作结束时压力 −2.0", "§17.3.1"),
            F("释放占用", "时长走完释放自身占用", "§17.3.1"),
            F("无法开始", "相位不允许、自己忙或在睡", "§17.3.1"),
            F("玩家取消", "规格未定义（待定：是否允许中途摘下耳机）", "待裁定"),
            F("目标离开", "不适用", ""),
            F("外部事件打断", "上课铃 → 不结算减压，按打断 +0.5 结算", "§17.3.1"),
            F("阶段结束", "同打断语义", "§17.3.1"),
            F("释放移动锁", "占用期间不可移动（与睡觉同构）", "§17.3.1"),
            F("释放占用／会话", "结束或中断时释放", "§17.3.1"),
            F("资源预留与返还", "无", ""),
            F("倍率覆盖", "无", ""),
            F("正常路径", "占用 30 tick → 结束时压力 −2.0", "§17.3.1"),
            F("失败与边界路径", "被上课铃打断不得回血；不得与睡觉/出门叠加结算", "§17.3.1"),
            F("重复请求／通知去重", "同一占用期只结算 1 次", "§17.3.1"),
            F("验收标准", "第五道门：机制必须非零上场（音乐须有上场率）", "§17.5 验收 4"),
        ],
    },
    {
        "id": "eat_snack",
        "name": "吃零食",
        "status": "未开工（P0 规格完成 2026-10-09）",
        "new": True,
        "table": {
            "kind": "主行为（状态层动作，与睡觉同构）", "duration": "15",
            "payoff": "不适用（减压 −1.5）", "noise": "1", "join_mode": "待定（规格未定义）",
        },
        "ov": {
            "实现状态": "未开工（P0-3 第一批减压动作）",
            "位置姿态（现状）": "规格未定义（未开工）",
            "时间倍率（现状）": "1×（玩家占用期间按全局 3×）",
            "触发／门槛（现状）": "NPC 触发概率 snack_p=0.02；玩家每局 5 份（snack_count_per_run=5）",
            "主要效果": "动作结束时 stress −1.5（leisure.csv snack_relief，待建）",
        },
        "f": [
            F("层级类型", "主行为（占时段、期间不发起/接受交互）", "§17.3.1"),
            F("数值分类（A–E）", "不适用：只改自身压力", "§17.3.1"),
            F("定义版本／状态", "未开工（P0-3 第一批减压动作）", "§17.0、§17.3.1"),
            F("规则来源", "v4/17 §17.3.1、§17.3.2；`data/rules/leisure.csv`（待建）；`behavior_probs.snack_p`（待建）",
              "docs/gdd/v4/17-P0功能细分规格.md"),
            F("实现位置", "（无实现）内核行为组件 + 菜单项 + 份数计数器", "§17.5"),
            F("kind", "主行为（状态层动作）；待落 behaviors.csv", "§17.3.1"),
            F("行为用途", "吃点东西快速回一口血：耗时最短、幅度最小的减压方式", "§17.3.1"),
            F("收益档 payoff", "不适用（减压走 leisure.csv）", "§17.3.5"),
            F("发起方式", "NPC 概率路径（snack_p=0.02）；玩家菜单项", "§17.3.1"),
            F("允许阶段", "课间", "§17.3.1"),
            F("发起者", "自己", ""),
            F("目标", "无", ""),
            F("人数范围", "1", "§17.3.1"),
            F("加入／退出规则（join_mode）", "待定（规格未定义）", "§17.3.1"),
            F("状态条件", "清醒、空闲、未移动、份数 > 0（玩家）", "§17.3.2"),
            F("允许区域／交互点", "规格未定义（待定）", "待裁定"),
            F("姿态要求", "规格未定义（待定）", ""),
            F("执行中需持续满足的条件", "占用期内不得发起/接受交互", "§17.3.1"),
            F("条件不满足时", "玩家份数为 0 时菜单不可用；NPC 不发起", "§17.3.2"),
            F("决策侧（做不做）", "NPC：snack_p=0.02（标定起点）；玩家：主动选择（消耗 1 份）", "§17.3.5"),
            F("判定侧（成不成）", "无判定", "§17.3.1"),
            F("玩家确认", "玩家自己选择", "§10.1（v4）"),
            F("判定读值（信念／真值）", "无", ""),
            F("拒绝／超时分支", "不适用", ""),
            F("duration（tick）", "15（snack_duration）", "§17.3.5"),
            F("执行结束条件", "占用时长走完", "§17.3.1"),
            F("时间不够时", "被相位切换打断：减压不结算，按 +0.5 打断代价结算", "§17.3.1"),
            F("时间倍率", "1×（玩家占用期间按全局 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "玩家：每局 5 份（snack_count_per_run，`player_absence`/leisure 待定落点）；NPC 不限量（常物）",
              "§17.3.2"),
            F("移动模式", "原地", "§17.3.1"),
            F("占用对象", "自己", "§17.3.1"),
            F("允许并发行为", "无", "§17.3.1"),
            F("噪音 noise", "1（会抬高环境音量 → 自然产生社会后果）", "§17.3.1"),
            F("效果清单（w_events）", "不进 w_events：`leisure.csv snack_relief=1.5`（待建）", "§17.3.5"),
            F("方向与对象", "自身压力 −1.5（动作结束时一次性）", "§17.3.1"),
            F("计算方式", "参数直减", "§17.3.1"),
            F("结算时机", "**动作结束时一次性结算**", "§17.3.1"),
            F("结算次数", "每次动作 1 次", "§17.3.1"),
            F("中断后处理", "被打断不回血，只付打断代价", "§17.3.1"),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "动作公开可见；噪音计入环境层", "§17.3.1"),
            F("提示／日志／动画", "待定", ""),
            F("请求", "NPC 概率命中 / 玩家点击菜单", "§17.3.1"),
            F("校验", "份数、空闲、相位", "§17.3.2"),
            F("执行", "占用 15 tick", "§17.3.1"),
            F("结算与反馈", "结束时压力 −1.5；玩家扣 1 份", "§17.3.1、§17.3.2"),
            F("释放占用", "时长走完释放", "§17.3.1"),
            F("无法开始", "份数为 0、相位不允许、自己忙或在睡", "§17.3.2"),
            F("玩家取消", "规格未定义", "待裁定"),
            F("外部事件打断", "上课铃 → 不结算减压", "§17.3.1"),
            F("释放移动锁", "占用期间不可移动", "§17.3.1"),
            F("释放占用／会话", "结束或中断时释放", "§17.3.1"),
            F("资源预留与返还", "份数在动作开始时预扣还是结束时扣：规格未定义（待裁定）", "待裁定"),
            F("正常路径", "占用 15 tick → 压力 −1.5，份数 −1", "§17.3.1"),
            F("失败与边界路径", "份数耗尽后不可再发起；打断不得扣份又回血", "§17.3.2"),
            F("验收标准", "第五道门：零食须有非零上场率", "§17.5 验收 4"),
        ],
    },
    {
        "id": "read_book",
        "name": "看书",
        "status": "未开工（P0 规格完成 2026-10-09）",
        "new": True,
        "table": {
            "kind": "主行为（状态层动作，与睡觉同构）", "duration": "40",
            "payoff": "不适用（减压 −2.5）", "noise": "0", "join_mode": "待定（规格未定义）",
        },
        "ov": {
            "实现状态": "未开工（P0-3 第一批减压动作；受物品门控）",
            "位置姿态（现状）": "规格未定义（未开工）",
            "时间倍率（现状）": "1×（玩家占用期间按全局 3×）",
            "触发／门槛（现状）": "NPC 触发概率 book_p=0.02；**需持有课外书**（seeds.csv book 列）",
            "主要效果": "动作结束时 stress −2.5（leisure.csv book_relief，待建）",
        },
        "f": [
            F("层级类型", "主行为（占时段、期间不发起/接受交互）", "§17.3.1"),
            F("数值分类（A–E）", "不适用：只改自身压力", "§17.3.1"),
            F("定义版本／状态", "未开工（P0-3；物品门控为最小集）", "§17.0、§17.3.2"),
            F("规则来源", "v4/17 §17.3.1、§17.3.2；`data/rules/leisure.csv`、`data/characters/seeds.csv` book 列（均待建）",
              "docs/gdd/v4/17-P0功能细分规格.md"),
            F("实现位置", "（无实现）内核行为组件 + 物品门控字段", "§17.5"),
            F("kind", "主行为（状态层动作）；待落 behaviors.csv", "§17.3.1"),
            F("行为用途", "翻课外书：减压幅度最大的课间动作，代价是占用 40 tick", "§17.3.1"),
            F("收益档 payoff", "不适用（减压走 leisure.csv）", "§17.3.5"),
            F("发起方式", "NPC 概率路径（book_p=0.02，仅持有者）；玩家入口预留（0 本，菜单灰置）", "§17.3.2"),
            F("允许阶段", "课间", "§17.3.1"),
            F("发起者", "自己", ""),
            F("目标", "无", ""),
            F("人数范围", "1", "§17.3.1"),
            F("加入／退出规则（join_mode）", "待定（规格未定义）", "§17.3.1"),
            F("状态条件", "清醒、空闲、未移动、**持有课外书**", "§17.3.2"),
            F("允许区域／交互点", "规格未定义（待定）", "待裁定"),
            F("姿态要求", "规格未定义（待定）", ""),
            F("执行中需持续满足的条件", "占用期内不得发起/接受交互", "§17.3.1"),
            F("条件不满足时", "无书则不发起 / 菜单灰置", "§17.3.2"),
            F("决策侧（做不做）", "NPC：book_p=0.02（仅 book=1 的角色）；玩家：P0 不可用", "§17.3.5、§17.3.2"),
            F("判定侧（成不成）", "无判定", "§17.3.1"),
            F("玩家确认", "不适用（玩家 0 本）", "§17.3.2"),
            F("判定读值（信念／真值）", "无", ""),
            F("duration（tick）", "40（book_duration）", "§17.3.5"),
            F("执行结束条件", "占用时长走完", "§17.3.1"),
            F("时间不够时", "被相位切换打断：减压不结算，按 +0.5 打断代价结算", "§17.3.1"),
            F("时间倍率", "1×（玩家占用期间按全局 3×）", "time_flow.csv"),
            F("资源／次数／冷却", "物品门控：NPC 由 `seeds.csv book` 列（0/1，按难度缩放：8 人班 3 / 16 人班 6 / 24 人班 10）；玩家 0 本，入口预留",
              "§17.3.2"),
            F("移动模式", "原地", "§17.3.1"),
            F("占用对象", "自己", "§17.3.1"),
            F("允许并发行为", "无", "§17.3.1"),
            F("噪音 noise", "0", "§17.3.1"),
            F("效果清单（w_events）", "不进 w_events：`leisure.csv book_relief=2.5`（待建）", "§17.3.5"),
            F("方向与对象", "自身压力 −2.5（动作结束时一次性）", "§17.3.1"),
            F("计算方式", "参数直减", "§17.3.1"),
            F("结算时机", "**动作结束时一次性结算**", "§17.3.1"),
            F("结算次数", "每次动作 1 次", "§17.3.1"),
            F("中断后处理", "被打断不回血，只付打断代价", "§17.3.1"),
            F("玩家获得的信息", "无专属情报", ""),
            F("可见范围", "动作公开可见", "§17.3.1"),
            F("提示／日志／动画", "待定", ""),
            F("请求", "NPC 概率命中（仅持有者）", "§17.3.2"),
            F("校验", "持有书、空闲、相位", "§17.3.2"),
            F("执行", "占用 40 tick", "§17.3.1"),
            F("结算与反馈", "结束时压力 −2.5", "§17.3.1"),
            F("释放占用", "时长走完释放", "§17.3.1"),
            F("无法开始", "无书、相位不允许、自己忙或在睡", "§17.3.2"),
            F("玩家取消", "不适用（玩家 P0 不可用）", "§17.3.2"),
            F("外部事件打断", "上课铃 → 不结算减压", "§17.3.1"),
            F("释放移动锁", "占用期间不可移动", "§17.3.1"),
            F("释放占用／会话", "结束或中断时释放", "§17.3.1"),
            F("资源预留与返还", "书为持有物，不掉落不消耗（P0）；赠送/没收 P3", "§17.3.2、§17.6 ⑤"),
            F("正常路径", "持有者占用 40 tick → 压力 −2.5", "§17.3.1"),
            F("失败与边界路径", "物品门控不得用「前三天送书」等日期写法（违反不变式 1，已废弃）", "§17.3.2"),
            F("验收标准", "第五道门：看书须有非零上场率（仅持有者样本内）", "§17.5 验收 4"),
        ],
    },
    {
        "id": "leave_class",
        "name": "出门",
        "status": "未开工（P0 规格完成 2026-10-09）",
        "new": True,
        "table": {
            "kind": "玩家独有（状态层 + 快进）", "duration": "本课间剩余时间",
            "payoff": "不适用（邻居 A −3）", "noise": "不适用", "join_mode": "不适用",
        },
        "ov": {
            "实现状态": "未开工（P0-3；玩家独有）",
            "位置姿态（现状）": "离开教室（不在场）",
            "时间倍率（现状）": "待定：快进语义（跳过本课间剩余时间）",
            "触发／门槛（现状）": "玩家主动；每课间限 1 次；上课段不可出",
            "主要效果": "对 8 邻域邻居 A −3（leave_absence，待落 w_events）",
        },
        "f": [
            F("层级类型", "状态层 + 快进（玩家独有）；跳过本课间剩余时间", "§17.3.3"),
            F("数值分类（A–E）", "不适用（社交代价经 w_events 落 A）", "§17.3.3"),
            F("定义版本／状态", "未开工（P0-3；出门为玩家独有，NPC 出门不在本版本）", "§17.3.3"),
            F("规则来源", "v4/17 §17.3.3；`data/rules/player_absence.csv`（待建）；`w_events.leave_absence`（待建）",
              "docs/gdd/v4/17-P0功能细分规格.md"),
            F("实现位置", "（无实现）内核玩家状态 + 快进接口", "§17.5"),
            F("kind", "玩家独有动作（不进 behaviors.csv 的 NPC 触发体系）", "§17.3.3"),
            F("行为用途", "出教室透口气：跳过本课间剩余时间，代价是邻居好感下降", "§17.3.3"),
            F("收益档 payoff", "不适用（社交代价 base 3，常规档上限）", "§17.3.3"),
            F("发起方式", "仅玩家主动（NPC 不做）", "§17.3.3"),
            F("允许阶段", "课间；上课段不可出", "§17.3.3"),
            F("发起者", "玩家", ""),
            F("目标", "无（代价落在邻居身上）", "§17.3.3"),
            F("人数范围", "1", ""),
            F("加入／退出规则（join_mode）", "不适用", ""),
            F("状态条件", "课间相位、本课间未出门过、玩家未处于其他占用", "§17.3.3"),
            F("允许区域／交互点", "教室外（不在场）", "§17.3.3"),
            F("姿态要求", "不适用", ""),
            F("距离／遮挡／相邻规则", "代价对象 = 8 邻域座位同桌（邻居，非全班）", "§17.3.3"),
            F("执行中需持续满足的条件", "出门期间玩家不参与任何判定与涓流", "§17.3.3"),
            F("条件不满足时", "不可发起（每课间已用过 / 上课段）", "§17.3.3"),
            F("决策侧（做不做）", "玩家选择（跳过决策侧）", "§10.1（v4）"),
            F("判定侧（成不成）", "无判定（出门必定成功）", "§17.3.3"),
            F("玩家确认", "玩家自己选择", "§10.1（v4）"),
            F("判定读值（信念／真值）", "读真值邻接关系（座位 8 邻域）", "§17.3.3"),
            F("duration（tick）", "本课间剩余时间（快进；不是固定时长）", "§17.3.3"),
            F("执行结束条件", "课间结束（相位切换）", "§17.3.3"),
            F("时间倍率", "待定：快进语义如何与 TimeFlow 三倍速相互作用（规格未定义）", "待裁定"),
            F("资源／次数／冷却", "每课间至多 1 次（`player_absence.csv max_per_break=1`）", "§17.3.5"),
            F("移动模式", "离场（不参与教室内的移动体系）", "§17.3.3"),
            F("占用对象", "玩家自己（不在场）", "§17.3.3"),
            F("允许并发行为", "无（玩家不参与任何判定与涓流）", "§17.3.3"),
            F("噪音 noise", "不适用", ""),
            F("效果清单（w_events）", "leave_absence（axis=affinity，base=−3，tier=normal，待落表）", "§17.3.3、§17.3.5"),
            F("方向与对象", "**邻居 → 玩家** 好感 −3（8 邻域同桌各 1 次）；全班不叠加", "§17.3.3"),
            F("计算方式", "统一影响公式（常规档上限 base 3）", "§17.3.3"),
            F("结算时机", "出门动作生效时一次性结算（对每位邻居各 1 次）", "§17.3.3"),
            F("结算次数", "每位邻居 1 次；每课间最多出门 1 次", "§17.3.3"),
            F("中断后处理", "相位切换即结束；已结算的邻居好感不回滚", "§17.3.3"),
            F("玩家获得的信息", "无专属情报（代价不做即时提示：需裁定是否提示）", "待裁定"),
            F("可见范围", "玩家不在场，NPC 照常结算", "§17.3.3"),
            F("来源／可靠程度", "邻居直接感知（一手）", "§17.3.3"),
            F("提示／日志／动画", "待定（表现层：门口/走廊）", ""),
            F("请求", "玩家点击菜单「出门」", "§17.3.3"),
            F("校验", "相位为课间、本课间未用过", "§17.3.3"),
            F("执行", "快进本课间剩余时间；NPC 照常结算；玩家学习/减压全部不结算", "§17.3.3"),
            F("结算与反馈", "出门生效时对 8 邻域邻居各结算 A −3", "§17.3.3"),
            F("释放占用", "课间结束回到教室（相位切换时复位）", "§17.3.3"),
            F("无法开始", "上课段；本课间已出门一次", "§17.3.3"),
            F("玩家取消", "规格未定义（出门后是否可提前回来）", "待裁定"),
            F("目标离开", "不适用", ""),
            F("外部事件打断", "不适用（本身就是快进到相位结束）", ""),
            F("释放移动锁", "出门期间玩家不可操作教室内行为", "§17.3.3"),
            F("释放占用／会话", "课间结束释放", "§17.3.3"),
            F("资源预留与返还", "无", ""),
            F("倍率覆盖", "待定：快进与 3× 的叠加口径未定义", "待裁定"),
            F("正常路径", "课间出门 → 快进 → 邻居 A −3", "§17.3.3"),
            F("失败与边界路径", "出门期间玩家的学习（成绩累积）与减压一律不结算", "§17.3.3"),
            F("验收标准", "玩家出门不得被算作学习时间；邻居代价只落 8 邻域", "§17.3.3"),
        ],
    },
]


# ══════════════════════════════════════════════════════════════════════
# 生成
# ══════════════════════════════════════════════════════════════════════
def build():
    wb = Workbook()
    wb.remove(wb.active)

    _, behavior_rows = load_table("data/rules/behaviors.csv")
    behavior_by_id = {row.get("behavior", ""): row for row in behavior_rows}

    write_guide_sheet(wb)
    write_overview_sheet(wb, behavior_by_id)
    write_learning_sheet(wb)
    for index, event in enumerate(EVENTS, start=1):
        write_event_sheet(wb, "%02d_%s" % (index, event["id"]), event, behavior_by_id)
    write_w_events_sheet(wb)
    write_probability_sheet(wb)
    write_threshold_sheet(wb)
    write_geometry_sheet(wb)
    write_time_sheet(wb)
    write_status_tag_sheet(wb)
    write_social_event_sheet(wb)

    wb.save(OUT)
    print("saved:", OUT)


def write_guide_sheet(wb):
    ws = new_sheet(wb, "填写说明", [30, 96, 34])
    ws.cell(row=1, column=1, value="行为事件表 · 填写模板（标准格式 + 现状预填）").font = TITLE_FONT
    ws.cell(row=2, column=1,
            value="生成：tools/export_event_cards.py ｜ 现状快照：2026-10-09 仓库版本 ｜ 数值一律以 data/ 为准").font = NOTE_FONT
    row = 4

    def section(title):
        nonlocal row
        write_block_title(ws, row, title, 3)
        row += 1

    def line(text, source=""):
        nonlocal row
        write_row(ws, row, [text, source, ""], fills={3: FILL_IN})
        row += 1

    section("怎么用")
    line("1. 先在「总览」看 23 个事件的清单、现状与分类，确认这次大调整要动哪些事件。", "Sheet：总览")
    line("2. 读「学习维度」：成绩轴 grade、学习时长累加器、分段表、P0 新参数；并裁定 ④ 的学习判定口径。", "Sheet：学习维度")
    line("3. 逐事件到对应 sheet（01_study … 23_leave_class），只在「新值／改动（填写）」列写你的调整。", "Sheet：01_* … 23_*")
    line("4. 现状列是只读参考：重跑生成脚本会被覆盖，不要在现状列做长期笔记。", "")
    line("5. 数值类改动同步改「效果表」「概率表」「判定门槛」「位置几何」「时间与相位」，学习维度相关改「学习维度」页。", "")
    line("6. 改完按 AGENTS.md 跑快门禁（check_config / test_core / verify_formula / check_docs），再把方案落回 v4 主文档（§8 / §9 / §10 / §17）与 CHANGELOG。",
         "AGENTS.md 提交与 PR")

    section("列说明（事件卡与各数据表一致）")
    line("分区 / 字段", "13 个维度，所有事件共用同一套字段；缺失填「（未记录）」")
    line("现状（预填）", "2026-10-09 仓库行为；冲突或未定义处已就地标注")
    line("来源", "该现状的证据来源：配置表 / 组件脚本 / 主文档小节")
    line("新值／改动（填写）", "本次大调整要写成什么样（可直接写新规则或「沿用」）")
    line("备注（填写）", "风险、待定项、需要同步改的配置键")

    section("必须拆细的三处（否则会重现老问题）")
    line("① 加点的方向与时机：「发起者→目标的好感」与「发起者自身压力」是两条效果；还要写清开始结算还是完成结算。",
         "docs/design/行为事件标准格式.md §2")
    line("② 判定不能只填是/否：位置检查、NPC 是否接受、玩家是否同意、行为是否成功是不同步骤；玩家主动同意后不再掷骰替玩家选择。", "")
    line("③ 位置必须含姿态与执行期移动规则：学习/睡觉要求到座位并坐下；聊天可站可坐，但正式开始要取消原行走路线并锁定移动。", "")

    section("统一流程模板（不需要的阶段可省略）")
    line("请求 → 条件检查 → 接近位置 → 姿态准备 → 确认／判定 → 执行 → 结算与反馈 → 释放占用", "事件卡「⑩ 具体流程」即按此展开")
    line("现状澄清 1：**已实现的行为**一律在「执行」起点一次性施加效果，没有「完成时结算」；把已实现行为改成完成时结算属于玩法变更。",
         "scripts/systems/behaviors/*.gd")
    line("现状澄清 2：P0 规格（§17.3.1）首次引入第二类时机——听音乐/吃零食/看书**在动作结束时结算**；被相位切换打断时「减压不结算、只付打断代价」。",
         "docs/gdd/v4/17-P0功能细分规格.md")

    section("标记约定（「定义版本／状态」列）")
    line("已实现", "内核与组件都已通：chat / join_chat / tease / report / rumor / roughhouse / exclude / comfort / ask_help / apologize / sleep / study / ask_about")
    line("部分实现", "配置或即时效果在、结构未落地：move（NPC 耗时）、rumor（记忆模型）、inform")
    line("未实装", "有规格与配置、无组件：share_secret")
    line("未启用", "显式关闭且不在排期：eavesdrop")
    line("已合并", "不再是独立行为：pass_note")
    line("未开工（规格已定）", "19–23：老师巡查 / 听音乐 / 吃零食 / 看书 / 出门 —— P0 规格完成、实现未开工；这些卡的现状列填的是**规格**，不是代码行为")

    section("现状来源（2026-10-09 快照）")
    for item in [
        "data/rules/behaviors.csv —— kind / duration / payoff / noise / join_mode",
        "data/balance/w_events.csv —— 每条效果的轴 / 档位 / 性格敏感度",
        "data/rules/behavior_probs.csv —— 环境类每 tick 概率与涓流",
        "data/rules/behavior_thresholds.csv —— 阈值类与判定侧门槛",
        "data/rules/player_interaction.csv —— 闲聊范围、邀请超时、线索条数",
        "data/rules/movement.csv —— 速度、碰撞半径、导航容差",
        "data/rules/seats.csv、stand_points.csv —— 座位与站立点",
        "data/rules/phases.csv —— 相位时长 / 启用规则 / 玩家权限",
        "data/rules/time_flow.csv、time_runtime.csv、time_presentation.csv —— 倍率与学期长度",
        "data/rules/status_tags.csv —— 心结、秘密同盟",
        "docs/gdd/v4/ 拆分版主文档（§8 人物行为 / §9 人物设计 / §10 玩家操作 / §11 社会事件 / §14 工程规范）—— 行为、玩家操作、社会事件",
        "docs/gdd/v4/17-P0功能细分规格.md —— 学习维度（成绩轴 / 学习时长累加器 / 老师巡查 / 减压三动作 / 出门 / 上课好感涓流）",
        "scripts/systems/behaviors/*.gd、scripts/core/sim_core.gd —— 结算点位与顺序",
    ]:
        line(item)

    section("边界声明")
    line("本文件只承载设计填写，不表示任何新规则已经批准；现行规则仍以 docs/gdd/v4/ 拆分版主文档为准。", "")
    line("现状列与 data/ 冲突时以 data/ 为准；「未记录」表示该字段在现行规格与实现里都没有定义。", "")


def write_learning_sheet(wb):
    """学习维度（P0-1 成绩轴）：轴定位 / 涓流与累加器 / 分段表 / 判定口径待裁定 / 新参数汇总。"""
    ws = new_sheet(wb, "学习维度", [30, 66, 26, 40, 24])
    ws.cell(row=1, column=1, value="学习维度（成绩轴 grade）· P0-1 规格 ｜ 实现状态：未开工").font = TITLE_FONT
    ws.cell(row=2, column=1,
            value="来源：docs/gdd/v4/17-P0功能细分规格.md ｜ 参数为标定起点，正式取值以 data/ 为准").font = NOTE_FONT
    row = 4

    def section(title):
        nonlocal row
        write_block_title(ws, row, title, 5)
        row += 1

    def kv(label, value, source="", hint=""):
        nonlocal row
        write_row(ws, row, [label, value, source, hint, ""], fills={1: LABEL_FILL, 4: FILL_IN, 5: FILL_IN})
        row += 1

    section("① 轴定位（与 好感／敌对／信任／压力 不同层）")
    kv("轴名 / 变量", "成绩 grade[i]（个体状态量）", "§17.1.1")
    kv("层级", "与压力同层；**不进 A/H/T 矩阵、不参与统一影响公式与传导**", "§17.1.1")
    kv("值域", "0–750（grade_max = 750）", "§17.1.4")
    kv("初始值", "玩家 250 固定（grade_init_player）；NPC 200–650 种子化均匀抽样（grade_init_npc_min/max）——开局种子层，运行期与玩家同权", "§17.1.1")
    kv("呈现", "time_hud 右上角「成绩 NNN ｜ 距期末考 N 天」；期末考日 = 第 30 天（term_days，属学期制度）；玩家看不到 NPC 具体分数", "§17.1.3")
    kv("数值通道", "**不走 w_events**：增长来自学习时长累加器；考试结算在 P2 规格", "§17.1.2")
    kv("禁止项", "不做身份 / 角色 ID 判断，不按性格 J 维做初始偏置；「爱学习」是标签与行为的产物", "§17.1.1、§9.11")

    section("② 成绩涓流：学习时长累加器（绕开 0.1 舍入）")
    kv("累加器", "study_acc[i]：每 tick 处于「学习状态」时 +1", "§17.1.2")
    kv("「学习状态」判定", "主行为 = 学习，或默认空闲（§8.15 注释语义）——口径待裁定，见 ④", "§17.1.2")
    kv("升分", "study_acc ≥ ticks_per_point(grade) 时 grade += 1、study_acc -= ticks_per_point（按当前档查表）", "§17.1.2")
    kv("上限", "grade = 750 时 acc 清零、不再累积", "§17.1.2")
    kv("上课段", "**不累积**（被动听讲 ≠ 自主学习；是否计入列为 §17.6 ① 开放项）", "§17.1.2")
    kv("跨天", "study_acc 保留，不随 settle_day 清零（「学了一半」不蒸发）", "§17.1.2")
    kv("打断语义（P1）", "非自愿清空、自愿保留（P1 §18.1.2 已裁决）", "§17.6 ②")
    kv("量级预估", "<300 档约 +12 分/天（玩家 250 起步正处此档）；≥650 档约 +3–4 分/天，领先者自然放缓", "§17.1.2")

    section("③ 分段表 grade_table.csv（每档 +3s 推定；整列可调，改表不改代码）")
    write_header_row(ws, row, ["成绩区间", "每 +1 分所需 tick", "等效速率（仅供参考）", "新值／改动（填写）", "备注（填写）"])
    row += 1
    for band, ticks, rate in [
        ("< 300", 10, "~0.100 分/tick"),
        ("300–349", 13, "~0.077"),
        ("350–399", 16, "~0.063"),
        ("400–449", 19, "~0.053"),
        ("450–499", 22, "~0.045"),
        ("500–549", 25, "~0.040"),
        ("550–599", 28, "~0.036"),
        ("600–649", 31, "~0.032"),
        ("650–699", 34, "~0.029"),
        ("700–750", 37, "~0.027"),
    ]:
        write_row(ws, row, [band, ticks, rate, "", ""], fills={4: FILL_IN, 5: FILL_IN})
        row += 1
    row += 1

    section("④ 「学习状态」判定：两种口径（待你裁定；选一个写进 study 卡）")
    kv("口径 A（现行实现）", "默认空闲即学习：不做任何主行为且未走动即为学习；成绩累积与老师豁免都按此口径", "§8.15、§17.1.2",
       "候选 A：保持现状")
    kv("口径 B（上一轮建议）", "必须「在允许学习的座位/书桌交互点 + 已坐下 + 未移动 + 未参加其他活动」才算学习；离开座位或开始走路即退出", "用户 2026-10-09 指出",
       "候选 B：加位置与姿态门槛")
    kv("联动 ①：成绩", "口径直接决定 study_acc 何时累加（口径 B 会让「不忙但在走廊晃」不再涨分）", "§17.1.2")
    kv("联动 ②：老师豁免", "老师到场加压的豁免名单是「睡觉 / 学习 / 出门」——口径决定谁免于 +3", "§17.2.3")
    kv("联动 ③：压力涓流", "现行 study_stress（每天 2 次、每次 +1）按「不忙即在学」结算；口径 B 需同步改判定", "behavior_probs.csv")

    section("⑤ 新增参数汇总（§17.4 标定清单，均待落 data/）")
    write_header_row(ws, row, ["表", "键", "初值（标定起点）", "新值／改动（填写）", "备注（填写）"])
    row += 1
    for table, key, init, note in [
        ("grade_table.csv", "band_upper / ticks_per_point ×10", "见 ③ 分段表", "整列可调，改表不改代码"),
        ("grade_table.csv", "grade_max / grade_init_player / grade_init_npc_min / grade_init_npc_max", "750 / 250 / 200 / 650", "玩家固定 250；NPC 随机 200–650"),
        ("teacher.csv", "visit_checks / visit_p", "25,65 / 0.25", "到场率 ≈43.75%/课间，至多 1 次"),
        ("teacher.csv", "stay_ticks / suppress_behavior_mult / volume_target_mult", "30 / 0.3 / 0.5", "停留半段课间；压场走环境层"),
        ("leisure.csv", "三项 relief（music / snack / book）", "2.0 / 1.5 / 2.5", "动作结束时结算"),
        ("leisure.csv", "三项 duration（music / snack / book）", "30 / 15 / 40", "tick"),
        ("leisure.csv", "snack_count_per_run", "5", "玩家每局零食份数"),
        ("player_absence.csv", "max_per_break", "1", "每课间出门上限；社交代价落在 w_events"),
        ("behavior_probs.csv", "music_p / snack_p / book_p", "0.02 / 0.02 / 0.02", "NPC 触发概率（标定起点）"),
        ("w_events.csv", "teacher_visit_stress / leave_absence", "3 / −3", "均常规档（stress / affinity）"),
        ("transmission.csv", "class_affinity_gain", "0.2", "上课好感涓流：相邻且清醒对子，每天 2 次"),
        ("seeds.csv", "book 列", "8 人班 3 / 16 人班 6 / 24 人班 10 为 1", "环境事实，非倾向；按难度缩放"),
    ]:
        write_row(ws, row, [table, key, init, "", note], fills={4: FILL_IN})
        row += 1
    row += 1

    section("⑥ 待建数据表（脚本自动检测存在性）")
    for rel in [
        "data/rules/grade_table.csv", "data/rules/teacher.csv",
        "data/rules/leisure.csv", "data/rules/player_absence.csv",
    ]:
        exists = os.path.exists(os.path.join(ROOT, rel))
        kv(rel, "已存在" if exists else "**待建**", "§17.1.4 / §17.2.5 / §17.3.5")
    for rel, change in [
        ("data/characters/seeds.csv", "新增 book 列（0/1）"),
        ("data/rules/behavior_probs.csv", "新增 music_p / snack_p / book_p"),
        ("data/balance/w_events.csv", "新增 teacher_visit_stress / leave_absence"),
        ("data/rules/transmission.csv", "新增 class_affinity_gain"),
    ]:
        kv(rel, change + ("（已存在，待加列/行）" if os.path.exists(os.path.join(ROOT, rel)) else "（表待建）"), "§17.4")

    section("⑦ 验收与开放项")
    kv("验收 1 对拍", "同种子跑 7 天，grade 序列与 study_acc 逐位一致（Python ↔ GDScript）", "§17.5-1")
    kv("验收 2 手算", "连续学习 100 tick：<300 档 → +10 分；700 档 → +2 分（余 26 tick）", "§17.5-2")
    kv("验收 3 老师", "到场率 ≈43.75%/课间（±抽样噪声），任意课间到场 ≤1 次", "§17.5-3")
    kv("验收 4 六道门", "爆发均值预期下移（减压出口与老师加压反向）；好感均值 32.4 是唯一未达标门；新减压项须有非零上场率", "§17.5-4")
    kv("开放 ① 上课段计入", "现：不计入；裁决时点 P1 标定轮", "§17.6 ①")
    kv("开放 ② 打断清空 acc", "已在 P1 §18.1.2 裁决（非自愿清空、自愿保留）", "§17.6 ②")
    kv("开放 ③ 快速学习", "已在 P1 §18.1 规格化", "§17.6 ③")
    kv("开放 ④ 周考 / 奖励", "已在 P2 §19.1 规格化（exam.csv + 进步奖 / 特等奖 / 免罚卷）", "§17.6 ④")
    kv("开放 ⑤ 课外书赠送 / 没收", "P3 物品系统（P0 玩家 0 本、入口灰置）", "§17.6 ⑤")
    kv("开放 ⑥ 老师压制窃听 / 流言", "观察一批实测后决定", "§17.6 ⑥")


def write_overview_sheet(wb, behavior_by_id):
    headers = [
        "序号", "行为 ID", "中文名", "kind", "层级类型", "实现状态", "发起方式", "参与者分类",
        "duration(tick)", "payoff", "noise", "join_mode", "触发／门槛（现状）",
        "位置与姿态（现状）", "时间倍率（现状）", "主要效果（w_events）", "本次调整（填写）",
    ]
    ws = new_sheet(wb, "总览", [6, 14, 12, 10, 20, 34, 26, 12, 12, 8, 7, 10, 40, 34, 22, 40, 34])
    write_header_row(ws, 1, headers)
    row = 2
    for index, event in enumerate(EVENTS, start=1):
        src = behavior_by_id.get(event["id"], {})
        over = event.get("table", {})
        ov = event["ov"]
        field = {f[0]: f[1] for f in event["f"]}
        values = [
            index, event["id"], event["name"], over.get("kind", src.get("kind", "")),
            field.get("层级类型", ""),
            ov.get("实现状态", ""),
            field.get("发起方式", ""),
            field.get("人数范围", ""),
            over.get("duration", src.get("duration", "")),
            over.get("payoff", src.get("payoff", "")),
            over.get("noise", src.get("noise", "")),
            over.get("join_mode", src.get("join_mode", "")),
            ov.get("触发／门槛（现状）", ""), ov.get("位置姿态（现状）", ""),
            ov.get("时间倍率（现状）", ""), ov.get("主要效果", ""), "",
        ]
        write_row(ws, row, values, fills={17: FILL_IN})
        row += 1
    row += 1
    write_block_title(ws, row, "读法", len(headers))
    row += 1
    write_row(ws, row, ["1", "「层级类型」与「参与者分类」用同一套字段；主行为 / 附加行为 / 状态层 / 默认状态的划分见 v4 主文档 §8 分层总则。", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])
    row += 1
    write_row(ws, row, ["2", "19–23 为 P0 规格（老师巡查 / 听音乐 / 吃零食 / 看书 / 出门）：**实现未开工**，现状列填的是规格而非代码行为；对应参数见「学习维度」页。", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""])


def write_event_sheet(wb, sheet_name, event, behavior_by_id):
    ws = new_sheet(wb, sheet_name, [30, 74, 30, 34, 26])
    ws.cell(row=1, column=1, value="行为卡：%s（%s）" % (event["name"], event["id"])).font = TITLE_FONT
    ws.cell(row=2, column=1, value="现状：%s ｜ 只读列不要改；请在「新值／改动（填写）」列写本次大调整" % event["status"]).font = NOTE_FONT
    headers = ["分区 / 字段", "现状（预填：2026-10-09 仓库快照）", "来源", "新值／改动（填写）", "备注（填写）"]
    row = 4
    write_header_row(ws, row, headers)
    row += 1

    src = behavior_by_id.get(event["id"], {})
    over = event.get("table", {})
    source_note = "behaviors.csv" if src else "P0 规格（待落表）"
    auto = {
        "行为 ID": (event["id"], "behaviors.csv" if src else "P0 规格（待落 behaviors.csv）"),
        "事件名": (event["name"], "behaviors.csv" if src else "P0 规格"),
        "kind": (over.get("kind", src.get("kind", "")), source_note),
        "收益档 payoff": (over.get("payoff", src.get("payoff", "")), source_note),
        "duration（tick）": (over.get("duration", src.get("duration", "")), source_note),
        "噪音 noise": (over.get("noise", src.get("noise", "")), source_note),
        "加入／退出规则（join_mode）": (over.get("join_mode", src.get("join_mode", "")), source_note),
    }
    filled = {f[0]: (f[1], f[2]) for f in event["f"]}
    hints = event.get("hints", {})
    notes = event.get("notes", {})

    for section, field_names in SECTIONS:
        write_block_title(ws, row, section, len(headers))
        row += 1
        for field in field_names:
            if field in filled:
                current, source = filled[field]
            elif field in auto:
                current, source = auto[field]
            elif field in DEFAULTS:
                current, source = DEFAULTS[field]
            else:
                current, source = "（未记录）", ""
            write_row(ws, row, [field, current, source, hints.get(field, ""), notes.get(field, "")],
                      fills={1: LABEL_FILL, 4: FILL_IN, 5: FILL_IN})
            row += 1


def write_raw_block(ws, row, title, headers, rows):
    """写一个「原表 + 两列填写栏」的块，返回下一可用行号。"""
    cols = len(headers) + 2
    write_block_title(ws, row, title, cols)
    row += 1
    write_header_row(ws, row, headers + ["新值／改动（填写）", "备注（填写）"])
    row += 1
    for data in rows:
        values = [data.get(head, "") for head in headers] + ["", ""]
        write_row(ws, row, values, fills={cols - 1: FILL_IN, cols: FILL_IN})
        row += 1
    return row + 1


def write_w_events_sheet(wb):
    headers, rows = load_table("data/balance/w_events.csv")
    owner_map = {
        "tease": "tease", "reject": "join_chat（被拒反噬）", "report": "report",
        "comfort": "comfort", "roughhouse": "roughhouse", "conformity": "从众（§9.5）",
        "noise": "音量氛围（§9.2）", "exclude": "exclude", "leak": "share_secret",
        "humiliate": "tease（羞辱档）", "topic": "chat", "rumor": "rumor",
        "ask_help": "ask_help", "apologize": "apologize",
        "teacher": "teacher_patrol", "leave": "leave_class",
    }
    enriched = []
    for data in rows:
        event_id = data.get("event_id", "")
        owner = ""
        for prefix, name in owner_map.items():
            if event_id.startswith(prefix):
                owner = name
                break
        item = dict(data)
        item["归属行为"] = owner
        enriched.append(item)
    ws = new_sheet(wb, "效果表 w_events", [28, 10, 8, 8, 8, 8, 8, 10, 8, 40, 22, 24, 20])
    write_block_title(ws, 1, "效果表（w_events.csv）：方向由「归属行为 + 轴 + base 正负」共同决定，请在填写栏写明方向与结算时机", len(headers) + 3)
    next_row = write_raw_block(ws, 2, "全部效果行（%d 条）" % len(enriched),
                               headers + ["归属行为"], enriched)
    pending = [
        {"event_id": "teacher_visit_stress", "axis": "stress", "base": "3", "tier": "normal",
         "class": "—", "note": "老师巡查到场：全班压力 +3（豁免 睡觉 / 学习 / 出门）",
         "归属行为": "teacher_patrol"},
        {"event_id": "leave_absence", "axis": "affinity", "base": "-3", "tier": "normal",
         "class": "—", "note": "出门：8 邻域邻居对玩家好感 −3（常规档上限）",
         "归属行为": "leave_class"},
    ]
    write_raw_block(
        ws, next_row,
        "P0 待创建效果行（尚未落 data/balance/w_events.csv；来源 §17.2.5、§17.3.5）",
        headers + ["归属行为"], pending,
    )


def write_probability_sheet(wb):
    headers, rows = load_table("data/rules/behavior_probs.csv")
    ws = new_sheet(wb, "概率表 behavior_probs", [26, 12, 70, 26, 22])
    write_block_title(ws, 1, "环境类概率与涓流（behavior_probs.csv）", len(headers) + 2)
    write_raw_block(ws, 2, "全部参数（%d 条）" % len(rows), headers, rows)


def write_threshold_sheet(wb):
    headers, rows = load_table("data/rules/behavior_thresholds.csv")
    ws = new_sheet(wb, "判定门槛", [24, 22, 8, 10, 78, 24, 22])
    write_block_title(ws, 1, "阈值与判定侧门槛（behavior_thresholds.csv）：决策侧（做不做）与判定侧（成不成）必须分别填写", len(headers) + 2)
    write_raw_block(ws, 2, "全部门槛（%d 条）" % len(rows), headers, rows)


def write_geometry_sheet(wb):
    ws = new_sheet(wb, "位置几何", [34, 12, 10, 74, 24, 22])
    row = 1
    for rel, title in [
        ("data/rules/player_interaction.csv", "玩家交互几何与线索参数"),
        ("data/rules/seats.csv", "座位表（空间层）"),
        ("data/rules/stand_points.csv", "站立点（空闲站立位置）"),
        ("data/rules/movement.csv", "移动与导航参数"),
    ]:
        headers, rows = load_table(rel)
        if not headers:
            continue
        row = write_raw_block(ws, row, "%s —— %s" % (title, rel), headers, rows)


def write_time_sheet(wb):
    ws = new_sheet(wb, "时间与相位", [26, 12, 12, 60, 24, 22])
    row = 1
    for rel, title in [
        ("data/rules/phases.csv", "相位定义（时长 / 启用规则 / 玩家权限）"),
        ("data/rules/time_flow.csv", "世界倍率（走路正常速度；玩家占用型行为三倍）"),
        ("data/rules/time_runtime.csv", "时间运行时参数"),
        ("data/rules/time_presentation.csv", "时间呈现参数"),
    ]:
        headers, rows = load_table(rel)
        if not headers:
            continue
        row = write_raw_block(ws, row, "%s —— %s" % (title, rel), headers, rows)


def write_status_tag_sheet(wb):
    headers, rows = load_table("data/rules/status_tags.csv")
    ws = new_sheet(wb, "状态标签", [20, 8, 12, 12, 30, 12, 10, 70, 24, 22])
    write_block_title(ws, 1, "状态标签（跨天持续状态，与一次性效果、乘性衰减是三种语义）", len(headers) + 2)
    write_raw_block(ws, 2, "全部标签（%d 条）" % len(rows), headers, rows)


def write_social_event_sheet(wb):
    ws = new_sheet(wb, "社会事件", [22, 26, 52, 12, 10, 12, 30, 22])
    row = 1
    for rel, title in [
        ("data/rules/social_events.csv", "社会事件表（多阶段、跨相位、改变结构）"),
        ("data/rules/social_event_triggers.csv", "社会事件触发条件"),
    ]:
        headers, rows = load_table(rel)
        if not headers:
            continue
        row = write_raw_block(ws, row, "%s —— %s" % (title, rel), headers, rows)

    stage_headers = ["阶段", "相位", "机制（现状规格）", "玩家可参与", "新值／改动（填写）", "备注（填写）"]
    write_block_title(ws, row, "班委选举五阶段（主文档 §11.4，现状为规格、未实现）", len(stage_headers))
    row += 1
    write_header_row(ws, row, stage_headers)
    row += 1
    stages = [
        ("① 酝酿", "课间", "「改选」作为一条流言进入系统（带倾向、会染色、会被窃听）", "打探 / 表态 / 传话"),
        ("② 提名", "课间", "候选人 = 各强连接簇的话事人（簇内 influence 最高者）", "自荐 / 支持他人"),
        ("③ 模拟投票", "课间", "非正式试探：通过闲聊/打听探口风 → 影响各方信念", "拉票 / 试探 / 虚张声势"),
        ("④ 实际投票", "上课", "正式投票（上课是发酵层，结果在你无法干预时产生）", "只能看情报日志"),
        ("⑤ 结果公布", "放学", "计票 → 新身份 + 簇标签重算 + 简报条目", "看《每日简报》"),
    ]
    for stage in stages:
        write_row(ws, row, list(stage) + ["", ""], fills={5: FILL_IN, 6: FILL_IN})
        row += 1
    row += 1
    write_row(ws, row, ["触发条件（任一，全部为数值判据）",
                        "① 权威崩解：班长曾压力爆发（≥90）且影响跌破中位数　② 阵营分裂：≥2 个稳定簇且簇间平均敌对≥阈值　③ 玩家提议：消耗一次课间动作并满足支持门槛",
                        "", "", "", ""])
    row += 1
    write_row(ws, row, ["投票算法", "U_vote(i,c) = α_A·A[i][c] + α_T·T[i][c] + α_I·influence(c)；softmax(U_vote/τ)，每人一票；平票按 influence 破平；当选者获「班委」身份标签，落选者压力 +4~5（重大档）",
                        "", "", "", ""])


if __name__ == "__main__":
    build()

