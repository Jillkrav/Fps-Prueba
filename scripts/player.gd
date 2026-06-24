extends CharacterBody3D
class_name Player

signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var weapon_placeholder_scene: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")

var active_weapon: Weapon = null

func _ready() -> void:
	max_health     = ConfigManager.salud_jugador
	current_health = max_health
	# No capturamos el mouse aqui. El HUD lo maneja con F1 y al hacer click para jugar.
	# Input.mouse_mode se deja como lo tenga el HUD (VISIBLE al entrar al mapa).
	add_to_group("player")
	setup_weapon()
	health_changed.emit(current_health, max_health)

func setup_weapon() -> void:
	for child in weapon_holder.get_children():
		child.queue_free()
	var weapon_instance: Node = weapon_placeholder_scene.instantiate()
	weapon_holder.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon
	var selected: String = "USP"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and "selected_weapon" in gs:
		selected = gs.selected_weapon
	active_weapon.initialize_from_name(selected)
	active_weapon.weapon_fired.connect(_on_weapon_fired)
	active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	# Solo rotar camara si el mouse esta capturado
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	# Click izquierdo captura el mouse para empezar a jugar
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if is_dead:
		return
	if Input.is_physical_key_pressed(KEY_R):
		if active_weapon:
			active_weapon.start_reload()
	# Disparar solo si el mouse esta capturado
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_physical_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			shoot()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()

func shoot() -> void:
	if not active_weapon:
		return
	if active_weapon.can_fire():
		var hits: Array = active_weapon.fire()
		for hit in hits:
			var target_node: Node = hit["collider"]
			if target_node and target_node.has_method("take_damage"):
				if target_node is Player:
					target_node.take_damage(hit["damage_vs_player"])
				else:
					target_node.take_damage(hit["damage_vs_npc"])

func take_damage(amount: float, zona: String = "Torso") -> void:
	if is_dead:
		return
	var multiplicador: float = 1.0
	match zona:
		"Cabeza": multiplicador = ConfigManager.mult_cabeza
		"Torso":  multiplicador = ConfigManager.mult_torso
	current_health -= amount * multiplicador
	current_health = clamp(current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		die()

func die() -> void:
	is_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()

func resupply() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
	if active_weapon:
		active_weapon.resupply()

func _on_weapon_fired(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)

func _on_weapon_ammo_changed(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)
