"""Bring the right window wall up to the desk column; Blender preview only."""
import bpy,json
from pathlib import Path
from mathutils import Matrix
out=Path(__file__).resolve().parent
# Right desk centers are x=1.875; outer desktop edge is about x=2.245.
# Move the right wall inner surface from x~3.53 to x~2.78.
shift=.75
old_left=-3.6;old_right=3.6;new_right=old_right-shift
scale=(new_right-old_left)/(old_right-old_left)
shell_transform=Matrix.Translation((old_left,0,0))@Matrix.Diagonal((scale,1,1,1))@Matrix.Translation((-old_left,0,0))
changed=[]
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    n=o.name;w=o.matrix_world.copy();p=w.translation
    if '_Room_RightWall_' in n or 'WarmWindowTall' in n or 'WindowPlant' in n:
        w.translation.x-=shift
    elif any(k in n for k in ('_Room_Floor','_Room_BackWall_','Continuous ceiling slab','Shallow ceiling beam','Perimeter cornice')):
        w=shell_transform@w
    elif n.startswith(('box_','sphere_','cylinder_')) and p.x>2.7:
        w.translation.x-=shift
    else:continue
    o.matrix_world=w;changed.append(n)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'classroom_compact_window_side.blend'))
bpy.context.scene.render.filepath=str(out/'04_window_side.png')
bpy.ops.render.render(write_still=True)
(out/'window_side_report.json').write_text(json.dumps({'blender_only':True,'right_wall_shift_m':shift,'desk_positions_unchanged':True,'right_desk_to_wall_gap_approx_m':.54,'changed_meshes':len(changed)},indent=2),encoding='utf-8')
