# Animated 3D Unit Models

## Space Marine MVP

The starting Planet Lander deploys three `space_marine` units when touchdown completes. They spawn on passable tiles around the module, participate in the existing unit selection, pathfinding, formation, and collision systems, and are rendered only by `IsoUnit3DLayer`.

The runtime scene is generated at:

`assets/3D/units/space_marine/runtime/space_marine_run_03.glb`

It is built from Meshy's `Meshy_AI_Space_Marine_biped_Animation_Run_03_withSkin.glb`, which contains the skinned mesh, `Skeleton3D`, and `Armature|Run_03|baselayer` animation. The animation is changed to linear looping at runtime and plays while unit speed is above the movement threshold. Idle currently uses the first bind/run pose; a dedicated idle animation can replace this later.

Meshy's GLB contains geometry, skinning, skeleton, and animation but no texture resources. Its generated UV layout is not compatible with the Hyper3D base textures even though the meshes have practically identical surfaces. `tools/build_space_marine_runtime.py` uses Blender's nearest-face interpolation to calculate the Hyper3D base mesh UV map for Meshy's vertices, then copies Meshy's original GLB and patches only its `TEXCOORD_0` accessor. Do not replace this with a normal Blender GLB export: re-exporting changes the rig's coordinate system and breaks the existing animation. `IsoUnit3DLayer` recursively overrides the runtime mesh material with the diffuse, emissive, normal, roughness, and metallic maps from `assets/3D/units/space_marine/base/`.

Regenerate after replacing either source model:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/build_space_marine_runtime.py
```

`Meshy_AI_Space_Marine_biped_rigged` is not needed at runtime for this MVP. Its character-only GLB can be retained as a clean rig source for future animation-library workflows.

## Future animated units

When adding another rigged unit:

1. Prefer one GLB containing mesh, skin, skeleton, and the animation needed at runtime.
2. Verify the node tree contains a `Skeleton3D`, skinned `MeshInstance3D`, and `AnimationPlayer`.
3. Verify exact animation names and loop settings; generated exporters often use long armature-based names and non-looping defaults.
4. If animation GLBs omit textures, apply the authoritative base-model PBR material only after confirming that UVs match.
5. Warm the scene and material during an existing loading phase before the unit can spawn.
6. Keep simulation role, position, heading, speed, selection, and pathfinding in `UnitState`; the animated scene is presentation only.
7. Hide the corresponding 2D fallback while the 3D renderer owns the role, but keep 2D selection/status overlays when useful.
8. Use the shared 3D texture import policy: VRAM compression, mipmaps, explicit normal-map import, and desktop/mobile Web variants.

Separate animation GLBs can later be consolidated into a Godot animation library or imported through a dedicated Blender pipeline. Do not assume a character-only rig file is required when an animation GLB already includes the skinned character.
