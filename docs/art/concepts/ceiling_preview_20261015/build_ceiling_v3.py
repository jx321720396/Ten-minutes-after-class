"""Recessed lighting preview, preserving v2 and all runtime assets."""
import bpy,json
from pathlib import Path
OUT=Path(__file__).resolve().parent
cfg=json.loads((OUT/'ceiling_v2.json').read_text(encoding='utf-8'))
cfg.update({'housing_center_y':3.428,'housing_size':[.24,1.24,.04], 'diffuser_center_y':3.405,'diffuser_size':[.20,1.20,.008],'light_center_y':3.38,'opening_size':[.25,1.25,.14],'trim_width':.018,'trim_depth':.012,'trim_center_y':3.399,'beam_rows':[-5.4,-1.8,1.8,5.4]})
(OUT/'ceiling_v3.json').write_text(json.dumps(cfg,indent=2),encoding='utf-8')
c=bpy.data.collections['02 Ceiling proposal (new)']
for o in list(c.objects):
    if o.name.startswith(('Lamp','Shallow ceiling beam')): bpy.data.objects.remove(o,do_unlink=True)
def move(o):
    for old in list(o.users_collection): old.objects.unlink(o)
    c.objects.link(o)
def box(name,size,pos,mat=None,bevel=False):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos); o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); move(o)
    if mat:o.data.materials.append(bpy.data.materials[mat])
    if bevel:
        m=o.modifiers.new('Fine edge','BEVEL'); m.width=.002; m.segments=2
    return o
slab=next(o for o in c.objects if o.name.startswith('Continuous ceiling slab'))
for y in cfg['beam_rows']: box('Shallow ceiling beam',(10.2,.12,.08),(0,y,3.36),'Ceiling warm off white',True)
for col,x in enumerate(cfg['columns_x']):
    for row,z in enumerate(cfg['rows_godot_z']):
        y=-z; tag=f'C{col}_R{row}'
        cutter=box('Recess cutter',cfg['opening_size'],(x,y,3.40))
        mod=slab.modifiers.new('Actual recessed opening '+tag,'BOOLEAN'); mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=cutter
        bpy.context.view_layer.objects.active=slab; bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter,do_unlink=True)
        box('LampHousing_'+tag,cfg['housing_size'],(x,y,cfg['housing_center_y']),'Light enamel')
        box('LampDiffuser_'+tag,cfg['diffuser_size'],(x,y,cfg['diffuser_center_y']),'Light opal diffuser',True)
        w,l,_=cfg['opening_size']; t=cfg['trim_width']; d=cfg['trim_depth']; h=cfg['trim_center_y']
        for side in (-1,1):
            box('LampTrimLong_'+tag,(t,l+2*t,d),(x+side*(w+t)/2,y,h),'Light enamel',True)
            box('LampTrimEnd_'+tag,(w,t,d),(x,y+side*(l+t)/2,h),'Light enamel',True)
        bpy.ops.object.light_add(type='AREA',location=(x,y,cfg['light_center_y'])); light=bpy.context.object; move(light); light.name='LampSource_'+tag
        light.data.energy=cfg['blender_total_lamp_watts']/9; light.data.shape='RECTANGLE'; light.data.size=1.2; light.data.size_y=.2
bpy.ops.object.select_all(action='DESELECT')
for o in c.objects:
    if o.type=='MESH':o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'ceiling_proposal_v3.glb'),export_format='GLB',use_selection=True,export_apply=True)
bpy.ops.file.pack_all(); bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'current_classroom_ceiling_v3.blend'))
print('PASS: 9 actual recessed openings, no suspension, flush diffusers, beams between light rows')
