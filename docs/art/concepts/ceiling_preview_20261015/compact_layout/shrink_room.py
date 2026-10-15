"""Smaller shell variant, retaining the accepted desk grid. Blender only."""
import bpy,json
from pathlib import Path
from mathutils import Matrix
out=Path(__file__).resolve().parent
previous=json.loads((out/'comparison_report.json').read_text(encoding='utf-8'))
characters={x['object'] for x in previous['character_seat_mapping']}
sx=.9; sy=.88
for o in list(bpy.context.scene.objects):
    if o.type not in ('MESH','LIGHT'):continue
    name=o.name
    if name in characters or '_Seats_' in name or 'DeskSideBag' in name:continue
    p=o.matrix_world.translation
    # Preserve desktop decorations and all desk/chair proportions.
    if name.startswith(('box_','cylinder_','sphere_')) and abs(p.x)<2.35 and abs(p.y)<3.4 and .55<p.z<1.2:continue
    world=o.matrix_world.copy()
    # Keep the lectern whole; bring it slightly toward the front row.
    if '_Podium_' in name or 'PodiumPlant' in name or 'PodiumSupplies' in name:
        world.translation.y+=.3
    elif o.type=='LIGHT':
        world.translation.x*=sx;world.translation.y*=sy
    else:
        world=Matrix.Diagonal((sx,sy,1,1))@world
    o.matrix_world=world
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'classroom_compact_smaller_room.blend'))
s=bpy.context.scene
s.render.filepath=str(out/'03_smaller_room.png');bpy.ops.render.render(write_still=True)
(out/'smaller_room_report.json').write_text(json.dumps({'blender_only':True,'room_width_m':7.2,'room_depth_m':10.56,'desk_grid_unchanged':True,'characters_unchanged':True,'camera_unchanged':True,'lectern_forward_shift_m':.3},indent=2),encoding='utf-8')
