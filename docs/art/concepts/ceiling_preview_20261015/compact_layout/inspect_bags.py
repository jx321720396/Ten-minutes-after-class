import bpy,json
for o in bpy.context.scene.objects:
    if 'DeskSideBag1_' in o.name or '_Seats_P1_Desk_' in o.name:
        print(json.dumps({'name':o.name,'pos':list(o.matrix_world.translation),'size':list(o.dimensions),'parent':o.parent.name if o.parent else None}))
