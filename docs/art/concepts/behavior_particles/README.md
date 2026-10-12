# 行为符号气泡

用户批准的六类样式：闲聊多彩符号、学习蓝青数学符号、听音乐薄荷绿音符、吃零食橙黄图标、看课外书紫色书页、安慰粉杏爱心。头顶独立生成，轻微上扬后向外飘落，持续缩小淡出、近地消散。图标不代表隐藏态度或行为成功。

实现沿用 `scripts/ui/chat_activity_bubble.gd` 与现有教室接线，配置在 `data/ui/behavior_particles.json`；书页／零食为本项目代码绘制的 SVG，其余符号使用随包字体。没有新增外部素材授权。

`classroom.png` 是 Godot 4.7.2、D3D12 Mobile 的实际教室截图。截图工具只在独立实例里注入六类公开行为，用于同时检验样式，并非普通游玩记录；不修改模拟规则或游戏存档。实际玩家与 NPC 只在对应行为发生时发射。

重现：`godot --path . --script tools/capture_behavior_particles.gd`，输出 `tools/out/behavior_particles/classroom.png`。需图形渲染，不使用 headless。

验收覆盖：真实会话和公开状态、双方独立发射、未揭晓隐藏、生命周期、结束／切换／解绑清理、暂停冻结、不同世界倍率下生成与消散均按现实秒、hold 冻结和恢复、大步长不补喷、容量限制与模拟 RNG 隔离；真实教室聊天集成验证接线。

## 位图字形（2026-10-12）

闲聊一类的 4 个符号（`?` `!` `★` `~`）另有**位图字形**版本：用项目字体在 Blender 里挤出 + 倒角做成的立体白字形，运行时按各自 style 配色 `modulate`，所以随机配色不变。

- 工具：[`tools/build_symbol_bitmaps_blender.py`](../../../tools/build_symbol_bitmaps_blender.py)，配置 [`data/ui/behavior_particles_blender.json`](../../../data/ui/behavior_particles_blender.json)
- 资产：`assets/textures/ui/behavior_particles/{question,exclaim,star,wave}.png`（256²、白色、透明底）
- 接入点：`data/ui/behavior_particles.json` 的 `bitmaps` 字段（符号 → 贴图）。**字段为空或贴图缺失时自动回退字体字形**——这既是唯一的接入点，也是撤回开关。
- 预览：`bitmaps_preview.png`（4 个字形）、`bitmaps_size_compare.png`（上 = `font_size` 54、下 = 34 的实机对照）、`bitmaps_report.json`

**实测结论（重要）**：符号在默认 `font_size 34` 下只有约 25 px，**立体感几乎不可见**；放大到 54 才看得出边缘圆润与高光（见 `bitmaps_size_compare.png`）。也就是说，位图字形本身对「生硬」的改善很小——粒子看起来硬的主因是**运动曲线**（缩放为线性、横移匀速、各粒子参数完全相同）。

> ✅ **2026-10-12 已单独处理曲线**：`_sample()` 的缩放改为幂曲线、横移改为减速、新增弹入、每个粒子单独扰动速度与大小；五个系数都在 `data/ui/behavior_particles.json`，置回默认值即完全回到旧曲线（详见 `CHANGELOG.md`）。**落下曲线未动**。

位图目前只覆盖闲聊一类，其余五类仍走字体 / SVG。

## 光圈下线（2026-10-12）

原来的每个符号背后都画一个 32 边形的圆盘光晕（`halo_alpha 0.09`）。用户裁定「**不需要这个，只要有本身的形状**」，因此：

- `data/ui/behavior_particles.json` 新增 `halo_enabled`（当前 `false`）——**不再创建** halo 节点，`halo_alpha` / `halo_radius_pixels` / `halo_segments` 三个参数保留备用；
- 撤回/恢复：把 `halo_enabled` 置 `true` 即完全回到原样（这是唯一开关）；
- 六个行为族一起生效（不是只改闲聊）。
