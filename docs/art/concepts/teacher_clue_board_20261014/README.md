# 老师版每日推理板素材与截图

日期：2026-10-14。素材与实现均在移动端 main-mobile。

## 素材

- `assets/textures/ui/clue_board/notebook-paper-v1.webp`：内置 imagegen 生成，已复制进仓库；无文字奶油色方格纸，左侧打孔、和纸胶带。原图未覆盖。
- `assets/textures/ui/clue_board/pencil-dash.svg`：原生矢量虚线纹理，供预置 Line2D 表示推测。
- 学生卡片复用档案头像映射及场景现有立绘；没有把演示概念图中的人物当作正式角色素材。
- 标题、按钮、人物、事件、关系线均为 `scenes/ui/clue_board.tscn` 的独立原生节点，不烘焙进底图、不在运行时创建。

生成方式：内置 imagegen（非 CLI/API 回退）；提示词如下。

> Production game UI background texture asset only. A flat front-facing cream ivory graph-paper notebook page for a Chinese school teacher's daily relationship investigation board. Landscape 16:9. Edge-to-edge fine pale sage 24px graph grid, warm matte paper fiber subtle watercolor texture. Six punched notebook holes on far left margin only, a tiny muted sage washi tape at top left corner and small beige tape at bottom right corner. Very subtle irregular paper edge and subtle layered paper corners. Entire central 90 percent clean blank writing surface with uniform high readability. Soft cozy hand-painted stationery aesthetic, restrained warm ivory and sage palette. No text, no numbers, no lettering, no portraits, no people, no icons, no lines connecting nodes, no cards, no UI controls, no classroom, no photographic perspective, no drop shadow outside paper. This bitmap is the background layer; real Godot nodes will overlay all dynamic content.

## 实机渲染截图

`clue_board_1080.png` / `clue_board_720.png` 由真实教室场景、测试专用事件夹具生成，不是正式存档；截图脚本为 `tests/integration/capture_clue_board.gd`。`--dense` 额外检查全池 16 名学生的排布。

本机运行环境为 Godot 4.6.3 Compatibility；项目目标 4.7.2 尚未在本机验收。不据图片宣称 Android 真机测试完成。
