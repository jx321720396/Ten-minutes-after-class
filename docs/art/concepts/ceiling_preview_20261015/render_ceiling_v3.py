import bpy, math
from pathlib import Path
from mathutils import Vector
out=Path(__file__).resolve().parent
s=bpy.context.scene
s.cycles.samples=40
s.render.filepath=str(out/'v3_blender_interior.png')
bpy.ops.render.render(write_still=True)
c=s.camera; c.location=(0,-9.5,3.35)
c.rotation_euler=(Vector((0,.3,0))-c.location).to_track_quat('-Z','Y').to_euler()
c.data.sensor_fit='VERTICAL'; c.data.sensor_height=24; c.data.lens=12/math.tan(math.radians(18))
s.render.filepath=str(out/'v3_blender_original_camera.png')
bpy.ops.render.render(write_still=True)
