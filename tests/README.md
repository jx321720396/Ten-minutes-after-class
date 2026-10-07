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

`tests/invariants/` 已落地**铁律测试脚手架**（Python 离线检查，2026-10-06）：

| 脚本 | 铁律 | 现状 |
|---|---|---|
| [`invariants/check_no_character_id.py`](invariants/check_no_character_id.py) | 无角色名 / 角色 ID 判断 | `scripts/systems/`、`scripts/npc/` 未落地 → 「暂时没测到」 |
| [`invariants/check_observer_readonly.py`](invariants/check_observer_readonly.py) | 观察层只读 | 运行时腿借 `tools/core_sim.py` 已跑出真实计数（读 2466 / 写 0） |
| [`invariants/check_magic_numbers.py`](invariants/check_magic_numbers.py) | 数值不落在脚本里 | `scripts/core/`、`systems/`、`npc/` 未落地 → 「暂时没测到」 |

详见 [`invariants/README.md`](invariants/README.md)；一键运行：`bash tools/run_tests.sh`。

`tests/invariants/fixtures/` 是**哨兵夹具**：故意违反铁律的小样本，用来证明扫描器本身有效 ——
内核目录还没落地时，三条铁律不再是「纯 SKIP」，而是「哨兵 PASS + 真实目录 SKIP」。
见 [`invariants/fixtures/README.md`](invariants/fixtures/README.md)。

另外三个子目录也已落地骨架（2026-10-07），策略见 [`../docs/qa/测试策略.md`](../docs/qa/测试策略.md)：

| 目录 | 内容 | 现状 |
|---|---|---|
| [`integration/`](integration/README.md) | 无头整局 `run_term.gd` + **逐 tick 对拍器** [`test_tick_parity.py`](integration/test_tick_parity.py)（Python ↔ GDScript，误差 ≤ 1%） | 内核未落地 → 明确 SKIP；对拍器自带自检 |
| [`balance/`](balance/README.md) | 批量标定 `run_batch.gd` | 内核未落地 → 明确 SKIP；离线口径见 `tools/check_metrics.py`（100 局） |
| [`emergence/`](emergence/README.md) | 主文档第十六章 **13 条现象**验收清单 [`cases.md`](emergence/cases.md) + GUT 骨架 | 逐条 `pending`，内核落地后填断言 |

> 三处共同的纪律：**内核未落地就明确 SKIP，不假绿** —— 宁可显示「暂时没测到」，也不写一个永远通过的假断言。
