# tests/invariants/ —— 铁律测试

> 状态：脚手架落地 ｜ 维护者：程序 / 测试 ｜ 最后更新：2026-10-06
> 策略依据：[`../../docs/qa/测试策略.md`](../../docs/qa/测试策略.md) §2 ｜ 铁律出处：[`../../AGENTS.md`](../../AGENTS.md)「硬性约束」

本目录是**设计红线的自动化守门人**：铁律被后续改动悄悄破坏时，这里必须亮红灯。
脚本是 **Python 离线检查**（与本机没有 Godot 的现实一致，见 [`../../tools/README.md`](../../tools/README.md)），
不依赖引擎、不修改工程文件，只读。

## 三个检查脚本

| 脚本 | 铁律 | 查什么 | 命中即 |
|---|---|---|---|
| [`check_no_character_id.py`](check_no_character_id.py) | 1 四层分离 | `scripts/systems/`、`scripts/npc/` 里的角色名字面量、角色编号常量、`char_id == 7` 式比较 | FAIL |
| [`check_observer_readonly.py`](check_observer_readonly.py) | 2 观察层只读 | A 静态扫 `scripts/systems/observer/` 的矩阵写入；B 运行时给 `A/H/T/O` 装计数代理，统计观察层更新期间的**读写次数**，写数必须为 0 | FAIL |
| [`check_magic_numbers.py`](check_magic_numbers.py) | 3 数值集中 | `scripts/core`、`scripts/systems`、`scripts/npc` 里除结构常量外的数值字面量 | FAIL |

公共设施在 [`_common.py`](_common.py)（源码扫描、逐行注释/字符串拆分、报告与退出码）。

## 运行

```bash
python tests/invariants/check_no_character_id.py
python tests/invariants/check_observer_readonly.py
python tests/invariants/check_magic_numbers.py
```

或随一键脚本一起跑（含六道门与 Godot 侧）：

```bash
bash tools/run_tests.sh
```

Windows 本机控制台是 GBK 时，先 `export PYTHONIOENCODING=utf-8`（`run_tests.sh` 已内置）。

## 退出码与「暂时没测到」

- `0` = 通过（含「暂时没测到」）；`1` = 有铁律违规（可接 CI 判红）。
- 目标目录 / 数据表 / 内核模块**不存在**时，脚本标 `[SKIP] 暂时没测到` 并正常退出 ——
  **绝不崩溃**（`_common.guard()` 兜住任何未预料异常）。
- 现状（骨架期）：`scripts/systems/`、`scripts/npc/`、`scripts/core/` 尚未落地，
  铁律 1 / 3 全 `SKIP`；铁律 2 的运行时腿借 `tools/core_sim.py` 已经能跑出真实计数。

## 维护约定

- **白名单在脚本内维护**：铁律 1 的白名单是注释/文档串中的角色名（INFO，不算失败）；
  铁律 3 的白名单是结构常量集合（`check_magic_numbers.py` 的 `WHITELIST`）。
- 新增规则实现时必须让对应铁律测试从 `SKIP` 转为 `PASS`，不允许长期停在「暂时没测到」。
- GDScript 内核落地后，铁律 2 的断言要同步搬进 GUT（`tests/unit/`），Python 侧保留为离线兜底。
