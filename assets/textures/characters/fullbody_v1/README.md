# 人物全身立绘 v1

2026-10-12 使用内置 imagegen 根据纸张推理板概念图的校园插画方向生成。24 名 NPC 对应 `data/characters/appearance.csv`，另含男女主角，共 26 张独立 RGBA PNG。`manifest.json` 保存角色编号、姓名、文件名和生成源路径；`validation.json` 记录尺寸、透明像素与人物边界；`index.html` 提供整班总览。

美术方向：柔和日系校园插画、蓝白运动校服、炭灰长裤、白色运动鞋；每位同学采用独立发型、脸型与姿态。参考仅为本聊天生成的推理板概念图，不含真实人物或第三方品牌素材。

当前为静态站姿美术稿，尚未绑定人物场景、替换旧贴图或修改外观表。不是动作帧、表情集或八方向素材。校服细节存在生成差异，角色新外貌也需美术复核。高分辨率原稿保留用于审看；正式接入应按显示尺寸输出运行时素材，并按项目要求控制体积。

生成提示约定：single full-body Chinese high-school student, soft hand-drawn anime illustration matching paper-board reference, blue and ivory track jacket, white T-shirt, charcoal trousers, white/navy sneakers, entire figure visible, transparent background, distinct face and hairstyle, no text/frame/props/background. 各角色外貌描述见生成名单，不参与行为逻辑。
