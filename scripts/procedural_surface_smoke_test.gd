extends SceneTree

const ProceduralMapGenerator := preload("res://scripts/procedural_map_generator.gd")
const Terrain3DLayer := preload("res://scripts/iso_terrain_3d_layer.gd")
const SurfaceDetail3DLayer := preload("res://scripts/iso_surface_detail_3d_layer.gd")
const Mountain3DLayer := preload("res://scripts/iso_mountain_3d_layer.gd")


func _initialize() -> void:
	var map_data := ProceduralMapGenerator.generate(Vector2i(48, 48), 424242, 10, 16, 3, 4, 55, 50)
	var repeated_map := ProceduralMapGenerator.generate(Vector2i(48, 48), 424242, 10, 16, 3, 4, 55, 50)
	var sample_tile := Vector2i(34, 29)
	if not is_equal_approx(map_data.get_moisture(sample_tile), repeated_map.get_moisture(sample_tile)):
		_fail("Surface ecology fields should be deterministic for a fixed seed.")
		return

	var terrain_layer := Terrain3DLayer.new()
	root.add_child(terrain_layer)
	terrain_layer.set_map_data(map_data)
	var expected_chunks := ceili(float(map_data.size.x) / float(terrain_layer.CHUNK_SIZE)) * ceili(float(map_data.size.y) / float(terrain_layer.CHUNK_SIZE))
	if terrain_layer.get_child_count() != expected_chunks:
		_fail("Ground should contain %d continuous chunks, found %d." % [expected_chunks, terrain_layer.get_child_count()])
		return
	if terrain_layer.last_cells_processed != map_data.size.x * map_data.size.y:
		_fail("Ground chunk rebuild should account for every logical cell.")
		return
	var first_chunk := terrain_layer.get_child(0) as MeshInstance3D
	if first_chunk == null or not first_chunk.mesh is ArrayMesh:
		_fail("Ground chunks should be procedural ArrayMesh instances.")
		return
	var arrays := first_chunk.mesh.surface_get_arrays(0)
	if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != 4:
		_fail("A flat terrain chunk should need one quad, not one mesh per tile.")
		return
	if not first_chunk.material_override is ShaderMaterial:
		_fail("Ground chunks should use the shared baked-surface shader.")
		return
	var terrain_shader_code: String = (first_chunk.material_override as ShaderMaterial).shader.code
	if terrain_layer.baked_albedo_texture == null or terrain_layer.last_surface_bake_usec <= 0:
		_fail("Ground appearance should be baked once into an albedo texture during map loading.")
		return
	var expected_bake_size := Vector2i(
		mini(map_data.size.x * terrain_layer.SURFACE_TEXELS_PER_TILE, terrain_layer.MAX_SURFACE_TEXTURE_SIZE),
		mini(map_data.size.y * terrain_layer.SURFACE_TEXELS_PER_TILE, terrain_layer.MAX_SURFACE_TEXTURE_SIZE)
	)
	if terrain_layer.baked_texture_size != expected_bake_size:
		_fail("The baked ground texture should preserve its configured high-resolution texel density.")
		return
	print("surface_bake_size=%s bake_ms=%.2f" % [terrain_layer.baked_texture_size, float(terrain_layer.last_surface_bake_usec) / 1000.0])
	if not terrain_shader_code.contains("baked_albedo_map") or not terrain_shader_code.contains("ATTENUATION"):
		_fail("Runtime ground rendering should sample one baked texture and receive realtime cast shadows.")
		return
	for forbidden_runtime_work in ["value_noise", "fbm", "domain_warp", "surface_height", "world_height_gradient", "geology_map", "NORMAL =", "ROUGHNESS ="]:
		if terrain_shader_code.contains(forbidden_runtime_work):
			_fail("Baked ground shader still performs runtime procedural work: %s" % forbidden_runtime_work)
			return
	terrain_layer.set_grid_visible(false)
	if terrain_layer.grid_visible or terrain_layer.get_child_count() != expected_chunks:
		_fail("The debug grid should be a shader overlay and toggling it must not rebuild geometry.")
		return

	var detail_layer := SurfaceDetail3DLayer.new()
	root.add_child(detail_layer)
	detail_layer.set_map_data(map_data)
	if detail_layer.last_placement_count <= 0 or detail_layer.get_child_count() <= 0:
		_fail("Ecology fields should produce procedural surface detail instances.")
		return
	if detail_layer.last_scree_placement_count <= 0:
		_fail("Mountain-edge fields should scatter rubble beyond the geometric talus skirt.")
		return
	for child in detail_layer.get_children():
		if not child is MultiMeshInstance3D:
			_fail("Surface details should be batched into MultiMesh instances.")
			return
		var instance := child as MultiMeshInstance3D
		if instance.multimesh == null or instance.multimesh.instance_count <= 0:
			_fail("Every surface detail batch should contain visible instances.")
			return
		if instance.name.split("_").size() < 3:
			_fail("Surface detail batches should expose their render chunk in the node name.")
			return

	var mountain_layer := Mountain3DLayer.new()
	root.add_child(mountain_layer)
	mountain_layer.set_map_data(map_data)
	if mountain_layer.get_child_count() != 1:
		_fail("The restored mountain renderer should create one massif mesh without transition geometry.")
		return
	var mountain_mesh := mountain_layer.get_node_or_null("ProceduralMountainMassifs") as MeshInstance3D
	if mountain_mesh == null:
		_fail("The restored mountain renderer should create its original massif mesh.")
		return
	var mountain_material := mountain_mesh.material_override as StandardMaterial3D
	if mountain_material == null or not mountain_material.vertex_color_use_as_albedo or mountain_material.cull_mode != BaseMaterial3D.CULL_DISABLED:
		_fail("The restored mountain renderer should use its original faceted vertex-color material.")
		return
	var mountain_arrays := mountain_mesh.mesh.surface_get_arrays(0)
	var mountain_normals: PackedVector3Array = mountain_arrays[Mesh.ARRAY_NORMAL]
	for normal in mountain_normals:
		if normal.y < -0.0001:
			_fail("Mountain face normals should never point beneath the terrain.")
			return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
