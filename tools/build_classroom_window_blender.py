"""Build warm classroom window assemblies and reuse the existing bookshelf plant."""

import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / "data/ui/classroom_window_blender.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs/art/concepts/classroom_warm_windows"
ASSETS = ROOT / "assets/models/classroom_window"
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
WINDOW = []
MATS = {}


for name, value in CFG["palette"].items():
    color = [int(value[i:i+2],16)/255 for i in (1,3,5)]
    linear = [v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in color]
    material = bpy.data.materials.new("Window_"+name)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*linear,1)
    principled.inputs["Roughness"].default_value = .74
    if name == "glass":
        principled.inputs["Alpha"].default_value = CFG["glass_alpha"]
        principled.inputs["Roughness"].default_value = .25
        material.surface_render_method = "DITHERED"
    MATS[name] = material


def finish(obj, name, material, window=True):
    obj.name = name
    obj.data.materials.append(MATS[material])
    if window:
        WINDOW.append(obj)
    return obj


def box(name, size, position, material, window=True, bevel=.004):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Soft edges", "BEVEL")
        modifier.width = min(bevel,min(size)*.3)
        modifier.segments = 2
        obj.modifiers.new("Corner normals", "WEIGHTED_NORMAL")
    return finish(obj,name,material,window)


w,h,f,d = (CFG[key] for key in ("width","height","frame","frame_depth"))
for index,z in enumerate((f/2,h-f/2)):
    box(f"OuterRail_{index}",(w,d,f),(0,0,z),"frame")
for side in (-1,1):
    box(f"OuterStile_{side}",(f,d,h-2*f),(side*(w-f)/2,0,h/2),"frame")
box("Transom",(w-f,d*.9,.044),(0,0,CFG["transom_height"]),"frame")
for index,x in enumerate(CFG["mullions"]):
    box(f"Mullion_{index}",(.038,d*.85,h-f),(x,0,h/2),"frame")
for index,z in enumerate((.078,CFG["transom_height"]-.04)):
    box(f"SlidingTrack_{index}",(w-f,.11,.011),(0,-.008,z),"rail")
# Sliding sash edges and compact pull handles remain readable from the room.
for index,x in enumerate(CFG["mullions"]):
    box(f"SlidingSash_{index}",(.026,.035,CFG["transom_height"]-.13),(x-.038,-.059,CFG["transom_height"]/2),"rail")
    box(f"HandleMount_{index}",(.035,.024,.15),(x-.038,-.080,.76),"handle")
    box(f"HandleGrip_{index}",(.017,.040,.11),(x-.038,-.101,.76),"frame")
box("StoneWindowSill",CFG["sill_size"],(0,-.12,0),"sill",bevel=.012)
box("SillFrontLip",(2.94,.027,.034),(0,-.300,-.008),"sill")
box("Glass",(w-f,.003,h-f),(0,.023,h/2),"glass",bevel=0)
box("CurtainRod",(3.25,.018,.020),(0,CFG["rod_offset"],2.064),"handle")

for index,center in enumerate(CFG["curtain_centers"]):
    verts,faces=[],[]
    steps=CFG["curtain_segments"]
    for row in range(13):
        fraction=row/12
        z=CFG["curtain_top"]-fraction*CFG["curtain_height"]
        taper=1-.38*math.exp(-((fraction-.6)/.13)**2)
        for step in range(steps+1):
            u=step/steps
            x=center+(u-.5)*CFG["curtain_width"]*taper
            y=CFG["curtain_offset"]+CFG["curtain_fold_depth"]*math.cos(u*math.tau*CFG["curtain_folds"])
            verts.append((x,y,z))
    for row in range(12):
        for step in range(steps):
            a=row*(steps+1)+step
            faces.append((a,a+1,a+steps+2,a+steps+1))
    mesh=bpy.data.meshes.new(f"CurtainMesh_{index}")
    mesh.from_pydata(verts,[],faces)
    obj=bpy.data.objects.new(f"FoldedCurtain_{index}",mesh)
    bpy.context.collection.objects.link(obj)
    finish(obj,obj.name,"curtain")
    for polygon in mesh.polygons:
        polygon.use_smooth=True
    modifier=obj.modifiers.new("Cloth thickness","SOLIDIFY")
    modifier.thickness=.003
    box(f"CurtainTie_{index}",(.21,.037,.032),(center,CFG["tie_offset"],CFG["curtain_top"]-CFG["curtain_height"]*.6),"tie")


def export_group(objects,path,flip_front=False):
    groups={}
    for original in objects:
        obj=original.copy()
        obj.data=original.data.copy()
        if flip_front:
            # Existing room window anchors present their -Z face to the interior.
            obj.matrix_world=Matrix.Rotation(math.pi,4,"Z")@obj.matrix_world
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.convert(target="MESH")
        obj=bpy.context.object
        groups.setdefault(obj.data.materials[0].name,[]).append(obj)
    merged=[]
    for material,parts in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in parts:obj.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.join()
        obj=bpy.context.object
        obj.name=material
        merged.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in merged:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False)
    count=len(merged)
    for obj in merged:bpy.data.objects.remove(obj,do_unlink=True)
    return count


window_meshes=export_group(WINDOW,ASSETS/"prop_window_warm_v1.glb",flip_front=True)

# Load the exact original foliage, stems, pot and soil; do not regenerate them.
with bpy.data.libraries.load(str(ROOT/CFG["plant_source"]),link=False) as (available,loaded):
    loaded.objects=[name for name in available.objects if name in ("CeramicPot","PotSoil") or name.startswith(("Stem_","CurvedLeaf_"))]
plant=[]
for obj in loaded.objects:
    if obj is None:continue
    bpy.context.collection.objects.link(obj)
    obj.location-=Vector(CFG["plant_origin"])
    plant.append(obj)
assert len(plant)==30,"Unexpected source plant objects"
plant_meshes=export_group(plant,ASSETS/"prop_potted_plant_reused.glb")
for obj in plant:
    obj.location+=Vector(CFG["preview_plant_position"])

# Source project keeps editable geometry and a simple window opening for preview.
box("WallLeft",(1,.18,2.4),(-2.03,.10,.9),"wall",False)
box("WallRight",(1,.18,2.4),(2.03,.10,.9),"wall",False)
box("WallAbove",(3.06,.18,.7),(0,.10,2.2),"wall",False)
box("WallBelow",(3.06,.18,.9),(0,.10,-.48),"wall",False)
box("Floor",(200,200,.02),(0,0,-.96),"floor",False,0)
settings=CFG["render"]
bpy.ops.object.camera_add(location=settings["camera_position"])
camera=bpy.context.object
camera.rotation_euler=(Vector(settings["camera_target"])-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type="ORTHO"
camera.data.ortho_scale=settings["camera_size"]
scene=bpy.context.scene
scene.camera=camera
bpy.ops.object.light_add(type="AREA",location=settings["area_position"])
light=bpy.context.object
light.data.energy=settings["area_energy"]
light.data.size=settings["area_size"]
light.data.color=(1,.91,.78)
light.rotation_euler=(Vector(settings["camera_target"])-light.location).to_track_quat("-Z","Y").to_euler()
scene.world.use_nodes=True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.79,.85,.92,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=settings["world_strength"]
scene.render.engine="CYCLES"
scene.cycles.samples=settings["samples"]
scene.cycles.use_denoising=True
scene.render.resolution_x,scene.render.resolution_y=settings["resolution"]
scene.render.resolution_percentage=100
scene.view_settings.view_transform="AgX"
scene.render.image_settings.file_format="PNG"
scene.render.filepath=str(OUT/"window_blender_preview.png")
bpy.ops.object.select_all(action="DESELECT")
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=="VIEW_3D":
            area.spaces.active.region_3d.view_location=Vector(settings["camera_target"])
            area.spaces.active.region_3d.view_distance=settings["camera_size"]*1.2
            area.spaces.active.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
            area.spaces.active.shading.type="MATERIAL"
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/"classroom_window_warm_v1.blend"))
bpy.ops.render.render(write_still=True)
report={"blender":bpy.app.version_string,"window_meshes":window_meshes,"plant_meshes":plant_meshes,"reused_plant_objects":len(plant),"plant_source":CFG["plant_source"]}
(OUT/"build_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print("WINDOW_COMPLETE",report)
