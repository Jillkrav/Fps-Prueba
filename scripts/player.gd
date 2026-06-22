extends CharacterBody3D
class_name Player

# Señales para comunicar cambios en la HUD (desacoplada)
signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()

@export var max_health: float = 100.0
@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# Estado de salud
var current_health: float = 100.0
var is_dead: bool = false

# Gravedad
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Nodos
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var weapon_placeholder_scene: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")

var active_weapon: Weapon = null

func _ready() -> void:
	current_health = max_health
	
	# Capturar el mouse para control en primera persona
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Instanciar el arma seleccionada en GameState
	setup_weapon()
	
	# Emitir valores iniciales
	health_changed.emit(current_health, max_health)

func setup_weapon() -> void:
	# Eliminar armas previas si las hay
	for child in weapon_holder.get_children():
		child.queue_free()
		
	# Crear la nueva arma
	var weapon_instance: Node = weapon_placeholder_scene.instantiate()
	weapon_holder.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon
	
	# Obtener configuración desde el Singleton GameState
	var selected: String = "metralleta"
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		selected = gs.selected_weapon
		
	var weapon_configs: Dictionary = {}
	if gs and "WEAPON_CONFIGS" in gs:
		weapon_configs = gs.WEAPON_CONFIGS
		
	var config: Dictionary = weapon_configs.get(selected, {
		"name": "Metralleta",
		"damage": 10.0,
		"fire_rate": 0.12,
		"max_ammo": 120,
		"clip_size": 30,
		"spread": 0.03,
		"range": 50.0,
		"color": Color(0.2, 0.6, 1.0)
	})
	
	active_weapon.initialize_from_config(config)
	
	# Conectar señales del arma
	active_weapon.weapon_fired.connect(_on_weapon_fired)
	active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	
	# Notificar a la HUD con el sistema de cargador/reserva
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
		
	# Movimiento de cámara con el mouse
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func _process(_delta: float) -> void:
	if is_dead:
		return
		
	# Tecla Escape para salir o liberar cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Presionar R para recargar manualmente
	if Input.is_physical_key_pressed(KEY_R):
		if active_weapon:
			active_weapon.start_reload()

	# Input de disparo continuado o simple
	if Input.is_physical_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		shoot()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Salto (opcional, si se pulsa Espacio o salto de acción)
	if (Input.is_action_just_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_SPACE)) and is_on_floor():
		velocity.y = jump_velocity

	# Dirección del movimiento basada en WASD / Teclas de cursor
	var input_dir: Vector2 = Vector2.ZERO
	
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
		
	input_dir = input_dir.normalized()
	
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
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
			var target: Node = hit["collider"]
			if target and target.has_method("take_damage"):
				target.take_damage(hit["damage"])

func take_damage(amount: float) -> void:
	if is_dead:
		return
		
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
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

func _on_weapon_fired(curr_ammo: int, mx_ammo: int) -> void:
	ammo_changed.emit(curr_ammo, mx_ammo)

func _on_weapon_ammo_changed(curr_ammo: int, mx_ammo: int) -> void:
	ammo_changed.emit(curr_ammo, mx_ammo)
