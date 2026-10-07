# tests/balance/ —— 批量标定

> 状态：骨架落地 ｜ 维护者：程序 / 测试 ｜ 最后更新：2026-10-07
> 策略依据：[`../../docs/qa/测试策略.md`](../../docs/qa/测试策略.md) §4

## 这里测什么

≥100 局批量跑，验证**整局统计**而非单局：

| 指标 | 目标（主文档 §3.4） |
|---|---|
| 好感增长曲线 | 陌生(20) → 朋友(60) 用 2–3 天 |
| 压力爆发频率 | 每 1–2 天一次，集中第 2、3 段课间 |
| 派系/格局弧线 | 第 1 周成阵营 → 第 2–3 周博弈 → 第 4 周稳定或大事件 |
| 数值饱和 | 30 天后大面积顶到 100 的比例 < 阈值 |

## 与 Python 侧的分工

离线六道门里的 **`tools/check_metrics.py`（100 局）** 与 **`tools/diversity_report.py`（100 局）**
已经承担了同一套判据，而且**不依赖引擎**（见 [`../../docs/qa/测试策略.md`](../../docs/qa/测试策略.md) §4）。

所以本目录的定位是：**当 GDScript 内核落地后**，用引擎内的实现复跑同一批统计，
与 Python 侧结果对拍（误差 ≤ 1%）—— 防止「Python 对、GDScript 不对」。

现状：`scripts/core/` 未落地 → [`run_batch.gd`](run_batch.gd) 明确 SKIP。

## 运行

```bash
godot --headless --path . --script tests/balance/run_batch.gd -- --runs=100 --days=30 --seed=1
```
