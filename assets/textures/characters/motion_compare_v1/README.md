# 陈阳方向与动作对比小样

2026-10-12 内置 imagegen，分别以本项目陈阳 Q 版小样和正常比例全身立绘为参考生成两套 8 列 × 4 行、32 帧透明图集。来源均为本聊天生成的原创角色稿。两个文件均为 1448×1086 RGBA。

打开 index.html 查看方向选择、动作播放和完整图集。frames.json 为零起始列号与方向行号，已记录两套左右方向行序不同。实际生成尺寸不满足整像素等高四行，因此预览按四舍五入边界读取。

每行列序：站立；行走四帧；聊天两帧；坐姿。坐姿为单帧，不是坐下过渡动画。Q 版行序为正、背、左、右；正常比例行序为正、背、右、左。

提示约束：same character identity and uniform, 32 isolated figures in 8x4 grid, four directions, idle/walk/chat/sitting action columns, transparent background, consistent scale and baseline, full-body visible. 输出存在步态重复、人物对齐与基线漂移，尚未完成动画连贯性验收；用于比较风格和动作方向，不能宣称为最终游戏动画。原贴图与人物场景未修改。
