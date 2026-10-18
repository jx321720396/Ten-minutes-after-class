# Blender 暖木色书架小样 v2

2026-10-12，按用户提供的教室与书架效果参考制作。使用本机 `E:/blender/blender.exe`（5.2.2 LTS）程序建模，保留可编辑的原生工程。

## 交付

- `school_bookshelf_blender_v2.blend`：可编辑模型、打包木纹贴图、课堂墙面/地砖展示布景、摄影机和光照。
- `blender_preview.png`：Blender Cycles 实际渲染，非 AI 生成图。
- `godot_preview.png`：同一 GLB 在 Godot 4.7.2 内实际渲染，使用既有独立书架展示场景的光照。
- `assets/models/bookshelf/prop_bookshelf_blender_v2.glb`：仅家具和摆件，含材质与嵌入式木纹贴图，不含展示墙面、灯光、相机。
- `assets/models/bookshelf/prop_bookshelf_blender_wood.webp`：原创数学纹理，用于暖木色表面。
- `build_report.json`：生成版本、种子、对象数量与产物位置。

柜体宽 1.0 m、高 1.55 m、深 0.36 m；顶部摆件另算。GLB 为米制、Y 向上，正面朝 +Z，原点在地面中心；Blender 工程 Z 向上、正面朝 -Y。不能直接沿用上一版朝 -Z 的相机位置。

细化了木板倒角、板材纹理 UV、书封与内页、文件夹指孔、部分倾斜书本、锥形空心花盆、弯曲茎叶。Blender 摄影布景和 Godot 展示光照不同，因此两张图不能当作最终主教室渲染一致性的结论。

## 复现

参数位于 `data/ui/school_bookshelf_blender.json`，使用固定种子。

```powershell
& 'E:/blender/blender.exe' --background --factory-startup --python tools/build_school_bookshelf_blender.py
& 'C:/Users/极星/Desktop/Godot_v4.7.2-stable_win64.exe' --path . --script tools/capture_school_bookshelf_blender.gd
```

第二步直接解析 GLB，检查网格数量、米制宽度和包围盒，并生成引擎截图。`tools/out/bookshelf_blender_build.log` 与 `tools/out/bookshelf_blender_godot.log` 为本机运行记录。

## 范围

独立美术试样，未替换生产教室、未修改碰撞或导航。GLB 当前保留细分物件用于验收；正式接入时可按材质合并网格并配置碰撞。模型和纹理为项目内原创，没有新增第三方资产。
