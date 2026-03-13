class_name TerrainGenerator

var terrain_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var cave_noise_2 := FastNoiseLite.new()

func _init() -> void:
	terrain_noise.seed = 12345
	terrain_noise.frequency = 0.01
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	cave_noise.seed = 99999
	cave_noise.frequency = 1.0
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	cave_noise_2.seed = 98765
	cave_noise_2.frequency = 1.0
	cave_noise_2.noise_type = FastNoiseLite.TYPE_SIMPLEX

func get_surface_height(world_x: int, world_z: int) -> int:
	var height_noise = terrain_noise.get_noise_2d(world_x, world_z)
	return int((height_noise + 1.0) * 0.5 * 20.0) + 20

func get_cave_value(world_x: int, y: int, world_z: int) -> float:
	var cave_a = cave_noise.get_noise_3d(
		(world_x + 1000.37) * 0.035,
		(y + 2000.91) * 0.02,
		(world_z + 3000.53) * 0.035
	)

	var cave_b = cave_noise_2.get_noise_3d(
		(world_x + 4000.11) * 0.018,
		(y + 5000.77) * 0.03,
		(world_z + 6000.29) * 0.018
	)

	return min(abs(cave_a), abs(cave_b))

func get_cave_threshold(surface_height: int, y: int) -> float:
	var depth_factor = clamp(float(surface_height - y) / 25.0, 0.0, 1.0)
	return lerp(0.02, 0.05, depth_factor)

func get_block_at(world_x: int, y: int, world_z: int) -> int:
	var surface_height = get_surface_height(world_x, world_z)

	if y > surface_height:
		return VoxelBlocks.AIR

	if y == surface_height:
		return VoxelBlocks.GRASS

	var cave_value = get_cave_value(world_x, y, world_z)
	var cave_threshold = get_cave_threshold(surface_height, y)

	if cave_value < cave_threshold and y < surface_height - 2:
		return VoxelBlocks.AIR
	elif y >= surface_height - 3:
		return VoxelBlocks.DIRT
	else:
		return VoxelBlocks.STONE
