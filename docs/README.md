# 文档索引

> 状态：生效 ｜ 维护者：全体 ｜ 最后更新：2026-10-04

本目录是《下课十分钟》全部文档的入口。**玩法看 `gdd/`（主文档），工程看 `design/`。**

## 分类

| 目录 | 内容 | 权威性 |
|---|---|---|
| [`gdd/`](gdd/README.md) | 玩法设计：**主文档 v3.1** + 工程契约索引 | **唯一事实源** |
| [`design/`](design/架构总览.md) | 技术设计：架构、数据模型、规则引擎、统一影响公式、信念矩阵、术语 | 工程实现依据 |
| [`production/`](production/路线图.md) | 路线图、里程碑、比赛提交清单 | 决定"现在做什么" |
| [`art/`](art/视觉风格指南.md) | 视觉风格与 UI 规范 | 美术交付依据 |
| [`audio/`](audio/音频设计.md) | 音频设计 | 音频交付依据 |
| [`qa/`](qa/测试策略.md) | 测试策略与验收清单 | 验收依据 |
| [`localization/`](localization/本地化说明.md) | 本地化流程与文案规范 | 文案交付依据 |
| [`references/`](references/README.md) | 旧版规格与历史策划资料 | 参考，**不生效** |
| [`archive/`](archive/README.md) | 已废弃文档归档 | 仅考古 |

## 维护规则

1. **单一事实源**：玩法规格只在 [`gdd/core-gameplay-v3.1.md`](gdd/core-gameplay-v3.1.md) 里维护——要改规格就改它，并在 `CHANGELOG.md` 记录。工程契约（公式、数据结构、可见性、数值铁律）在 [`design/`](design/架构总览.md)；两处不得互相复制结论，只能互相引用章节号。
2. **状态标记**：每篇文档头部标注 `状态：骨架 / 草案 / 评审中 / 生效 / 归档` 与 `维护者`。
3. **同步义务**：影响实现的规格改动，须在同一 PR 内更新 `design/` 文档并在 `CHANGELOG.md` 记录。
4. **禁止新增顶层分类**：新文档归入现有目录；确需新增须在 PR 说明理由。
5. CI 会校验文档内的相对链接有效性（`.github/scripts/check_docs_links.py`）。

## 阅读路径

- **新程序**：[`gdd/core-gameplay-v3.1.md`](gdd/core-gameplay-v3.1.md)（§3 时间、§4 架构、§5–§8 数值）→ [`design/统一影响公式.md`](design/统一影响公式.md) → [`design/信念矩阵.md`](design/信念矩阵.md) → [`design/规则引擎设计.md`](design/规则引擎设计.md)
- **新策划**：先读主文档 §3.4 标定目标与 [`design/统一影响公式.md`](design/统一影响公式.md) §2.5 数值铁律 → 主文档全文 → [`production/路线图.md`](production/路线图.md)
- **新美术 / 音频**：主文档 §14 可视化 → [`art/视觉风格指南.md`](art/视觉风格指南.md) / [`audio/音频设计.md`](audio/音频设计.md)
