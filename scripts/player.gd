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

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	if mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
