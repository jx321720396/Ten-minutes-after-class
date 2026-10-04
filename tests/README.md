# tests/ —— 测试

> 状态：骨架 ｜ 维护者：程序 / 测试 ｜ 最后更新：2026-10-04
> 策略依据：[`../docs/qa/测试策略.md`](../docs/qa/测试策略.md)

## 目录规划

```
tests/
├─ unit/          单测：每条规则的分支、公式、钳制
├─ invariants/    铁律测试：无角色 ID 判断、观察层只读、数值不落在脚本
├─ integration/   无头集成：整局推进、存档往返、确定性快照
├─ balance/       批量标定：≥100 局统计（可产出报告）
└─ emergence/     涌现验收：v3.0 §15 的 13 条现象用例
```

## 框架选型（待定，M1 前决定）

| 方案 | 优点 | 备注 |
|---|---|---|
| **GUT** | 生态成熟、社区用例多 | 作为默认候选 |
| gdUnit4 | 断言与套件功能更丰富 | 若需要参数化与报告再评估 |

选定后需在 `addons/` 下安装，并在本文件与 `../docs/qa/测试策略.md` 中记录版本。

## 运行方式（规划）

```bash
# 单测（需先安装测试框架）
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# 无头整局（确定性检查：同种子同结果）
godot --headless --path . --script tests/integration/run_term.gd -- --days=30 --seed=12345

# 批量标定
godot --headless --path . --script tests/balance/run_batch.gd -- --runs=100 --seed=1
```

## 前提条件（重要）

内核必须**不依赖节点树与渲染**才能被测试驱动：见 [`../docs/design/架构总览.md`](../docs/design/架构总览.md) 第 1 节的边界约束。测试出现"必须先实例化某个场景"时，说明该约束已被破坏，应作为缺陷处理。

## 现状

当前目录仅有本说明文件（M0）。测试框架与用例在 M1 随规则实现同步建立——**每条规则合入时必须带对应单测**（见 `../CONTRIBUTING.md` 第 8 节 PR 流程）。
