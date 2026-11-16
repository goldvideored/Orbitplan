extends CharacterBody3D
## Персонаж от первого лица. Движение считается у себя на клиенте,
## позиция отправляется серверу (см. world.gd).

const SPEED := 6.0
const SPRINT := 10.0
const JUMP := 4.5
const GRAVITY := 4.0     # спутник — гравитация низкая, прыжки длинные
const SENS := 0.0025
const MAP := 64

var active := true       # false в режиме вида сверху
var dead := false
var head: Node3D
var cam: Camera3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.35
	cs.height = 1.8
	col.shape = cs
	col.position.y = 0.9
	add_child(col)

	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)

	cam = Camera3D.new()
	cam.fov = 80
	cam.far = 2000
	head.add_child(cam)


func _unhandled_input(event: InputEvent) -> void:
	if not active or dead:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-mm.relative.x * SENS)
		head.rotation.x = clampf(head.rotation.x - mm.relative.y * SENS, -1.5, 1.5)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input := Vector2.ZERO
	if active and not dead:
		if Input.is_key_pressed(KEY_W):
			input.y -= 1
		if Input.is_key_pressed(KEY_S):
			input.y += 1
		if Input.is_key_pressed(KEY_A):
			input.x -= 1
		if Input.is_key_pressed(KEY_D):
			input.x += 1
		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP

	var spd := SPRINT if Input.is_key_pressed(KEY_SHIFT) else SPEED
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	move_and_slide()

	position.x = clampf(position.x, 0.3, MAP - 0.3)
	position.z = clampf(position.z, 0.3, MAP - 0.3)
	if position.y < -5.0:
		position.y = 1.0
		velocity = Vector3.ZERO


func look_dir() -> Vector3:
	return -cam.global_transform.basis.z
