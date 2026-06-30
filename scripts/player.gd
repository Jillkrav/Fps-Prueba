extends CharacterBody3D
class_name Player

signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()

@export var speed: float = 6.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var is_invisible: bool = false
var is_crouching: bool = false
# Team ID — matches GameState.player_team, used by NPC detection
var equipo_id: int:
	get: return GameState.player_team
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var weapon_placeholder_scene: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")
const BOT_DEBUG_OVERLAY: PackedScene = preload("res://scenes/npcs/bot_debug_overlay.tscn")

var _original_height: float = 0.0
var _debug_overlay: Node3D = null

var active_weapon: Weapon = null

# ─── Pickup confirmation system ──────────────────────────────────────────
## Referencia al pickup pendiente de confirmación (arma diferente).
var _pending_pickup: Node = null
## Distancia máxima para mantener el prompt de confirmación.
const _PICKUP_CONFIRM_RANGE: float = 3.0

func _ready() -> void:
	add_to_group("player")
	max_health = ConfigManager.salud_jugador
	current_health = max_health
	# FIX: usar GameState directamente en lugar de get_node con cast inseguro
	if GameState.player_team == int(Enums.Equipo.ESPECTADOR):
		GameState.player_team = int(Enums.Equipo.AZUL)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# El arma se equipa externamente (DevMenu, team_weapon_selector, etc.)
	active_weapon = null
	health_changed.emit(current_health, max_health)
	_setup_debug_overlay()

func setup_weapon(nombre_arma: String) -> void:
	for child in weapon_holder.get_children():
		child.queue_free()
	var weapon_instance: Node = weapon_placeholder_scene.instantiate()
	weapon_holder.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon
	active_weapon.initialize_from_name(nombre_arma)
	if not active_weapon.weapon_fired.is_connected(_on_weapon_fired):
		active_weapon.weapon_fired.connect(_on_weapon_fired)
	if not active_weapon.weapon_ammo_changed.is_connected(_on_weapon_ammo_changed):
		active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)

func cambiar_arma(nombre_arma: String) -> void:
	if not is_instance_valid(active_weapon):
		setup_weapon(nombre_arma)
		return
	if active_weapon.weapon_fired.is_connected(_on_weapon_fired):
		active_weapon.weapon_fired.disconnect(_on_weapon_fired)
	if active_weapon.weapon_ammo_changed.is_connected(_on_weapon_ammo_changed):
		active_weapon.weapon_ammo_changed.disconnect(_on_weapon_ammo_changed)
	active_weapon.initialize_from_name(nombre_arma)
	active_weapon.weapon_fired.connect(_on_weapon_fired)
	active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	GameState.selected_weapon = nombre_arma

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameState.mouse_sensitivity
		var invert_y: float = -1.0 if GameState.mouse_invert_y else 1.0
		rotate_y(-event.relative.x * sens)
		head.rotate_x(event.relative.y * sens * invert_y)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	# ── Crouch ─────────────────────────────────────────────────────────
	var was_crouching: bool = is_crouching
	is_crouching = Input.is_action_pressed("crouch")
	if is_crouching and not was_crouching:
		# Reducir altura del collision shape
		if collision_shape and collision_shape.shape is CapsuleShape3D:
			var shape: CapsuleShape3D = collision_shape.shape
			_original_height = shape.height
			shape.height = _original_height * 0.5
			head.position.y = shape.height * 0.5
	elif not is_crouching and was_crouching:
		# Restaurar altura
		if collision_shape and collision_shape.shape is CapsuleShape3D and _original_height > 0.0:
			var shape: CapsuleShape3D = collision_shape.shape
			shape.height = _original_height
			head.position.y = shape.height * 0.5

	# ── Jump ───────────────────────────────────────────────────────────
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	# ── Movement ───────────────────────────────────────────────────────
	var current_speed: float = crouch_speed if is_crouching else speed
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	move_and_slide()

func shoot() -> void:
	if not active_weapon:
		return
	if active_weapon.can_fire():
		var hits: Array = active_weapon.fire()
		var killer_id: int = -1
		if is_instance_valid(MatchManager):
			killer_id = MatchManager.get_player_id_by_pawn(self)
		for hit in hits:
			var target_node: Node = hit["collider"]
			if not target_node:
				continue
			# Si el collider es un Area3D (hitbox como HeadHitbox), buscar el
			# NpcBase padre subiendo en el arbol.
			if target_node is Area3D:
				var parent: Node = target_node.get_parent()
				while parent:
					if parent.has_method("take_damage"):
						target_node = parent
						break
					parent = parent.get_parent()
			if target_node.has_method("take_damage"):
				if target_node is Player:
					target_node.take_damage(hit["damage_vs_player"], "Torso", killer_id)
				else:
					target_node.take_damage(hit["damage_vs_npc"], "Torso", killer_id)

func take_damage(amount: float, zona: String = "Torso", killer_id: int = -1) -> void:
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
		die(killer_id)

func die(killer_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_died.emit()
	# Reportar la muerte al MatchManager para estadisticas + respawn unificado
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(self, killer_id)
		MatchManager.reportar_muerte_player()

func respawn() -> void:
	is_dead = false
	current_health = max_health
	
	# Restaurar municion al maximo (cargador + reserva)
	if active_weapon:
		active_weapon.resupply()
		ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	
	# Teletransportar al spawn point del equipo actual
	if is_instance_valid(MatchManager):
		var spawn: Marker3D = MatchManager.obtener_spawn_point(GameState.player_team)
		if spawn:
			global_position = spawn.global_position
	
	# Re-habilitar controles
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(current_health, max_health)
	_setup_debug_overlay()

func change_team(new_team: int) -> bool:
	"""
	Cambia de equipo usando el sistema unificado del MatchManager.
	El flujo es: cambiar equipo internamente -> morir -> respawn automatico
	Esto asegura que el jugador reaparezca en la base del nuevo equipo.
	"""
	if not is_instance_valid(MatchManager):
		return false
	return MatchManager.cambiar_equipo_jugador(new_team)

func resupply() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
	if active_weapon:
		active_weapon.resupply()
		ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)

# ─── Debug Overlay (Propiedades de unidad) ─────────────────────────────
func _setup_debug_overlay() -> void:
	if BotDebugOverlay.enabled:
		_add_debug_overlay()
	else:
		_remove_debug_overlay()

func _add_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return
	var overlay: Node3D = BOT_DEBUG_OVERLAY.instantiate()
	add_child(overlay)
	_debug_overlay = overlay

func _remove_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
		_debug_overlay = null

# ─── Pickup System ─────────────────────────────────────────────────────
## Llamado por el Pickup cuando el jugador entra en su área de recogida.
func _on_pickup_area_entered(pickup: Node) -> void:
	if is_dead:
		return
	if not is_instance_valid(pickup):
		return
	
	# ── Solo interceptar pickups de armas ────────────────────────────
	if pickup is WeaponPickup:
		_handle_weapon_pickup_area(pickup)
		return
	
	# ── Pickups no-arma: recoger inmediatamente ──────────────────────
	pickup.pick_up(self)

## Maneja la entrada al área de un arma en el suelo.
func _handle_weapon_pickup_area(pickup: Node) -> void:
	if not is_instance_valid(pickup):
		return
	
	var weapon_name: String = pickup.pickup_data.get("tipo_arma", "")
	if weapon_name == "":
		return
	
	# ── Caso A: El jugador ya tiene esta misma arma → auto-recoger (munición)
	var tiene_misma_arma: bool = false
	if active_weapon and is_instance_valid(active_weapon):
		tiene_misma_arma = active_weapon.weapon_name.to_lower() == weapon_name.to_lower()
	
	if tiene_misma_arma:
		# Si hay un prompt pendiente de otra arma, cancelarlo
		_cancel_pending_pickup()
		# Recoger inmediatamente (solo suma munición)
		pickup.pick_up(self)
		return
	
	# ── Caso B: Arma diferente → mostrar prompt de confirmación
	# Cancelar cualquier prompt anterior
	_cancel_pending_pickup()
	
	_pending_pickup = pickup
	
	# Mostrar prompt en HUD
	var current_weapon_name: String = ""
	if active_weapon and is_instance_valid(active_weapon):
		current_weapon_name = active_weapon.weapon_name
	
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_weapon_prompt"):
		hud.show_weapon_prompt(weapon_name, current_weapon_name)

## El jugador salió del área de recogida — cancelar el prompt.
func _on_pickup_area_exited(pickup: Node) -> void:
	if _pending_pickup == pickup:
		_cancel_pending_pickup()

## Cancela el prompt de recogida actual.
func _cancel_pending_pickup() -> void:
	if _pending_pickup:
		_pending_pickup = null
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("hide_weapon_prompt"):
			hud.hide_weapon_prompt()

## Confirma la recogida del arma pendiente.
func _confirm_pending_pickup() -> void:
	if not _pending_pickup or not is_instance_valid(_pending_pickup):
		_cancel_pending_pickup()
		return
	
	var pickup: Node = _pending_pickup
	_pending_pickup = null
	
	# Ocultar prompt
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("hide_weapon_prompt"):
		hud.hide_weapon_prompt()
	
	# Recoger el arma
	pickup.pick_up(self)

func _process(_delta: float) -> void:
	if is_dead:
		return
	
	# ── Manejar arma activa (disparo/recarga) ────────────────────────
	if active_weapon:
		if Input.is_action_pressed("reload"):
			active_weapon.start_reload()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if Input.is_action_pressed("shoot"):
				shoot()
	
	# ── Confirmar recogida pendiente ─────────────────────────────────
	if _pending_pickup and Input.is_action_just_pressed("interact"):
		_confirm_pending_pickup()
	
	# ── Verificar distancia al pickup pendiente ──────────────────────
	if _pending_pickup and is_instance_valid(_pending_pickup):
		var dist: float = global_position.distance_to(_pending_pickup.global_position)
		if dist > _PICKUP_CONFIRM_RANGE:
			_cancel_pending_pickup()

func _on_weapon_fired(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)

func _on_weapon_ammo_changed(curr: int, mx: int) -> void:
	ammo_changed.emit(curr, mx)
