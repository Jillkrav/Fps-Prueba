extends CharacterBody3D
class_name Player

signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()
signal camera_mode_changed(is_third_person: bool)

@export var speed: float = 6.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# ─── Third person camera config ────────────────────────────────────────
@export var third_person_distance: float = 3.0      # Distancia detrás del jugador
@export var third_person_height: float = 1.5        # Altura del pivote
@export var third_person_lateral_offset: float = 0.0 # Offset lateral (positivo = derecha)
@export var third_person_smoothing: float = 5.0      # Velocidad de suavizado
@export var third_person_min_distance: float = 0.5   # Distancia mínima al colisionar

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var is_invisible: bool = false
var is_crouching: bool = false
# Team ID — matches GameState.player_team, used by NPC detection
var equipo_id: int:
	get: return GameState.player_team
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

## Radio del capsule shape leído en _ready() (para step-up assist)
var _capsule_radius: float = 0.65

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var third_person_pivot: Node3D = $ThirdPersonPivot
@onready var spring_arm: SpringArm3D = $ThirdPersonPivot/SpringArm3D
@onready var third_person_camera: Camera3D = $ThirdPersonPivot/ThirdPersonCamera
@onready var wall_detector: RayCast3D = $ThirdPersonPivot/WallDetector
@onready var body_mesh: MeshInstance3D = $MeshInstance3D
@onready var visor_mesh: MeshInstance3D = $MeshInstance3D/VisorMesh
@onready var third_person_weapon_socket: Marker3D = $ThirdPersonWeaponSocket
const BOT_DEBUG_OVERLAY: PackedScene = preload("res://scenes/npcs/bot_debug_overlay.tscn")

var _original_height: float = 0.0
var _debug_overlay: Node3D = null

var active_weapon: Weapon = null
@export var is_third_person: bool = false

# ─── Step-up assist state ──────────────────────────────────────────
# (cooldown no necesario: el impulso se aplica continuamente mientras se detecta el escalón)

# ─── Vault / Step-up 2 ────────────────────────────────────────────────────
## Controlador de vaulting para objetos más grandes que el step-up assist.
var _vault_controller: VaultController = null

## Indica si hay un obstáculo vaultable disponible (para icono HUD).
var vault_available: bool = false
## Se emite cuando cambia la disponibilidad del vault.
signal vault_availability_changed(available: bool)

# ─── Pickup confirmation system ──────────────────────────────────────────
## Referencia al pickup pendiente de confirmación (arma diferente).
var _pending_pickup: Node = null
## Distancia máxima para mantener el prompt de confirmación.
const _PICKUP_CONFIRM_RANGE: float = 3.0

func _ready() -> void:
	add_to_group("player")
	max_health = ConfigManager.salud_jugador
	current_health = max_health
	# ── Step-up: configurar CharacterBody3D para movimiento natural ────
	# El factor MÁS importante es el radio de la cápsula (0.65 en escena).
	# El step-up interno de move_and_slide() escala con el radio de la
	# forma de colisión. Radio 0.65 → step máximo ≈ 0.42 unidades.
	motion_mode = MotionMode.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(48.0)   # 45° default + 3° margen para rampas/bordes
	floor_block_on_wall = false          # NO bloquearse en paredes — las caras
										 # laterales de rampas CSGBox3D no
										 # deben detener al jugador. El step-up
										 # nativo funciona sin este bloqueo.
	floor_constant_speed = true          # Velocidad constante en pendientes
	floor_stop_on_slope = true           # No deslizarse en pendientes
	
	# Leer radio real de la cápsula para step-up assist
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		_capsule_radius = collision_shape.shape.radius
	# FIX: usar GameState directamente en lugar de get_node con cast inseguro
	if GameState.player_team == int(Enums.Equipo.ESPECTADOR):
		GameState.player_team = int(Enums.Equipo.AZUL)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# El arma se equipa externamente (DevMenu, team_weapon_selector, etc.)
	active_weapon = null
	# ── Vault controller (step-up 2) ──
	_vault_controller = VaultController.new()
	_vault_controller.setup(self)
	health_changed.emit(current_health, max_health)
	_setup_debug_overlay()

	# ── Third person camera setup ──────────────────────────────────
	# SpringArm3D: solo capa 1 (geometría del mundo), excluye al Player
	spring_arm.spring_length = third_person_distance
	spring_arm.collision_mask = 1
	spring_arm.margin = 0.15
	spring_arm.add_excluded_object(get_rid())
	# WallDetector: mismo alcance y máscara que el SpringArm3D
	wall_detector.target_position.z = third_person_distance
	wall_detector.collision_mask = 1
	wall_detector.hit_from_inside = true
	# Posición del pivote y cámara
	third_person_pivot.position.y = third_person_height
	third_person_camera.current = false
	third_person_camera.position.z = third_person_distance  # Posición inicial
	# Sincronizar visibilidad inicial del cuerpo y armas
	_update_body_visibility()

func setup_weapon(nombre_arma: String) -> void:
	for child in weapon_holder.get_children():
		child.queue_free()

	# Cargar la escena del arma en tiempo de ejecución (no preload)
	# para evitar problemas de compilación encadenada con autoloads.
	var weapon_scene: PackedScene = ResourceLoader.load(
		"res://scenes/weapons/weapon_placeholder.tscn",
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if not weapon_scene:
		push_error("setup_weapon: No se pudo cargar weapon_placeholder.tscn")
		return
	var weapon_instance: Node = weapon_scene.instantiate()
	if not weapon_instance:
		push_error("setup_weapon: weapon_scene.instantiate() devolvió null")
		return
	weapon_holder.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon
	if not active_weapon:
		push_error("setup_weapon: weapon_instance no es un Weapon (script no cargado?)")
		return
	active_weapon.initialize_from_name(nombre_arma)
	if not active_weapon.weapon_fired.is_connected(_on_weapon_fired):
		active_weapon.weapon_fired.connect(_on_weapon_fired)
	if not active_weapon.weapon_ammo_changed.is_connected(_on_weapon_ammo_changed):
		active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	# Crear/sincronizar el visual de tercera persona
	_setup_third_person_weapon_visual()

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
	if event.is_action_pressed("toggle_third_person"):
		toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameState.mouse_sensitivity
		var invert_y: float = -1.0 if GameState.mouse_invert_y else 1.0
		rotate_y(-event.relative.x * sens)
		head.rotate_x(event.relative.y * sens * invert_y)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))

# ─── Camera mode toggle (1st / 3rd person) ──────────────────────────
func toggle_camera_mode() -> void:
	if is_dead:
		return
	set_camera_mode(not is_third_person)

func set_camera_mode(enable_third_person: bool) -> void:
	if is_dead:
		return
	if enable_third_person == is_third_person:
		return
	is_third_person = enable_third_person
	_apply_camera_mode()

func _apply_camera_mode() -> void:
	if is_third_person:
		camera.current = false
		third_person_camera.current = true
	else:
		third_person_camera.current = false
		camera.current = true
	_update_body_visibility()
	camera_mode_changed.emit(is_third_person)

# ─── Body visibility (1st / 3rd person) ──────────────────────────
func _update_body_visibility() -> void:
	"""Muestra/oculta el mesh del cuerpo según el modo de cámara.
	En tercera persona el cuerpo es visible; en primera se oculta.
	El visor/cabeza se oculta si la cámara 3P está demasiado cerca."""
	if not is_instance_valid(body_mesh):
		return
	body_mesh.visible = is_third_person
	# Ocultar visor cuando la cámara está cerca del pivot (evita clipping)
	if is_instance_valid(visor_mesh):
		var too_close: bool = is_third_person and third_person_camera.position.z < 1.5
		visor_mesh.visible = is_third_person and not too_close
	# Weapon visuals: 1P en primera persona, 3P en tercera persona
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = not is_third_person
	if is_instance_valid(third_person_weapon_socket):
		third_person_weapon_socket.visible = is_third_person

# ─── Third person weapon visual ──────────────────────────────────
func _setup_third_person_weapon_visual() -> void:
	"""Crea una copia visual del arma actual para tercera persona.
	Solo incluye MeshInstance3D (sin RayCast3D, Area3D, Audio, ni script)."""
	_clear_third_person_weapon_visual()
	if not active_weapon or not is_instance_valid(active_weapon):
		return
	# Cargar la misma escena del arma
	var weapon_scene: PackedScene = ResourceLoader.load(
		"res://scenes/weapons/weapon_placeholder.tscn",
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if not weapon_scene:
		return
	var visual: Node3D = weapon_scene.instantiate()
	visual.set_script(null)  # Eliminar toda la lógica
	_strip_non_visual_nodes(visual)
	visual.name = active_weapon.weapon_name + "_3P"
	third_person_weapon_socket.add_child(visual)
	third_person_weapon_socket.visible = is_third_person

func _clear_third_person_weapon_visual() -> void:
	"""Elimina el visual 3P anterior."""
	for child in third_person_weapon_socket.get_children():
		child.queue_free()

func _strip_non_visual_nodes(node: Node) -> void:
	"""Elimina recursivamente nodos de lógica (no visuales) de la copia."""
	var children: Array[Node] = node.get_children()
	for child in children:
		if child is RayCast3D or child is Area3D or child is AudioStreamPlayer3D:
			child.queue_free()
		else:
			_strip_non_visual_nodes(child)


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

	# ── Jump & Vault (step-up 2) ──────────────────────────────────────
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var vault_check_dir: Vector3 = direction if direction.length_squared() > 0.01 else -global_transform.basis.z
	
	# ── Verificar disponibilidad de vault (para HUD) ────────────────
	var was_vault_available: bool = vault_available
	vault_available = false
	if _vault_controller and is_on_floor() and not _vault_controller.is_vaulting():
		vault_available = _vault_controller.can_vault(vault_check_dir, current_time)
		# Solo mostrar el indicador si hay intención de movimiento (input_dir > 0)
		# o si el jugador está mirando activamente hacia el obstáculo
		if input_dir.length() < 0.1:
			vault_available = false
	if vault_available != was_vault_available:
		vault_availability_changed.emit(vault_available)
	
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		if vault_available and _vault_controller and _vault_controller.try_vault(vault_check_dir, current_time):
			vault_available = false
			vault_availability_changed.emit(false)  # Ocultar HUD inmediatamente
		else:
			velocity.y = jump_velocity

	# ── Movement ───────────────────────────────────────────────────────
	var current_speed: float = crouch_speed if is_crouching else speed
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
	
	# ── Step-up assist ═════════════════════════════════════════════════
	# Dos raycasts horizontales detectan escalones/obstáculos delante
	# del personaje midiendo la altura REAL del escalón:
	#   - RAY BAJO: desde 0.15 u. sobre los pies → detecta cara vertical
	#   - RAY ALTO: desde altura máxima escalable → verifica espacio libre
	# Si el bajo impacta y el alto no → hay un escalón subible.
	# Se aplica impulso vertical continuo mientras dure el contacto.
	if is_on_floor():
		var input_len: float = Vector2(input_dir.x, input_dir.y).length()
		if input_len > 0.1:
			var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
			var check_dist: float = _capsule_radius + 0.3
			
			# RAY BAJO: detecta cara vertical del escalón (0.15 u. sobre pies)
			var low_origin: Vector3 = global_position + Vector3(0, 0.15, 0)
			var low_end: Vector3 = low_origin + direction * check_dist
			var low_query = PhysicsRayQueryParameters3D.create(low_origin, low_end)
			low_query.collision_mask = collision_mask
			low_query.exclude = [self]
			var low_hit: Dictionary = space_state.intersect_ray(low_query)
			
			# RAY ALTO: verifica espacio libre arriba del escalón
			var top_h: float = _capsule_radius * 1.2
			var high_origin: Vector3 = global_position + Vector3(0, top_h, 0)
			var high_end: Vector3 = high_origin + direction * check_dist
			var high_query = PhysicsRayQueryParameters3D.create(high_origin, high_end)
			high_query.collision_mask = collision_mask
			high_query.exclude = [self]
			var high_hit: Dictionary = space_state.intersect_ray(high_query)
			
			# Step detectado: bajo impacta (cara vertical) Y alto NO impacta (paso libre)
			if not low_hit.is_empty() and high_hit.is_empty():
				if low_hit.normal.y < 0.3:  # Cara vertical
					velocity.y = max(velocity.y, 3.0)  # Impulso fuerte y continuo
	
	# ── Vault / Step-up 2 — procesar si está en curso ────────────────────
	if _vault_controller and _vault_controller.is_vaulting():
		_vault_controller.process_vault(delta, current_time)
		vault_available = false
		move_and_slide()
		return
	
	move_and_slide()

	# ── Third person camera: pivot sync + collision + smoothing ═══════
	if is_third_person:
		# 1. Rotación del pivote: pitch del Head (la cámara hereda el yaw
		#    del Player automáticamente por ser child del Player).
		third_person_pivot.rotation.x = head.rotation.x
		if third_person_lateral_offset != 0.0:
			spring_arm.position.x = third_person_lateral_offset

		# 2. Detectar geometría entre el pivote y la posición deseada
		wall_detector.target_position.z = third_person_distance
		wall_detector.force_raycast_update()

		var desired_z: float = third_person_distance
		if wall_detector.is_colliding():
			var hit_point: Vector3 = wall_detector.get_collision_point()
			var hit_dist: float = wall_detector.global_position.distance_to(hit_point)
			desired_z = max(hit_dist - spring_arm.margin, third_person_min_distance)

		# 3. Suavizado framerate-independent (ease-out)
		var current_z: float = third_person_camera.position.z
		var smooth_factor: float = 1.0 - exp(-third_person_smoothing * delta)
		third_person_camera.position.z = lerp(current_z, desired_z, smooth_factor)

		# 4. Ocultar visor si la cámara está muy cerca del pivot
		if is_instance_valid(visor_mesh):
			var too_close: bool = third_person_camera.position.z < 1.5
			visor_mesh.visible = not too_close

func shoot() -> void:
	if not active_weapon:
		return
	if active_weapon.can_fire():
		var categoria: String = active_weapon.categoria_municion
		# Un único punto de apuntado desde la cámara activa
		var aim_target: Vector3 = _get_aim_target()

		# ── Hit-scan (balas, perdigones): muzzle → aim_target ────────────
		if categoria in ["bala", "perdigones"]:
			# El override hace que perform_raycast_with_spread() apunte
			# desde el RayCast3D del arma hacia aim_target, detectando
			# paredes intermedias entre el muzzle y el objetivo.
			active_weapon.override_hitscan_target(aim_target)

		# ── Proyectiles físicos: spawn delante de cámara → aim_target ───
		elif categoria in ["arrojadiza", "explosiva", "plasma"]:
			var shoot_pos: Vector3 = _get_shoot_position()
			var shoot_dir: Vector3 = (aim_target - shoot_pos).normalized()
			active_weapon.set_shoot_override(shoot_pos, shoot_dir)

		# ── Melee: sin override (usa Area3D del arma directamente) ───────
		# (cuerpo_a_cuerpo se maneja 100% desde _fire_melee en weapon.gd)

		var hits: Array = active_weapon.fire()

		# ── Hit-scan: procesar hits directamente ──────────────────────────
		# (melee y proyectiles aplican su daño desde weapon.gd/projectile)
		if categoria in ["bala", "perdigones"]:
			_process_hits(hits)
		# ── Proyectiles: el daño lo gestiona el proyectil al impactar ────
		# (projectile_base.gd llama a target.take_damage en on_hit)

# ─── Procesamiento de daño hit-scan ────────────────────────────────────
func _process_hits(hits: Array) -> void:
	var killer_id: int = -1
	if is_instance_valid(MatchManager):
		killer_id = MatchManager.get_player_id_by_pawn(self)
	for hit in hits:
		var target_node: Node = hit.get("collider")
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
			var dmg: float = hit.get("damage_vs_npc", 0.0)
			if target_node is Player:
				dmg = hit.get("damage_vs_player", 0.0)
			target_node.take_damage(dmg, "Torso", killer_id)


## Devuelve el punto del mundo al que apunta el crosshair.
## Raycast desde la cámara activa (1P o 3P) hasta el alcance del arma.
## Ignora al propio Player y sus nodos de colisión internos.
func _get_aim_target() -> Vector3:
	var active_cam: Camera3D = third_person_camera if is_third_person else camera
	if not active_cam:
		return global_position - global_transform.basis.z * 50.0
	var cam_pos: Vector3 = active_cam.global_position
	var cam_dir: Vector3 = -active_cam.global_transform.basis.z
	var alcance: float = active_weapon.weapon_range if active_weapon and is_instance_valid(active_weapon) else 50.0
	var end_pos: Vector3 = cam_pos + cam_dir * alcance
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam_pos, end_pos)
	query.collision_mask = collision_mask  # Capas 1, 3, 4 (mundo, NPCs, pickups)
	# Excluir Player, arma y todo nodo con colisión física
	var exclude_rids: Array[RID] = [get_rid()]
	if active_weapon and is_instance_valid(active_weapon):
		_collect_collision_rids(active_weapon, exclude_rids)
	query.exclude = exclude_rids
	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.get("position", end_pos)


## Recolecta recursivamente RIDs de nodos CollisionObject3D (Area3D, PhysicsBody3D).
func _collect_collision_rids(node: Node, rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	for child: Node in node.get_children():
		_collect_collision_rids(child, rids)


## Devuelve la posición desde donde debe salir un proyectil.
## Usa la cámara activa (1P o 3P) como origen.
## Incluye safety check anti-pared: si la posición queda dentro de geometría,
## la desplaza justo delante de la superficie.
func _get_shoot_position() -> Vector3:
	var active_cam: Camera3D = third_person_camera if is_third_person else camera
	if not active_cam:
		return global_position + Vector3(0, 1.5, 0)
	var pos: Vector3 = active_cam.global_position - active_cam.global_transform.basis.z * 0.5
	# Safety: verificar que no spawn dentro de una pared
	var fwd: Vector3 = -active_cam.global_transform.basis.z
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var check := PhysicsRayQueryParameters3D.create(pos, pos + fwd * 0.3)
	check.collision_mask = 1  # Solo geometría del mundo
	check.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(check)
	if not hit.is_empty():
		pos = hit.position + hit.normal * 0.05
	return pos


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
	_update_body_visibility()
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
	_update_body_visibility()
	_setup_debug_overlay()

func change_team(new_team: int) -> bool:
	"""
	Cambia de equipo usando el sistema unificado del MatchManager.
	El flujo es: cambiar equipo internamente -> morir -> respawn automatico
	Esto asegura que el jugador reaparezca en la base del nuevo equipo.
	"""
	if not is_instance_valid(MatchManager):
		return false
	var result: bool = MatchManager.cambiar_equipo_jugador(new_team)
	_update_body_visibility()
	return result

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
