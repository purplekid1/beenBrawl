extends CharacterBody3D


const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const ATTACK_RANGE := 3.0
const DUMMY_HIT_FORCE := 4.0
const COMBO_ANIMATIONS: Array[StringName] = [
	&"Arms_cross_R",
	&"Arms_Heavy_L",
	&"Arms_cross_L",
	&"Arms_Heavy_R"
]

var combo_step: int = -1
var attack_in_progress: bool = false
var queued_next_attack: bool = false
var attack_token: int = 0

@onready var animation_player: AnimationPlayer = $"CollisionShape3D/fighter Arms/AnimationPlayer"
@onready var camera: Camera3D = $"CollisionShape3D/fighter Arms/Arms_Rig/Skeleton3D/BoneAttachment3D/Camera3D"
@onready var hit_effect_scene: PackedScene = preload("res://hit_effect.tscn")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not animation_player.animation_finished.is_connected(_on_attack_animation_finished):
		animation_player.animation_finished.connect(_on_attack_animation_finished)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_register_attack_click()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()


func _register_attack_click() -> void:
	if attack_in_progress:
		queued_next_attack = true
		return

	combo_step = 0
	_play_attack_step()


func _play_attack_step() -> void:
	attack_in_progress = true
	queued_next_attack = false

	var attack_animation: StringName = COMBO_ANIMATIONS[combo_step]
	animation_player.play(attack_animation)

	attack_token += 1
	var step_token: int = attack_token
	var animation_length: float = animation_player.get_animation(attack_animation).length
	var hit_delay: float = maxf(0.03, animation_length * 0.3)
	get_tree().create_timer(hit_delay).timeout.connect(func() -> void:
		if step_token != attack_token:
			return
		_process_hit())


func _on_attack_animation_finished(animation_name: StringName) -> void:
	if not attack_in_progress:
		return

	if animation_name != COMBO_ANIMATIONS[combo_step]:
		return

	if queued_next_attack and combo_step < COMBO_ANIMATIONS.size() - 1:
		combo_step += 1
		_play_attack_step()
		return

	_reset_combo()


func _reset_combo() -> void:
	combo_step = -1
	queued_next_attack = false
	attack_in_progress = false


func _process_hit() -> void:
	var hit_from: Vector3 = camera.global_position
	var hit_to: Vector3 = hit_from + (-camera.global_transform.basis.z * ATTACK_RANGE)
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(hit_from, hit_to)
	ray_query.exclude = [self]
	ray_query.collide_with_areas = false
	var hit_result: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray_query)
	if hit_result.is_empty():
		return

	var hit_position: Vector3 = hit_result["position"]
	var hit_normal: Vector3 = hit_result["normal"]
	_spawn_hit_effect(hit_position, hit_normal)

	var hit_body: Object = hit_result["collider"]
	if hit_body is RigidBody3D:
		var rigid_body: RigidBody3D = hit_body
		var impulse: Vector3 = ((-camera.global_transform.basis.z) + (hit_normal * 0.35)).normalized() * DUMMY_HIT_FORCE
		var local_offset: Vector3 = hit_position - rigid_body.global_position
		rigid_body.apply_impulse(impulse, local_offset)


func _spawn_hit_effect(hit_position: Vector3, hit_normal: Vector3) -> void:
	var hit_effect := hit_effect_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(hit_effect)
	hit_effect.global_position = hit_position
	hit_effect.look_at(hit_position + hit_normal, Vector3.UP)

	var sparks := hit_effect.get_node_or_null("Sparks") as GPUParticles3D
	if sparks:
		sparks.restart()
		sparks.emitting = true

	var shockwave := hit_effect.get_node_or_null("shockwave") as GPUParticles3D
	if shockwave:
		shockwave.restart()
		shockwave.emitting = true

	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(hit_effect):
			hit_effect.queue_free())
