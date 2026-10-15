import bpy
from pathlib import Path
from mathutils import Vector
out=Path(__file__).resolve().parent
c=bpy.context.scene.camera
c.location=(-3.1,-3.8,1.13);c.data.lens=32
c.rotation_euler=(Vector((-2.29,-3.04,.69))-c.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.render.filepath=str(out/'05_bag_hook_detail.png')
bpy.ops.render.render(write_still=True)
