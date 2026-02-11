extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const ATTACK_RANGE := 3.0
const DUMMY_HIT_FORCE := 4.0
const MOUSE_SENSITIVITY := 0.0025
const CAMERA_PITCH_LIMIT := deg_to_rad(75.0)
const CAMERA_BASE_PITCH := -PI * 0.5
const COMBO_ATTACK_COUNT := 4

var combo_step := -1
var attack_in_progress := false
var queued_next_attack := false
var attack_token := 0
var camera_pitch := 0.0
var combo_sequence = []

@onready var animation_player: AnimationPlayer = $"CollisionShape3D/fighter Arms/AnimationPlayer"
@onready var animation_tree: AnimationTree = $"CollisionShape3D/fighter Arms/AnimationTree"
@onready var camera: Camera3D = $"CollisionShape3D/fighter Arms/Arms_Rig/Skeleton3D/BoneAttachment3D/Camera3D"
@onready var hit_effect_scene: PackedScene = preload("res://hit_effect.tscn")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	animation_tree.active = true
	if not animation_player.animation_finished.is_connected(_on_attack_animation_finished):
		animation_player.animation_finished.connect(_on_attack_animation_finished)
	_apply_camera_pitch()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_register_attack_click()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_look(event.relative)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()


func _rotate_look(relative_motion: Vector2) -> void:
	rotate_y(-relative_motion.x * MOUSE_SENSITIVITY)
	camera_pitch = clamp(camera_pitch - relative_motion.y * MOUSE_SENSITIVITY, -CAMERA_PITCH_LIMIT, CAMERA_PITCH_LIMIT)
	_apply_camera_pitch()


func _apply_camera_pitch() -> void:
	camera.rotation.x = CAMERA_BASE_PITCH + camera_pitch


func _register_attack_click() -> void:
	if attack_in_progress:
		queued_next_attack = true
		return

	combo_sequence = _build_combo_sequence()
	combo_step = 0
	_play_attack_step()


func _build_combo_sequence() -> Array:
	var start_with_left := _start_combo_on_left()
	if start_with_left:
		return [&"Arms_cross_L", &"Arms_cross_R", &"Arms_cross_L", &"Arms_Heavy_R"]
	return [&"Arms_cross_R", &"Arms_cross_L", &"Arms_cross_R", &"Arms_Heavy_L"]


func _start_combo_on_left() -> bool:
	var playback := _get_playback()
	if playback == null:
		return false

	var current_node = playback.get_current_node()
	if current_node == &"Arms_Idle_R":
		return true
	if current_node == &"Arms_Idle_L":
		return false
	if current_node == &"Arms_cross_R" or current_node == &"Arms_Heavy_R":
		return true
	if current_node == &"Arms_cross_L" or current_node == &"Arms_Heavy_L":
		return false
	return false


func _play_attack_step() -> void:
	if combo_step < 0 or combo_step >= combo_sequence.size():
		_reset_combo()
		return

	attack_in_progress = true
	queued_next_attack = false

	var attack_animation := combo_sequence[combo_step]
	var playback := _get_playback()
	if playback == null:
		_reset_combo()
		return
	playback.travel(attack_animation)

	attack_token += 1
	var step_token := attack_token
	var attack_clip := animation_player.get_animation(attack_animation)
	if attack_clip == null:
		return
	var hit_delay := max(0.03, attack_clip.length * 0.3)
	get_tree().create_timer(hit_delay).timeout.connect(func() -> void:
		if step_token != attack_token:
			return
		_process_hit())


func _on_attack_animation_finished(animation_name: StringName) -> void:
	if not attack_in_progress:
		return
	if combo_step < 0 or combo_step >= combo_sequence.size():
		return
	if animation_name != combo_sequence[combo_step]:
		return

	if queued_next_attack and combo_step < COMBO_ATTACK_COUNT - 1:
		combo_step += 1
		_play_attack_step()
		return

	_reset_combo()


func _reset_combo() -> void:
	combo_step = -1
	queued_next_attack = false
	attack_in_progress = false
	combo_sequence.clear()


func _get_playback():
	return animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _process_hit() -> void:
	var hit_from := camera.global_position
	var hit_to := hit_from + (-camera.global_transform.basis.z * ATTACK_RANGE)
	var ray_query := PhysicsRayQueryParameters3D.create(hit_from, hit_to)
	ray_query.exclude = [self]
	ray_query.collide_with_areas = false
	var hit_result := get_world_3d().direct_space_state.intersect_ray(ray_query)
	if hit_result.is_empty():
		return

	_spawn_hit_effect(hit_result.position, hit_result.normal)

	var hit_body = hit_result.collider
	if hit_body is RigidBody3D:
		var impulse = ((-camera.global_transform.basis.z) + (hit_result.normal * 0.35)).normalized() * DUMMY_HIT_FORCE
		var local_offset = hit_result.position - hit_body.global_position
		hit_body.apply_impulse(impulse, local_offset)


func _spawn_hit_effect(hit_position: Vector3, hit_normal: Vector3) -> void:
	var hit_effect := hit_effect_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(hit_effect)
	hit_effect.global_position = hit_position
