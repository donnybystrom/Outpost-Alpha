extends RefCounted

const DEFAULT_MAX_VARIANTS := 32

var material: StandardMaterial3D


func load_tree_meshes(obj_path: String, max_variants := DEFAULT_MAX_VARIANTS) -> Array[ArrayMesh]:
	var meshes: Array[ArrayMesh] = []
	var file := FileAccess.open(obj_path, FileAccess.READ)
	if file == null:
		push_warning("Could not open tree collection OBJ: %s" % obj_path)
		return meshes

	var positions: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var normals: Array[Vector3] = []
	var current_faces: Array[PackedStringArray] = []
	var has_object := false

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("o "):
			if has_object and not current_faces.is_empty():
				_add_mesh_from_faces(meshes, positions, uvs, normals, current_faces)
				current_faces.clear()
				if meshes.size() >= max_variants:
					break
			has_object = true
		elif line.begins_with("v "):
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif line.begins_with("vt "):
			var parts := line.split(" ", false)
			if parts.size() >= 3:
				uvs.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
		elif line.begins_with("vn "):
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()).normalized())
		elif line.begins_with("f ") and has_object:
			var face := line.split(" ", false)
			if face.size() >= 4:
				face.remove_at(0)
				current_faces.append(face)

	if meshes.size() < max_variants and not current_faces.is_empty():
		_add_mesh_from_faces(meshes, positions, uvs, normals, current_faces)

	return meshes


func _add_mesh_from_faces(meshes: Array[ArrayMesh], positions: Array[Vector3], uvs: Array[Vector2], normals: Array[Vector3], faces: Array[PackedStringArray]) -> void:
	var used_vertex_indices: Array[int] = []
	for face in faces:
		for token in face:
			var vertex_index := _obj_index_to_array_index(_face_vertex_index(token), positions.size())
			if vertex_index >= 0 and not used_vertex_indices.has(vertex_index):
				used_vertex_indices.append(vertex_index)

	if used_vertex_indices.is_empty():
		return

	var min_point: Vector3 = positions[used_vertex_indices[0]]
	var max_point: Vector3 = min_point
	for vertex_index in used_vertex_indices:
		var point: Vector3 = positions[vertex_index]
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		min_point.z = minf(min_point.z, point.z)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)
		max_point.z = maxf(max_point.z, point.z)

	var center := Vector3(
		(min_point.x + max_point.x) * 0.5,
		min_point.y,
		(min_point.z + max_point.z) * 0.5
	)
	var mesh_vertices := PackedVector3Array()
	var mesh_uvs := PackedVector2Array()
	var mesh_normals := PackedVector3Array()

	for face in faces:
		for index in range(1, face.size() - 1):
			var triangle_start := mesh_vertices.size()
			_append_face_vertex(mesh_vertices, mesh_uvs, mesh_normals, positions, uvs, normals, face[0], center)
			_append_face_vertex(mesh_vertices, mesh_uvs, mesh_normals, positions, uvs, normals, face[index], center)
			_append_face_vertex(mesh_vertices, mesh_uvs, mesh_normals, positions, uvs, normals, face[index + 1], center)
			if mesh_vertices.size() == triangle_start + 3:
				_set_triangle_normal(mesh_vertices, mesh_normals, triangle_start)

	if mesh_vertices.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes.append(mesh)


func _append_face_vertex(mesh_vertices: PackedVector3Array, mesh_uvs: PackedVector2Array, mesh_normals: PackedVector3Array, positions: Array[Vector3], uvs: Array[Vector2], normals: Array[Vector3], token: String, center: Vector3) -> void:
	var position_index := _obj_index_to_array_index(_face_vertex_index(token), positions.size())
	if position_index < 0:
		return
	mesh_vertices.append(positions[position_index] - center)

	var uv_index := _obj_index_to_array_index(_face_uv_index(token), uvs.size())
	if uv_index >= 0:
		mesh_uvs.append(uvs[uv_index])
	else:
		mesh_uvs.append(Vector2.ZERO)

	var normal_index := _obj_index_to_array_index(_face_normal_index(token), normals.size())
	if normal_index >= 0:
		mesh_normals.append(normals[normal_index])
	else:
		mesh_normals.append(Vector3.UP)


func _set_triangle_normal(mesh_vertices: PackedVector3Array, mesh_normals: PackedVector3Array, triangle_start: int) -> void:
	var point_a := mesh_vertices[triangle_start]
	var point_b := mesh_vertices[triangle_start + 1]
	var point_c := mesh_vertices[triangle_start + 2]
	var normal := (point_b - point_a).cross(point_c - point_a).normalized()
	if normal.length_squared() <= 0.0001:
		normal = Vector3.UP
	if normal.y < 0.0:
		normal = -normal
	for offset in range(3):
		mesh_normals[triangle_start + offset] = normal


func _face_vertex_index(token: String) -> int:
	var parts := token.split("/")
	if parts.is_empty():
		return 0
	return parts[0].to_int()


func _face_uv_index(token: String) -> int:
	var parts := token.split("/")
	if parts.size() < 2 or parts[1].is_empty():
		return 0
	return parts[1].to_int()


func _face_normal_index(token: String) -> int:
	var parts := token.split("/")
	if parts.size() < 3 or parts[2].is_empty():
		return 0
	return parts[2].to_int()


func _obj_index_to_array_index(obj_index: int, array_size: int) -> int:
	if obj_index > 0:
		return obj_index - 1 if obj_index <= array_size else -1
	if obj_index < 0:
		var resolved := array_size + obj_index
		return resolved if resolved >= 0 and resolved < array_size else -1
	return -1
