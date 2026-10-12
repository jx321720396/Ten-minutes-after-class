"""Chat speech-bubble sprites: background Blender render of pop / idle / fade frames.

Run: blender --background --factory-startup --python tools/build_chat_bubble_blender.py
Presentation-layer art only — no matrix, probability or gameplay value is touched.

产物：
  assets/textures/ui/speech_bubble/{pop,idle,fade}_NN.png + static.png
  docs/art/concepts/chat_bubble/{blender_preview.png, build_report.json, chat_bubble_blender_v1.blend}

设计（与 `docs/art/concepts/chat_bubble/README.md` 一致）：
  1. 轮廓 = 圆角矩形（密折线） + 两段二次贝塞尔"弯刀尾"，无直线折角；
  2. 动画以**尾巴尖为支点**：弹入等比长大 + easeOutBack 过冲（不是缩放到 0）；
     淡出以"缩小 + 上浮"为主，只在最后两帧做 alpha 消失（否则半透明时背后的墨线会透出显脏）；
  3. `view_transform` 用 Standard —— 默认 AgX 会把白色压成灰。
"""

import json
import math
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/chat_bubble_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / CFG["outputs"]["concept_dir"]
ASSETS = ROOT / CFG["outputs"]["assets_dir"]
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)

SHAPE = CFG["shape"]
INK = CFG["materials"]["ink"]
CAM = CFG["camera"]
SEQ = CFG["sequence"]
RENDER = CFG["render"]


def linear_channel(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def color(hex_color):
    raw = [int(hex_color[i : i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(linear_channel(c) for c in raw)


# ------------------------------------------------------------------ 轮廓
def rounded_rect_points(width, height, radius, segments):
    """逆时针：右上 -> 左上 -> 左下 -> 右下，相邻弧端点之间是直线段。"""
    hw, hh = width / 2.0, height / 2.0
    points = []
    for cx, cy, start in ((hw - radius, hh - radius, 0.0), (-hw + radius, hh - radius, 90.0),
                          (-hw + radius, -hh + radius, 180.0), (hw - radius, -hh + radius, 270.0)):
        for i in range(segments + 1):
            angle = math.radians(start + 90.0 * i / segments)
            points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def quad_bezier(p0, p1, p2, segments):
    points = []
    for i in range(segments + 1):
        t = i / float(segments)
        mt = 1.0 - t
        points.append((mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
                       mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]))
    return points


def tail_points():
    hh = -SHAPE["height"] / 2.0
    tip = (SHAPE["tail_tip"][0], SHAPE["tail_tip"][1])
    depth = hh - tip[1]
    width = SHAPE["tail_root_width"]
    root_l = (SHAPE["tail_root"] - width / 2.0, hh)
    root_r = (SHAPE["tail_root"] + width / 2.0, hh)
    ctrl_l = (SHAPE["tail_root"] - width * 0.10, hh - depth * SHAPE["tail_bulge"])
    ctrl_r = (tip[0] + width * 0.62, hh - depth * SHAPE["tail_bulge"] * 0.92)
    segments = SHAPE["tail_segments"]
    return quad_bezier(root_l, ctrl_l, tip, segments) + quad_bezier(tip, ctrl_r, root_r, segments)[1:]


def outline_points():
    """把底边那段直线替换成尾巴弧线。"""
    hh = -SHAPE["height"] / 2.0
    points = rounded_rect_points(SHAPE["width"], SHAPE["height"],
                                 SHAPE["corner_radius"], SHAPE["corner_segments"])
    best, gap = 0, 1e9
    for i in range(len(points)):
        a, b = points[i], points[(i + 1) % len(points)]
        if abs(a[1] - hh) < 1e-6 and abs(b[1] - hh) < 1e-6:
            distance = abs(b[0] - a[0])
            if distance < gap:
                best, gap = i, distance
    return list(points[: best + 1]) + tail_points() + list(points[best + 1 :])


PIVOT = (SHAPE["tail_tip"][0], SHAPE["tail_tip"][1])


def build_bubble():
    """曲线 -> 网格；物体原点 = 尾巴尖（动画支点）。"""
    points = outline_points()
    curve = bpy.data.curves.new("BubbleCurve", type="CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    curve.extrude = SHAPE["thickness"] / 2.0
    curve.bevel_depth = SHAPE["edge_bevel"]
    curve.bevel_resolution = SHAPE["bevel_resolution"]
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, (x, y) in enumerate(points):
        spline.points[i].co = (x - PIVOT[0], y - PIVOT[1], 0.0, 1.0)
    spline.use_cyclic_u = True
    obj = bpy.data.objects.new("Bubble", curve)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    obj.select_set(False)
    return obj


def set_alpha(mat, bsdf, alpha):
    """alpha < 1 时必须切混合模式，否则 EEVEE 里 alpha 不生效。"""
    if bsdf is not None and "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        for attr, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            if hasattr(mat, attr):
                try:
                    setattr(mat, attr, value)
                except Exception as exc:  # noqa: BLE001
                    print("alpha blend setup failed (%s): %s" % (attr, exc))
                break


def style_variant(source, name, alpha=1.0):
    """复制一份气泡：纸白本体 + 墨色描边外壳（外壳跟随本体变换）。"""
    paper = CFG["materials"]["paper"]
    body = source.copy()
    body.data = source.data.copy()
    body.name = name
    bpy.context.collection.objects.link(body)
    mat = bpy.data.materials.new(name + "_Paper")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color(paper["color"]), 1.0)
        for key, value in (("Roughness", paper["roughness"]), ("Metallic", paper["metallic"]),
                           ("Coat Weight", paper["coat"]), ("Coat Roughness", paper["coat_roughness"])):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = value
    set_alpha(mat, bsdf, alpha)
    body.data.materials.append(mat)

    outline = body.copy()
    outline.data = source.data.copy()
    outline.name = name + "_Ink"
    bpy.context.collection.objects.link(outline)
    outline.parent = body
    modifier = outline.modifiers.new("Ink", type="SOLIDIFY")
    modifier.thickness = INK["thickness"]
    modifier.offset = 1.0
    modifier.use_flip_normals = True
    ink_mat = bpy.data.materials.new(name + "_InkMat")
    ink_mat.use_nodes = True
    ink_bsdf = ink_mat.node_tree.nodes.get("Principled BSDF")
    if ink_bsdf is not None:
        ink_bsdf.inputs["Base Color"].default_value = (*color(INK["color"]), 1.0)
        if "Roughness" in ink_bsdf.inputs:
            ink_bsdf.inputs["Roughness"].default_value = INK["roughness"]
    ink_mat.use_backface_culling = True
    set_alpha(ink_mat, ink_bsdf, alpha ** SEQ["fade"]["ink_alpha_power"])
    outline.data.materials.append(ink_mat)
    return [body, outline]


def set_visible(objects, visible):
    for obj in objects:
        obj.hide_render = not visible


def pose(body, scale_x, scale_y, lift=0.0):
    body.scale = (scale_x, scale_y, 1.0)
    body.location = (body.location.x, lift, 0.0)


def ease_out_back(t):
    c1 = SEQ["pop"]["back_overshoot"]
    c3 = SEQ["pop"]["back_c3"]
    return 1.0 + c3 * (t - 1.0) ** 3 + c1 * (t - 1.0) ** 2


# ------------------------------------------------------------------ 场景
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
ENGINES = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
ENGINE_FALLBACK = False
if RENDER["engine"] in ENGINES:
    scene.render.engine = RENDER["engine"]
else:
    ENGINE_FALLBACK = True
    scene.render.engine = RENDER["fallback_engine"] if RENDER["fallback_engine"] in ENGINES else ENGINES[0]
if scene.render.engine == "CYCLES":
    scene.cycles.samples = RENDER["samples"]
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = True
else:
    scene.eevee.taa_render_samples = RENDER["samples"]
scene.view_settings.view_transform = RENDER["view_transform"]
scene.render.film_transparent = RENDER["film_transparent"]
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"

scene.world = bpy.data.worlds.new("BubbleWorld")
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
if background is not None:
    background.inputs[0].default_value = (*color(RENDER["world_color"]), 1.0)
    background.inputs[1].default_value = RENDER["world_strength"]
for light_cfg in RENDER["lights"]:
    data = bpy.data.lights.new(light_cfg["name"], type="SUN")
    data.energy = light_cfg["energy"]
    data.angle = math.radians(light_cfg["angle_degrees"])
    light = bpy.data.objects.new(light_cfg["name"], data)
    light.rotation_euler = tuple(light_cfg["rotation"])
    scene.collection.objects.link(light)

bubble = build_bubble()
bubble.hide_render = True


def add_camera(resolution, columns=1):
    data = bpy.data.cameras.new("Cam")
    data.type = "ORTHO"
    data.ortho_scale = CAM["ortho_scale"] * columns
    cam = bpy.data.objects.new("Cam", data)
    cam.location = (CAM["center"][0], CAM["center"][1], 8.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = resolution * columns
    scene.render.resolution_y = resolution
    return cam


def render_to(path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print("rendered %s" % path.name)


def render_frame(name, scale_x, scale_y, lift, alpha):
    objects = style_variant(bubble, name, alpha)
    pose(objects[0], scale_x, scale_y, lift)
    set_visible(objects, True)
    render_to(ASSETS / (name + ".png"))
    set_visible(objects, False)
    return objects


# ------------------------------------------------------------------ 序列帧
add_camera(CAM["frame_resolution"])
rendered = []

pop = SEQ["pop"]
for i in range(pop["frames"]):
    t = i / float(max(1, pop["frames"] - 1))
    curve_scale = max(pop["min_scale"], ease_out_back(t))
    scale_y = curve_scale
    scale_x = scale_y * (1.0 + max(0.0, 1.0 - curve_scale) * pop["squash_compensation"])
    render_frame("pop_%02d" % i, scale_x, scale_y, 0.0, 1.0)
    rendered.append("pop_%02d" % i)

idle = SEQ["idle"]
for i in range(idle["frames"]):
    u = i / float(idle["frames"])
    breath = (1.0 - math.cos(math.tau * u * idle["cycles"])) / 2.0
    scale_y = 1.0 + idle["scale_amplitude"] * breath
    scale_x = 1.0 - idle["squash_amplitude"] * breath
    render_frame("idle_%02d" % i, scale_x, scale_y, idle["lift"] * breath, 1.0)
    rendered.append("idle_%02d" % i)

fade = SEQ["fade"]
for i in range(fade["frames"]):
    u = i / float(max(1, fade["frames"] - 1))
    scale = 1.0 - fade["shrink"] * u
    alpha = 1.0 if u < fade["alpha_hold"] else 1.0 - (u - fade["alpha_hold"]) / (1.0 - fade["alpha_hold"])
    render_frame("fade_%02d" % i, scale, scale, fade["lift"] * u, alpha)
    rendered.append("fade_%02d" % i)

# 静帧：放大一档，供 UI 直接当贴图用
add_camera(CAM["still_resolution"])
still = style_variant(bubble, "static")
set_visible(still, True)
render_to(ASSETS / "static.png")
set_visible(still, False)

# ------------------------------------------------------------------ 预览拼版
columns = CAM["preview_columns"]
rows = math.ceil(len(rendered) / columns)
size = CAM["frame_resolution"]
sheet = np.zeros((size * rows, size * columns, 4), dtype=np.float32)
for index, name in enumerate(rendered):
    image = bpy.data.images.load(str(ASSETS / (name + ".png")))
    data = np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)
    # Blender 图像行序自下而上：按视觉上→下排（第 0 帧在左上）
    row, column = (rows - 1) - index // columns, index % columns
    sheet[row * size : (row + 1) * size, column * size : (column + 1) * size] = data
    bpy.data.images.remove(image)
preview = bpy.data.images.new("Preview", width=size * columns, height=size * rows, alpha=True)
preview.pixels.foreach_set(sheet.ravel())
preview.filepath_raw = str(OUT / "blender_preview.png")
preview.file_format = "PNG"
preview.save()

bpy.ops.wm.save_as_mainfile(filepath=str(OUT / CFG["outputs"]["blend_name"]))

anchor_x = (0.0 - (CAM["center"][0] - CAM["ortho_scale"] / 2.0)) / CAM["ortho_scale"]
anchor_y = (0.0 - (CAM["center"][1] - CAM["ortho_scale"] / 2.0)) / CAM["ortho_scale"]
summary = {
    "blender": bpy.app.version_string,
    "engine": scene.render.engine,
    "engine_fallback": ENGINE_FALLBACK,
    "seed": CFG["seed"],
    "frames": {key: SEQ[key]["frames"] for key in ("pop", "idle", "fade")},
    "frame_resolution": CAM["frame_resolution"],
    "still_resolution": CAM["still_resolution"],
    "anchor_tail_tip_normalized": [round(anchor_x, 4), round(anchor_y, 4)],
    "assets": [str(ASSETS / (name + ".png")) for name in rendered] + [str(ASSETS / "static.png")],
    "preview": str(OUT / "blender_preview.png"),
    "blend": str(OUT / CFG["outputs"]["blend_name"]),
}
(OUT / "build_report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print("CHAT_BUBBLE_COMPLETE", json.dumps({k: summary[k] for k in
      ("blender", "engine", "engine_fallback", "frames", "anchor_tail_tip_normalized")}, ensure_ascii=False))
