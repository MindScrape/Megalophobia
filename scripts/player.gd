extends CharacterBody3D

@export var can_move: bool = true
@export var can_sprint: bool = true
@export var move_speed: float = 5.0
@export var move_speed_sprint: float = 8.0
@export var move_sprint: bool = false
@export var move_acceleration: float = 3.0
@export var move_deacceleration: float = 6.0
@export var mouse_captured: bool = true
@export var mouse_sensitivity_x: float = 0.3
@export var mouse_sensitivity_y: float = 0.3
@export var mouse_max_up: float = 90.0
@export var mouse_max_down: float = -80.0
@export var jump_speed: float = 5.0
@export var allow_fall_input: bool = true
@export var gravity_strength: float = 15
@export var gravity_vector: Vector3 = Vector3(0, -1, 0)
@export var floor_normal: Vector3 = Vector3(0, 1, 0)
@export var jump_vector: Vector3 = Vector3(0, 1.1, 0)
@export var reach: float = 5.0

@onready var camera: Camera3D = $Camera3D

var world: Node = null					# Reference to world for block interactions, set on spawn
var _highlight: MeshInstance3D = null	# Simple box highlight for targeted block
var _ray_result: Dictionary = {}		# Cache raycast result for use across multiple functions in a single frame

func initialize(world_node: Node) -> void:
	world = world_node

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_create_highlight()

# Called every frame
func _process(_delta: float) -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position + (-camera.global_transform.basis.z * reach)
	)
	query.exclude = [self]
	_ray_result = space.intersect_ray(query)

	if _ray_result.is_empty():
		_highlight.visible = false
		return

	var nudged = _ray_result["position"] + _ray_result["normal"] * -0.01
	_highlight.global_position = nudged.floor() + Vector3(0.5, 0.5, 0.5)
	_highlight.visible = true

func _create_highlight() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var s := 0.501
	var corners = [
		Vector3(-s, -s, -s), Vector3( s, -s, -s),
		Vector3( s, -s,  s), Vector3(-s, -s,  s),
		Vector3(-s,  s, -s), Vector3( s,  s, -s),
		Vector3( s,  s,  s), Vector3(-s,  s,  s),
	]
	var edges = [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
	]
	for e in edges:
		st.add_vertex(corners[e[0]])
		st.add_vertex(corners[e[1]])

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK

	_highlight = MeshInstance3D.new()
	_highlight.mesh = st.commit()
	_highlight.material_override = mat
	_highlight.top_level = true
	_highlight.visible = false
	add_child(_highlight)

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO

	if can_move and (is_on_floor() or allow_fall_input):
		if Input.is_action_pressed("move_left"):
			dir.x -= 1.0
		if Input.is_action_pressed("move_right"):
			dir.x += 1.0
		if Input.is_action_pressed("move_forward"):
			dir.z -= 1.0
		if Input.is_action_pressed("move_backwards"):
			dir.z += 1.0

		if Input.is_action_just_pressed("move_jump") and is_on_floor():
			velocity += jump_vector * jump_speed - (jump_vector * -1.0).normalized() * velocity.dot(jump_vector * -1.0)

		if can_sprint and Input.is_action_pressed("move_sprint") and is_on_floor():
			move_sprint = true
		elif can_sprint and is_on_floor():
			move_sprint = false

	var target_speed := move_speed_sprint if move_sprint else move_speed

	if dir != Vector3.ZERO:
		dir = (transform.basis * dir.normalized()) * target_speed

	if is_on_floor() or dir != Vector3.ZERO:
		var acceleration := move_acceleration if dir.dot(velocity) > 0.0 else move_deacceleration
		var vp := gravity_vector.normalized() * velocity.dot(gravity_vector)
		var horizontal_velocity := velocity - vp
		horizontal_velocity = horizontal_velocity.lerp(dir, acceleration * delta)
		velocity = horizontal_velocity + vp

	if not is_on_floor():
		velocity += gravity_vector * gravity_strength * delta

	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity_x
		camera.rotation_degrees.x = clamp(
			camera.rotation_degrees.x + -event.relative.y * mouse_sensitivity_y,
			mouse_max_down,
			mouse_max_up
		)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_pick_block()

func _try_pick_block() -> void:
	if _ray_result.is_empty() or world == null:
		return
	var hit_pos = _ray_result["position"] + _ray_result["normal"] * -0.01
	var chunk_coord = world.world_to_chunk(hit_pos)
	var local_pos = world.world_to_local(hit_pos)
	# print("Hit block at world ", hit_pos, " chunk ", chunk_coord, " local ", local_pos)
	world.set_block(chunk_coord, local_pos, VoxelBlocks.AIR)


func get_player_chunk_coord() -> Vector2i:
	var px = floor(self.global_position.x / VoxelConstants.CHUNK_SIZE.x)
	var pz = floor(self.global_position.z / VoxelConstants.CHUNK_SIZE.z)
	return Vector2i(px, pz)
