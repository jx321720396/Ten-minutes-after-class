# 纯2D固定俯视动作小样（2026-10-12）

用户反馈上一版2D人物与3D桌椅混合效果不协调，本次尝试统一为手绘纯2D，固定约60度斜俯视，保留蓝白校服、木板桌椅和中国高中室内细节。用于评估风格方向，未替换主教室。

## 查看

- Godot场景：`scenes/game/classroom_2d_motion_sample.tscn`，F6运行。
- 实录：`motion-20261012.gif`；坐姿：`seated-20261012.png`。
- 图片：`assets/textures/samples/classroom_2d/background_v1.png` 和 `student_motion_v1.png`。
- 配置：`data/ui/classroom_2d_motion_sample.json`；纯Node2D/Sprite2D/Polygon2D，没有3D节点、光照或相机移动。
- 录制：`godot --path . --script tools/capture_classroom_2d_motion_sample.gd`，再 `py tools/package_classroom_2d_motion_preview.py`。
- 检查：`godot --headless --path . --script tools/verify_classroom_2d_motion_sample.gd`。

## 动作与局限

### 快速版 v2

按用户反馈移除全部站立到屈膝的中间姿势，行走由3.6秒缩短到1.8秒，入座由1.4秒缩短到0.18秒，抵达后直接切换最终坐姿。步态由6提高到10关键帧/秒，帧切换末尾50%时间以相邻帧短混合缓解硬跳变；移动按路径长度匀速插值。实录提高到30帧/秒，GIF采用30/40毫秒交替时长以保持实际播放速度。

新版预览：`motion-fast-20261012-v2.gif`。这是实时帧混合与位置插值，不是光流补绘的新肢体帧；短暂混合仍可能出现轻微重影，多朝向和侧向步态仍未完成。已验证入座过程不会使用屈膝帧、行走相邻帧参与混合，以及最终坐姿稳定。以下动作时长为初版记录，新版以本段和JSON配置为准。

3.6秒朝上走到椅子左侧 → 1.4秒向座位移动并屈膝坐下 → 2秒保持坐姿。独立美术测试路径不参与行为决策、事件或模拟随机。行走使用4帧俯视图，坐下使用4帧专门姿势，脚底加纯2D接触阴影。椅背前景直接引用背景局部的AtlasTexture，不改写生成像素。人物手臂和头部处在桌面之上。

本次只具备朝上行走，侧向入座尚未补转身与横向步态，因此入座侧移是简化演示；动作少帧、轻微形变仍需精修。背景为整张绘图，桌椅尚未拆成可自由摆放资产。固定绘制角度比3D混合容易统一，但不支持任意旋转镜头。此版用于审美选择，不能据此宣称全游戏人物动画已完成。

已校验纯2D节点、固定视野、地面位置实际变化、最终座位位置、稳定坐姿；新增GDScript格式和静态检查通过。GIF来自实际Godot逐帧渲染。

## 生成记录

使用内置imagegen，共生成背景、人物动作图及一次修正；第一版出现抬脚超过头部的错误，选用修正后的动作图。原始RGBA保留，运行时用AtlasTexture裁切，无Python图像改绘。GIF封装只处理引擎截图。

### 背景提示词

Pure 2D hand-painted Chinese high school game background, polished cozy indie RPG environmental illustration, crisp shapes delicate wood grain, muted warm colors, NOT 3D render, NOT photorealistic. Single fixed orthographic overhead camera looking down 60 degrees above the floor, screen top is north, no perspective vanishing point. Landscape 1536x1024. Small intimate classroom study area, warm cream terrazzo floor with subtle square grid, a SINGLE Chinese school student desk and its wooden chair at the upper center of the composition, desk facing NORTH screen top. IMPORTANT placement: tabletop centered x=768 y=350, spans x600..936 y290..400, desk legs extend down to y500, chair seat centered x768 y510, chair back at screen SOUTH y580. Empty chair and desk no people. Desk honey brown rectangular wood top, gray-blue steel tubes, open compartment, small stacked textbooks and pale blue notebook on far NORTH edge of desk, chair matching golden wood panels and tubular metal frame. Chair tucked moderately under desk but empty seat clearly visible, no clutter over walking area. Lower half y650..1000 is unobstructed floor for character walking towards chair. Upper edge subtle classroom wall with green lower paint and bulletin corner, sun from upper left, localized soft watercolor contact shadows, edge vignette subtle. Camera never changes. Desk rear/SOUTH side faces viewer. Refined 2D cartoon illustration, visible brush texture but clear game asset outlines. No text, no UI, no other desks, no people.

### 人物提示词

Create a transparent pure 2D game character animation atlas MATCHING the overhead camera and painterly style of reference classroom background (first reference). Second reference is identity/costume reference only, do NOT use its eye-level camera. Exact boy messy short dark brown hair blue-white Chinese tracksuit navy trousers white stripes white/navy sneakers. Camera fixed ORTHOGRAPHIC OVERHEAD 60 DEGREES ABOVE FLOOR, seen FROM BEHIND facing SCREEN TOP (north), strongly see crown of head, top of shoulders, tops of shoes. Not sideview, not frontview; no face visible. Character proportions about 4.5 heads with overhead foreshortening, polished hand-drawn indie RPG sprite. Exactly EIGHT isolated poses 4 columns x2 rows, equal cells, clear gutters, all same scale camera head size, no props, text, grids, ground, halo or shadow. Upper row NORTH WALK LOOP: left shoe forwards farther screen TOP and right shoe backwards BOTTOM with opposite arm swing; feet passing under body; right shoe forwards TOP and left shoe backwards BOTTOM opposite arms; opposite feet passing. Gentle small natural steps, change leg phase clearly; no high knee lift. Lower row SIT DOWN: standing rear facing north hands slightly forwards; hips descending and torso leaning forwards; nearly seated knees bending towards north; fully seated upright facing NORTH on an INVISIBLE chair at INVISIBLE desk, shoulders relaxed, arms forwards north on invisible desktop, hips lower screen south, feet under desk beyond knees. No furniture at all. Seated silhouette shorter than standing with same head size, do NOT enlarge seated to fill cell. Exact same overhead60 camera all eight frames. Crisp clean alpha. Aspect ratio 3:2 landscape sheet.

### 修正提示词

Correct ONLY the upper row four walking sprites of this transparent atlas. Keep lower row seated transition sprites exactly unchanged. Maintain matching handpainted pure2D overhead60 camera, rear facing screen TOP. Serious anatomy error: shoes appear ABOVE HEAD in frames1 and3. REMOVE those shoes and bizarre extreme stretched legs. In ALL four walking frames all legs and shoes MUST be below the waist towards screen bottom, shoes never above waist. Walking north with SMALL short stride, two shoes beneath torso partially visible at screen bottom; overhead view with legs foreshortened. Frame1 left lower shoe slightly higher screen y than right lower shoe; frame2 feet close side by side; frame3 right lower shoe slightly higher screen y than left lower shoe, opposite arms; frame4 feet close passing with opposite arm positions. Gentle ordinary walking, no kicking no split no high knee. Four columns two rows unchanged precise equal layout. Identical crowns of head / shoulder size and silhouette camera; no furniture, no text, transparent background no glow. Rear facing north, absolutely no faces. Preserve seated poses lower row.
