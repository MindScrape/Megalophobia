class_name VoxelConstants

const CHUNK_WIDTH: int = 16     # x
const CHUNK_HEIGHT: int = 16    # y (per sub-chunk)
const CHUNK_DEPTH: int = 16     # z
const CHUNK_SIZE: Vector3i = Vector3i(CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_DEPTH)
const CUBE_SIZE: float = 1.0

const WORLD_HEIGHT: int = 64                           # total world height in voxels
const NUM_Y_CHUNKS: int = WORLD_HEIGHT / CHUNK_HEIGHT  # number of vertical sub-chunks (= 4)

const CUBE_ATLAS_ROWS: int = 16
const CUBE_ATLAS_COLS: int = 16
 
