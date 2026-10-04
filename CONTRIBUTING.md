# 贡献指南

本文档面向《下课十分钟》的所有协作者（程序、策划、美术、音频、测试）。

---

## 1. 开工前必读

1. [`docs/gdd/core-gameplay-v3.1.md`](docs/gdd/core-gameplay-v3.1.md) —— **玩法唯一事实源（主文档）**，在仓库内维护。改规格就改这份文档，并在 `CHANGELOG.md` 记录；工程契约（铁律、编号、数据接口）见 `docs/design/`。
2. [`docs/design/架构总览.md`](docs/design/架构总览.md) —— 工程结构与模块边界。
3. 本文件的设计铁律一节。

---

## 2. 设计铁律（评审会直接打回的红线）

| # | 铁律 | 说明 |
|---|---|---|
| 1 | **禁止脚本化** | 任何"到这里必然发生某事"的写法都要被质疑：把涌现部分换成脚本，游戏还能成立吗？ |
| 2 | **禁止角色名/角色 ID 判断** | 行为逻辑必须是 `f(性格四维, 透明度, 当前状态)` 的纯函数。角色专属效果只能写进开局种子（身份层），否则删除。 |
| 3 | **观察层只读** | O1 簇标签器、"孤立"标签只供 UI 与简报读取，**不得回写任何矩阵或数值**。 |
| 4 | **假信息必须有破绽** | 推理板中任何矛盾信息都必须可通过交叉验证发现，不允许出现纯噪声。 |
| 5 | **数值可标定** | 所有"每 tick"数值必须能按 v3.0 §3.4 的三条目标反推，不允许拍脑袋定值。 |

---

## 3. 分支模型

| 分支 | 用途 |
|---|---|
| `main` | 可运行、可构建的稳定线；**禁止直接推送**，一律走 PR |
| `feat/<主题>` | 新功能（如 `feat/social-matrix`） |
| `fix/<主题>` | 缺陷修复 |
| `docs/<主题>` | 文档变更 |
| `art/<主题>` | 美术/音频资源导入与调整 |
| `balance/<主题>` | 纯数值标定与平衡调整 |
| `refactor/<主题>` | 不改变行为的重构 |

分支从最新 `main` 切出，保持短生命周期（建议 ≤ 3 天），及时 rebase。

---

## 4. 提交信息规范

采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：`<类型>(<范围>): <描述>`

- 类型：`feat` / `fix` / `docs` / `art` / `balance` / `refactor` / `test` / `chore` / `build`
- 范围：模块名，如 `matrix`（态度矩阵）、`rules`（行为规则）、`ui`、`report`（简报）、`cliff`（推理板）
- 描述用中文或英文均可，但**同一仓库保持一致**（当前约定用中文）。

示例：

```
feat(rules): 实现 R5 消息传歪的态度染色
balance(transmission): 传导系数 β 由 0.3 下调至 0.22，抑制第 2 周饱和
docs(gdd): 补充 11.3 环境事实清单
```

一个提交只做一件事；纯格式化改动单独提交。

---

## 5. GDScript 风格

遵循 [Godot 官方 GDScript 风格指南](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)，并结合本项目约定：

- **缩进**：Tab（由 `.editorconfig` 强制），不用空格。
- **命名**：文件/变量/函数 `snake_case`，类 `PascalCase`，常量 `CONSTANT_CASE`。
- **类型**：公开函数标注参数与返回类型；新代码不得省略 `-> void` 之类的返回标注。
- **节点引用**：用 `@onready var x: NodeType = $Path`，不要在 `_process` 里反复 `get_node`。
- **信号**：优先在 `_ready()` 中 `connect()`，信号名用过去式（`closed`、`confirmed_clear`）。
- **禁止**：`get_node("../../X")` 这类脆弱长路径、魔法数字（改用 `data/` 配置或 `const`）。
- **数据驱动**：角色种子、规则参数、数值表一律放 `data/`，代码只读表不写死。

提交前本地检查（可选）：

```bash
pip install gdtoolkit==4.*
gdformat --check scripts/ && gdlint scripts/
```

---

## 6. 资源规范

- **目录**：`assets/textures/`、`assets/audio/{bgm,sfx}/`、`assets/fonts/`，禁止在根目录散落资源。
- **命名**：`类别_对象_变体[_状态].扩展名`，全小写蛇形，例如 `ui_btn_primary_hover.png`、`sfx_chalk_write_01.wav`。
- **图集**：同屏 UI 元素使用图集，避免零碎贴图。
- **第三方资源**：必须登记到 `assets/CREDITS.md`（名称、作者、来源链接、许可协议），未登记的资源禁止合入。
- **体积**：单个贴图建议 ≤ 1 MB，音频统一 OGG（BGM）/ WAV 或 OGG（SFX）。

---

## 7. 文档规范

- 结构：`docs/` 下按 `gdd/ design/ production/ art/ audio/ qa/ localization/ references/ archive/` 分类，禁止新增顶层目录。
- 每篇文档头部标注 **状态**（`骨架` / `草案` / `评审中` / `生效`）与 **维护者**。
- 权威规格只有一份（v3.0）；细化文档必须**引用章节号**而非复制结论，避免双源冲突。
- 文档改动与代码改动同 PR 提交；影响玩法结论的改动必须同步更新 `CHANGELOG.md`。

---

## 8. PR 流程

1. 开 PR 前：本地跑通（Godot 打开无报错、主菜单可运行），`CHANGELOG.md` 已更新。
2. PR 描述使用模板，勾选检查清单；**涉及玩法逻辑的 PR 必须写明"检验一/检验二"如何通过**。
3. 至少 1 名评审通过；涉及数值的改动需要另一名标定参与者复核。
4. 合并方式：Squash merge，保持 `main` 线性历史。
5. 合并后删除分支。

---

## 9. 禁止提交的内容

已在 `.gitignore` 中排除，若发现被跟踪请立即移除：

- `.godot/`、`/android/`、导出产物（`build/`、`dist/`、`export/`、`*.pck`）；
- Reasonix 本地配置与附件（`.reasonix/`、`reasonix.toml`）；
- Office 临时文件（`~$*`）、系统文件（`Thumbs.db`、`desktop.ini`、`.DS_Store`）；
- 任何密钥、令牌、个人隐私数据。
