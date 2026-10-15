import bpy
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[5]
out=root/'assets/models/classroom_compact';out.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
items=[o for o in bpy.context.scene.objects if 'DeskSideBag1_' in o.name or o.name in ('Hook mounting plate P1','J hook P1','Bag carrying loop P1')]
assert len(items)==7
for o in items:
    w=o.matrix_world.copy();w.translation-=Vector((1.875,-3,0));o.matrix_world=w;o.select_set(True)
bpy.context.view_layer.objects.active=items[0]
bpy.ops.object.convert(target='MESH')
bpy.ops.export_scene.gltf(filepath=str(out/'bag_left_hook.glb'),export_format='GLB',use_selection=True,export_apply=True)
