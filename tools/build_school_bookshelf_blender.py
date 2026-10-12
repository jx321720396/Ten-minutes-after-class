"""Blender background modeling, textured GLB export, and reference render.

Run: blender --background --factory-startup --python tools/build_school_bookshelf_blender.py
Only produces an independent art sample; no production classroom replacement.
"""

import json
import math
import random
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/school_bookshelf_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs/art/concepts/school_bookshelf_blender"
ASSETS = ROOT / "assets/models/bookshelf"
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
RNG = random.Random(CFG["seed"])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
MODEL = []


def rgb(hex_color):
    return [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def linear(c):
    return c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*map(linear, rgb(color)), 1)
    bsdf.inputs["Roughness"].default_value = 0.78
    mat.diffuse_color = (*map(linear, rgb(color)), 1)
    return mat


MATS = {name: material(name, color) for name, color in CFG["palette"].items()}


def wood_texture():
    settings = CFG["texture"]
    n = settings["resolution"]
    u, v = np.meshgrid(np.linspace(0, 1, n), np.linspace(0, 1, n))
    warp = u + 0.012 * np.sin(v * 9 + u * 7) + 0.006 * np.sin(v * 19)
    grain = np.sin(warp * settings["grain_frequency"] * math.tau)
    fine = np.sin(warp * 480 + np.sin(v * 12)) * 0.15
    variation = 1 + settings["grain_strength"] * (grain + fine)
    base = np.asarray(rgb(CFG["palette"]["wood"]))
    pixels = np.ones((n, n, 4), dtype=np.float32)
    pixels[:, :, :3] = np.clip(base[None, None, :] * variation[:, :, None], 0, 1)
    image = bpy.data.images.new("WarmWoodGrain", width=n, height=n)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(ASSETS / "prop_bookshelf_blender_wood.png")
    image.file_format = "PNG"
    image.save()
    image.pack()
    mat = MATS["wood"]
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = image
    mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])


wood_texture()


def finish(obj, name, mat, model=True):
    obj.name = name
    obj.data.materials.append(MATS[mat])
    if model:
        MODEL.append(obj)
    return obj


def box(name, size, pos, mat="wood", bevel=None, model=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat == "wood":
        # Run the grain along each board's longest visible dimension.
        uv = obj.data.uv_layers.active
        for polygon in obj.data.polygons:
            normal_axis = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
            axes = [axis for axis in range(3) if axis != normal_axis]
            short_axis, long_axis = sorted(axes, key=lambda axis: size[axis])
            for loop_index in polygon.loop_indices:
                point = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
                uv.data[loop_index].uv = (point[short_axis] / size[short_axis] + 0.5, point[long_axis] / size[long_axis] + 0.5)
    amount = CFG["bevel"] if bevel is None else bevel
    if amount:
        modifier = obj.modifiers.new("Soft furniture edges", "BEVEL")
        modifier.width = min(amount, min(size) * 0.35)
        modifier.segments = CFG["bevel_segments"]
        modifier = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        modifier.keep_sharp = True
    return finish(obj, name, mat, model)


w, d, h, t = (CFG[k] for k in ("width", "depth", "height", "board_thickness"))
for side in (-1, 1):
    box("WoodSide_L" if side < 0 else "WoodSide_R", (t, d, h), (side * (w - t) / 2, 0, h / 2))
box("RecessedBack", (w - 2 * t, 0.022, h - t), (0, d / 2 - 0.019, h / 2), "back", bevel=0.003)
for index, z in enumerate(CFG["shelf_heights"]):
    box(f"Shelf_{index}", (w - 2 * t, d, t), (0, 0, z))


def book(name, width, depth, height, pos, color, tilt=0):
    pivot = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = pos
    pivot.rotation_euler.y = math.radians(tilt)
    MODEL.append(pivot)
    cover = CFG["book_cover"]
    parts = [
        box(name + "_Pages", (width - 2 * cover, depth - cover * 2, height - 0.01), (0, 0, height / 2), "paper", 0.001),
        box(name + "_FrontCover", (cover, depth, height), (-width / 2 + cover / 2, 0, height / 2), color, 0.001),
        box(name + "_BackCover", (cover, depth, height), (width / 2 - cover / 2, 0, height / 2), color, 0.001),
        box(name + "_Spine", (width, cover * 2, height), (0, -depth / 2 + cover, height / 2), color, 0.002),
        box(name + "_Label", (width * 0.55, 0.001, CFG["book_label_height"]), (0, -depth / 2 - 0.001, height * 0.74), "paper", 0.0003)
    ]
    for part in parts:
        part.parent = pivot
    return pivot


palette = ["red", "blue", "green", "yellow", "blue", "paper", "green", "red", "blue", "green"]
for row, z in enumerate(CFG["shelf_heights"][:-1]):
    x = -w / 2 + t + 0.025
    for i in range(CFG["books_per_shelf"]):
        bw = CFG["book_widths"][(i + row) % len(CFG["book_widths"])]
        bh = CFG["book_heights"][(i + row * 2) % len(CFG["book_heights"])]
        y = -0.022 + RNG.uniform(-0.015, 0.012)
        color = palette[(i + row * 2) % len(palette)]
        tilt = 7 if i == 9 else 0
        pivot = book(f"Book_R{row}_{i:02}", bw, CFG["book_depth"], bh, (x + bw / 2, y, z + t / 2 + 0.002), color, tilt)
        if row == 0 and i < 2:
            for child in pivot.children:
                if child.data.materials[0] != MATS["paper"]:
                    child.data.materials[0] = MATS["yellow"]
            bpy.ops.mesh.primitive_torus_add(major_radius=0.009, minor_radius=0.0025, major_segments=16, minor_segments=6)
            ring = finish(bpy.context.object, f"FolderFingerRing_{i}", "back")
            ring.parent = pivot
            ring.location = (0, -CFG["book_depth"] / 2 - 0.003, 0.06)
            ring.rotation_euler.x = math.pi / 2
        x += bw + CFG["book_gap"]

for i, color in enumerate(("paper", "blue")):
    box(f"StackedBook_{i}", (0.29, 0.22, 0.045), (0.20, 0.005, h + 0.024 + i * 0.052), color, 0.003)
    box(f"StackedPages_{i}", (0.274, 0.222, 0.029), (0.20, -0.001, h + 0.024 + i * 0.052), "paper", 0.001)

# A hollow tapered pot, curved stems, and bent pointed leaves, all exportable meshes.
plant = CFG["plant"]
px, py, pz = plant["position"]
radius, ph = plant["pot_radius"], plant["pot_height"]
verts, faces = [], []
rings = [(radius * 0.77, 0), (radius, ph - 0.006), (radius, ph), (radius * 0.90, ph), (radius * 0.90, ph - 0.016)]
for rad, z in rings:
    for i in range(32):
        angle = i * math.tau / 32
        verts.append((px + rad * math.cos(angle), py + rad * math.sin(angle), pz + z))
for j in range(len(rings) - 1):
    for i in range(32):
        nxt = (i + 1) % 32
        faces.append((j * 32 + i, j * 32 + nxt, (j + 1) * 32 + nxt, (j + 1) * 32 + i))
mesh = bpy.data.meshes.new("TaperedPotMesh")
mesh.from_pydata(verts, [], faces)
pot = bpy.data.objects.new("CeramicPot", mesh)
bpy.context.collection.objects.link(pot)
finish(pot, pot.name, "pot")
for polygon in mesh.polygons:
    polygon.use_smooth = True
bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius * 0.89, depth=0.008, location=(px, py, pz + ph - 0.012))
finish(bpy.context.object, "PotSoil", "soil")

for i in range(plant["leaf_count"]):
    angle = i * 2.39996
    direction = Vector((math.cos(angle), math.sin(angle), 0))
    base = Vector((px, py, pz + ph - 0.008))
    leaf_base = base + direction * (0.035 + i % 3 * 0.025) + Vector((0, 0, 0.045 + i % 4 * 0.036))
    curve = bpy.data.curves.new(f"StemCurve_{i}", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.0022
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(2)
    for point, location in zip(spline.bezier_points, (base, (base + leaf_base) / 2 + Vector((0, 0, 0.035)), leaf_base)):
        point.co = location
        point.handle_left_type = point.handle_right_type = "AUTO"
    stem = bpy.data.objects.new(f"Stem_{i}", curve)
    bpy.context.collection.objects.link(stem)
    finish(stem, stem.name, "stem")
    bpy.context.view_layer.objects.active = stem
    stem.select_set(True)
    bpy.ops.object.convert(target="MESH")
    stem.select_set(False)
    length = plant["leaf_length"] * RNG.uniform(0.85, 1.12)
    width = plant["leaf_width"]
    cross = Vector((-direction.y, direction.x, 0))
    leaf_verts, leaf_faces = [], []
    for step in range(9):
        fraction = step / 8
        center = leaf_base + direction * length * fraction + Vector((0, 0, 0.05 * math.sin(fraction * math.pi) - 0.035 * fraction))
        span = width * math.sin(fraction * math.pi) ** 0.8
        for side in (-1, 0, 1):
            p = center + cross * span * side + Vector((0, 0, -abs(side) * span * 0.22))
            leaf_verts.append(tuple(p))
    for step in range(8):
        for side in range(2):
            a = step * 3 + side
            leaf_faces.append((a, a + 3, a + 4, a + 1))
    mesh = bpy.data.meshes.new(f"LeafMesh_{i}")
    mesh.from_pydata(leaf_verts, [], leaf_faces)
    obj = bpy.data.objects.new(f"CurvedLeaf_{i:02}", mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj, obj.name, "leaf_light" if i % 3 == 0 else "leaf")
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    modifier = obj.modifiers.new("Leaf thickness", "SOLIDIFY")
    modifier.thickness = 0.001

# Only furniture belongs to the portable GLB; backdrop stays in the .blend.
bpy.ops.object.select_all(action="DESELECT")
for obj in MODEL:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS / "prop_bookshelf_blender_v2.glb"), export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_cameras=False, export_lights=False)

# A simple classroom corner provides an honest lighting / scale preview.
box("Floor", (200, 200, 0.04), (0, 0, -0.025), "tile", 0, False)
for i in range(-8, 9):
    value = i * 0.45
    box(f"GroutX_{i}", (0.004, 8, 0.001), (value, 0, -0.004), "grout", 0, False)
    box(f"GroutY_{i}", (8, 0.004, 0.001), (0, value, -0.004), "grout", 0, False)
box("CreamWall", (8, 0.08, 3.5), (0, 0.31, 1.75), "wall", 0, False)
box("SageWainscot", (8, 0.015, 0.92), (0, 0.26, 0.46), "sage", 0, False)
box("Skirting", (8, 0.025, 0.09), (0, 0.248, 0.045), "skirting", 0.002, False)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


settings = CFG["render"]
bpy.ops.object.camera_add(location=settings["camera_position"])
camera = bpy.context.object
aim(camera, settings["camera_target"])
camera.data.type = "ORTHO"
camera.data.ortho_scale = settings["ortho_scale"]
scene = bpy.context.scene
scene.camera = camera
bpy.ops.object.light_add(type="SUN")
sun = bpy.context.object
sun.rotation_euler = [math.radians(v) for v in settings["sun_rotation"]]
sun.data.energy = settings["sun_energy"]
sun.data.angle = settings["sun_angle"]
sun.data.color = (1.0, 0.88, 0.71)
bpy.ops.object.light_add(type="AREA", location=settings["area_position"])
area = bpy.context.object
area.data.energy = settings["area_energy"]
area.data.shape = "DISK"
area.data.size = settings["area_size"]
aim(area, (0, 0, 0.9))
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.74, 0.80, 0.86, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = settings["world_strength"]
scene.render.engine = "CYCLES"
scene.cycles.samples = settings["samples"]
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = settings["resolution"]
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "blender_preview.png")
bpy.ops.object.select_all(action="DESELECT")
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_location = Vector(settings["camera_target"])
            area.spaces.active.region_3d.view_distance = settings["ortho_scale"] * 1.4
            area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type = "MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "school_bookshelf_blender_v2.blend"))
bpy.ops.render.render(write_still=True)
summary = {"blender": bpy.app.version_string, "seed": CFG["seed"], "model_objects": len(MODEL), "glb": str(ASSETS / "prop_bookshelf_blender_v2.glb"), "blend": str(OUT / "school_bookshelf_blender_v2.blend"), "preview": scene.render.filepath}
(OUT / "build_report.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print("BOOKSHELF_COMPLETE", json.dumps(summary, ensure_ascii=False))
