# 办公室界面实施计划

> For agentic workers: use superpowers:executing-plans to implement task by task in this chat.

**Goal:** 原生 Godot 办公室第二主界面，保留教室运行并复用已有工具。
**Architecture:** 教室保留原实例，OfficeHub 控制覆盖视图和输入；办公室背景与原生 UI 分离。
**Tech Stack:** Godot 4.7.2、GDScript、内置 imagegen。
**Spec:** ../specs/2026-10-14-office-hub-design.md

## Global Constraints

- 在 main-mobile 当前目录工作，保留已有未提交改动，不改模拟规则。
- 美术与节点分离；颜色、尺寸、入口配置集中 data/ui/office_hub.json。
- 复用同一内核、时钟、百科、档案、推理板，不实现未裁定私聊数值。

## Review Focus

办公室与监控禁用现场输入；往返保留原内核；工具面板高于办公室且关闭后可继续操作；暂停不被意外解除；两种横屏尺寸不溢出。

## Task 1：背景和办公室节点

Files: assets/backgrounds/office/office_idle_v01.webp、data/ui/office_hub.json、scenes/game/office.tscn、scripts/game/office.gd。
- [x] 生成不含 UI 的办公室背景并检查。
- [x] 建立原生容器、按钮、标题、真实时间、暂停与设置节点；运行资源导入。

## Task 2：视图和入口接线

Files: scripts/game/office_hub.gd、scripts/game/classroom.gd、tests/integration/test_office_hub.gd。
Interfaces: OfficeHub.set_mode(mode: String)、mode_name() -> String；Office.bind_sources(clock: Node)、action_requested(action: String)。
- [x] 先写测试，验证办公室/监控/教室输入模式、内核身份不变与时间推进，运行确认失败。
- [x] 保留课堂时钟与导航，切换显示与输入；接通已有百科、推理板与档案，选择学生召唤时显示未接入状态。
- [x] 验证测试通过；现场与办公室共用原有暂停设置。

## Task 3：视觉及项目校验

Files: tests/integration/capture_office_hub.gd、docs/qa/办公室界面验收-2026-10-14.md、CHANGELOG.md。
- [x] 导入资源、GDScript 格式和静态检查、快门禁。
- [x] 捕获 1920×1080 与 1280×720 实际截图，检查六个入口与覆盖面板。
- [x] 更新完成记录与限制；不提交其他并行改动、不推送。

## Execution ledger

Ruling: 使用当前用户指定 main-mobile 工作区，不创建隔离工作树，避免丢失当前改动与协作接线。
Ruling: 用户已要求按设计继续，本聊天直接执行；不另行请求相同实施授权。

完成记录：无 UI 背景已生成，六个入口与原工具接线完成。办公室独立集成测试 PASS；快门禁 313/61/11 项与文档检查通过；GUT unit 413/413。两种横屏实际截图已检查。复查发现的初始禁用状态覆盖和学生列表拖动误选已复现并修复。全仓格式和静态检查的既有问题保留，未提交或推送。

