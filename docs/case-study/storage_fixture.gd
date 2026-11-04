# Exercise the real serialization helpers in a disposable directory.
# Debug gameplay still bypasses disk persistence.
extends "res://scripts/chunk_store.gd"

func _get_path(coord: Vector3i) -> String:
	return "/private/tmp/megalophobia-case-study/delta_%d_%d_%d.dat" % [coord.x, coord.y, coord.z]
