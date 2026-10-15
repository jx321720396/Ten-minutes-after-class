import bpy,json,re
from pathlib import Path
out=Path(__file__).resolve().parent
removed=[]
for o in list(bpy.data.objects):
    if re.search(r'_Seats_P0(?:_|$)',o.name) or 'DeskSideBag0_' in o.name:
        removed.append(o.name); bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'classroom_final_no_side_desk.blend'))
(out/'removed_side_desk.json').write_text(json.dumps(removed,indent=2),encoding='utf-8')
print('Removed old P0 meshes:',len(removed))
