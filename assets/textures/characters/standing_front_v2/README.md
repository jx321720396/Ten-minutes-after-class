# 全班自然站姿 v2

2026-10-15。按用户选择「沿用教室里的新版陈阳，去掉光晕、减弱高光和衣褶」，保留陈阳确认稿，并用内置 imagegen 为其余十五人生成完整连贯的自然站姿。

每人独立 1024×1536 RGBA PNG：放松肩线、双臂自然下垂、手离开口袋、双脚分开落地；保留原发型、脸型、眼镜与发饰。生成中出现的带文字排版海报已弃用，未复制到本目录或绑定运行时。生成参考、源路径与最终提示分别见 manifest.json、generation_sources.json、generation_prompt.txt。

接入：data/ui/student_poses.json 按外观配置映射，不在行为逻辑中按姓名分支。standing_floor_pixel 记录每张图实际鞋底的源像素位置，ClassroomActors 只调整显示中心，保留既有放大比例及人物逻辑根节点；不影响坐姿逐图标定、导航或玩法数值。档案和推理板共同读取 data/ui/npc_profile.json 中的同款上半身裁切。

validation.json 保存透明比例、尺寸、实体边界及 SHA-256，16 图唯一性通过。何川一张源图的两个角存在 1/255 透明量化噪点，运行时透明裁切不会显示；未用 Python 改写任何像素。生成图的全透明像素可能仍携带旧 RGB 背景颜色，实际显示以 alpha 为准，Godot 原生图册和教室截图验证没有光晕。

查看 docs/art/concepts/standing_roster_20261015/ 的全班图册、教室、档案和推理板截图。捕获工具 tools/capture_standing_roster.gd；复制与只读校验工具 tools/prepare_standing_roster.py。

本批优化站立图片；学习图维持既有资源。陈阳的连续网格行走仍属于单人小样，不代表已给其余十五人接入行走动画。
