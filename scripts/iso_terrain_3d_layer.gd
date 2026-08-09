extends Node3D

const PlanetSurfacePalette := preload("res://scripts/planet_surface_palette.gd")

const CHUNK_SIZE := 16
const GROUND_Y := 0.0

const TERRAIN_FOREST := 1
const TERRAIN_CRYSTAL := 2
const TERRAIN_ORE := 3
const TERRAIN_VENT := 4

var map_data: RefCounted
var material: ShaderMaterial
var biome_texture: ImageTexture
var ecology_texture: ImageTexture
var geology_texture: ImageTexture
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
	_build_field_textures()
	material.set_shader_parameter("biome_map", biome_texture)
	material.set_shader_parameter("ecology_map", ecology_texture)
	material.set_shader_parameter("geology_map", geology_texture)
	material.set_shader_parameter("map_size", Vector2(map_data.size))
	material.set_shader_parameter("colony_center", Vector2(map_data.start_tile))
	material.set_shader_parameter("build_radius", float(map_data.build_radius))
	material.set_shader_parameter("world_seed", float(map_data.seed % 100000))
	material.set_shader_parameter("show_grid", grid_visible)
	material.set_shader_parameter("bedrock_low", PlanetSurfacePalette.BEDROCK_LOW)
	material.set_shader_parameter("bedrock_mid", PlanetSurfacePalette.BEDROCK_MID)
	material.set_shader_parameter("weathered_dust", PlanetSurfacePalette.WEATHERED_DUST)
	material.set_shader_parameter("pale_regolith", PlanetSurfacePalette.PALE_REGOLITH)
	material.set_shader_parameter("rocky_scree", PlanetSurfacePalette.ROCKY_SCREE)
	material.set_shader_parameter("volcanic_crust", PlanetSurfacePalette.VOLCANIC_CRUST)
	material.set_shader_parameter("mineral_warm", PlanetSurfacePalette.MINERAL_WARM)
	material.set_shader_parameter("fungal_dark", PlanetSurfacePalette.FUNGAL_CRUST_DARK)
	material.set_shader_parameter("fungal_light", PlanetSurfacePalette.FUNGAL_CRUST_LIGHT)
	material.set_shader_parameter("crystal_color", PlanetSurfacePalette.CRYSTAL)
	material.set_shader_parameter("vent_color", PlanetSurfacePalette.VENT_MINERAL)

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


func _build_field_textures() -> void:
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
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D ecology_map : filter_linear, repeat_disable;
uniform sampler2D geology_map : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(96.0);
uniform vec2 colony_center = vec2(48.0);
uniform float build_radius = 25.0;
uniform float world_seed = 1.0;
uniform bool show_grid = true;
uniform vec4 bedrock_low = vec4(0.216, 0.212, 0.196, 1.0);
uniform vec4 bedrock_mid = vec4(0.369, 0.361, 0.337, 1.0);
uniform vec4 weathered_dust = vec4(0.298, 0.286, 0.259, 1.0);
uniform vec4 pale_regolith = vec4(0.439, 0.408, 0.357, 1.0);
uniform vec4 rocky_scree = vec4(0.282, 0.275, 0.255, 1.0);
uniform vec4 volcanic_crust = vec4(0.176, 0.180, 0.169, 1.0);
uniform vec4 mineral_warm = vec4(0.435, 0.325, 0.216, 1.0);
uniform vec4 fungal_dark = vec4(0.267, 0.267, 0.192, 1.0);
uniform vec4 fungal_light = vec4(0.424, 0.400, 0.263, 1.0);
uniform vec4 crystal_color = vec4(0.537, 0.322, 0.600, 1.0);
uniform vec4 vent_color = vec4(0.239, 0.412, 0.404, 1.0);

varying vec3 world_position;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32 + world_seed * 0.0001);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

vec2 crater_pattern(vec2 world_point) {
	vec2 crater_space = world_point * 0.052;
	vec2 cell = floor(crater_space);
	vec2 local = fract(crater_space);
	vec2 center = vec2(
		0.22 + hash21(cell + vec2(13.0, 7.0)) * 0.56,
		0.22 + hash21(cell + vec2(31.0, 19.0)) * 0.56
	);
	float radius = mix(0.10, 0.25, hash21(cell + vec2(47.0, 3.0)));
	float radial_distance = distance(local, center);
	float rim = 1.0 - smoothstep(0.025, 0.060, abs(radial_distance - radius));
	float basin = 1.0 - smoothstep(radius * 0.22, radius, radial_distance);
	return vec2(rim, basin);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 map_uv = clamp((world_position.xz + vec2(0.5)) / map_size, vec2(0.0001), vec2(0.9999));
	vec4 biome = texture(biome_map, map_uv);
	vec3 ecology = texture(ecology_map, map_uv).rgb;
	vec4 geology = texture(geology_map, map_uv);
	float mountain_edge = geology.r;
	float dustiness = geology.g;
	float surface_age = geology.b;
	float rockiness = geology.a;
	float colony_distance = distance(world_position.xz, colony_center);
	float wilderness = smoothstep(build_radius * 0.78, build_radius + 12.0, colony_distance);
	float broad = value_noise(world_position.xz * 0.085 + vec2(world_seed * 0.013));
	float detail = value_noise(world_position.xz * 0.62 - vec2(world_seed * 0.021));
	float veins = smoothstep(0.66, 0.86, value_noise(world_position.xz * 0.19 + vec2(37.0)) + ecology.b * 0.18);
	float weathered_patch = smoothstep(0.56, 0.76, value_noise(world_position.xz * 0.24 + vec2(19.0))) * mix(0.18, 1.0, wilderness);
	float macro_zone = value_noise(world_position.xz * 0.024 + vec2(world_seed * 0.003));
	vec2 wind_direction = normalize(vec2(0.93, 0.37));
	vec2 wind_normal = vec2(-wind_direction.y, wind_direction.x);
	float wind_streak = value_noise(vec2(dot(world_position.xz, wind_direction) * 0.075, dot(world_position.xz, wind_normal) * 0.014));
	vec2 crater = crater_pattern(world_position.xz + vec2(world_seed * 0.017));
	float crack_delta = abs(
		value_noise(world_position.xz * 0.37 + vec2(11.0))
		- value_noise(world_position.xz * 0.37 + vec2(11.19, 10.83))
	);
	float cracks = 1.0 - smoothstep(0.018, 0.060, crack_delta);

	// Buildable ground stays calm and legible; wilderness receives the stronger geology.
	vec3 basalt = mix(bedrock_low.rgb, bedrock_mid.rgb, 0.30 + broad * 0.34);
	basalt = mix(basalt, weathered_dust.rgb, 0.34 + weathered_patch * 0.22);
	float contrast = mix(0.08, 0.20, wilderness);
	basalt *= 1.0 + (detail - 0.5) * contrast;
	vec3 regolith = mix(weathered_dust.rgb, pale_regolith.rgb, 0.25 + wind_streak * 0.38);
	vec3 scree = mix(rocky_scree.rgb, bedrock_mid.rgb, detail * 0.32 + rockiness * 0.26);
	float dust_weight = dustiness * mix(0.18, 0.48, macro_zone) * (1.0 - mountain_edge * 0.82);
	float volcanic_weight = surface_age * smoothstep(0.58, 0.78, macro_zone) * wilderness * 0.24;
	basalt = mix(basalt, regolith, dust_weight);
	basalt = mix(basalt, volcanic_crust.rgb, volcanic_weight);
	basalt = mix(basalt, bedrock_mid.rgb * 1.04, crater.x * surface_age * wilderness * 0.16);
	basalt = mix(basalt, volcanic_crust.rgb, crater.y * surface_age * wilderness * 0.10);
	basalt = mix(basalt, volcanic_crust.rgb * 0.78, cracks * surface_age * wilderness * 0.055);

	vec3 fungal_crust = mix(fungal_dark.rgb, fungal_light.rgb, broad * 0.65 + detail * 0.20);
	vec3 crystal_ground = mix(basalt, crystal_color.rgb, 0.42 + broad * 0.16);
	vec3 ore_ground = mix(basalt, mineral_warm.rgb, 0.32 + veins * 0.22);
	vec3 vent_ground = mix(basalt, vent_color.rgb, 0.32 + detail * 0.12);

	vec3 ground = basalt;
	ground = mix(ground, fungal_crust, biome.r * mix(0.22, 0.56, wilderness));
	ground = mix(ground, crystal_ground, biome.g * 0.66);
	ground = mix(ground, ore_ground, biome.b * 0.64);
	ground = mix(ground, vent_ground, biome.a * 0.62);
	ground = mix(ground, scree, mountain_edge * 0.84);
	ground = mix(ground, mineral_warm.rgb, veins * ecology.b * wilderness * 0.10);
	ground = mix(ground, mineral_warm.rgb, smoothstep(0.66, 0.83, wind_streak + ecology.b * 0.22) * ecology.b * wilderness * 0.075);
	ground = mix(ground, mineral_warm.rgb * 0.72, ecology.g * wilderness * 0.035);

	if (show_grid) {
		vec2 edge_distance = abs(fract(world_position.xz + vec2(0.5)) - vec2(0.5));
		float grid_line = smoothstep(0.465, 0.495, max(edge_distance.x, edge_distance.y));
		ground = mix(ground, ground * 0.78, grid_line * 0.18);
	}

	ALBEDO = ground;
	// A low base fill preserves readability inside cast shadows. The light pass below supplies
	// the brighter, shadow-attenuated portion instead of baking all brightness into emission.
	EMISSION = ground * mix(0.48, 0.28, wilderness);
	ROUGHNESS = clamp(0.91 + dust_weight * 0.075 + mountain_edge * 0.045 - ecology.b * veins * wilderness * 0.12, 0.72, 1.0);
	SPECULAR = 0.16;
}

void light() {
	// Wrapped diffuse is deliberate: the planet's low sun still illuminates a horizontal RTS board,
	// while ATTENUATION restores silhouettes from units, buildings and mountain massifs.
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float wrapped_diffuse = mix(0.34, 1.0, facing);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * wrapped_diffuse * 1.45;
}
"""
