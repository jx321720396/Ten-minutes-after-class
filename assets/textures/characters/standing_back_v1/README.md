# 站立背影 v1

16 张 1024×1536 RGBA PNG，每人一张，由内置 imagegen 逐人参考现有 standing_front_v2 / identity_v3 正面生成。不替换原图，不共用头发或身体身份。

绑定、脚底与身高校正在 data/ui/student_poses.json 的 bindings；朝向阈值在同文件 group_facing。外观场景通过 appearance.csv 的 sprite 键匹配，运行逻辑没有姓名或角色编号分支。

提示词及参考源见 generation.json。全员预览可用 `godot --path . --script tools/capture_group_facing.gd -- catalog` 重新生成；运行效果见 docs/qa/共同活动背影验收-2026-10-18.md。既有 Sprite3D alpha cut 用于隐藏素材边缘低透明像素，保留 PNG 原生透明通道。
