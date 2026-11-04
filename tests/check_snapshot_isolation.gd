# A semaphore holds the worker until live data is changed on the main thread.
# Tests the actual generate_mesh_async snapshot boundary, without mesh-server calls.
# Run: godot --headless --path . --script tests/check_snapshot_isolation.gd
extends SceneTree

class SnapshotWorld extends Node:
	var chunks: Dictionary = {}
	func get_chunk(coord: Vector3i) -> Chunk:
		return chunks.get(coord)

class SnapshotChunk extends Chunk:
	var gate := Semaphore.new()
	var hold_generation := false
	var captured_voxel := -1
	var captured_neighbor := -1
	var completed := false
	func _generate_voxels_pure(_coord: Vector3i, _generator: TerrainGenerator) -> PackedInt32Array:
		gate.wait()
		var generated := PackedInt32Array()
		generated.resize(4096)
		generated.fill(VoxelBlocks.DIRT)
		return generated
	func _compute_mesh_data(data: PackedInt32Array, neighbors: Dictionary) -> Dictionary:
		if not hold_generation:
			gate.wait()
		captured_voxel = data[0]
		if neighbors.has(Vector3i.RIGHT):
			captured_neighbor = neighbors[Vector3i.RIGHT][0]
		return {"mesh":null,"shape":null}
	func _apply_mesh_data(_mesh: ArrayMesh, _shape: Shape3D, on_complete: Callable,
			_new_voxels: PackedInt32Array = PackedInt32Array(), _revision: int = -1) -> void:
		completed = true
		if on_complete.is_valid():
			on_complete.call()

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures.append(description)

func _run() -> void:
	var world := SnapshotWorld.new()
	var chunk := SnapshotChunk.new()
	var neighbor := Chunk.new()
	chunk.world = world
	chunk.voxels.resize(4096)
	chunk.voxels.fill(VoxelBlocks.GRASS)
	neighbor.voxels.resize(4096)
	neighbor.voxels.fill(VoxelBlocks.DIRT)
	world.chunks[Vector3i.RIGHT] = neighbor
	chunk.generate_mesh_async(Callable())
	chunk.voxels[0] = VoxelBlocks.AIR
	neighbor.voxels[0] = VoxelBlocks.STONE
	chunk.gate.post()
	WorkerThreadPool.wait_for_task_completion(chunk._mesh_task_id)
	chunk._mesh_task_id = -1
	await process_frame
	_expect(chunk.captured_voxel == VoxelBlocks.GRASS, "worker keeps the original chunk voxel")
	_expect(chunk.captured_neighbor == VoxelBlocks.DIRT, "worker keeps the original neighboring voxel")
	_expect(chunk.completed, "completion is deferred back to the main loop")
	chunk.free()
	neighbor.free()
	world.free()

	var fresh := SnapshotChunk.new()
	fresh.hold_generation = true
	var cached_delta := {0:VoxelBlocks.STONE}
	fresh._pending_delta = cached_delta
	fresh.generate_mesh_async(Callable())
	cached_delta[0] = VoxelBlocks.AIR
	fresh.gate.post()
	WorkerThreadPool.wait_for_task_completion(fresh._mesh_task_id)
	fresh._mesh_task_id = -1
	await process_frame
	_expect(fresh.captured_voxel == VoxelBlocks.STONE, "worker keeps the original saved edit delta")
	_expect(fresh._pending_delta.is_empty(), "pending delta is consumed by the request")
	fresh.free()
	print("Snapshot isolation: %d failed checks" % failures.size())
	quit(1 if not failures.is_empty() else 0)
