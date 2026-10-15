import bpy
from pathlib import Path
out=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.data.collections['02 Ceiling proposal (new)'].objects:
    if obj.type=='MESH': obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'ceiling_proposal.glb'),export_format='GLB',use_selection=True,export_apply=True)
