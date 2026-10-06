# tests/ —— 测试

> 状态：GUT 9.7.1 已接入 ｜ 维护者：程序 / 测试 ｜ 最后更新：2026-10-06
> 策略依据：[`../docs/qa/测试策略.md`](../docs/qa/测试策略.md)

## 目录规划

```
tests/
├─ unit/          单测：每条规则的分支、公式、钳制
├─ invariants/    铁律测试：无角色 ID 判断、观察层只读、数值不落在脚本
├─ integration/   无头集成：整局推进、存档往返、确定性快照
├─ balance/       批量标定：≥100 局统计（可产出报告）
└─ emergence/     涌现验收：主文档 §15 的 13 条现象用例
```

## 框架选型（已定：GUT 9.7.1）

| 方案 | 优点 | 备注 |
|---|---|---|
| **GUT** | 生态成熟、社区用例多 | **已选定并接入**：`addons/gut/`（v9.7.1，对应 Godot 4.7.x） |
| gdUnit4 | 断言与套件功能更丰富 | 未采用；如后续需要参数化与报告再评估 |

版本记录（2026-10-06）：GUT **9.7.1**（官方兼容表对应 Godot 4.7.x），同步记录于 `../docs/qa/测试策略.md`。

## 运行方式

```bash
# 单测（GUT 9.7.1，已接入）
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# Windows 本机未把 Godot 加入 PATH 时，用 console 版全路径（普通版抓不到 headless 输出）：
# "E:/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# 无头整局（规划中：待内核落地）
godot --headless --path . --script tests/integration/run_term.gd -- --days=30 --seed=12345

# 批量标定（规划中）
godot --headless --path . --script tests/balance/run_batch.gd -- --runs=100 --seed=1
```

## 前提条件（重要）

内核必须**不依赖节点树与渲染**才能被测试驱动：见 [`../docs/design/架构总览.md`](../docs/design/架构总览.md) 第 1 节的边界约束。测试出现"必须先实例化某个场景"时，说明该约束已被破坏，应作为缺陷处理。

## 现状

已接入 GUT 9.7.1（`addons/gut/`），`tests/unit/` 有冒烟用例 `test_smoke.gd`；其余子目录随规则实现建立——**每条规则合入时必须带对应单测**（见 `../CONTRIBUTING.md` 第 8 节 PR 流程）。
