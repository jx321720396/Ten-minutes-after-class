import bpy,math,json
from pathlib import Path
from mathutils import Vector
out=Path(__file__).resolve().parent
material=bpy.data.materials.new('Podium lower warm grey matte laminate')
material.use_nodes=True
p=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
color=tuple(((v/255+.055)/1.055)**2.4 for v in (193,190,179))
p.inputs['Base Color'].default_value=(*color,1)
p.inputs['Roughness'].default_value=.82
targets=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.endswith('Podium_Lectern_Body')]
assert len(targets)==1,[o.name for o in targets]
for o in targets:
    o.data=o.data.copy(); o.data.materials.clear(); o.data.materials.append(material)
s=bpy.context.scene; c=s.camera
c.location=(0,-9.5,3.35)
c.rotation_euler=(Vector((0,.3,0))-c.location).to_track_quat('-Z','Y').to_euler()
c.data.sensor_fit='VERTICAL'; c.data.sensor_height=24; c.data.lens=12/math.tan(math.radians(18))
s.cycles.samples=40
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'current_classroom_ceiling_v4_podium.blend'))
s.render.filepath=str(out/'v4_podium_warm_grey.png'); bpy.ops.render.render(write_still=True)
c.location=(2,-6.8,2.2); c.data.lens=35
c.rotation_euler=(Vector((0,-4.4,.7))-c.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(out/'v4_podium_detail.png'); bpy.ops.render.render(write_still=True)
(out/'podium_finish_report.json').write_text(json.dumps({'changed_objects':[o.name for o in targets],'finish':'warm grey matte laminate #c1beb3, no texture','top_wood_preserved':True,'runtime_scene_modified':False},indent=2),encoding='utf-8')
