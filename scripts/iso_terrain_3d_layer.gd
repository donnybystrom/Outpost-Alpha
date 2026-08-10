extends Node3D

const PlanetSurfacePalette := preload("res://scripts/planet_surface_palette.gd")

const CHUNK_SIZE := 16
const GROUND_Y := 0.0
const SURFACE_TEXELS_PER_TILE := 12
const MAX_SURFACE_TEXTURE_SIZE := 1536

const TERRAIN_FOREST := 1
const TERRAIN_CRYSTAL := 2
const TERRAIN_ORE := 3
const TERRAIN_VENT := 4

var map_data: RefCounted
var material: ShaderMaterial
var biome_texture: ImageTexture
var ecology_texture: ImageTexture
var geology_texture: ImageTexture
var crystal_glow_texture: ImageTexture
var baked_albedo_texture: ImageTexture
var baked_texture_size := Vector2i.ZERO
var last_surface_bake_usec := 0
var grid_visible := true
var rebuild_requests := 0
var last_cells_processed := 0
var last_rebuild_usec := 0
var last_reason := ""


func _ready() -> void:
	name = "Terrain3DLayer"
	_ensure_material()


func set_map_data(next_map_data: RefCounted) -> void:
	map_data = next_map_data
	_rebuild("set_map_data")


func set_grid_visible(next_grid_visible: bool) -> void:
	if grid_visible == next_grid_visible:
		return
	grid_visible = next_grid_visible
	_ensure_material()
	material.set_shader_parameter("show_grid", grid_visible)


func get_diagnostics() -> Dictionary:
	return {
		"draw_calls": get_child_count(),
		"redraw_requests": rebuild_requests,
		"last_draw_usec": 0,
		"last_cells": last_cells_processed,
		"last_bake_usec": last_rebuild_usec,
		"surface_bake_usec": last_surface_bake_usec,
		"baked_texture_size": baked_texture_size,
		"last_reason": last_reason,
		"chunks": get_child_count(),
	}


func _rebuild(reason: String) -> void:
	var started := Time.get_ticks_usec()
	rebuild_requests += 1
	last_reason = reason
	last_cells_processed = 0

	for child in get_children():
		child.queue_free()

	if map_data == null:
		last_rebuild_usec = Time.get_ticks_usec() - started
		return

	_ensure_material()
	var field_images := _build_field_textures()
	_bake_surface_textures(field_images)
	material.set_shader_parameter("baked_albedo_map", baked_albedo_texture)
	material.set_shader_parameter("crystal_glow_map", crystal_glow_texture)
	material.set_shader_parameter("map_size", Vector2(map_data.size))
	material.set_shader_parameter("show_grid", grid_visible)

	var chunk_count := Vector2i(
		ceili(float(map_data.size.x) / float(CHUNK_SIZE)),
		ceili(float(map_data.size.y) / float(CHUNK_SIZE))
	)
	for chunk_y in chunk_count.y:
		for chunk_x in chunk_count.x:
			var chunk_coord := Vector2i(chunk_x, chunk_y)
			var instance := MeshInstance3D.new()
			instance.name = "GroundChunk_%d_%d" % [chunk_x, chunk_y]
			instance.mesh = _build_chunk_mesh(chunk_coord)
			instance.material_override = material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)

	last_cells_processed = map_data.size.x * map_data.size.y
	last_rebuild_usec = Time.get_ticks_usec() - started


func _build_field_textures() -> Dictionary:
	var biome_image := Image.create(map_data.size.x, map_data.size.y, false, Image.FORMAT_RGBA8)
	var ecology_image := Image.create(map_data.size.x, map_data.size.y, false, Image.FORMAT_RGBA8)
	var geology_image := Image.create(map_data.size.x, map_data.size.y, false, Image.FORMAT_RGBA8)
	for y in map_data.size.y:
		for x in map_data.size.x:
			var tile := Vector2i(x, y)
			var terrain_id: int = map_data.get_terrain(tile)
			biome_image.set_pixel(x, y, Color(
				1.0 if terrain_id == TERRAIN_FOREST else 0.0,
				1.0 if terrain_id == TERRAIN_CRYSTAL else 0.0,
				1.0 if terrain_id == TERRAIN_ORE else 0.0,
				1.0 if terrain_id == TERRAIN_VENT else 0.0
			))
			ecology_image.set_pixel(x, y, Color(
				map_data.get_moisture(tile),
				map_data.get_radiation(tile),
				map_data.get_mineral_content(tile),
				1.0
			))
			geology_image.set_pixel(x, y, Color(
				map_data.get_mountain_edge_weight(tile),
				map_data.get_dustiness(tile),
				map_data.get_surface_age(tile),
				map_data.get_rockiness(tile)
			))
	biome_texture = ImageTexture.create_from_image(biome_image)
	ecology_texture = ImageTexture.create_from_image(ecology_image)
	geology_texture = ImageTexture.create_from_image(geology_image)
	crystal_glow_texture = ImageTexture.create_from_image(_build_crystal_glow_image(biome_image))
	return {
		"biome": biome_image,
		"ecology": ecology_image,
		"geology": geology_image,
	}


func _build_crystal_glow_image(biome_image: Image) -> Image:
	var glow_image := Image.create(map_data.size.x, map_data.size.y, false, Image.FORMAT_RGBA8)
	const GLOW_RADIUS := 3
	const GLOW_DISTANCE := 2.75
	for y in map_data.size.y:
		for x in map_data.size.x:
			var glow_strength := 0.0
			for offset_y in range(-GLOW_RADIUS, GLOW_RADIUS + 1):
				for offset_x in range(-GLOW_RADIUS, GLOW_RADIUS + 1):
					var source := Vector2i(x + offset_x, y + offset_y)
					if not map_data.is_inside(source) or biome_image.get_pixelv(source).g < 0.5:
						continue
					var distance := Vector2(float(offset_x), float(offset_y)).length()
					if distance > GLOW_DISTANCE:
						continue
					var candidate := 1.0 - smoothstep(0.0, GLOW_DISTANCE, distance)
					glow_strength = maxf(glow_strength, candidate)
			glow_image.set_pixel(x, y, Color(glow_strength, glow_strength, glow_strength, 1.0))
	return glow_image


func _bake_surface_textures(field_images: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	baked_texture_size = Vector2i(
		mini(map_data.size.x * SURFACE_TEXELS_PER_TILE, MAX_SURFACE_TEXTURE_SIZE),
		mini(map_data.size.y * SURFACE_TEXELS_PER_TILE, MAX_SURFACE_TEXTURE_SIZE)
	)
	var biome_image := _resized_field_image(field_images["biome"], baked_texture_size)
	var ecology_image := _resized_field_image(field_images["ecology"], baked_texture_size)
	var geology_image := _resized_field_image(field_images["geology"], baked_texture_size)
	var macro_image := _baked_noise_image(baked_texture_size, int(map_data.seed) + 3109, 0.030, 5, 0.54, true)
	var meso_image := _baked_noise_image(baked_texture_size, int(map_data.seed) + 3251, 0.145, 5, 0.52, true)
	var erosion_image := _baked_noise_image(baked_texture_size, int(map_data.seed) + 3319, 0.075, 4, 0.50, true)
	var detail_image := _baked_noise_image(baked_texture_size, int(map_data.seed) + 3391, 0.82, 4, 0.48, false)
	var grain_image := _baked_noise_image(baked_texture_size, int(map_data.seed) + 3499, 4.50, 2, 0.44, false)
	var cellular_image := _baked_cellular_image(baked_texture_size, int(map_data.seed) + 3557, 0.36)

	var pixel_count := baked_texture_size.x * baked_texture_size.y
	var base_colors := PackedColorArray()
	base_colors.resize(pixel_count)
	var baked_heights := PackedFloat32Array()
	baked_heights.resize(pixel_count)
	var albedo_image := Image.create(baked_texture_size.x, baked_texture_size.y, false, Image.FORMAT_RGBA8)

	var world_per_pixel := Vector2(
		float(map_data.size.x) / float(baked_texture_size.x),
		float(map_data.size.y) / float(baked_texture_size.y)
	)
	var wind_direction := Vector2(0.93, 0.37).normalized()
	var wind_normal := Vector2(-wind_direction.y, wind_direction.x)
	for pixel_y in baked_texture_size.y:
		for pixel_x in baked_texture_size.x:
			var pixel := Vector2i(pixel_x, pixel_y)
			var index := pixel_y * baked_texture_size.x + pixel_x
			var world_point := Vector2(
				(float(pixel_x) + 0.5) * world_per_pixel.x - 0.5,
				(float(pixel_y) + 0.5) * world_per_pixel.y - 0.5
			)
			var biome := biome_image.get_pixelv(pixel)
			var ecology := ecology_image.get_pixelv(pixel)
			var geology := geology_image.get_pixelv(pixel)
			var macro_noise := macro_image.get_pixelv(pixel).r
			var meso_noise := meso_image.get_pixelv(pixel).r
			var erosion_noise := erosion_image.get_pixelv(pixel).r
			var detail_noise := detail_image.get_pixelv(pixel).r
			var grain_noise := grain_image.get_pixelv(pixel).r
			var cellular_noise := cellular_image.get_pixelv(pixel).r
			var neighboring_meso := meso_image.get_pixel(mini(pixel_x + 3, baked_texture_size.x - 1), mini(pixel_y + 2, baked_texture_size.y - 1)).r
			var neighboring_cell := cellular_image.get_pixel(mini(pixel_x + 2, baked_texture_size.x - 1), mini(pixel_y + 2, baked_texture_size.y - 1)).r

			var mountain_edge := geology.r
			var dustiness := geology.g
			var surface_age := geology.b
			var rockiness := geology.a
			var colony_distance := world_point.distance_to(Vector2(map_data.start_tile))
			var wilderness := smoothstep(float(map_data.build_radius) * 0.78, float(map_data.build_radius) + 12.0, colony_distance)
			var buildable_calm := 1.0 - smoothstep(float(map_data.build_radius) * 0.68, float(map_data.build_radius) + 7.0, colony_distance)

			var wind_phase := world_point.dot(wind_normal) * 0.54 + (macro_noise - 0.5) * 5.2
			var wind_fold := pow(0.5 + 0.5 * sin(wind_phase), 5.0)
			var wind_streak := 0.5 + 0.5 * sin(world_point.dot(wind_direction) * 0.115 + (macro_noise - 0.5) * 4.4)
			var erosion_ridge := pow(1.0 - absf(sin(world_point.dot(wind_normal) * 0.92 + (erosion_noise - 0.5) * 6.2)), 3.0)
			var height_value := (macro_noise - 0.5) * 0.62 + wind_fold * 0.075 + (detail_noise - 0.5) * 0.085
			var crack_delta := absf(meso_noise - neighboring_meso)
			var cracks := 1.0 - smoothstep(0.018, 0.075, crack_delta)
			var plate_edge := smoothstep(0.055, 0.22, absf(cellular_noise - neighboring_cell))
			var gravel_cluster := smoothstep(0.63, 0.86, cellular_noise * 0.56 + detail_noise * 0.44)
			var grit := smoothstep(0.70, 0.86, grain_noise * 0.58 + detail_noise * 0.42)
			var grain_pebble := smoothstep(0.72, 0.87, grain_noise) * lerpf(0.30, 1.0, rockiness)

			var height_ramp := smoothstep(-0.24, 0.30, height_value)
			var weathered_patch := smoothstep(0.52, 0.73, meso_noise) * lerpf(0.16, 1.0, wilderness)
			var dust_filter := dustiness * smoothstep(0.38, 0.72, macro_noise - height_value * 0.35) * (1.0 - mountain_edge * 0.76)
			var bedrock_filter := rockiness * smoothstep(0.42, 0.70, meso_noise + height_value * 0.28 + gravel_cluster * 0.10)
			var wind_filter := wilderness * smoothstep(0.45, 0.70, wind_streak) * (0.30 + surface_age * 0.70)
			var fracture_filter := cracks * surface_age * lerpf(0.28, 0.82, wilderness)
			var scree_filter := smoothstep(0.035, 0.82, mountain_edge) * lerpf(0.72, 1.0, rockiness)
			var veins := smoothstep(0.64, 0.84, meso_noise + ecology.b * 0.18)
			var mineral_filter := ecology.b * veins * lerpf(0.22, 1.0, wilderness)

			var dust_material := PlanetSurfacePalette.WEATHERED_DUST.lerp(PlanetSurfacePalette.PRESSURE_DUST, clampf(0.22 + macro_noise * 0.46, 0.0, 1.0))
			dust_material = dust_material.lerp(PlanetSurfacePalette.PALE_REGOLITH, wind_filter * 0.16)
			dust_material = _scaled_color(dust_material, 1.0 + (detail_noise - 0.5) * lerpf(0.035, 0.075, wilderness))

			var crust_material := PlanetSurfacePalette.COMPACT_BEDROCK.lerp(PlanetSurfacePalette.ERODED_STONE, clampf(0.16 + height_ramp * 0.62, 0.0, 1.0))
			crust_material = crust_material.lerp(PlanetSurfacePalette.BEDROCK_MID, bedrock_filter * 0.30)
			crust_material = crust_material.lerp(PlanetSurfacePalette.VOLCANIC_CRUST, fracture_filter * 0.14)
			crust_material = _scaled_color(crust_material, 1.0 + (detail_noise - 0.5) * lerpf(0.07, 0.15, wilderness))

			var scree_material := PlanetSurfacePalette.ROCKY_SCREE.lerp(PlanetSurfacePalette.BEDROCK_MID, clampf(0.18 + detail_noise * 0.20, 0.0, 1.0))
			scree_material = scree_material.lerp(PlanetSurfacePalette.ERODED_STONE, rockiness * 0.20 + weathered_patch * 0.12)
			var mineral_material := crust_material.lerp(PlanetSurfacePalette.MINERAL_WARM, 0.30 + macro_noise * 0.14)

			var dust_weight := (0.26 + dust_filter * 1.12 + (1.0 - rockiness) * 0.14) * (1.0 - scree_filter * 0.76)
			var crust_weight := (0.68 + bedrock_filter * 0.94 + weathered_patch * 0.24 + buildable_calm * 0.24) * (1.0 - scree_filter * 0.38)
			var scree_weight := scree_filter * 1.58
			var total_weight := maxf(dust_weight + crust_weight + scree_weight, 0.0001)
			dust_weight /= total_weight
			crust_weight /= total_weight
			scree_weight /= total_weight
			var ground := dust_material * dust_weight + crust_material * crust_weight + scree_material * scree_weight
			ground = ground.lerp(mineral_material, mineral_filter * 0.16)

			var fungal_crust := PlanetSurfacePalette.FUNGAL_CRUST_DARK.lerp(PlanetSurfacePalette.FUNGAL_CRUST_LIGHT, macro_noise * 0.65 + detail_noise * 0.20)
			var crystal_ground := ground.lerp(PlanetSurfacePalette.CRYSTAL, 0.42 + macro_noise * 0.16)
			var ore_ground := ground.lerp(PlanetSurfacePalette.MINERAL_WARM, 0.32 + veins * 0.22)
			var vent_ground := ground.lerp(PlanetSurfacePalette.VENT_MINERAL, 0.32 + detail_noise * 0.12)
			ground = ground.lerp(fungal_crust, biome.r * lerpf(0.22, 0.56, wilderness))
			ground = ground.lerp(crystal_ground, biome.g * 0.66)
			ground = ground.lerp(ore_ground, biome.b * 0.64)
			ground = ground.lerp(vent_ground, biome.a * 0.62)
			ground = ground.lerp(PlanetSurfacePalette.MINERAL_WARM, mineral_filter * 0.08)
			# High-resolution passes are baked into the final color. They never run in the
			# runtime shader, but preserve crisp geological information at gameplay zoom.
			var micro_contrast := lerpf(0.075, 0.135, wilderness) * lerpf(0.80, 1.0, rockiness)
			ground = _scaled_color(ground, 1.0 + (grain_noise - 0.5) * micro_contrast)
			ground = ground.lerp(PlanetSurfacePalette.VOLCANIC_CRUST, plate_edge * surface_age * lerpf(0.12, 0.22, wilderness))
			ground = ground.lerp(PlanetSurfacePalette.ERODED_STONE, grit * gravel_cluster * lerpf(0.08, 0.20, rockiness))
			ground = ground.lerp(PlanetSurfacePalette.BEDROCK_HIGH, grain_pebble * lerpf(0.035, 0.11, wilderness))
			ground = ground.lerp(PlanetSurfacePalette.PRESSURE_DUST, erosion_ridge * dust_weight * lerpf(0.04, 0.11, wilderness))

			var relief_strength := lerpf(0.34, 1.0, wilderness) * lerpf(0.72, 1.18, rockiness)
			var baked_height := height_value
			baked_height += (detail_noise - 0.5) * (crust_weight * 0.045 + scree_weight * 0.080)
			baked_height += (grain_noise - 0.5) * lerpf(0.010, 0.024, rockiness)
			baked_height += (wind_streak - 0.5) * dust_weight * 0.030
			baked_height += erosion_ridge * dust_weight * 0.018
			baked_height += grit * gravel_cluster * scree_weight * 0.022
			baked_height -= fracture_filter * crust_weight * 0.018
			baked_height -= plate_edge * surface_age * 0.026
			baked_heights[index] = baked_height * relief_strength
			base_colors[index] = ground

	var baked_light_direction := Vector3(-0.44, 0.82, -0.37).normalized()
	for pixel_y in baked_texture_size.y:
		for pixel_x in baked_texture_size.x:
			var index := pixel_y * baked_texture_size.x + pixel_x
			var left_index := pixel_y * baked_texture_size.x + maxi(pixel_x - 1, 0)
			var right_index := pixel_y * baked_texture_size.x + mini(pixel_x + 1, baked_texture_size.x - 1)
			var up_index := maxi(pixel_y - 1, 0) * baked_texture_size.x + pixel_x
			var down_index := mini(pixel_y + 1, baked_texture_size.y - 1) * baked_texture_size.x + pixel_x
			var gradient_x := (baked_heights[right_index] - baked_heights[left_index]) / maxf(world_per_pixel.x * 2.0, 0.0001)
			var gradient_z := (baked_heights[down_index] - baked_heights[up_index]) / maxf(world_per_pixel.y * 2.0, 0.0001)
			var baked_normal := Vector3(-gradient_x * 0.72, 1.0, -gradient_z * 0.72).normalized()
			var diffuse := maxf(baked_normal.dot(baked_light_direction), 0.0)
			var baked_shading := lerpf(0.78, 1.08, diffuse)
			albedo_image.set_pixel(pixel_x, pixel_y, _scaled_color(base_colors[index], baked_shading))

	baked_albedo_texture = ImageTexture.create_from_image(albedo_image)
	last_surface_bake_usec = Time.get_ticks_usec() - started


func _resized_field_image(source: Image, target_size: Vector2i) -> Image:
	var result := source.duplicate()
	result.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
	return result


func _baked_noise_image(size: Vector2i, seed: int, world_frequency: float, octaves: int, gain: float, warped: bool) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = world_frequency * float(map_data.size.x) / float(size.x)
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.03
	noise.fractal_gain = gain
	noise.domain_warp_enabled = warped
	if warped:
		noise.domain_warp_amplitude = float(SURFACE_TEXELS_PER_TILE) * 1.8
		noise.domain_warp_frequency = noise.frequency * 0.72
		noise.domain_warp_fractal_octaves = 3
	return noise.get_image(size.x, size.y, false, false, true)


func _baked_cellular_image(size: Vector2i, seed: int, world_frequency: float) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = world_frequency * float(map_data.size.x) / float(size.x)
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = float(SURFACE_TEXELS_PER_TILE) * 1.25
	noise.domain_warp_frequency = noise.frequency * 0.58
	noise.domain_warp_fractal_octaves = 2
	return noise.get_image(size.x, size.y, false, false, true)


func _scaled_color(color: Color, scale: float) -> Color:
	return Color(
		clampf(color.r * scale, 0.0, 1.0),
		clampf(color.g * scale, 0.0, 1.0),
		clampf(color.b * scale, 0.0, 1.0),
		1.0
	)


func _build_chunk_mesh(chunk_coord: Vector2i) -> ArrayMesh:
	var start := chunk_coord * CHUNK_SIZE
	var end := Vector2i(
		mini(start.x + CHUNK_SIZE, map_data.size.x),
		mini(start.y + CHUNK_SIZE, map_data.size.y)
	)
	var min_x := float(start.x) - 0.5
	var min_z := float(start.y) - 0.5
	var max_x := float(end.x) - 0.5
	var max_z := float(end.y) - 0.5
	var vertices := PackedVector3Array([
		Vector3(min_x, GROUND_Y, min_z),
		Vector3(max_x, GROUND_Y, min_z),
		Vector3(max_x, GROUND_Y, max_z),
		Vector3(min_x, GROUND_Y, max_z),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var indices := PackedInt32Array([0, 2, 1, 0, 3, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _ensure_material() -> void:
	if material != null:
		return
	var shader := Shader.new()
	shader.code = _terrain_shader_code()
	material = ShaderMaterial.new()
	material.shader = shader


func _terrain_shader_code() -> String:
	return """
shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;

uniform sampler2D baked_albedo_map : filter_linear, repeat_disable;
uniform sampler2D crystal_glow_map : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(96.0);
uniform bool show_grid = true;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 map_uv = clamp((world_position.xz + vec2(0.5)) / map_size, vec2(0.0001), vec2(0.9999));
	vec3 ground = texture(baked_albedo_map, map_uv).rgb;
	float crystal_glow = texture(crystal_glow_map, map_uv).r;
	vec3 crystal_energy = vec3(0.38, 0.018, 0.72);

	if (show_grid) {
		vec2 edge_distance = abs(fract(world_position.xz + vec2(0.5)) - vec2(0.5));
		float grid_line = smoothstep(0.465, 0.495, max(edge_distance.x, edge_distance.y));
		ground = mix(ground, ground * 0.78, grid_line * 0.18);
	}

	ALBEDO = mix(ground, crystal_energy, crystal_glow * 0.025);
	// The baked texture supplies the finished surface appearance. This constant fill only keeps
	// realtime cast shadows readable; it performs no procedural surface or normal calculation.
	float crystal_pulse = 0.96 + sin(TIME * 0.48 + world_position.x * 0.17 + world_position.z * 0.13) * 0.04;
	EMISSION = ground * 0.42 + crystal_energy * crystal_glow * 0.18 * crystal_pulse;
}

void light() {
	// One cheap shadow-receiver pass. With the configured sun energy this restores the baked
	// color in direct light and darkens it only by the engine's existing shadow attenuation.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * 0.52;
}
"""
