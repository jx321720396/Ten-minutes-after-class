# docs/export/ —— 导出产物（docx）

> 状态：**生成物** ｜ 不入人工编辑 ｜ 最后更新：2026-10-05

本目录存放由 md 规格**自动导出**的 docx，用于分发与阅读（如提交、评审）。
**只读产物**：请勿直接编辑 docx —— 改动请改 md，然后重新导出。

## 产物清单

| 文件 | 来源 |
| --- | --- |
| `下课十分钟-游戏策划案-v3.1.docx` | [`../gdd/core-gameplay-v3.1.md`](../gdd/core-gameplay-v3.1.md)（完整策划案，§1–§18） |
| `开发进展-2026-10-05.docx` | [`../production/开发进展-2026-10-05.md`](../production/开发进展-2026-10-05.md)（本轮工作回顾） |

## 如何重新生成

```bash
# 导出预设的两份（见 tools/md2docx.py 的 PRESETS）
python tools/md2docx.py --all

# 或指定单个文件
python tools/md2docx.py docs/gdd/core-gameplay-v3.1.md docs/export/xxx.docx
```

> 转换器：[`../../tools/md2docx.py`](../../tools/md2docx.py)（基于 python-docx）。
> 支持标题 / 段落 / 列表 / 表格 / 代码块 / 引用 / 行内粗体与代码；
> 表格内未转义的 `|`（如绝对值 `|A − H|`）会被合并回中间列，避免整表错位。
