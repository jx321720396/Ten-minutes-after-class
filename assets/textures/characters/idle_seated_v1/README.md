# 全班空闲坐姿 v1

2026-10-16，使用内置 imagegen 编辑当前 16 人各自的学习坐姿素材。保留 identity_v3 对应的外貌、校服、正面稍俯视视角与腿脚构图，移除书、笔，抬头放松，双手分别轻放在大腿上。每人一张 1024×1536 透明 RGBA PNG，无桌椅。

已通过 data/ui/student_poses.json 的逐人 idle 绑定接入运行时：只要仍在自己座位范围内，实际学习显示学习图，其余行为默认空闲坐姿；走动标记不抢占在座判定，真正离座才恢复站姿。空闲双手留在桌面后方，不启用学习用前景手臂层。已结合真实桌椅检查全班坐姿与遮挡。

- manifest.json：人物编号、名称、sprite、参考图片及输出文件映射。
- generation_prompts.json：完整提示词和每人外貌特征。
- validation.json：图片尺寸、透明度与 SHA-256 检查。
- 预览：docs/art/concepts/idle_seated_20261016/all_16_idle_seated.webp。

预览工具：tools/capture_idle_roster.gd，使用 Godot 渲染素材对照、运行时教室截图及 16 人实际桌椅组合图。

