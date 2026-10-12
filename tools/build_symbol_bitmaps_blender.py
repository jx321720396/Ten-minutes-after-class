"""Symbol bitmaps for the behaviour particles: Blender background render of 3D glyphs.

Run: blender --background --factory-startup --python tools/build_symbol_bitmaps_blender.py
Presentation-layer art only — no matrix, probability or gameplay value is touched.

产物：
  assets/textures/ui/behavior_particles/<name>.png          白色字形（运行时用 modulate 上色）
  docs/art/concepts/behavior_particles/bitmaps_preview.png  符号拼版预览
  docs/art/concepts/behavior_particles/bitmaps_report.json  引擎 / 字形 / 路径记录

为什么要立体化：现在符号是**平铺的字体字形**，形状单薄、没有质感。
这里给字形加 extrude + bevel，让边缘圆润、能吃到柔和高光；贴图统一渲成**白色**，
由运行时按各自的 style 配色 modulate —— 所以不会丢掉原来的随机配色。
"""

import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/behavior_particles_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / CFG["outputs"]["concept_dir"]
ASSETS = ROOT / CFG["outputs"]["assets_dir"]
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)

RENDER = CFG["render"]


def linear_channel(value):
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def color(hex_color):
    return tuple(linear_channel(int(hex_color[i : i + 2], 16) / 255.0) for i in (1, 3, 5))


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
scene.render.resolution_x = CFG["resolution"]
scene.render.resolution_y = CFG["resolution"]

scene.world = bpy.data.worlds.new("SymbolWorld")
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

# 相机：让字形占画面的 fill_ratio（与字体渲染的视觉大小对齐）
ortho = CFG["glyph_size"] / CFG["fill_ratio"]
camera_data = bpy.data.cameras.new("Cam")
camera_data.type = "ORTHO"
camera_data.ortho_scale = ortho
camera = bpy.data.objects.new("Cam", camera_data)
camera.location = (0.0, 0.0, 8.0)
scene.collection.objects.link(camera)
scene.camera = camera

FONT = bpy.data.fonts.load(str(ROOT / CFG["font"]))
SYMBOL_MAT = CFG["materials"]["symbol"]


def make_material():
    mat = bpy.data.materials.new("Symbol")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color(SYMBOL_MAT["color"]), 1.0)
        for key, value in (("Roughness", SYMBOL_MAT["roughness"]), ("Metallic", SYMBOL_MAT["metallic"]),
                           ("Coat Weight", SYMBOL_MAT["coat"]), ("Coat Roughness", SYMBOL_MAT["coat_roughness"])):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = value
    return mat


def build_glyph(char):
    bpy.ops.object.text_add(location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.data.body = char
    obj.data.font = FONT
    obj.data.size = CFG["glyph_size"]
    obj.data.align_x = "CENTER"
    obj.data.align_y = "CENTER"
    obj.data.extrude = CFG["extrude"]
    obj.data.bevel_depth = CFG["bevel"]
    obj.data.bevel_resolution = CFG["bevel_resolution"]
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    # 按包围盒居中：不同字形在字体里基线不同，贴图里统一居中更整齐
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    center_x = (min(c.x for c in corners) + max(c.x for c in corners)) / 2.0
    center_y = (min(c.y for c in corners) + max(c.y for c in corners)) / 2.0
    for vert in obj.data.vertices:
        vert.co.x -= center_x
        vert.co.y -= center_y
    obj.data.materials.append(make_material())
    bpy.ops.object.shade_smooth()
    return obj


rendered = []
for entry in CFG["symbols"]:
    glyph = build_glyph(entry["char"])
    path = ASSETS / (entry["name"] + ".png")
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print("rendered %s (%r) verts=%d" % (path.name, entry["char"], len(glyph.data.vertices)))
    rendered.append({"name": entry["name"], "char": entry["char"], "used_by": entry.get("used_by", ""),
                     "vertices": len(glyph.data.vertices), "path": str(path)})
    bpy.data.objects.remove(glyph, do_unlink=True)

# 拼版预览：一行排开
size = CFG["resolution"]
sheet = np.zeros((size, size * len(rendered), 4), dtype=np.float32)
for index, entry in enumerate(rendered):
    image = bpy.data.images.load(entry["path"])
    data = np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)
    sheet[:, index * size : (index + 1) * size] = data
    bpy.data.images.remove(image)
sheet_image = bpy.data.images.new("Preview", width=size * len(rendered), height=size, alpha=True)
sheet_image.pixels.foreach_set(sheet.ravel())
sheet_image.filepath_raw = str(OUT / "bitmaps_preview.png")
sheet_image.file_format = "PNG"
sheet_image.save()

summary = {
    "blender": bpy.app.version_string,
    "engine": scene.render.engine,
    "engine_fallback": ENGINE_FALLBACK,
    "font": CFG["font"],
    "resolution": CFG["resolution"],
    "fill_ratio": CFG["fill_ratio"],
    "glyphs": rendered,
    "preview": str(OUT / "bitmaps_preview.png"),
}
(OUT / "bitmaps_report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print("SYMBOL_BITMAPS_COMPLETE", json.dumps(
    {"engine": summary["engine"], "engine_fallback": ENGINE_FALLBACK,
     "glyphs": [g["name"] for g in rendered]}, ensure_ascii=False))
