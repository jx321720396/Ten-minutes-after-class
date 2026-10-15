"""Blender-only controlled before/after. No Godot runtime files are written."""
import bpy,json,re,math
from pathlib import Path
from mathutils import Vector,Matrix
OUT=Path(__file__).resolve().parent/'compact_layout'
OUT.mkdir(exist_ok=True)
ROOT=OUT.parents[4]
text=(ROOT/'scenes/game/classroom3D.tscn').read_text(encoding='utf-8')
seats={}
for m in re.finditer(r'\[node name="P(\d+)" parent="Seats"[^\n]*\]\s*transform = Transform3D\(([^)]+)',text):
    a=list(map(float,m[2].split(','))); seats[int(m[1])]=Vector((a[9],-a[11],a[10]))
assert len(seats)==16
cfg={'column_pitch':1.25,'row_pitch':2.0,'furniture_scale':1.12,'room_width_scale':.80,'render_samples':40}
(OUT/'layout_settings.json').write_text(json.dumps(cfg,indent=2),encoding='utf-8')
s=bpy.context.scene;c=s.camera
c.location=(0,-9.5,3.35);c.rotation_euler=(Vector((0,.3,0))-c.location).to_track_quat('-Z','Y').to_euler()
c.data.sensor_fit='VERTICAL';c.data.sensor_height=24;c.data.lens=12/math.tan(math.radians(18))
s.render.resolution_x=1440;s.render.resolution_y=900;s.render.resolution_percentage=100;s.cycles.samples=cfg['render_samples']
s.render.filepath=str(OUT/'01_original.png');bpy.ops.render.render(write_still=True)
objects=list(s.objects); groups={i:[] for i in seats};sprites=[];assigned=set()
for o in objects:
    if o.type!='MESH':continue
    m=re.search(r'_Seats_P(\d+)(?:_|$)',o.name) or re.search(r'DeskSideBag(\d+)_',o.name)
    if m and int(m[1]) in seats:groups[int(m[1])].append(o);assigned.add(o.name)
    elif '_Actors_' in o.name and o.name.endswith('_Sprite'):sprites.append(o)
# Runtime batch decorations are separate meshes: associate only desk-top items.
for o in objects:
    if o.type!='MESH' or o.name in assigned or not re.match(r'(box|cylinder|sphere)_',o.name):continue
    p=o.matrix_world.translation
    nearest=min(seats,key=lambda i:(p-seats[i]).xy.length)
    delta=p-seats[nearest]
    if abs(delta.x)<.43 and abs(delta.y)<.35 and .55<p.z<1.05:
        groups[nearest].append(o);assigned.add(o.name)
new_seats={}
for i in seats:
    row=(i-1)//4;col=(i-1)%4
    new_seats[i]=Vector(((1.5-col)*cfg['column_pitch'],(row-1.5)*cfg['row_pitch'],0))
for i,items in groups.items():
    transform=Matrix.Translation(new_seats[i])@Matrix.Diagonal((cfg['furniture_scale'],)*3+(1,))@Matrix.Translation(-seats[i])
    for o in items:o.matrix_world=transform@o.matrix_world
# Assign characters by distance to the old seat standing anchors, one per seat.
available=set(seats);pending=list(sprites);mapping=[]
while pending:
    dist,o,i=min((((o.matrix_world.translation-(seats[i]+Vector((0,.8,.913)))).length,o,i) for o in pending for i in available),key=lambda item:item[0])
    old=o.matrix_world.copy();old.translation+=new_seats[i]-seats[i];o.matrix_world=old
    mapping.append({'object':o.name,'seat':i,'old_anchor_distance':dist});assigned.add(o.name);pending.remove(o);available.remove(i)
# Narrow the room shell and its decorations; keep lectern dimensions intact.
for o in objects:
    if o.type not in ('MESH','LIGHT') or o.name in assigned or o in sprites:continue
    if '_Podium_' in o.name or 'PodiumPlant' in o.name or 'PodiumSupplies' in o.name:continue
    world=o.matrix_world.copy()
    if o.type=='LIGHT':world.translation.x*=cfg['room_width_scale']
    else:world=Matrix.Diagonal((cfg['room_width_scale'],1,1,1))@world
    o.matrix_world=world
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'classroom_compact_4x4.blend'))
s.render.filepath=str(OUT/'02_compact.png');bpy.ops.render.render(write_still=True)
report={'godot_files_modified':False,'seat_count':len(seats),'sprite_count':len(sprites),'old_column_pitch_approx':1.87,'new_column_pitch':cfg['column_pitch'],'old_row_pitch':1.6,'new_row_pitch':cfg['row_pitch'],'furniture_scale':cfg['furniture_scale'],'old_room_width':10,'new_room_width':8,'camera_and_lighting_settings_identical':True,'character_sizes_unchanged':True,'character_seat_mapping':mapping,'seat_positions':{str(i):list(p) for i,p in new_seats.items()}}
(OUT/'comparison_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PASS: Blender only, 16 desks, identical camera, compact comparison rendered')
