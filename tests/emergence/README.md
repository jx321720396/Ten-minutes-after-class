# tests/emergence/ —— 涌现验收

> 状态：骨架落地（用例清单已就位，断言待内核）｜ 维护者：程序 / 测试 / 策划 ｜ 最后更新：2026-10-07
> 现象来源：主文档 [`core-gameplay-v3.1.md`](../../docs/gdd/core-gameplay-v3.1.md) **第十六章「涌现现象对照表」**

## 这里测什么

「这游戏是不是真的在涌现」——主文档第十六章的 **13 条现象**逐条转成**可复现用例**
（固定种子 + 操作序列 → 期望现象），作为里程碑回归清单。

判定原则（设计铁律）：**每一行的右列只能是机制，不能是脚本**。
用例要验证的是「机制跑起来自然长出现象」，不是「写到第 N 天必然发生 X」。

## 用例清单

见 [`cases.md`](cases.md)（13 条现象的机制来源 + 验证方式 + 现状）。
可执行的 GUT 骨架在 [`test_emergence.gd`](test_emergence.gd)，现状为逐条 **pending**。

## 现状（为什么现在全是 pending）

GDScript 内核（`scripts/core/`）与行为层（`scripts/npc/`、`scripts/systems/`）尚未移植 ——
冲刺计划 D8–D10 的交付物。没有内核就没有可观察的模拟，写断言只会变成「写死期望值」，
那恰恰违反本目录的判定原则。

因此现在只落地**用例契约**：现象、机制来源、验证方式、期望观测点。
内核落地后逐条把 `pending(...)` 换成真实断言，这一目录才具备拦截能力。

## 运行（内核落地后）

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/emergence -gexit
```
