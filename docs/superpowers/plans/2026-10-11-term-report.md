# 期末结算 Implementation Plan

> 使用 superpowers:executing-plans 在当前工作区执行；用户已明确要求落地，不另开工作区，不覆盖现有修改，不提交或推送。

**Goal:** 让第30天真实结算打开期末报告，并逐事件回放双向情感。

**Architecture:** TermRecord是无节点的只读历史组件，SimCore在权威结算入口记录动作及关系；TermReplay只应用记录到展示副本；TermReport与EmotionMeter负责UI，结局统计与归档独立于玩法。

**Tech Stack:** Godot/GDScript、GUT、JSON配置。

**Spec:** ../specs/2026-10-11-term-report-design.md

## Global Constraints

矩阵只经访问器读取；采集零RNG、零矩阵写入；阈值与呈现参数集中data/；关系不显示数字；保留工作区已有修改。

## Review Focus

同tick增减不能合并丢箭头；NPC邀请不能计成玩家发起；多人加入不能按对象重复计数；拖动不得累计旧箭头；期末不能进入第31天；最大矩阵需要滚动；没有历史时不能补造。

## Tasks

- [ ] 1. GUT失败用例：记录/五格/回放接口尚不存在；验证失败。
- [ ] 2. scripts/core/term_record.gd及SimCore挂钩：真实增量、检查点、动作生命周期、统计导出；验证计数与模拟纯净。
- [ ] 3. scripts/game/term_replay.gd：按序应用、筛选、拖动、重播；验证最终矩阵及同tick增减。
- [ ] 4. scripts/ui/emotion_meter.gd、term_report.gd及对应场景：五格填充箭头、双向选择、矩阵、统计、收尾；配置data/ui/term_report.json。
- [ ] 5. classroom与main_menu接入：期末自动打开、HUD重新打开、结束冻结、上局归档查看。
- [ ] 6. 文档和CHANGELOG同步；GUT全套、离线快门禁、格式静态检查、真实UI截图验收。

## Execution ledger

2026-10-11：设计来自本聊天已确认标准。完整存档恢复、六档结局及推理对照不冒充完成。现有工作区含用户修改，直接在原工作区做最小补丁。
