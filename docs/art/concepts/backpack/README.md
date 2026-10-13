# 书包物品界面

2026-10-12 按用户确认的书包概念图实施，使用内置 imagegen，无 API / CLI。

## 素材与提示词

- `assets/textures/ui/backpack/items-v1.png`：原始装满书包参考，完整 navy canvas open school backpack，暖光、米色内衬、紫色课外书、银色 MP3 与白色耳机、橙色饼干包；透明背景，无文字或品牌。
- `empty-v1.png`：编辑上述图，只移除书、MP3、耳机、饼干包，保持书包轮廓、尺寸、缝线、拉链与光照。
- `objects-v1.png`：从原图提取三件物品透明轮廓的中间参考。
- `atlas-v1.png`：最终物品层；将原始三物品整理为透明 2×2 atlas，左上课外书、右上 MP3 与耳机、左下零食、右下空白；每格保留边距，不跨格，不加文字。

## 运行与验证

右下角独立「书包」按钮进入局部面板，与「百科全书／推理板」并排并共享纸签样式；再次点击收起；三个物品动作快捷按钮进入对应选择。点击物品或纸签，选择「拿出来」提交既有行为。打开不冻结世界，数量与不可用原因随原行为栏快照刷新，Esc 只收起。玩家开局无书，不显示书插画；获得后自动出现；零食耗尽则对应物品消失。

配置在 `data/ui/backpack.json`，组件位于 `scenes/ui/backpack_panel.tscn` / `scripts/ui/backpack_panel.gd`。不修改核心行为、数值或随机序列。

2026-10-13：补齐三种物品通过生产面板 → 行为栏 → 控制器 → SimCore → EventBus → HUD／书包的接线验证；完成和铃声中断通知改在动作清理后发出，事件到达即刷新面板，拿取校验失败也刷新。修正百科零食／课外书的实装状态，新增 MP3 词条。沿用本目录 2026-10-12 的概念素材与现有 `data/rules/leisure.csv`，未调整平衡数值。见 [验收记录](../../../qa/书包物品事件接线验收-2026-10-13.md)。

`tools/capture_backpack.gd` 在真实教室输出 `tools/out/backpack/actual-inventory.png` 和 `owned-book.png`。后一张仅向 UI 注入一本书的预览快照，不代表开局库存。截图时钟暂停只属于截图工具。

针对性 GUT：`tests/unit/test_backpack_panel.gd` 检查空库存、相位刷新、单次意图、Esc，以及通过生产行为栏和控制器拿零食仅扣一份。另复跑行为栏布局与既有玩家交互、减压库存门禁测试。

独立入口截图：entry.png 与 entry-hover.png；纸签样式参数在 data/ui/campus_theme.json 的 utility_style，线条图标在 assets/icons/actions/backpack.svg。
