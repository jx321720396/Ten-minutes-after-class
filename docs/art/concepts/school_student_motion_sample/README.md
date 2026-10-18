# 人物移动与坐下动作小样（2026-10-12）

独立表现层试片，使用同一蓝白校服男生设计与原桌椅小样。Godot 4.7.2 / D3D12 Mobile 实际渲染：3秒走到座位侧面 → 1.1秒屈膝落座 → 2秒保持坐姿，循环播放。

- 场景：`scenes/game/school_student_motion_sample_showroom.tscn`，在编辑器 F6 运行。
- 参数与帧裁切：`data/ui/school_student_motion_sample.json`。
- 动作贴图：`assets/textures/characters/samples/school_student_walk_v1.webp`、`school_student_sit_v1.png`。保留生成器原始 RGBA，没有重新绘制或修改像素；AtlasTexture 按实际布局裁切。
- 演示：`motion-20261012.gif`；坐姿截图：`seated-20261012.png`。
- 录制：`godot --path . --script tools/capture_school_student_motion_sample.gd`。
- 检查：`godot --headless --path . --script tools/verify_school_student_motion_sample.gd`。

## 实现与限制

角色是 Sprite3D，逐帧替换肢体姿势，同时在世界中移动，使用真实桌椅深度遮挡；坐下使用屈膝与降低头部的独立姿势。演示路径从椅子侧面进入座位，不从椅背穿过。所有时间、路径和视觉比例集中配置。本场景的固定路径只是美术测试夹具，不改变游戏事件、人物行为规则或模拟随机源，未接入主教室。

生成帧目前仍有接触姿态重复、头发与脸部跳变、行走侧面转为坐姿三分之二侧面的突然变化。坐姿手臂与桌面、鞋底的透视仍需进一步校准。4帧方案只能验证外观和状态切换，不作为已完成的生产动画。正式版本宜由动画师精修6–8帧步态、补转身与起身及多朝向，或采用分层骨骼动画。

检查覆盖实际世界移动、与桌椅 SitPoint 对齐、可见头部随坐下下降、坐姿帧和位置稳定。渲染录制完成，没有该小样的脚本或资源报错。

## 生成方式与提示词

使用内置 imagegen，参考已保存站姿人物图。前两次全动作图行走接触帧重复，选用第二次的坐下帧；第三次仅生成低抬膝侧面行走。未继续消耗生成额度追求生产级动画。

### 首次生成

Create a production animation sprite sheet for the EXACT teenage Chinese schoolboy in the reference: identical youthful face, messy dark brown hair, blue and white zip tracksuit over cream T shirt, navy trousers white side stripes, white/navy sneakers, refined painterly anime illustration. Transparent background. Exactly EIGHT full-body poses in a precise FOUR COLUMNS by TWO ROWS grid, each cell equal width/height. No text, labels, cell borders, furniture, shadows or environment. Camera fixed three-quarter facing screen RIGHT, eye level, no perspective changes. ALL eight cells share identical character scale, foot ground baseline and generous margins; seated poses are shorter vertically, do NOT enlarge them. Upper row four consecutive WALK LOOP keyframes: left leg forward/right back with opposite arms; passing feet with right knee lifted; right leg forward/left back with opposite arms; passing feet with left knee lifted. Arms out of pockets, natural opposite arm swing, weight shifts, believable walk. Lower row four SIT DOWN transition keyframes: upright standing feet close and both hands forward; hips lowering backwards and knees bending; almost seated knees near right angles, torso slight lean; fully seated on an INVISIBLE chair, thighs horizontal towards screen right, lower legs vertical, both feet on same ground line, forearms comfortably extending forward on an INVISIBLE school desk. Chair seat at 27 percent of standing height, desk surface at 46 percent of standing height. Draw ONLY the character, do not draw desk or chair. Maintain exact head size, limb lengths, uniform details throughout. High-quality clean alpha silhouette, no halo. Wide landscape sheet, crisp complete faces and fingers.

### 坐姿选用版本

Refine this animation sheet into a usable transparent sprite atlas. Keep same exact boy, costume, art style and lower-row sit-down sequence. Strict 4 columns x 2 rows, each isolated pose must fit entirely WITHIN its own equal cell, no spill across boundaries, character horizontally centered in each cell with at least 8% margin, feet on baseline 96% of each cell height. Same scale in ALL cells; standing head at 8% cell height, seated head lower. Fix TOP ROW walking: frame1 LEFT foot forwards, RIGHT foot behind, RIGHT arm forwards LEFT arm backwards; frame2 RIGHT foot lifting and passing LEFT planted foot, LEFT arm moving forwards; frame3 RIGHT foot forwards LEFT foot behind, LEFT arm forwards RIGHT arm backwards; frame4 LEFT foot lifting and passing RIGHT planted foot, RIGHT arm moving forwards. Frames1 and3 MUST show different anatomical legs and arm positions, frames2 and4 different anatomical knees lifted. Walk leisurely with low knees, no marching high knee lift. Fixed 3/4 right facing camera. BOTTOM row: standing ready; knees bent hips dropping; settling seated; seated thighs horizontal knees90deg feet grounded forearms forwards. No furniture, NO opaque background, NO glow or shadows or text. All heads identical size. 1536x1024 landscape.

### 行走选用版本

Animation asset: same schoolboy from reference, same anime painterly quality, blue white tracksuit, navy trousers stripes white sneakers. Draw exactly FOUR walking poses arranged horizontally left to right, each contained within one quarter of wide image, equal scale and consistent feet baseline, transparent background, NO glow, no labels, no furniture. FULL SIDE PROFILE facing RIGHT (nose points right), identical face/head/clothing in all. Walking slow small steps, knees LOW. Pose1: NEAR leg (visible side stripes) extends forward RIGHT, far leg back LEFT, near arm back LEFT and far arm forward RIGHT. Pose2: near leg planted centered, FAR leg knee slightly bent passes forward, near arm beginning to swing forwards. Pose3: NEAR leg extends BACK LEFT, FAR leg extends forwards RIGHT; near arm FORWARD RIGHT, far arm BACK LEFT. Very important: pose3 clearly reverses the near leg and arm from pose1. Pose4: FAR leg planted centered, NEAR leg bent slightly passes forwards, near arm beginning to swing backwards. Four DISTINCT gait phases, contact/pass/opposite contact/opposite pass. No high knees. Precise character animator walk cycle, 4x1 evenly spaced, full bodies including all shoes with margins. Do not duplicate poses. No seated poses.
