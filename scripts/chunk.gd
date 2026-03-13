@tool
class_name Chunk
extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D
var terrain_generator: TerrainGenerator = null
var chunk_coord: Vector2i = Vector2i.ZERO
var world: Node = null
var cube_mesh: ArrayMesh
var voxels: PackedInt32Array

const CUBE_SIZE: float = VoxelConstants.CUBE_SIZE
const WIDTH: int = VoxelConstants.CHUNK_WIDTH
const HEIGHT: int = VoxelConstants.CHUNK_HEIGHT
const DEPTH: int = VoxelConstants.CHUNK_DEPTH

@export var atlas_texture: Texture2D
const atlas_cols: int = VoxelConstants.CUBE_ATLAS_COLS
const atlas_rows: int = VoxelConstants.CUBE_ATLAS_ROWS

# Prevent sampling neighboring tiles (tweak if needed)
@export var uv_inset_pixels: float = 0.5

# Renders the texture onto the 3D Mesh from the script
@export var set_material_in_code: bool = true

const FACE_TOP := 0
const FACE_BOTTOM := 1
const FACE_SIDE := 2

const BLOCKS := {
	VoxelBlocks.AIR: {
		"name": "Air",
		"type": "empty",
		"collidable": false,
		"opaque": false,
		"tiles": {
			FACE_TOP: Vector2i(0, 15),
			FACE_BOTTOM: Vector2i(0, 15),
			FACE_SIDE: Vector2i(0, 15)
		}
	},
	VoxelBlocks.GRASS: {
		"name": "Grass",
		"type": "solid",
		"collidable": true,
		"opaque": true,
		"tiles": {
			FACE_TOP: Vector2i(0, 0),
			FACE_BOTTOM: Vector2i(2, 0),
			FACE_SIDE: Vector2i(3, 0)
		}
	},
	VoxelBlocks.DIRT: {
		"name": "Dirt",
		"type": "solid",
		"collidable": true,
		"opaque": true,
		"tiles": {
			FACE_TOP: Vector2i(2, 0),
			FACE_BOTTOM: Vector2i(2, 0),
			FACE_SIDE: Vector2i(2, 0)
		}
	},
	VoxelBlocks.STONE: {
		"name": "Stone",
		"type": "solid",
		"collidable": true,
		"opaque": true,
		"tiles": {
			FACE_TOP: Vector2i(1, 0),
			FACE_BOTTOM: Vector2i(1, 0),
			FACE_SIDE: Vector2i(1, 0)
		}
	}
}

func initialize(coord: Vector2i, surrounding_world: Node, terrain_generator: TerrainGenerator) -> void:
	chunk_coord = coord
	world = surrounding_world
	terrain_generator = terrain_generator


func _ready() -> void:
	print("Generating voxel data at chunk: %s" % chunk_coord)
	if voxels.is_empty():
		generate_voxels()
	# generate_mesh()
	# We need to have this in the ready function of the chunk if we want to render the textures
	if set_material_in_code and atlas_texture:
		var shader := load("res://shaders/voxel_atlas.gdshader")
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("atlas_texture", atlas_texture)
		mat.set_shader_parameter("atlas_grid", Vector2(atlas_cols, atlas_rows))
		mesh_instance.material_override = mat


func get_block_def(block_id: int) -> Dictionary:
	return BLOCKS.get(block_id, BLOCKS[VoxelBlocks.AIR])

func is_collidable(block_id: int) -> bool:
	return get_block_def(block_id).get("collidable", false)

func is_opaque(block_id: int) -> bool:
	return get_block_def(block_id).get("opaque", false)

func is_empty(block_id: int) -> bool:
	return get_block_def(block_id).get("type", "empty") == "empty"


func _voxel_index(x: int, y: int, z: int) -> int:
	return x + WIDTH * (z + DEPTH * y)


func get_voxel(x:int,y:int,z:int) -> int:
	return voxels[_voxel_index(x,y,z)]


func set_voxel(x:int,y:int,z:int,val:int) -> void:
	voxels[_voxel_index(x,y,z)] = val


func get_voxel_safe(x:int, y:int, z:int) -> int:
	# Y outside chunk = air
	if y < 0 or y >= HEIGHT:
		return VoxelBlocks.AIR
	# inside this chunk
	if x >= 0 and x < WIDTH and z >= 0 and z < DEPTH:
		return get_voxel(x,y,z)
	# Currently previewing a single chunk, so no world exists...
	if not world:
		return VoxelBlocks.AIR
	# determine neighboring chunk
	var neighbor_coord := chunk_coord
	if x < 0:
		neighbor_coord.x -= 1
	elif x >= WIDTH:
		neighbor_coord.x += 1

	if z < 0:
		neighbor_coord.y -= 1
	elif z >= DEPTH:
		neighbor_coord.y += 1

	var neighbor = world.get_chunk(neighbor_coord)
	if neighbor == null:
		return VoxelBlocks.AIR
	var nx = posmod(x, WIDTH)
	var nz = posmod(z, DEPTH)
	return neighbor.get_voxel(nx, y, nz)


func generate_mesh():
	mesh_instance.mesh = null
	cube_mesh = null

	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var colors: Array[Color] = []

	greedy_axis(0, vertices, normals, uvs, colors)
	greedy_axis(1, vertices, normals, uvs, colors)
	greedy_axis(2, vertices, normals, uvs, colors)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(uvs)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)

	cube_mesh = ArrayMesh.new()
	cube_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = cube_mesh
	var trimesh_shape := cube_mesh.create_trimesh_shape()
	collision_shape.shape = trimesh_shape


func generate_voxels() -> void:
	voxels = PackedInt32Array()
	voxels.resize(WIDTH * HEIGHT * DEPTH)

	if not terrain_generator:
		terrain_generator = TerrainGenerator.new()

	for x in range(WIDTH):
		for z in range(DEPTH):
			var world_x = chunk_coord.x * WIDTH + x
			var world_z = chunk_coord.y * DEPTH + z

			for y in range(HEIGHT):
				var block_id = terrain_generator.get_block_at(world_x, y, world_z)
				set_voxel(x, y, z, block_id)


func create_face(direction: Vector3, pos: Vector3, uv_coords: Array[Vector2]) -> Dictionary:
	var quad_vertices: Array[Vector3] = []
	var quad_normals: Array[Vector3] = []
	var quad_uvs: Array[Vector2] = oriented_uvs_for_face(direction, uv_coords)

	match direction:
		Vector3.UP:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE
			]
		Vector3.DOWN:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE
			]
		Vector3.LEFT:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE
			]
		Vector3.RIGHT:
			quad_vertices = [
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE
			]
		Vector3.FORWARD:
			quad_vertices = [
				pos + Vector3(-0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5, -0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5, -0.5) * CUBE_SIZE,
				pos + Vector3(-0.5,  0.5, -0.5) * CUBE_SIZE
			]
		Vector3.BACK:
			quad_vertices = [
				pos + Vector3(-0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5,  0.5,  0.5) * CUBE_SIZE,
				pos + Vector3( 0.5, -0.5,  0.5) * CUBE_SIZE,
				pos + Vector3(-0.5, -0.5,  0.5) * CUBE_SIZE
			]
		_:
			return {"vertices": [], "normals": [], "uvs": []}

	quad_normals.resize(4)
	quad_normals.fill(direction)

	return {
		"vertices": [
			quad_vertices[0], quad_vertices[1], quad_vertices[2],
			quad_vertices[0], quad_vertices[2], quad_vertices[3],
		],
		"normals": [
			quad_normals[0], quad_normals[1], quad_normals[2],
			quad_normals[0], quad_normals[2], quad_normals[3],
		],
		"uvs": [
			quad_uvs[0], quad_uvs[1], quad_uvs[2],
			quad_uvs[0], quad_uvs[2], quad_uvs[3],
		]
	}


func oriented_uvs_for_face(face_dir: Vector3, base_uvs: Array[Vector2]) -> Array[Vector2]:
	# base_uvs is [BL, BR, TR, TL] or whatever you decided—just be consistent.
	# Your current get_tile_uvs returns: [ (u0,v1), (u1,v1), (u1,v0), (u0,v0) ]
	# which corresponds to: [BL, BR, TR, TL] in UV space (Godot's V grows downward in many setups).
	#
	# We’ll rotate/flip so that "up" on the texture points toward +Y for all side faces.

	match face_dir:
		Vector3.FORWARD:
			# Often needs a flip to keep consistent with BACK
			return [base_uvs[1], base_uvs[0], base_uvs[3], base_uvs[2]]
		Vector3.BACK:
			return [base_uvs[3], base_uvs[2], base_uvs[1], base_uvs[0]]
		Vector3.LEFT:
			# rotate 90
			return [base_uvs[1], base_uvs[2], base_uvs[3], base_uvs[0]]
		Vector3.RIGHT:
			# rotate 270
			# TODO: There is a bug where this face is vertically mirrored
			return [base_uvs[1], base_uvs[2], base_uvs[3], base_uvs[0]]
		Vector3.UP:
			# optional: depends on how you want top oriented
			return base_uvs
		Vector3.DOWN:
			# optional: flip to make bottom not mirrored
			return [base_uvs[3], base_uvs[2], base_uvs[1], base_uvs[0]]
		_:
			return base_uvs


func block_tile_for_face(block_id: int, face_dir: Vector3) -> Vector2i:
	var block = BLOCKS.get(block_id, BLOCKS[0])
	var tiles = block["tiles"]

	if face_dir == Vector3.UP:
		return tiles[FACE_TOP]
	elif face_dir == Vector3.DOWN:
		return tiles[FACE_BOTTOM]
	else:
		return tiles[FACE_SIDE]


func get_tile_uvs(tile_x: int, tile_y: int) -> Array[Vector2]:
	# Each tile in UV space
	var tile_u := 1.0 / float(atlas_cols)
	var tile_v := 1.0 / float(atlas_rows)

	# Optional: flip Y if your atlas indexing starts at top-left
	# If your tiles appear vertically flipped/wrong row, uncomment:
	# tile_y = (atlas_rows - 1) - tile_y

	var u0 := float(tile_x) * tile_u
	var v0 := float(tile_y) * tile_v
	var u1 := u0 + tile_u
	var v1 := v0 + tile_v

	# Inset by a small amount (in pixels) to avoid bleeding
	if atlas_texture and uv_inset_pixels > 0.0:
		var tex_w := float(atlas_texture.get_width())
		var tex_h := float(atlas_texture.get_height())
		var inset_u := uv_inset_pixels / tex_w
		var inset_v := uv_inset_pixels / tex_h
		u0 += inset_u
		u1 -= inset_u
		v0 += inset_v
		v1 -= inset_v

	# Quad UV order must match your vertex order.
	# Here we map the quad corners consistently.
	return [
		Vector2(u0, v1),
		Vector2(u1, v1),
		Vector2(u1, v0),
		Vector2(u0, v0),
	]

func greedy_axis(axis:int, vertices, normals, uvs, colors):

	var dims:Array[int] = [WIDTH, HEIGHT, DEPTH]

	var u = (axis + 1) % 3
	var v = (axis + 2) % 3

	var x:Array[int] = [0,0,0]
	var q:Array[int] = [0,0,0]

	q[axis] = 1

	var mask:Array[int] = []
	mask.resize(dims[u] * dims[v])

	for i in range(-1, dims[axis]):
		x[axis] = i

		var n = 0

		for j in range(dims[v]):
			x[v] = j

			for k in range(dims[u]):
				x[u] = k

				var a: int = get_voxel_safe(x[0], x[1], x[2])
				var b: int = get_voxel_safe(x[0] + q[0], x[1] + q[1], x[2] + q[2])

				if (a != VoxelBlocks.AIR) != (b != VoxelBlocks.AIR):
					mask[n] = a if a != VoxelBlocks.AIR else -b
				else:
					mask[n] = 0

				n += 1
		n = 0

		for j in range(dims[v]):
			var t = 0
			while t < dims[u]:

				var c = mask[n]

				if c == 0:
					t += 1
					n += 1
					continue

				var w = 1
				while t+w < dims[u] and mask[n+w] == c:
					w += 1

				var h = 1
				var done = false

				while j+h < dims[v]:

					for k in range(w):
						if mask[n + k + h*dims[u]] != c:
							done = true
							break

					if done:
						break

					h += 1
				# Emit the quad
				x[u] = t
				x[v] = j

				var du = [0,0,0]
				var dv = [0,0,0]

				du[u] = w
				dv[v] = h

				add_quad(vertices, normals, uvs, colors, x, du, dv, axis, c)
				for l in range(h):
					for k in range(w):
						mask[n + k + l*dims[u]] = 0

				t += w
				n += w

func add_quad(vertices, normals, uvs, colors, x, du, dv, axis, block_id):
	var quad_sign := 1 if block_id > 0 else -1

	var face_dir := Vector3.ZERO
	face_dir[axis] = quad_sign

	var normal := Vector3.ZERO
	normal[axis] = -quad_sign

	var p = Vector3(x[0], x[1], x[2])
	p[axis] += 1
	p *= CUBE_SIZE

	var u_vec = Vector3(du[0], du[1], du[2]) * CUBE_SIZE
	var v_vec = Vector3(dv[0], dv[1], dv[2]) * CUBE_SIZE

	var verts = [
		p,
		p + u_vec,
		p + u_vec + v_vec,
		p + v_vec
	]

	var tile := block_tile_for_face(abs(block_id), face_dir)

	# Repeat UVs across the merged quad.
	var repeat_u: float = abs(du[0] + du[1] + du[2])
	var repeat_v: float = abs(dv[0] + dv[1] + dv[2])

	var quad_uvs = oriented_greedy_uvs(face_dir, repeat_u, repeat_v)

	# Store atlas tile coords in COLOR.rg.
	# Dividing by 255.0 matches the shader's recovery logic.
	var tile_color := Color(tile.x / 255.0, tile.y / 255.0, 0.0, 1.0)

	if quad_sign > 0:
		vertices.append_array([
			verts[0], verts[2], verts[1],
			verts[0], verts[3], verts[2]
		])

		uvs.append_array([
			quad_uvs[0], quad_uvs[2], quad_uvs[1],
			quad_uvs[0], quad_uvs[3], quad_uvs[2]
		])
	else:
		vertices.append_array([
			verts[0], verts[1], verts[2],
			verts[0], verts[2], verts[3]
		])

		uvs.append_array([
			quad_uvs[0], quad_uvs[1], quad_uvs[2],
			quad_uvs[0], quad_uvs[2], quad_uvs[3]
		])

	normals.append_array([
		normal, normal, normal,
		normal, normal, normal
	])

	colors.append_array([
		tile_color, tile_color, tile_color,
		tile_color, tile_color, tile_color
	])


# THE UV SHIT ISNT WORKING AND IM TIRED.
# TODO FIX ORIENTATION OF BLOCKS.
func make_uv_rect(w: float, h: float) -> Array[Vector2]:
	return [
		Vector2(0, h), # BL
		Vector2(w, h), # BR
		Vector2(w, 0), # TR
		Vector2(0, 0)  # TL
	]

func rotate_uvs_ccw(uvs: Array[Vector2]) -> Array[Vector2]:
	return [uvs[1], uvs[2], uvs[3], uvs[0]]

func rotate_uvs_cw(uvs: Array[Vector2]) -> Array[Vector2]:
	return [uvs[3], uvs[0], uvs[1], uvs[2]]

func rotate_uvs_180(uvs: Array[Vector2]) -> Array[Vector2]:
	return [uvs[2], uvs[3], uvs[0], uvs[1]]

func flip_uvs_horizontal(uvs: Array[Vector2]) -> Array[Vector2]:
	return [uvs[1], uvs[0], uvs[3], uvs[2]]

func flip_uvs_vertical(uvs: Array[Vector2]) -> Array[Vector2]:
	return [uvs[3], uvs[2], uvs[1], uvs[0]]

func oriented_greedy_uvs(face_dir: Vector3, repeat_u: float, repeat_v: float) -> Array[Vector2]:
	var base_uvs: Array[Vector2] = [
		Vector2(0, repeat_v),
		Vector2(repeat_u, repeat_v),
		Vector2(repeat_u, 0),
		Vector2(0, 0)
	]

	# var ccw_90_uvs: Array[Vector2] = [
	# 	Vector2(0, 0),
	# 	Vector2(0, repeat_u),
	# 	Vector2(repeat_v, repeat_u),
	# 	Vector2(repeat_v, 0)
	# ]

	var cw_90_uvs: Array[Vector2] = [
		Vector2(repeat_v, repeat_u),
		Vector2(repeat_v, 0),
		Vector2(0, 0),
		Vector2(0, repeat_u)
	]

	# var rot_180_uvs: Array[Vector2] = [
	# 	Vector2(repeat_u, 0),
	# 	Vector2(0, 0),
	# 	Vector2(0, repeat_v),
	# 	Vector2(repeat_u, repeat_v)
	# ]

	match face_dir:
		Vector3.FORWARD:
			return base_uvs
		Vector3.BACK:
			return base_uvs
		Vector3.LEFT:
			return cw_90_uvs
		Vector3.RIGHT:
			return cw_90_uvs
		Vector3.UP:
			return base_uvs
		Vector3.DOWN:
			return base_uvs
		_:
			return base_uvs
