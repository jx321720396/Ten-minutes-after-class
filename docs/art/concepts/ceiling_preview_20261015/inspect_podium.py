import bpy,json
for o in bpy.context.scene.objects:
    if o.type=='MESH' and 'podium' in o.name.lower():
        print(json.dumps({'name':o.name,'location':list(o.matrix_world.translation),'materials':[m.name if m else None for m in o.data.materials]},ensure_ascii=False))
