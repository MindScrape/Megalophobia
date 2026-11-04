# Capture instrumentation only. Gameplay keeps using scripts/chunk.gd.
extends "res://scripts/chunk.gd"

var observations: Array[Dictionary] = []

func _apply_mesh_data(mesh: ArrayMesh, shape: Shape3D, on_complete: Callable,
		new_voxels: PackedInt32Array = PackedInt32Array(), request_revision: int = -1) -> void:
	observations.append({
		"request_revision": request_revision,
		"current_revision": _voxel_revision,
		"rejected": request_revision != -1 and request_revision != _voxel_revision,
	})
	super._apply_mesh_data(mesh, shape, on_complete, new_voxels, request_revision)
