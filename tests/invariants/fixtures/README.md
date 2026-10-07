# fixtures/ —— 铁律扫描器的「哨兵样本」

> ⚠️ **这些文件是故意违反铁律的。不要"修好"它们。**

## 它们干什么用

`tests/invariants/` 的三个铁律脚本各带一段**哨兵自检**：先拿本目录当扫描目标跑一遍，
**必须**报出违规 —— 报不出来，说明扫描器本身坏了（正则写错、路径过滤失效、编码问题…），
此时脚本会把哨兵判为 `[FAIL]`。

这就解决了一个要命的问题：`scripts/core/`、`scripts/systems/`、`scripts/npc/`
还没落地时，铁律 1/3 只能一直显示「暂时没测到」，**没人知道扫描器到底能不能用**。
有了哨兵，扫描器每天都被真正的违规样本检验一次。

## 目录内容

| 文件 | 故意违反的铁律 | 触发规则 |
|---|---|---|
| [`scripts/systems/behavior_rules.gd`](scripts/systems/behavior_rules.gd) | 铁律 1 无角色名 / 角色 ID 判断 | `char_id == 7`、`"陈阳"`、`CHAR_05` |
| [`scripts/npc/decide.gd`](scripts/npc/decide.gd) | 铁律 3 数值不落在脚本里 | 魔法数字 `3.5`、`1.4`、`12.0` |
| [`scripts/systems/observer/labeler.gd`](scripts/systems/observer/labeler.gd) | 铁律 2 观察层只读 | `A[viewer][j] = 50.0` 写回矩阵 |
| [`data/characters/seeds.csv`](data/characters/seeds.csv) | —— | 哨兵用的最小种子表（提供 alias） |

## 两条纪律

1. **别修**：看到扫描器报告这些文件违规，那正是它该干的事。
2. **保持语法合法**：这些 `.gd` 会被 Godot 编辑器正常解析（语法正确、只是内容违规），
   所以**不会**污染引擎输出；改动时请保持这一点。
