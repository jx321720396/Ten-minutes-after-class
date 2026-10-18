# 全班坐姿吃零食贴图

日期：2026-10-18。使用内置 imagegen，每人一次独立生成，以该学生现有 idle_seated_v1 透明坐姿为编辑目标；未使用 CLI/API 回退。

16 张 1024×1536 RGBA 图保留原始画布与姿态比例，转换为 WebP q90，仅作格式压缩，保留 alpha。人物对应和生成源文件见 assets/textures/characters/snack_seated_v1/manifest.json。原始 PNG 保留在 Codex generated_images 中。

## 生成提示词

Use case: identity-preserve edit. Edit ONLY this reference student into a seated eating-a-snack game sprite. Preserve this exact person's face, hair, eyes, glasses if present, blue-white school uniform, drawing style, full-body seated front-view proportions and head/feet coordinates on the original 1024x1536 canvas. One hand holds a plain small open biscuit pouch at stomach height; other hand brings a small round biscuit to lips, relaxed natural expression. Keep knees and shoes identical to reference. Both hands anatomically correct. Transparent background with real alpha. No desk, chair, scenery, text, watermark, ground shadow or extra characters. Output a single character, not a sheet.

首张使用相同要求的提示词，明确右手将圆饼干送至嘴边、左手持无品牌零食袋，其余采用上面的统一提示词。输入图为 manifest 中每人的 reference；没有在图片内绘制桌椅。

## 接入

data/ui/student_poses.json 的 activity_poses 将 eat_snack 映射到同名姿态，各学生 binding 绑定独立贴图。仅在原有姿态选择确认在座且在场时使用。离座恢复站姿，活动结束按原有活动切回；学习、聊天背影继续使用原素材。人物不新增行为判断，内核与随机数不变。

## 验证入口

- tests/unit/test_snack_seated_pose.gd：切换协议、16 人独立绑定、纹理尺寸和预加载。
- tools/capture_snack_seated.gd：真实教室中全班活动夹具，检查显示、随机数和成绩不变，输出两种分辨率截图。夹具仅运行在独立进程，不保存。

本批结果：专项 2/2、123 项断言通过；真实教室 36 项检查通过；已人工查看 classroom_snack_1280.png，人物吃零食姿态与桌面遮挡正常。格式、静态和两套字体覆盖检查通过。

扩大执行旧 test_layered_student_pose.gd 得到 5/8：两项仍用旧素材 manifest 的 PNG 文件名对比现行 WebP 路径；真实教室测试还有 dummy 渲染器与旧 UI 节点空引用报错。本批未修改这些旧清单／测试，不能宣称整个坐姿测试集通过；新姿态另经 GL 真实教室截图和独立回归验证。

