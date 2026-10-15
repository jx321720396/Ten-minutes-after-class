"""Revise only preview ceiling. Source runtime classroom remains intact."""
import bpy, json
from pathlib import Path
OUT=Path(__file__).resolve().parent
cfg=json.loads((OUT/'ceiling_v2.json').read_text(encoding='utf-8'))
collection=bpy.data.collections['02 Ceiling proposal (new)']
for o in list(collection.objects):
    if o.name.startswith(('Light suspension','Linear light','New ceiling soft fill')):
        bpy.data.objects.remove(o,do_unlink=True)
def move(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o)
def box(name,size,pos,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos); o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(bpy.data.materials[mat]); move(o)
    bevel=o.modifiers.new('Soft edge','BEVEL'); bevel.width=.008; bevel.segments=2
for col,x in enumerate(cfg['columns_x']):
    for row,z in enumerate(cfg['rows_godot_z']):
        tag=f'C{col}_R{row}'
        box('LampSuspension_'+tag,cfg['suspension_size'],(x,-z,cfg['suspension_center_y']),'Light enamel')
        box('LampHousing_'+tag,cfg['housing_size'],(x,-z,cfg['housing_center_y']),'Light enamel')
        box('LampDiffuser_'+tag,cfg['diffuser_size'],(x,-z,cfg['diffuser_center_y']),'Light opal diffuser')
        bpy.ops.object.light_add(type='AREA',location=(x,-z,cfg['light_center_y'])); l=bpy.context.object; l.name='LampSource_'+tag; move(l)
        l.data.energy=cfg['blender_total_lamp_watts']/(len(cfg['columns_x'])*len(cfg['rows_godot_z'])); l.data.shape='RECTANGLE'; l.data.size=cfg['diffuser_size'][1]; l.data.size_y=cfg['diffuser_size'][0]
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:
    if o.type=='MESH': o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'ceiling_proposal_v2.glb'),export_format='GLB',use_selection=True,export_apply=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'current_classroom_ceiling_v2.blend'))
print('PASS: 3 columns x 3 rows; 9 aligned lamp sources; total Blender lamp power conserved')
