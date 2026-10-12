"""Native stylized student mesh with a basic deformation rig; no sprite billboards."""

import json
import math
import random
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/school_student_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs/art/concepts/school_student_blender"
ASSETS = ROOT / "assets/models/school_student"
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
RNG = random.Random(CFG["seed"])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
MODEL = []
WEIGHTS = {}
MATS = {}


def linear_color(hex_color):
    channels = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return tuple(v / 12.92 if v < 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels)


for name, color in CFG["palette"].items():
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*linear_color(color), 1)
    node.inputs["Roughness"].default_value = 0.8
    MATS[name] = material


def finish(obj, name, mat, bones=("Head",)):
    obj.name = name
    obj.data.materials.append(MATS[mat])
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    if bones:
        MODEL.append(obj)
        WEIGHTS[name] = bones
    return obj


def mesh_object(name, vertices, faces, mat, bones=("Head",)):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, bones)


def ellipsoid(name, position, size, mat, bones=("Head",)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=CFG["segments"], ring_count=CFG["sphere_rings"], radius=0.5, location=position)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bones)


def box(name, position, size, mat, bones, bevel=0.008):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = obj.modifiers.new("Soft edges", "BEVEL")
    modifier.width = min(bevel, min(size) * 0.4)
    modifier.segments = 3
    modifier = obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return finish(obj, name, mat, bones)


def tube(name, points, radii, mat, bones):
    verts, faces = [], []
    count = CFG["segments"]
    for index, (point, radius) in enumerate(zip(points, radii)):
        center = Vector(point)
        direction = Vector(points[min(index + 1, len(points) - 1)]) - Vector(points[max(index - 1, 0)])
        direction.normalize()
        cross = direction.cross(Vector((0, 1, 0))).normalized()
        other = direction.cross(cross).normalized()
        for step in range(count):
            angle = math.tau * step / count
            verts.append(tuple(center + radius * (cross * math.cos(angle) + other * math.sin(angle))))
    for index in range(len(points) - 1):
        for step in range(count):
            nxt = (step + 1) % count
            faces.append((index * count + step, index * count + nxt, (index + 1) * count + nxt, (index + 1) * count + step))
    faces += [tuple(reversed(range(count))), tuple(range((len(points) - 1) * count, len(points) * count))]
    return mesh_object(name, verts, faces, mat, bones)


def stroke(name, points, radius, mat, bones=("Head",)):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, position in zip(spline.bezier_points, points):
        point.co = position
        point.handle_left_type = point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(MATS[mat])
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    MODEL.append(obj)
    WEIGHTS[name] = bones
    return obj


# Five-head-style proportions, recognizable from an elevated classroom camera.
head = CFG["head"]
ellipsoid("Face", head["center"], head["size"], "skin")
ellipsoid("Neck", (0, 0, 1.252), (0.095, 0.095, 0.12), "skin", ("Neck",))
for side in (-1, 1):
    ellipsoid(f"Ear_{side}", (side * 0.14, 0.002, 1.417), (0.037, 0.045, 0.062), "skin")
    x = side * head["eye_x"]
    ellipsoid(f"EyeWhite_{side}", (x, head["eye_y"], head["eye_z"]), (0.049, 0.018, 0.035), "eye_white")
    ellipsoid(f"Iris_{side}", (x, head["eye_y"] - 0.010, head["eye_z"]), (0.022, 0.008, 0.029), "iris")
    ellipsoid(f"EyeGlint_{side}", (x - 0.003, head["eye_y"] - 0.014, head["eye_z"] + 0.007), (0.007, 0.003, 0.008), "eye_white")
    stroke(f"UpperEyelid_{side}", [(x - 0.023, -0.122, 1.455), (x, -0.13, 1.465), (x + 0.023, -0.122, 1.455)], 0.0025, "hair")
    stroke(f"Eyebrow_{side}", [(x - 0.022, -0.119, 1.488), (x, -0.128, 1.494), (x + 0.022, -0.119, 1.489)], 0.0035, "hair")
ellipsoid("Nose", (0, -0.125, 1.406), (0.023, 0.029, 0.032), "skin")
stroke("Smile", [(-0.025, -0.116, 1.358), (0, -0.124, 1.352), (0.025, -0.116, 1.358)], 0.0025, "mouth")

# Hair cap ends higher on the forehead than at the back; sculpted tapered bangs.
hair = CFG["hair"]
center = Vector(hair["center"])
rx, ry, rz = hair["radius"]
verts, faces = [], []
for ring in range(10):
    f = ring / 9
    for step in range(32):
        angle = step * math.tau / 32
        front = max(0, -math.sin(angle))
        bottom = 1.93 - front * 0.79
        polar = 0.018 + f * bottom
        verts.append(tuple(center + Vector((rx * math.sin(polar) * math.cos(angle), ry * math.sin(polar) * math.sin(angle), rz * math.cos(polar)))))
for ring in range(9):
    for step in range(32):
        nxt = (step + 1) % 32
        faces.append((ring * 32 + step, ring * 32 + nxt, (ring + 1) * 32 + nxt, (ring + 1) * 32 + step))
mesh_object("HairCap", verts, faces, "hair")
for index in range(hair["bang_count"]):
    x = -0.119 + index * 0.039
    z = 1.516 + RNG.uniform(-0.025, 0.024)
    start = Vector((x * 0.8, -0.091, 1.596))
    middle = Vector((x, -0.133, 1.554))
    tip = Vector((x - 0.023, -0.128, z))
    start.z += .014
    start.y += .01
    strand = tube(f"Bang_{index}", [start, (start+middle)/2, middle, (middle+tip)/2, tip], [.016,.026,.025,.016,.0008], "hair", ("Head",))
    for vertex in strand.data.vertices:
        # Flatten each strand's depth, preserving its curved centerline.
        ring = vertex.index // CFG["segments"]
        center_y = [start.y, ((start+middle)/2).y, middle.y, ((middle+tip)/2).y, tip.y][ring]
        vertex.co.y = center_y + (vertex.co.y-center_y)*.43
for side in (-1, 1):
    ellipsoid(f"Sideburn_{side}", (side * 0.13, -0.023, 1.458), (0.036, 0.07, 0.106), "hair")
tube("TopHairTuft", [(-.02,.015,1.623),(-.045,.01,1.639),(-.075,.005,1.646)], [.025,.02,.0008], "hair", ("Head",))

# Jacket and track pants use actual thickness and separate color panels.
verts, faces = [], []
for z, xr, yr in CFG["torso_rings"]:
    for step in range(CFG["segments"]):
        angle = math.tau * step / CFG["segments"]
        verts.append((xr * math.cos(angle), yr * math.sin(angle), z))
for ring in range(len(CFG["torso_rings"]) - 1):
    for step in range(CFG["segments"]):
        nxt = (step + 1) % CFG["segments"]
        faces.append((ring * CFG["segments"] + step, ring * CFG["segments"] + nxt, (ring + 1) * CFG["segments"] + nxt, (ring + 1) * CFG["segments"] + step))
mesh_object("WhiteJacket", verts, faces, "white", ("Spine", "Chest"))
ellipsoid("WaistBand", (0,0,0.874), (0.312,0.183,0.05), "blue", ("Hips",))
ellipsoid("JacketHem", (0,0,.898), (.319,.196,.037), "white", ("Spine",))
ellipsoid("PantsHip", (0,0,0.869), (0.276,0.18,0.13), "blue", ("Hips",))
stroke("JacketZipper", [(0,-0.095,0.925),(0,-0.105,1.09),(0,-0.087,1.19)], 0.003, "metal", ("Spine", "Chest"))
for side in (-1, 1):
    stroke(f"CollarEdge_{side}", [(side*.077,-.045,1.234),(side*.067,-.077,1.216),(side*.037,-.083,1.192)], .011, "blue", ("Chest",))
    stroke(f"JacketPocket_{side}", [(side*.095,-.095,1.025),(side*.067,-.099,.973)], .0023, "blue", ("Spine",))
    suffix = "L" if side > 0 else "R"
    ellipsoid(f"ShoulderCap_{suffix}", (side*.175,0,1.166), (.137,.120,.139), "blue", (f"UpperArm.{suffix}",))
    points = [(side*x,y,z) for x,y,z in CFG["arm_points"]]
    tube(f"Sleeve_{suffix}", points, CFG["arm_radii"], "blue", (f"UpperArm.{suffix}",f"Forearm.{suffix}"))
    stripe = [(side*(x+radius*.79),y-.025,z) for (x,y,z),radius in zip(CFG["arm_points"],CFG["arm_radii"])]
    stroke(f"SleeveStripe_{suffix}", stripe, .008, "white", (f"UpperArm.{suffix}",f"Forearm.{suffix}"))
    ellipsoid(f"WhiteCuff_{suffix}", (side*.255,-.015,.815), (.086,.082,.028), "white", (f"Forearm.{suffix}",))
    ellipsoid(f"Hand_{suffix}", (side*.255,-.018,.766), (.053,.046,.082), "skin", (f"Hand.{suffix}",))
    ellipsoid(f"Thumb_{suffix}", (side*.228,-.028,.775), (.023,.034,.042), "skin", (f"Hand.{suffix}",))
    for finger in range(3):
        ellipsoid(f"Finger_{suffix}_{finger}", (side*.255 + (finger-1)*.012,-.023,.729), (.012,.026,.032), "skin", (f"Hand.{suffix}",))
    points = [(side*x,y,z) for x,y,z in CFG["leg_points"]]
    tube(f"PantsLeg_{suffix}", points, CFG["leg_radii"], "blue", (f"Thigh.{suffix}",f"Shin.{suffix}"))
    stripe = [(side*(x+radius*.96),y,z) for (x,y,z),radius in zip(CFG["leg_points"],CFG["leg_radii"])]
    stroke(f"PantsStripe_{suffix}", stripe, .0055, "white", (f"Thigh.{suffix}",f"Shin.{suffix}"))
    box(f"ShoeSole_{suffix}", (side*.1,CFG["shoe_y"],.016), CFG["shoe_size"], "sole", (f"Foot.{suffix}",))
    ellipsoid(f"Sneaker_{suffix}", (side*.1,CFG["shoe_y"]+.006,.064), (.099,.187,.095), "white", (f"Foot.{suffix}",))
    box(f"HeelAccent_{suffix}", (side*.1,.026,.074), (.071,.013,.030), "blue", (f"Foot.{suffix}",), .004)
    for lace in range(3):
        stroke(f"ShoeLace_{suffix}_{lace}", [(side*.1-.027,-.045-lace*.018,.109-lace*.003),(side*.1+.027,-.045-lace*.018,.109-lace*.003)], .0023, "sole", (f"Foot.{suffix}",))
ellipsoid("SchoolEmblem", (.08,-.101,1.128), (.029,.005,.029), "blue", ("Chest",))

# A named 18-bone rig, with smoothly interpolated two-bone limb weights.
bpy.ops.object.armature_add()
rig = bpy.context.object
rig.name = "StudentRig"
bpy.ops.object.mode_set(mode="EDIT")
rig.data.edit_bones.remove(rig.data.edit_bones[0])
for definition in CFG["bones"]:
    bone = rig.data.edit_bones.new(definition["name"])
    bone.head = definition["head"]
    bone.tail = definition["tail"]
    if "parent" in definition:
        bone.parent = rig.data.edit_bones[definition["parent"]]
bpy.ops.object.mode_set(mode="OBJECT")
rig.show_in_front = True


def bone_distance(point, bone):
    head, tail = bone.head_local, bone.tail_local
    along = tail - head
    fraction = max(0, min(1, (point-head).dot(along)/along.length_squared))
    return (point-head-along*fraction).length


for obj in MODEL:
    names = WEIGHTS[obj.name]
    groups = [obj.vertex_groups.new(name=name) for name in names]
    for vertex in obj.data.vertices:
        point = obj.matrix_world @ vertex.co
        distances = [bone_distance(point, rig.data.bones[name]) for name in names]
        values = [1/(d+.018)**3 for d in distances]
        for group, value in zip(groups, values):
            group.add([vertex.index], value/sum(values), "REPLACE")
    obj.parent = rig
    modifier = obj.modifiers.new("Student skin", "ARMATURE")
    modifier.object = rig

# Merge export-only copies, preserving bone groups, for a compact portable skin.
copies = []
for original in MODEL:
    obj = original.copy()
    obj.data = original.data.copy()
    obj.parent = None
    bpy.context.collection.objects.link(obj)
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
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
merged.name = "StudentSkinnedMesh"
modifier = merged.modifiers.new("Student skin", "ARMATURE")
modifier.object = rig
merged.parent = rig
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ASSETS / "char_school_student_blender_v1.glb"), export_format="GLB", use_selection=True, export_yup=True, export_skins=True, export_animations=False)
bpy.data.objects.remove(merged, do_unlink=True)

# Test that the source weights actually deform when an upper-arm bone rotates.
arm = rig.pose.bones["UpperArm.L"]
arm.rotation_mode = "XYZ"
test_obj = next(obj for obj in MODEL if obj.name == "Sleeve_L")
depsgraph = bpy.context.evaluated_depsgraph_get()
before = [vertex.co.copy() for vertex in test_obj.evaluated_get(depsgraph).data.vertices]
arm.rotation_euler.y = .25
bpy.context.view_layer.update()
after = [vertex.co.copy() for vertex in test_obj.evaluated_get(depsgraph).data.vertices]
deformation = max((a-b).length for a,b in zip(after,before))
assert deformation > .005, "Skin did not respond to the armature"
arm.rotation_euler.y = 0
bpy.context.view_layer.update()

box("StudioFloor", (0,0,-.015), (200,200,.03), "ground", (), 0)
settings = CFG["render"]
bpy.ops.object.camera_add(location=settings["camera_position"])
camera = bpy.context.object
camera.rotation_euler = (Vector(settings["camera_target"])-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = settings["ortho_scale"]
scene = bpy.context.scene
scene.camera = camera
bpy.ops.object.light_add(type="AREA", location=settings["light_position"])
light = bpy.context.object
light.data.energy = settings["light_energy"]
light.data.size = settings["light_size"]
light.data.color = (1,.9,.8)
light.rotation_euler = (Vector(settings["camera_target"])-light.location).to_track_quat("-Z","Y").to_euler()
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.75,.82,.9,1)
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
            area.spaces.active.region_3d.view_distance = settings["ortho_scale"]*1.3
            area.spaces.active.region_3d.view_rotation = camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type = "MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "school_student_blender_v1.blend"))
bpy.ops.render.render(write_still=True)
report = {"blender":bpy.app.version_string,"seed":CFG["seed"],"source_meshes":len(MODEL),"bones":len(rig.data.bones),"arm_deformation_test_m":deformation,"animations_included":False}
(OUT / "build_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print("STUDENT_COMPLETE",report)
