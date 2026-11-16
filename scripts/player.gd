extends CharacterBody3D
## Персонаж от первого лица на круглой планете.
## «Низ» — всегда к центру планеты, тело выравнивается по нормали каждый кадр.
## Движение считается у себя на клиенте, позиция отправляется серверу (см. world.gd).

const SPEED := 6.0
const SPRINT := 10.0
const JUMP := 5.0
const GRAVITY := 6.0     # слабая гравитация: терраса 0.5 м берётся прыжком легко
const SENS := 0.0025

var active := true       # false, когда включена орбитальная камера
var dead := false
var look_locked := false  # true, пока открыто круговое меню
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
	cam.near = 0.1
	cam.far = 15000
	head.add_child(cam)

	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.3


func _unhandled_input(event: InputEvent) -> void:
	if not active or dead:
		return
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not look_locked:
		rotate_object_local(Vector3.UP, -mm.relative.x * SENS)
		head.rotation.x = clampf(head.rotation.x - mm.relative.y * SENS, -1.5, 1.5)


func _physics_process(delta: float) -> void:
	var up := global_position.normalized()

	# выравниваем тело: локальная ось Y = нормаль планеты, поворот (yaw) сохраняется
	var b := global_transform.basis
	var x := b.x - up * b.x.dot(up)
	if x.length() < 0.001:
		x = b.z.cross(up)
	x = x.normalized()
	global_transform.basis = Basis(x, up, x.cross(up))
	up_direction = up

	var input := Vector2.ZERO
	var want_jump := false
	if active and not dead:
		if Input.is_key_pressed(KEY_W):
			input.y -= 1
		if Input.is_key_pressed(KEY_S):
			input.y += 1
		if Input.is_key_pressed(KEY_A):
			input.x -= 1
		if Input.is_key_pressed(KEY_D):
			input.x += 1
		want_jump = Input.is_key_pressed(KEY_SPACE)

	var spd := SPRINT if Input.is_key_pressed(KEY_SHIFT) else SPEED
	var dir := global_transform.basis * Vector3(input.x, 0, input.y)
	if dir.length() > 0.001:
		dir = dir.normalized()

	var vr := velocity.dot(up)
	if is_on_floor():
		vr = -0.5
		if want_jump:
			vr = JUMP
	else:
		vr -= GRAVITY * delta
	velocity = dir * spd + up * vr
	move_and_slide()


func look_dir() -> Vector3:
	return -cam.global_transform.basis.z


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
