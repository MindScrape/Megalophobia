extends RefCounted
class_name ChunkStore

# user:// resolves to:
#   Windows: %APPDATA%\Godot\app_userdata\<project_name>\
#   macOS:   ~/Library/Application Support/Godot/app_userdata/<project_name>/
const SAVE_DIR = "user://chunks/"

var _cache: Dictionary = {}   # Vector3i -> Dictionary (voxel_index: int -> block_id: int)
var _dirty: Dictionary = {}   # Vector3i -> bool

func _init() -> void:
	if OS.is_debug_build():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func has_data(coord: Vector3i) -> bool:
	if OS.is_debug_build():
		return _cache.has(coord)
	return _cache.has(coord) or FileAccess.file_exists(_get_path(coord))


func get_delta(coord: Vector3i) -> Dictionary:
	if _cache.has(coord):
		return _cache[coord]
	if OS.is_debug_build():
		return {}
	return _load_from_disk(coord)


func record_edit(coord: Vector3i, voxel_idx: int, block_id: int) -> void:
	if not _cache.has(coord):
		_cache[coord] = {}
	_cache[coord][voxel_idx] = block_id
	_dirty[coord] = true


func flush(coord: Vector3i) -> void:
	if OS.is_debug_build() or not _dirty.get(coord, false):
		return
	_save_to_disk(coord, _cache[coord])
	_dirty.erase(coord)


func flush_all() -> void:
	if OS.is_debug_build():
		return
	for coord in _dirty.keys():
		_save_to_disk(coord, _cache[coord])
	_dirty.clear()


func _get_path(coord: Vector3i) -> String:
	return SAVE_DIR + str(coord.x) + "_" + str(coord.y) + "_" + str(coord.z) + ".dat"


func _save_to_disk(coord: Vector3i, delta: Dictionary) -> void:
	var file := FileAccess.open(_get_path(coord), FileAccess.WRITE)
	if file:
		file.store_var(delta)


func _load_from_disk(coord: Vector3i) -> Dictionary:
	var file := FileAccess.open(_get_path(coord), FileAccess.READ)
	if file == null:
		return {}
	var data = file.get_var()
	if data is Dictionary:
		_cache[coord] = data
		return data
	return {}
