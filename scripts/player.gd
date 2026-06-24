# scripts/player.gd
# Controla movimiento, disparo, salud y arma del jugador.
extends CharacterBody3D
class_name Player

signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()

@export var speed:             float = 6.0
@export var jump_velocity:     float = 4.5
@export var mouse_sensitivity: float = 0.002

# Salud — se inicializa desde ConfigManager en _ready()
var max_health:     float = 0.0
var current_health: float = 0.0
var is_dead:        bool  = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head:          Node3D    = $Head
@onready var camera:        Camera3D  = $Head/Camera3D
@onready var weapon_holder: Node3D    = $Head/Camera3D/WeaponHolder
@onready var weapon_placeholder_scene: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")

var active_weapon: Weapon = null

func _ready() -> void:
	# Leer salud desde ConfigManager
	max_health     = ConfigManager.salud_jugador
	current_health = max_health

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	setup_weapon()
	health_changed.emit(current_health, max_health)

func setup_weapon() -> void:
	# Limpiar armas previas
	for child in weapon_holder.get_children():
		child.queue_free()

	# Instanciar placeholder
	var weapon_instance: Node = weapon_placeholder_scene.instantiate()
	weapon_holder.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon

	# Leer arma seleccionada desde GameState (por defecto: USP)
	var selected: String = "USP"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs and "selected_weapon" in gs:
		selected = gs.selected_weapon

	# Inicializar arma desde ConfigManager
	active_weapon.initialize_from_name(selected)

	# Conectar señales
	active_weapon.weapon_fired.connect(_on_weapon_fired)
	active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)

# ── Input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func _process(_delta: float) -> void:
	if is_dead:
		return
	if Input.is_physical_key_pressed(KEY_R) and active_weapon:
		active_weapon.start_reload()
	if Input.is_physical_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		shoot()
	# NOTA: ui_cancel lo maneja exclusivamente hud.gd para evitar conflictos

# ── Movimiento ───────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if (Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_SPACE)) and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0

	var direction: Vector3 = (transform.basis * Vector3(input_dir.normalized().x, 0, input_dir.normalized().y)).normalized()
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

# ── Combate ──────────────────────────────────────────────────────────────

func shoot() -> void:
	if not active_weapon:
		return
	var hits: Array = active_weapon.fire()
	for hit in hits:
		var collider: Node = hit["collider"]
		if not collider or not collider.has_method("take_damage"):
			continue
		# Aplicar daño correcto según tipo de objetivo
		if collider is Player:
			collider.take_damage(hit["damage_vs_player"])
		else:
			collider.take_damage(hit["damage_vs_npc"])

## Recibe daño. zona: "Torso" (default) | "Cabeza"
func take_damage(amount: float, zona: String = "Torso") -> void:
	if is_dead:
		return
	var mult: float = ConfigManager.mult_torso
	if zona == "Cabeza":
		mult = ConfigManager.mult_cabeza
	current_health -= amount * mult
	current_health  = clamp(current_health, 0.0, max_health)
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

# ── Callbacks de señales ─────────────────────────────────────────────────

func _on_weapon_fired(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)

func _on_weapon_ammo_changed(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)
