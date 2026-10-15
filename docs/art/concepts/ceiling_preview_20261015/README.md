Blender ceiling study, 2026-10-15.

Current version: current_classroom_ceiling.blend.
This imports current_classroom.glb, a frozen runtime snapshot of the real
scenes/game/classroom3D.tscn on main-mobile, including runtime decorations,
MultiMesh instances and 16 character sprite planes. Seed: 20261015.

Collections separate the imported classroom, proposed ceiling and Blender
preview lights/cameras. Textures are packed. The original imported lights
are retained but disabled in renders; preview lighting is authored for Cycles.
Godot-only shader effects/contact shadows and 2D UI are excluded. Character
billboards are frozen to the original game camera, not converted to 3D bodies.

Preview only; no runtime scene or asset replaced. These are Blender lighting
studies, not Godot runtime screenshots. Earlier ceiling_interior.png and
ceiling_window_view.png were simplified studies and are superseded by
current_classroom_ceiling_interior.png and current_classroom_ceiling_windows.png.

Reproduce: run export_current.gd with Godot 4.7.2 using a real rendering
driver (--rendering-method gl_compatibility, NOT --headless). The dummy
headless renderer does not retain MultiMesh instance transforms correctly.
Then run edit_imported.py with Blender in background mode. Reports record
export/import counts.

Pressure comparison: pressure_0.png, pressure_50.png, pressure_100.png are
actual Godot screenshots, not Blender renders. export_ceiling.py exports
only the new ceiling geometry; capture_pressure.gd loads it into a temporary
runtime classroom and invokes the unchanged production pressure lighting.
All three frames use the same interior camera, seed and frozen simulation.
Only the isolated preview instance receives stress fixtures; no save or
production scene/config is written. The production 3-second transition is
settled before each capture. See pressure_report.json for measured colors.
Run capture_pressure.gd with a real rendering driver to reproduce.

V2: current_classroom_ceiling_v2.blend / ceiling_proposal_v2.glb replace the
two-column proposal with three columns by three rows (nine fixtures).
ceiling_v2.json stores all new fixture grid and preview settings.
Each Godot preview source is 0.016 m below its matching diffuser center.
The original six ceiling lights are disabled only in the preview instance;
nine aligned sources split their original total energy of 1.08 equally.
Their tint is synchronized with the unchanged production pressure lighting.

capture_ceiling_v2.gd outputs original-camera before/after and interior
0/50/100 comparisons plus the maximum right-follow position.
Actual style camera: (0,3.35,9.5), vertical FOV 36 degrees, right-follow
offset 0..0.8 m. The ceiling underside is 3.40 m above the floor.
102 line segments at three actor heights and two follow endpoints intersect
none of the new ceiling/fixture mesh AABBs; see ceiling_v2_report.json.
This check covers this captured arrangement and current camera settings,
not arbitrary future camera positions. Original-camera screenshots were
also visually inspected. No production scene, camera or lighting config
has been modified by these preview tools.

V3: current_classroom_ceiling_v3.blend has nine recessed luminaires.
Suspensions are removed; actual Boolean openings receive flush opal panels
at y=3.405 m, with slim trims. Beams move between fixture rows so they do
not cover the openings. Light source y=3.38 m. V2 stays available.
v3_blender_interior.png and v3_blender_original_camera.png are Blender
renders of the previously exported classroom snapshot, not runtime captures.
The latter reproduces the current game camera position/target and 36-degree
vertical FOV. Runtime V3 capture was attempted but could not complete:
concurrent workspace simulation changes cause initialization errors
(missing snack_count_per_run / player_interaction config). No unrelated
simulation files were changed to work around this. V3 pressure integration
has therefore not been reverified in the live runtime.


Production integration: user authorized import after removing P0 desk. classroom_final_no_side_desk.blend removes 18 old P0 desk/chair/bag meshes. Runtime uses its existing P1..P16 layout, new classroom_ceiling_recessed.tscn via scene_details, nine aligned pressure-tinted lights and node_material_overrides for podium body only. verify_recessed_ceiling.gd passes independently of simulation initialization. gdformat/gdlint pass for changed scripts. check_config fails on migration-deleted player_interaction.csv; full simulation runtime verification remains blocked by unrelated migration.
