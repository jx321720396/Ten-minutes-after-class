"""Standalone Blender study. Does not write runtime assets or Godot scenes."""
import bpy, json, re, math
from pathlib import Path
from mathutils import Matrix, Vector
OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
STYLE = json.loads((ROOT/'data/ui/classroom_art.json').read_text(encoding='utf-8'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
C = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def mat(name, color):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) or m.node_tree.nodes.new('ShaderNodeBsdfPrincipled'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=.82
    return m
M={k:mat(k,tuple((int(v['color'][i:i+2],16)/255)**2.2 for i in (1,3,5))) for k,v in STYLE['materials'].items()}
M['ceiling']=mat('Warm chalk plaster',(.77,.75,.68))
M['lamp']=mat('Opal diffuser',(.9,.89,.79))
next(n for n in M['lamp'].node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Emission Color'].default_value=(1,.93,.78,1)
next(n for n in M['lamp'].node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Emission Strength'].default_value=2
def box(name,size,pos,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos); o=bpy.context.object; o.name=name; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(M[material]); return o
text=(ROOT/'scenes/game/classroom3D.tscn').read_text(encoding='utf-8')
blocks=re.findall(r'\[([^\n]+)\]\n([^\[]*)',text)
meshes={}; exts={}; transforms={'.':Matrix.Identity(4)}
for header,body in blocks:
    idm=re.search(r'id="([^"]+)"',header)
    if header.startswith('ext_resource') and idm:
        path=re.search(r'path="([^"]+)"',header); exts[idm[1]]=path[1] if path else ''
    if header.startswith('sub_resource') and idm: meshes[idm[1]]=(header,body)
for header,body in blocks:
    if not header.startswith('node '): continue
    name=re.search(r'name="([^"]+)"',header)[1]; pm=re.search(r'parent="([^"]+)"',header)
    parent=pm[1] if pm else '.'; path=(parent+'/' if parent!='.' else '')+name
    t=Matrix.Identity(4); tm=re.search(r'Transform3D\(([^)]+)',body)
    if tm:
        a=list(map(float,tm[1].split(','))); t=Matrix(((a[0],a[3],a[6],a[9]),(a[1],a[4],a[7],a[10]),(a[2],a[5],a[8],a[11]),(0,0,0,1)))
    world=transforms.get(parent,Matrix.Identity(4))@t; transforms[path]=world
    if not path.startswith('Room/') or name=='Ceiling' or any(path==x or path.startswith(x+'/') for x in STYLE['hide_nodes']): continue
    mm=re.search(r'mesh = SubResource\("([^"]+)"',body)
    if not mm or mm[1] not in meshes: continue
    mh,mb=meshes[mm[1]]; sz=re.search(r'size = Vector[23]\(([^)]+)',mb)
    if not sz: continue
    dims=list(map(float,sz[1].split(',')))
    if 'PlaneMesh' in mh: dims=[dims[0],.04,dims[1]]
    elif 'QuadMesh' in mh: dims=[dims[0],dims[1],.015]
    if len(dims)!=3: continue
    mi=re.search(r'material = ExtResource\("([^"]+)"',mb); key='wall'
    if mi:
        basename=Path(exts.get(mi[1],'')).stem; key=STYLE['material_replacements'].get(basename,'wall')
    o=box(path,dims,(0,0,0),key); o.matrix_world=C@world@Matrix.Diagonal((*dims,1))
# Reuse the actual clean Blender desk export at current seat positions.
for path,t in transforms.items():
    if not path.startswith('Seats/P') or path=='Seats': continue
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/school_desk/prop_school_desk_blender_v1.glb'))
    for o in set(bpy.data.objects)-before:
        if o.parent is None: o.matrix_world=C@t@C.inverted()@o.matrix_world
# Reuse the current window model, with the same placement from the style table.
window=ROOT/'assets/models/classroom_window/prop_classroom_window_warm_v1.glb'
if not window.exists():
    window=next((ROOT/'assets/models/classroom_window').glob('*window*.glb'))
for p in STYLE['scene_details']:
    if 'school_window' not in p['scene']: continue
    before=set(bpy.data.objects); bpy.ops.import_scene.gltf(filepath=str(window))
    t=transforms[p['anchor_node']].copy() if 'anchor_node' in p else Matrix.Translation(Vector(p['position']))
    rot=p.get('rotation',[0,0,0]); t=t@Matrix.Rotation(math.radians(rot[1]),4,'Y')
    for o in set(bpy.data.objects)-before:
        if o.parent is None: o.matrix_world=C@t@C.inverted()@o.matrix_world
ceiling=[]
ceiling.append(box('Ceiling continuous slab',(10.4,12.4,.16),(0,0,3.48),'ceiling'))
for y in (-3.8,0,3.8): ceiling.append(box('Shallow cross beam',(10.2,.18,.18),(0,y,3.31),'ceiling'))
for x in (-4.96,4.96): ceiling.append(box('Perimeter cornice',(.12,12,.12),(x,0,3.32),'ceiling'))
for x in (-2.5,2.5):
    for y in (-3.5,0,3.5):
        ceiling.append(box('Pendant stem',(.035,.035,.22),(x,y,3.19),'metal'))
        ceiling.append(box('Linear light housing',(.26,1.28,.09),(x,y,3.03),'window'))
        ceiling.append(box('Opal twin lamp',(.19,1.18,.024),(x,y,2.975),'lamp'))
        bpy.ops.object.light_add(type='AREA',location=(x,y,2.95)); l=bpy.context.object; l.data.energy=65; l.data.shape='RECTANGLE'; l.data.size=1.15; l.data.size_y=.22
def aim(o,target): o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for y in (-3.2,0,3.2):
    bpy.ops.object.light_add(type='AREA',location=(5.3,y,2.3)); l=bpy.context.object; l.data.energy=340; l.data.shape='RECTANGLE'; l.data.size=2.4; l.data.size_y=1.6; l.data.color=(1,.86,.65); aim(l,(0,y+1,0))
scene=bpy.context.scene; scene.world.use_nodes=True
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Color'].default_value=(.68,.78,1,1)
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs['Strength'].default_value=.17
bpy.ops.object.camera_add(location=(-.8,-5.7,2.15)); camera=bpy.context.object; camera.data.lens=19; aim(camera,(.2,1,1.95)); scene.camera=camera
scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.render.resolution_x=1440; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.render.image_settings.file_format='PNG'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'classroom_ceiling_study.blend'))
scene.render.filepath=str(OUT/'ceiling_interior.png'); bpy.ops.render.render(write_still=True)
camera.location=(-3.5,-5.5,1.7); camera.data.lens=18; aim(camera,(1.4,1,2.25))
scene.render.filepath=str(OUT/'ceiling_window_view.png'); bpy.ops.render.render(write_still=True)
(OUT/'README.md').write_text('Blender ceiling study, 2026-10-15.\nPreview only; no runtime scene or asset replaced.\nRoom primitive geometry and desk/window assets reused from current mobile workspace.\nBlender lighting study is not a Godot runtime screenshot.\n',encoding='utf-8')
