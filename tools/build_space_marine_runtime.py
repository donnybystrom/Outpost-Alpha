"""Build the animated Space Marine runtime GLB with the Hyper3D base UV layout.

Run with:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/build_space_marine_runtime.py

The source GLB is copied byte-for-byte apart from its TEXCOORD_0 accessor. This
is intentional: re-exporting the rig through Blender changes Meshy's skeleton
coordinate system and breaks the otherwise working animation.
"""

from pathlib import Path
import json
import struct

import bpy


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BASE_OBJ = PROJECT_ROOT / "assets/3D/units/space_marine/base/base.obj"
ANIMATED_GLB = PROJECT_ROOT / "assets/3D/units/space_marine/Meshy_AI_Space_Marine_biped/Meshy_AI_Space_Marine_biped_Animation_Run_03_withSkin.glb"
OUTPUT_GLB = PROJECT_ROOT / "assets/3D/units/space_marine/runtime/space_marine_run_03.glb"


def only_mesh(label: str) -> bpy.types.Object:
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name != "Icosphere"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one {label} mesh, found {[obj.name for obj in meshes]}")
    return meshes[0]


def object_height(obj: bpy.types.Object) -> float:
    vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return max(point.z for point in vertices) - min(point.z for point in vertices)


def parse_glb(path: Path) -> tuple[bytearray, dict, int]:
    data = bytearray(path.read_bytes())
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total_length != len(data):
        raise RuntimeError(f"Invalid GLB header in {path}")

    cursor = 12
    document = None
    binary_offset = None
    while cursor < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, cursor)
        payload_offset = cursor + 8
        if chunk_type == 0x4E4F534A:  # JSON
            document = json.loads(bytes(data[payload_offset:payload_offset + chunk_length]))
        elif chunk_type == 0x004E4942:  # BIN
            binary_offset = payload_offset
        cursor = payload_offset + chunk_length

    if document is None or binary_offset is None:
        raise RuntimeError(f"GLB must contain JSON and BIN chunks: {path}")
    return data, document, binary_offset


def uv_accessor_info(document: dict, binary_offset: int) -> tuple[dict, int, int]:
    primitive = document["meshes"][0]["primitives"][0]
    accessor = document["accessors"][primitive["attributes"]["TEXCOORD_0"]]
    if accessor["componentType"] != 5126 or accessor["type"] != "VEC2" or accessor.get("sparse"):
        raise RuntimeError("Expected a dense float VEC2 TEXCOORD_0 accessor")
    view = document["bufferViews"][accessor["bufferView"]]
    stride = view.get("byteStride", 8)
    offset = binary_offset + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    return accessor, offset, stride


def mesh_uvs_by_vertex(mesh: bpy.types.Mesh) -> list[tuple[float, float]]:
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        raise RuntimeError("Mesh does not contain a UV map")

    result: list[tuple[float, float] | None] = [None] * len(mesh.vertices)
    for loop in mesh.loops:
        uv = tuple(uv_layer.data[loop.index].uv)
        previous = result[loop.vertex_index]
        if previous is not None and (abs(previous[0] - uv[0]) > 1e-5 or abs(previous[1] - uv[1]) > 1e-5):
            raise RuntimeError(
                f"Transferred UV seam needs a vertex split at vertex {loop.vertex_index}; "
                "the source GLB cannot be patched in place"
            )
        result[loop.vertex_index] = uv

    if any(uv is None for uv in result):
        raise RuntimeError("Some target vertices do not have UV coordinates")
    return result  # type: ignore[return-value]


glb_data, glb_document, glb_binary_offset = parse_glb(ANIMATED_GLB)
uv_accessor, uv_offset, uv_stride = uv_accessor_info(glb_document, glb_binary_offset)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(BASE_OBJ))
source_mesh = only_mesh("Hyper3D source")
source_mesh.name = "Hyper3D_UV_Source"

bpy.ops.import_scene.gltf(filepath=str(ANIMATED_GLB))
target_candidates = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name not in {source_mesh.name, "Icosphere"}]
if len(target_candidates) != 1:
    raise RuntimeError(f"Expected one Meshy target mesh, found {[obj.name for obj in target_candidates]}")
target_mesh = target_candidates[0]

if len(target_mesh.data.vertices) != uv_accessor["count"]:
    raise RuntimeError("Blender changed the GLB vertex ordering/count during import")

# Confirm that Blender vertex indices still correspond to the original GLB
# accessor before relying on those indices for the patched UV values.
original_blender_uvs = mesh_uvs_by_vertex(target_mesh.data)
for vertex_index, (u, v) in enumerate(original_blender_uvs):
    gltf_u, gltf_v = struct.unpack_from("<ff", glb_data, uv_offset + vertex_index * uv_stride)
    if abs(gltf_u - u) > 1e-5 or abs(gltf_v - (1.0 - v)) > 1e-5:
        raise RuntimeError(f"GLB/Blender UV vertex order differs at vertex {vertex_index}")

scale_ratio = object_height(target_mesh) / object_height(source_mesh)
source_mesh.scale = (scale_ratio, scale_ratio, scale_ratio)
bpy.context.view_layer.objects.active = source_mesh
source_mesh.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
source_mesh.select_set(False)

transfer = target_mesh.modifiers.new(name="Transfer Hyper3D UV", type="DATA_TRANSFER")
transfer.object = source_mesh
transfer.use_loop_data = True
transfer.data_types_loops = {"UV"}
transfer.loop_mapping = "POLYINTERP_NEAREST"
transfer.mix_mode = "REPLACE"
bpy.context.view_layer.objects.active = target_mesh
target_mesh.select_set(True)
bpy.ops.object.modifier_move_to_index(modifier=transfer.name, index=0)
bpy.ops.object.modifier_apply(modifier=transfer.name)
target_mesh.select_set(False)

transferred_uvs = mesh_uvs_by_vertex(target_mesh.data)
for vertex_index, (u, v) in enumerate(transferred_uvs):
    struct.pack_into("<ff", glb_data, uv_offset + vertex_index * uv_stride, u, 1.0 - v)

OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
OUTPUT_GLB.write_bytes(glb_data)

print(
    "Built Space Marine runtime GLB by patching TEXCOORD_0 only:",
    OUTPUT_GLB,
    "scale_ratio=",
    round(scale_ratio, 8),
    "vertices=",
    len(transferred_uvs),
)
