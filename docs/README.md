# 文档索引

> 状态：生效 ｜ 维护者：全体 ｜ 最后更新：2026-10-04

本目录是《下课十分钟》全部文档的入口。**玩法问题查 Notion，工程问题查 `design/`。**

## 分类

| 目录 | 内容 | 权威性 |
|---|---|---|
| [`gdd/`](gdd/README.md) | 玩法规格入口（**事实源在 Notion**） | 仓库侧只留工程契约与编号锚点 |
| [`design/`](design/架构总览.md) | 技术设计：架构、数据模型、规则引擎、术语与标识符 | 工程实现的依据 |
| [`production/`](production/路线图.md) | 路线图、里程碑、比赛提交清单 | 决定"现在做什么" |
| [`art/`](art/视觉风格指南.md) | 视觉风格与 UI 规范 | 美术交付依据 |
| [`audio/`](audio/音频设计.md) | 音频设计 | 音频交付依据 |
| [`qa/`](qa/测试策略.md) | 测试策略与验收清单 | 验收依据 |
| [`localization/`](localization/本地化说明.md) | 本地化流程与文案规范 | 文案交付依据 |
| [`references/`](references/README.md) | 历史资料归档 + v3.0 规格快照（编号锚点） | 参考，**非事实源** |
| [`archive/`](archive/README.md) | 已废弃文档归档 | 仅考古 |

## 维护规则

1. **事实源分区（最重要）**
   - **玩法规格 → Notion**（入口见 [`gdd/README.md`](gdd/README.md)）；
   - **工程契约 → 仓库 [`design/`](design/架构总览.md)**；
   - 两区之间靠**编号锚点**对齐（`gdd/` 指向的 v3.0 快照）。仓库内**不得复制玩法正文或数值表**。
2. **状态标记**：每篇文档头部标注 `状态：骨架 / 草案 / 评审中 / 生效 / 归档` 与 `维护者`。
3. **同步义务**：影响实现的玩法改动，须在同一 PR 内更新 `design/` 文档并在 `CHANGELOG.md` 记录。
4. **禁止新增顶层分类**：新文档归入现有目录；确需新增须在 PR 说明理由。
5. CI 会校验文档内的相对链接有效性（`.github/scripts/check_docs_links.py`）。

## 阅读路径

- **新程序**：Notion 玩法文档（§3 时间、§4 架构、§5–§8 数值）→ [`design/架构总览.md`](design/架构总览.md) → [`design/规则引擎设计.md`](design/规则引擎设计.md)
- **新策划**：Notion 玩法文档全文 → [`gdd/README.md`](gdd/README.md)（工程契约与编号约定）→ [`production/路线图.md`](production/路线图.md)
- **新美术 / 音频**：Notion 玩法文档 §14 可视化 → [`art/视觉风格指南.md`](art/视觉风格指南.md) / [`audio/音频设计.md`](audio/音频设计.md)
