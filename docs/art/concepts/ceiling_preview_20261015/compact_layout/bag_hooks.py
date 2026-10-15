"""Left-side bags with visible mounting plates, J hooks and carrying loops."""
import bpy,re,json
from pathlib import Path
from mathutils import Vector
out=Path(__file__).resolve().parent
collection=bpy.data.collections.new('Left desk hooks and bag handles');bpy.context.scene.collection.children.link(collection)
def material(name,color,metallic=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metallic;p.inputs['Roughness'].default_value=.45 if metallic else .88;return m
steel=material('Hook brushed dark steel',(.15,.19,.20),.65)
fabric=material('Bag woven carrying loop',(.09,.15,.17))
def tube(name,points,radius,mat):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.bevel_depth=radius;curve.bevel_resolution=3
    sp=curve.splines.new('POLY');sp.points.add(len(points)-1)
    for p,xyz in zip(sp.points,points):p.co=(*xyz,1)
    o=bpy.data.objects.new(name,curve);collection.objects.link(o);o.data.materials.append(mat);return o
def cube(name,pos,size):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos);o=bpy.context.object;o.name=name;o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(steel)
    for c in list(o.users_collection):c.objects.unlink(o)
    collection.objects.link(o)
count=0
for i in range(1,17):
    top=next(o for o in bpy.context.scene.objects if re.search(rf'_Seats_P{i}_Desk_Top$',o.name))
    bag=[o for o in bpy.context.scene.objects if f'DeskSideBag{i}_' in o.name]
    assert len(bag)==4,(i,len(bag))
    x,y,z=top.matrix_world.translation
    body=next(o for o in bag if o.name.endswith('_cloth'))
    old=body.matrix_world.translation.copy();desired=Vector((x-.465,y-.04,.495))
    delta=desired-old
    for o in bag:
        w=o.matrix_world.copy();w.translation+=delta;o.matrix_world=w
    # Plate attaches to the desk's left under-top frame, J-shaped hook opens upward.
    cube(f'Hook mounting plate P{i}',(x-.342,y-.04,.751),(.014,.065,.075))
    tube(f'J hook P{i}',[(x-.35,y-.04,.770),(x-.46,y-.04,.770),(x-.46,y-.04,.735),(x-.495,y-.04,.735),(x-.495,y-.04,.765)],.006,steel)
    # A visible short fabric loop joins the upper bag body to the hook cradle.
    tube(f'Bag carrying loop P{i}',[(x-.465,y-.086,.690),(x-.465,y-.086,.716),(x-.465,y-.065,.742),(x-.465,y-.015,.742),(x-.465,y+.006,.716),(x-.465,y+.006,.690)],.008,fabric)
    count+=1
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(out/'classroom_compact_left_bag_hooks.blend'))
s=bpy.context.scene;s.render.filepath=str(out/'05_left_bag_hooks.png');bpy.ops.render.render(write_still=True)
c=s.camera;c.location=(-.5,-4.8,1.45);c.data.lens=35;c.rotation_euler=(Vector((-2.25,-3,.66))-c.location).to_track_quat('-Z','Y').to_euler()
s.render.filepath=str(out/'05_bag_hook_detail.png');bpy.ops.render.render(write_still=True)
(out/'bag_hook_report.json').write_text(json.dumps({'bag_count':count,'hook_count':count,'position':'left side in current preview coordinates','runtime_modified':False},indent=2),encoding='utf-8')
