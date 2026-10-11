# 同学档案 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将用户已确认的同学档案概念图还原为游戏内可复用界面。

**Architecture:** 原生Control场景负责布局，表现层数据适配器仅处理已获得的闲聊记录。点击人物的现有菜单增加档案入口；档案暂停阅读，发起闲聊复用现有交互控制器。

**Tech Stack:** Godot 4.7.2 / GDScript / GUT / 场景内样式与程序纸纹。

**Spec:** `docs/art/ui_mockups/npc_profile_concept_v01.md` 与本会话用户确认；事实依据为主文档闲聊条款及 `PlayerChatIntel` 的历史快照契约。

## Global Constraints

- 不读NPC真实关系矩阵，不修改内核、随机流或模拟数值。
- 已知信息按方向、单轴与各自时间呈现；未知不等于零，不自动判定已过时。
- 角色外观复用场景内Sprite3D贴图；不硬编码角色个性。
- 文案放data/localization，显示档位阈值放data/ui；样式与布局可在场景修改。
- 在现有工作区保留用户未提交改动，不提交、不推送。

## Review Focus

- 同一关系三轴来自不同日期时不能使用同一个时间冒充全部最新。
- 重复记录、乱序记录、未知值与反向关系不能误覆盖。
- 暂停关闭、Esc、点击穿透不能恢复别人的暂停或触发世界操作。
- 无线索开局、长名字、多历史记录、1280×720窗口正常显示。
- 档案按钮与发起闲聊不绕过当前行动/相位检查。

### Task 1: 只读记录适配

Files: `scripts/ui/npc_profile_data.gd`, `data/localization/npc_profile.json`, `data/ui/npc_profile.json`, `tests/unit/test_npc_profile.gd`。

- [ ] 先写测试并确认缺少实现时失败。
- [ ] 实现 `build(history, source, subject)`：最新单轴快照、倒序历史、按请求去重的闲聊交集；只接受已获知记录。
- [ ] 测试方向、逐轴时间、空值与只读性。

### Task 2: 界面与接线

Files: `scenes/ui/npc_profile.tscn`, `scripts/ui/npc_profile.gd`, `scripts/ui/npc_profile_theme.gd`, `assets/shaders/ui_paper.gdshader`；菜单、教室脚本和场景仅增加接线。

- [ ] 原生容器实现人物栏、已知关系、滚动历史、估计空状态；添加字体、纸纹与四态按钮。
- [ ] 添加菜单入口；绑定core/actors/clock/interaction；暂停与聊天调用复用现有流程。
- [ ] 增加UI测试：未知开局、切人、Esc关闭与暂停所有权。

### Task 3: 验收与说明

- [ ] Godot导入、GUT单测与现有集成测试；快门禁、格式与lint。
- [ ] 真实场景截图检查；测试夹具中构建历史记录另验长内容（不向正式游戏注入假数据）。
- [ ] 更新主文档的档案展示条款、架构说明、美术交付清单与CHANGELOG。
- [ ] 汇报验证证据与未解决限制。

## Execution notes

用户已明确要求直接按已确认概念图实现，本轮直接执行，不再等待设计批准。现有工作区有图标/导出配置等修改，本任务不覆盖。
