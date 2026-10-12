"""Build the first prop in the classroom's staged Blender art pass.

Original geometry stays editable in .blend; GLB combines by material for reuse.
"""

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/school_desk_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs/art/concepts/classroom_blender_rollout/01_desk"
ASSETS = ROOT / "assets/models/school_desk"
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
SOURCE = []


def color(hex_color):
    values = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values)


MATS = {}
for name, definition in CFG["materials"].items():
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color(definition["color"]), 1)
    principled.inputs["Roughness"].default_value = definition["roughness"]
    principled.inputs["Metallic"].default_value = definition["metallic"]
    MATS[name] = mat
texture = bpy.data.images.load(str(ROOT / CFG["wood_texture"]))
texture.pack()
node = MATS["wood"].node_tree.nodes.new("ShaderNodeTexImage")
node.image = texture
MATS["wood"].node_tree.links.new(node.outputs["Color"], MATS["wood"].node_tree.nodes.get("Principled BSDF").inputs["Base Color"])


def finish(obj, name, material, source=True):
    obj.name = name
    obj.data.materials.append(MATS[material])
    if source:
        SOURCE.append(obj)
    return obj


def box(name, size, position, material, bevel=0.003, source=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material == "wood":
        uv = obj.data.uv_layers.active
        for face in obj.data.polygons:
            normal_axis = max(range(3), key=lambda axis: abs(face.normal[axis]))
            short, long = sorted([axis for axis in range(3) if axis != normal_axis], key=lambda axis: size[axis])
            for index in face.loop_indices:
                p = obj.data.vertices[obj.data.loops[index].vertex_index].co
                uv.data[index].uv = (p[short] / size[short] + 0.5, p[long] / size[long] + 0.5)
    if bevel:
        modifier = obj.modifiers.new("Rounded edges", "BEVEL")
        modifier.width = min(bevel, min(size) * 0.35)
        modifier.segments = CFG["bevel_segments"]
        modifier = obj.modifiers.new("Corner normals", "WEIGHTED_NORMAL")
        modifier.keep_sharp = True
    return finish(obj, name, material, source)


def tube(name, start, end, radius, material):
    start, end = Vector(start), Vector(end)
    bpy.ops.mesh.primitive_cylinder_add(vertices=CFG["tube_segments"], radius=radius, depth=(end - start).length, location=(start + end) / 2)
    obj = bpy.context.object
    obj.rotation_euler = (end - start).to_track_quat("Z", "Y").to_euler()
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return finish(obj, name, material)


box("RoundedDesktop", CFG["top_size"], (0, 0, CFG["top_height"]), "wood", CFG["top_bevel"])
x, y, z = CFG["leg_x"], CFG["leg_y"], CFG["frame_top"]
radius = CFG["frame_radius"]
for side in (-1, 1):
    for direction in (-1, 1):
        tube(f"Leg_{side}_{direction}", (side * x, direction * y, CFG["foot_height"]), (side * x, direction * y, z), radius, "steel")
        tube(f"RubberFoot_{side}_{direction}", (side * x, direction * y, 0), (side * x, direction * y, CFG["rubber_height"]), CFG["rubber_radius"], "rubber")
    tube(f"SideTopRail_{side}", (side * x, -y, z), (side * x, y, z), radius, "steel")
    tube(f"SideBottomRail_{side}", (side * x, -y, 0.13), (side * x, y, 0.13), radius * 0.8, "steel")
tube("RearCrossRail", (-x, -y, 0.36), (x, -y, 0.36), radius * 0.8, "steel")
cw, cd, cb, ch, sheet = (CFG[k] for k in ("cubby_width", "cubby_depth", "cubby_bottom", "cubby_height", "cubby_sheet"))
box("OpenCubbyBase", (cw, cd, sheet), (0, 0, cb), "steel", 0.002)
box("CubbyRear", (cw, sheet, ch), (0, -cd / 2, cb + ch / 2), "steel", 0.002)
for side in (-1, 1):
    box(f"CubbySide_{side}", (sheet, cd, ch), (side * cw / 2, 0, cb + ch / 2), "steel", 0.002)
tube("RoundedCubbyLip", (-cw / 2, cd / 2, cb), (cw / 2, cd / 2, cb), sheet * 0.65, "steel")
for side in (-1, 1):
    for direction in (-1, 1):
        tube(f"FlushDesktopScrew_{side}_{direction}", (side * (x - 0.01), direction * (y - 0.012), 0.759), (side * (x - 0.01), direction * (y - 0.012), 0.761), 0.006, "bolt")

# Rounded hook on the side, converted to portable mesh geometry.
curve = bpy.data.curves.new("BagHookCurve", "CURVE")
curve.dimensions = "3D"
curve.bevel_depth = CFG["hook_radius"]
curve.bevel_resolution = 2
spline = curve.splines.new("BEZIER")
spline.bezier_points.add(len(CFG["hook_points"]) - 1)
for point, position in zip(spline.bezier_points, CFG["hook_points"]):
    point.co = position
    point.handle_left_type = point.handle_right_type = "AUTO"
hook = bpy.data.objects.new("SideBagHook", curve)
bpy.context.collection.objects.link(hook)
finish(hook, hook.name, "steel")
bpy.ops.object.select_all(action="DESELECT")
hook.select_set(True)
bpy.context.view_layer.objects.active = hook
bpy.ops.object.convert(target="MESH")

# Apply modifiers to copies and join per material; editable originals are preserved.
export_objects = []
for material in ("wood", "steel", "rubber", "bolt"):
    copies = []
    for original in SOURCE:
        if original.data.materials[0] != MATS[material]:
            continue
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        copies.append(bpy.context.object)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in copies:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    merged = bpy.context.object
    merged.name = "Desk_" + material
    export_objects.append(merged)
bpy.ops.object.select_all(action="DESELECT")
for obj in export_objects:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS / "prop_school_desk_blender_v1.glb"), export_format="GLB", use_selection=True, export_yup=True, export_cameras=False, export_lights=False)
for obj in export_objects:
    bpy.data.objects.remove(obj, do_unlink=True)

# Preview book is not part of the clean furniture export.
box("PreviewBook", CFG["preview_book_size"], CFG["preview_book_position"], "book", source=False)
position = CFG["preview_book_position"].copy()
position[1] += CFG["preview_book_size"][1] / 2
box("PreviewPages", (0.129, 0.002, 0.016), position, "paper", 0.0005, False)
box("PreviewFloor", (200, 200, 0.02), (0, 0, -0.012), "ground", 0, False)
settings = CFG["render"]
bpy.ops.object.camera_add(location=settings["camera_position"])
camera = bpy.context.object
camera.rotation_euler = (Vector(settings["camera_target"]) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = settings["ortho_scale"]
scene = bpy.context.scene
scene.camera = camera
bpy.ops.object.light_add(type="AREA", location=settings["area_position"])
light = bpy.context.object
light.data.energy = settings["area_energy"]
light.data.size = settings["area_size"]
light.data.color = (1.0, 0.89, 0.76)
light.rotation_euler = (Vector(settings["camera_target"]) - light.location).to_track_quat("-Z", "Y").to_euler()
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = settings["world_strength"]
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.83, 0.90, 1)
scene.render.engine = "CYCLES"
scene.cycles.samples = settings["samples"]
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = settings["resolution"]
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "blender_preview.png")
scene.view_settings.view_transform = "AgX"
bpy.ops.object.select_all(action="DESELECT")
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == "VIEW_3D":
            area.spaces.active.region_3d.view_location = Vector(settings["camera_target"])
            area.spaces.active.region_3d.view_distance = settings["ortho_scale"] * 1.4
            area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type = "MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "school_desk_blender_v1.blend"))
bpy.ops.render.render(write_still=True)
report = {"blender": bpy.app.version_string, "source_objects": len(SOURCE), "export_meshes": len(export_objects), "seed": CFG["seed"], "glb_front": "-Z", "preview_book_exported": False}
(OUT / "build_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("DESK_COMPLETE", report)
