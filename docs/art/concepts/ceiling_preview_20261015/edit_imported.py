"""Import the real runtime snapshot, add ceiling in a separate collection."""
import bpy, json
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(OUT/'current_classroom.glb'))
scene=bpy.context.scene
source=list(scene.objects)
source_collection=bpy.data.collections.new('01 Current Godot classroom (imported)'); scene.collection.children.link(source_collection)
for o in source:
    for c in list(o.users_collection): c.objects.unlink(o)
    source_collection.objects.link(o)
ceiling_collection=bpy.data.collections.new('02 Ceiling proposal (new)'); scene.collection.children.link(ceiling_collection)
def move(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    ceiling_collection.objects.link(o)
    return o
def mat(name,color,emission=0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=.85
    p.inputs['Emission Color'].default_value=(1,.92,.77,1); p.inputs['Emission Strength'].default_value=emission
    return m
plaster=mat('Ceiling warm off white',(.76,.74,.69))
housing=mat('Light enamel',(.68,.70,.68)); opal=mat('Light opal diffuser',(.9,.88,.78),2)
def box(name,size,location,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location); o=move(bpy.context.object); o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(material)
    bevel=o.modifiers.new('Small edge bevel','BEVEL'); bevel.width=.008; bevel.segments=2
    return o
box('Continuous ceiling slab',(10.4,12.4,.14),(0,0,3.47),plaster)
for y in (-3.8,0,3.8): box('Shallow ceiling beam',(10.2,.16,.16),(0,y,3.33),plaster)
for x in (-4.98,4.98): box('Wall ceiling cornice',(.12,12.2,.12),(x,0,3.32),plaster)
for x in (-2.5,2.5):
    for y in (-3.5,0,3.5):
        box('Light suspension',(.025,.025,.21),(x,y,3.19),housing)
        box('Linear light housing',(.24,1.24,.07),(x,y,3.05),housing)
        box('Linear light diffuser',(.18,1.15,.018),(x,y,3.006),opal)
        bpy.ops.object.light_add(type='AREA',location=(x,y,2.99)); l=move(bpy.context.object); l.name='New ceiling soft fill'; l.data.energy=35; l.data.shape='RECTANGLE'; l.data.size=1.15; l.data.size_y=.18
def aim(o,target): o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
# Keep imported lights in the file; use Blender physical window light for this study.
for o in source:
    if o.type=='LIGHT': o.hide_render=True
preview=bpy.data.collections.new('03 Blender preview cameras and lighting'); scene.collection.children.link(preview)
def preview_move(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    preview.objects.link(o)
    return o
for y in (-3.2,0,3.2):
    bpy.ops.object.light_add(type='AREA',location=(4.85,y,2.5)); l=preview_move(bpy.context.object); l.name='Window daylight'; l.data.energy=240; l.data.shape='RECTANGLE'; l.data.size=2.4; l.data.size_y=1.7; l.data.color=(1,.88,.70); aim(l,(0,y+1,.4))
scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs['Color'].default_value=(.72,.81,1,1); bg.inputs['Strength'].default_value=.16
bpy.ops.object.camera_add(location=(-.6,-5.7,2.05)); cam=preview_move(bpy.context.object); cam.name='Preview interior'; cam.data.lens=19; aim(cam,(.1,1,1.95)); scene.camera=cam
scene.render.engine='CYCLES'; scene.cycles.samples=40; scene.cycles.use_denoising=True
scene.render.resolution_x=1440; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.render.image_settings.file_format='PNG'
# Pack every imported texture so the .blend remains editable on its own.
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'current_classroom_ceiling.blend'))
scene.render.filepath=str(OUT/'current_classroom_ceiling_interior.png'); bpy.ops.render.render(write_still=True)
cam.location=(-3.4,-5.4,1.85); cam.data.lens=18; aim(cam,(1,1,2.05))
scene.render.filepath=str(OUT/'current_classroom_ceiling_windows.png'); bpy.ops.render.render(write_still=True)
(OUT/'blender_import_report.json').write_text(json.dumps({'source':'current_classroom.glb','imported_objects':len(source),'imported_meshes':sum(o.type=='MESH' for o in source),'new_ceiling_objects':len(ceiling_collection.objects),'blender':bpy.app.version_string,'runtime_files_replaced':False},indent=2),encoding='utf-8')
