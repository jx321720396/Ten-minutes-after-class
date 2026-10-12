"""Editable classroom cabinet and schoolbag; portable, material-batched GLBs."""
import json
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
CFG = json.loads((ROOT / 'data/ui/classroom_furnishings_blender.json').read_text(encoding='utf-8'))
OUT = ROOT / 'docs/art/concepts/classroom_furnishings'
ASSETS = ROOT / 'assets/models/classroom_furnishings'
OUT.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def material(name, color):
    values = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c < .04045 else ((c + .055) / 1.055) ** 2.4 for c in values]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*linear, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*linear, 1)
    shader.inputs['Roughness'].default_value = .83
    return mat


MATS = {k: material(k, v) for k, v in CFG['palette'].items()}


def box(group, name, size, position, mat, bevel):
    bpy.ops.mesh.primitive_cube_add(size=1, location=position)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(MATS[mat])
    if bevel:
        modifier = obj.modifiers.new('Rounded edges', 'BEVEL')
        modifier.width = min(bevel, min(size) * .45)
        modifier.segments = 3
        obj.modifiers.new('Corner normals', 'WEIGHTED_NORMAL')
    group.append(obj)
    return obj


cabinet = []
c = CFG['cabinet']
w, d, h, t = (c[k] for k in ('width', 'depth', 'height', 'board'))
b = c['bevel']
box(cabinet, 'Carcass', (w-.01, d-.01, h-c['foot']-t), (0, 0, (h+c['foot']-t)/2), 'shadow', b)
box(cabinet, 'WarmWoodTop', (w, d, t), (0, 0, h-t/2), 'wood', b)
for side in (-1, 1):
    box(cabinet, 'EndPanel', (t, d-.01, h-c['foot']-t), (side*(w-t)/2, 0, (h+c['foot']-t)/2), 'body', b)
    for rear in (-1, 1):
        box(cabinet, 'Foot', (.065,.065,c['foot']), (side*(w/2-.09),rear*(d/2-.07),c['foot']/2), 'metal', b)
for row in range(2):
    door_h = (h-c['foot']-t)/2-c['gap']
    center_z = c['foot']+(row+.5)*(h-c['foot']-t)/2
    for side in (-1,1):
        center_x = side*w/4
        box(cabinet,'InsetDoor',(w/2-c['gap']-t/2,t,door_h),(center_x,-d/2,center_z),'door',b)
        handle_x = center_x-side*(w/4-.065)
        box(cabinet,'HandleBase',(.025,.01,c['handle']+.016),(handle_x,-d/2-t*.7,center_z+.035),'shadow',.003)
        box(cabinet,'Handle',(.018,.025,c['handle']),(handle_x,-d/2-t,center_z+.035),'metal',.004)

bag = []
s = CFG['bag']
bw, bd, bh = (s[k] for k in ('width','depth','height'))
box(bag,'SoftBody',(bw,bd,bh),(0,0,bh/2),'cloth',s['bevel'])
box(bag,'FrontPocket',(s['pocket_width'],bd*.28,s['pocket_height']),(0,-bd*.58,bh*.28),'pocket',.016)
box(bag,'PocketZip',(s['pocket_width']*.84,.006,.008),(0,-bd*.74,bh*.42),'zip',.003)
box(bag,'ZipPull',(.008,.01,.024),(bw*.29,-bd*.79,bh*.39),'metal',.003)
for side in (-1,1):
    box(bag,'HandleUpright',(.018,.022,.038),(side*s['handle_width']/2,0,bh+.012),'cloth',.007)
    box(bag,'Strap',(.025,.018,bh*.73),(side*bw*.28,bd*.52,bh*.5),'pocket',.008)
box(bag,'HandleGrip',(s['handle_width'],.022,.018),(0,0,bh+.031),'cloth',.008)
box(bag,'NamePatch',(.047,.006,.026),(bw*.21,-bd*.51,bh*.65),'zip',.004)


def export_group(objects, name):
    copies = []
    groups = {}
    for original in objects:
        obj = original.copy()
        obj.data = original.data.copy()
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')
        groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for mat, parts in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        joined = bpy.context.object
        joined.name = name + '_' + mat
        copies.append(joined)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in copies:
        obj.select_set(True)
    path = ASSETS / (name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    triangles = sum(sum(len(poly.vertices)-2 for poly in obj.data.polygons) for obj in copies)
    report = {'meshes':len(copies),'triangles':triangles,'bytes':path.stat().st_size}
    for obj in copies:
        bpy.data.objects.remove(obj,do_unlink=True)
    return report


report = {'cabinet':export_group(cabinet,'prop_storage_cabinet'), 'schoolbag':export_group(bag,'prop_schoolbag')}
existing = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/bookshelf/prop_bookshelf_blender_v2.glb'))
imported = [obj for obj in bpy.data.objects if obj not in existing]
report['reused_bookshelf'] = export_group([obj for obj in imported if obj.type=='MESH'],'prop_bookshelf_reused')
for obj in imported:
    bpy.data.objects.remove(obj,do_unlink=True)
for obj in bag:
    obj.location += Vector((.2,-.045,h))
settings = CFG['render']
bpy.ops.object.camera_add(location=settings['camera_position'])
camera = bpy.context.object
camera.rotation_euler = (Vector(settings['camera_target'])-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = settings['camera_size']
scene = bpy.context.scene
scene.camera = camera
bpy.ops.object.light_add(type='AREA',location=settings['area_position'])
light = bpy.context.object
light.data.energy = settings['area_energy']
light.data.size = settings['area_size']
light.rotation_euler = (Vector(settings['camera_target'])-light.location).to_track_quat('-Z','Y').to_euler()
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.8,.84,.9,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.7
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x,scene.render.resolution_y=settings['resolution']
scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'classroom_furnishings_v1.blend'))
scene.render.filepath=str(OUT/'blender_preview.png')
bpy.ops.render.render(write_still=True)
(OUT/'build_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
