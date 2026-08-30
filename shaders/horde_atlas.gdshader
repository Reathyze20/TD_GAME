shader_type canvas_item;

// P5 (docs/refactor/PATHFINDING.MD): lets one MultiMeshInstance2D draw many
// distractions that are all mid-walk-cycle at DIFFERENT frames/facings/variants at
// once, by keeping every needed sprite frame packed into one shared runtime atlas
// (scripts/components/horde_atlas.gd) and letting each instance pick its own sub-rect
// here. INSTANCE_CUSTOM is Godot's per-MultiMesh-instance custom_data channel
// (MultiMesh.use_custom_data): .xy is the frame's top-left UV in the atlas, .zw is its
// UV size (both normalized 0..1). Mirroring (west-facing = east art flipped, same
// convention distraction_animator.gd already used) is done by the CALLER via a
// negative X scale on the instance transform, not here — flipping the mesh's own
// vertices already flips which UV lands where on screen, so no separate mirror branch
// is needed in the shader.
//
// No fragment() override: the built-in default samples TEXTURE at this UV and
// multiplies by COLOR, which is exactly what is wanted — COLOR carries the
// per-instance hit-flash tint (DistractionAnimator.hit_flash_color()), same
// overbright-white formula the legacy per-node draw_texture_rect() call used.

void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
