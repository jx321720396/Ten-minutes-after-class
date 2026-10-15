import bpy,json
from mathutils import Vector
items=[]
for o in bpy.context.scene.objects:
    if o.type!='MESH': continue
    p=o.matrix_world.translation
    if abs(p.x)<1.3 and abs(p.y)<3 and min(o.dimensions)>.4:
        items.append({'name':o.name,'pos':list(p),'size':list(o.dimensions),'materials':[m.name if m else None for m in o.data.materials]})
print('CENTER_OBJECTS',json.dumps(items))
