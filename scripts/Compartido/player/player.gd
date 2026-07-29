extends CharacterBody3D
class_name Player

signal health_changed(current: float, max_val: float)
signal weapon_changed(weapon_name: String, current_ammo: int, max_ammo: int)
signal ammo_changed(current_ammo: int, max_ammo: int)
signal player_died()
signal camera_mode_changed(is_third_person: bool)
signal ads_changed(is_ads: bool)  # Fase 2: ADS toggle

@export var speed: float = 6.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

# ─── Third person camera config ────────────────────────────────────────
@export var third_person_distance: float = 2.0      # Distancia detrás del jugador
@export var third_person_height: float = 1.5        # Altura del pivote (hombro)
@export var third_person_lateral_offset: float = 0.7 # Offset lateral (positivo = derecha, RE4 style)
@export var third_person_smoothing: float = 5.0      # Velocidad de suavizado
@export var third_person_min_distance: float = 0.5   # Distancia mínima al colisionar
# ─── ADS camera config (RE4 style) ──────────────────────────────
@export var ads_lateral_offset: float = 0.3    # Offset lateral al apuntar (más centrado)
@export var ads_distance: float = 1.5          # Distancia al apuntar (más cerca del hombro)

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var is_invisible: bool = false
var is_crouching: bool = false
## Indica si el jugador está sosteniendo el gatillo (para VD).
var _is_firing: bool = false
# Team ID — matches GameState.player_team, used by NPC detection
var equipo_id: int:
	get: return GameState.player_team
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

## Radio del capsule shape leído en _ready() (para step-up assist)
var _capsule_radius: float = 0.65

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
# @onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder  # ELIMINADO (Fase 1)
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var third_person_pivot: Node3D = $ThirdPersonPivot
@onready var spring_arm: SpringArm3D = $ThirdPersonPivot/SpringArm3D
@onready var third_person_camera: Camera3D = $ThirdPersonPivot/ThirdPersonCamera
@onready var wall_detector: RayCast3D = $ThirdPersonPivot/WallDetector
@onready var body_mesh: MeshInstance3D = $MeshInstance3D
@onready var visor_mesh: MeshInstance3D = $MeshInstance3D/VisorMesh
@onready var third_person_weapon_socket: Marker3D = $ThirdPersonWeaponSocket
const BOT_DEBUG_OVERLAY: PackedScene = preload("res://scenes/Multiplayer/objetos/bots/bot_debug_overlay.tscn")

## Componente de estado de arma equipada/guardada (Fase 1).
@onready var weapon_equip_state: WeaponEquipState = $WeaponEquipState
var skin_model: Node3D = null
var model_anim_player: AnimationPlayer = null

## Referencia al AnimationSet activo (para consultar fallbacks, loop, speed en _update_animation).
var _current_anim_set: Resource = null

var _original_height: float = 0.0
var _debug_overlay: Node3D = null
## Timer para animación de hit reaction.
var _hit_timer: float = 0.0

var active_weapon: Weapon = null
@export var is_third_person: bool = false

# ─── ADS (Aim Down Sights) — Fase 2 ──────────────────────────────
var is_ads: bool = false
var _saved_fov: float = 75.0
const ADS_FOV: float = 45.0
const HIP_FOV: float = 75.0

# ─── Weapon aim delay / inertia — Fase 4 ────────────────────────
# Velocidades de rotación del arma (rad/s) según estado
const WEAPON_ROT_SPEED_IDLE: float = 8.0
const WEAPON_ROT_SPEED_WALK: float = 5.0
const WEAPON_ROT_SPEED_RUN: float  = 3.0
const WEAPON_ROT_SPEED_ADS: float  = 12.0
# Límites de rotación del arma relativos al cuerpo
const WEAPON_MAX_H_ANGLE: float = 45.0  # grados
const WEAPON_MAX_V_ANGLE: float = 30.0  # grados

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
	
	# ── Cargar skin/modelo desde SkinManager ────────────────────────
	_load_skin()
	
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
	spring_arm.position.x = third_person_lateral_offset  # Offset lateral inicial
	third_person_camera.current = false
	third_person_camera.position.z = third_person_distance  # Posición inicial
	# Ajustar cámara por personaje después de aplicar valores base.
	_apply_character_camera_config()
	# Sincronizar visibilidad inicial del cuerpo y armas
	_update_body_visibility()


# ══════════════════════════════════════════════════════════════════
# SISTEMA DE SKINS
# ══════════════════════════════════════════════════════════════════

## Carga la skin activa desde SkinManager.
## Si SkinManager no está disponible, no hace nada (el jugador
## funcionará sin modelo visual).
func _apply_character_camera_config() -> void:
	var skin_manager: Node = get_node_or_null("/root/SkinManager")
	if skin_manager == null or not skin_manager.has_method("get_camera_config"):
		return
	var config: Dictionary = skin_manager.get_camera_config()
	var first_person: Dictionary = config.get("first_person", {}) as Dictionary
	var third_person: Dictionary = config.get("third_person", {}) as Dictionary
	head.position.y = float(first_person.get("head_height", head.position.y))
	camera.fov = float(first_person.get("fov", camera.fov))
	third_person_pivot.position.y = float(third_person.get("height", third_person_pivot.position.y))
	spring_arm.spring_length = float(third_person.get("distance", spring_arm.spring_length))
	spring_arm.position.x = float(third_person.get("lateral_offset", spring_arm.position.x))
	third_person_camera.fov = float(third_person.get("fov", third_person_camera.fov))

func _load_skin() -> void:
	var skin_mgr = get_node_or_null("/root/SkinManager")
	if not skin_mgr:
		return
	# SkinManager.apply_skin instancia el modelo y llama _on_skin_applied()
	skin_mgr.apply_skin(self)


## Callback llamado por SkinManager después de instanciar el modelo.
## Configura texturas, animaciones y referencias para el modelo visual.
func _on_skin_applied(skin_data: SkinData, model_instance: Node3D) -> void:
	# ── Guardar referencias al modelo y AnimationPlayer ────────────
	skin_model = model_instance
	
	if skin_data.animation_player_path and not skin_data.animation_player_path.is_empty():
		model_anim_player = model_instance.get_node_or_null(skin_data.animation_player_path) as AnimationPlayer
	if model_anim_player == null:
		model_anim_player = model_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if model_anim_player == null:
		if skin_data.animation_set:
			push_warning("Player: la skin '%s' no tiene AnimationPlayer" % skin_data.id)
	
	# ── Aplicar texturas al mesh (delegado a SkinData) ────────────
	skin_data.apply_textures_to(model_instance)
	
	# ── Cargar animaciones desde AnimationSet ──────────────────────
	if not model_anim_player:
		return
	
	# Si el modelo no declara esqueleto (skin estática), omitimos
	# animaciones esqueléticas silenciosamente.
	if not skin_data.has_skeleton:
		print("Player: skin '%s' es estática (sin Skeleton3D) — omitiendo animaciones esqueléticas" % skin_data.id)
		return
	
	# Verificar que el esqueleto exista realmente en la escena
	if not skin_model.find_child("Skeleton3D", true, false):
		push_warning("Player: skin '%s' declara tener esqueleto pero no se encontró Skeleton3D" % skin_data.id)
		return
	
	# Elegir AnimationSet: el de la skin o el default global
	# Usamos Resource como tipo para evitar dependencias del parser con class_name
	var anim_set = skin_data.animation_set
	if not anim_set:
		anim_set = load("res://Assets/Animaciones/Player/animation_set_default.tres")
	if not anim_set:
		return
	
	_current_anim_set = anim_set
	
	# Garantizar que trabajamos con AnimationSet tipado (único formato soportado)
	var anim_set_typed: AnimationSet = anim_set as AnimationSet
	if not anim_set_typed:
		push_error("Player: anim_set no es un AnimationSet")
		return
	
	var anim_lib: AnimationLibrary = AnimationLibrary.new()
	
	# La lista de animaciones a cargar viene COMPLETA desde el AnimationSet.
	# animation_set_default.tres es el ÚNICO lugar que define qué animaciones
	# existen, su loop mode, fallback y velocidad. No hay duplicación en player.gd.
	var anim_names: Array[String] = anim_set_typed.get_animation_list()
	
	for anim_name: String in anim_names:
		var fbx_filename: String = anim_set_typed.get_filename(anim_name)
		if fbx_filename.is_empty():
			continue
		var fbx_path: String = anim_set_typed.fbx_directory.path_join(fbx_filename)
		var fbx_scene: PackedScene = load(fbx_path) as PackedScene
		if not fbx_scene:
			continue
		var inst: Node = fbx_scene.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("mixamo_com"):
			var src: Animation = ap.get_animation("mixamo_com")
			if src:
				var copy: Animation = src.duplicate(true)
				copy.resource_name = anim_name
				# Leer loop mode desde el AnimationSet (única fuente de verdad)
				copy.loop_mode = anim_set_typed.get_loop_mode(anim_name) as Animation.LoopMode
				anim_lib.add_animation(anim_name, copy)
		inst.queue_free()
	
	# Reemplazar la librería por defecto con la nuestra
	if model_anim_player.has_animation_library(""):
		model_anim_player.remove_animation_library("")
	if anim_lib.get_animation_list().size() > 0:
		model_anim_player.add_animation_library("", anim_lib)


func setup_weapon(nombre_arma: String) -> void:
	# Salir de ADS al cambiar de arma (Fase 2)
	if is_ads:
		is_ads = false
		_apply_ads()
		ads_changed.emit(false)
	# Limpiar el socket antes de instanciar la nueva arma
	for child in third_person_weapon_socket.get_children():
		child.queue_free()

	# Cargar la escena del arma en tiempo de ejecución (no preload)
	var weapon_scene: PackedScene = ResourceLoader.load(
		"res://scenes/Compartido/weapons/weapon_placeholder.tscn",
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
	# El arma real se instancia directamente en ThirdPersonWeaponSocket (Fase 1)
	third_person_weapon_socket.add_child(weapon_instance)
	active_weapon = weapon_instance as Weapon
	if not active_weapon:
		push_error("setup_weapon: weapon_instance no es un Weapon (script no cargado?)")
		return
	active_weapon.initialize_from_name(nombre_arma)
	if not active_weapon.weapon_fired.is_connected(_on_weapon_fired):
		active_weapon.weapon_fired.connect(_on_weapon_fired)
	if not active_weapon.weapon_ammo_changed.is_connected(_on_weapon_ammo_changed):
		active_weapon.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	# Sincronizar el bloqueo de equipamiento con el estado actual (Fase 3)
	_sync_weapon_equip_lock()
	if not weapon_equip_state.equip_state_changed.is_connected(_on_weapon_equip_state_changed):
		weapon_equip_state.equip_state_changed.connect(_on_weapon_equip_state_changed)
	weapon_changed.emit(active_weapon.weapon_name, active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	ammo_changed.emit(active_weapon.ammo_in_mag, active_weapon.reserve_ammo)
	# Sincronizar estado ADS con el arma recién equipada
	_sync_weapon_ads()
	# El arma en ThirdPersonWeaponSocket se muestra según el modo de cámara
	third_person_weapon_socket.visible = true

func cambiar_arma(nombre_arma: String) -> void:
	# Salir de ADS al cambiar de arma (Fase 2)
	if is_ads:
		is_ads = false
		_apply_ads()
		ads_changed.emit(false)
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
	if event.is_action_pressed("toggle_weapon"):
		if weapon_equip_state:
			weapon_equip_state.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ads"):
		toggle_ads()
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
	# Re-aplicar FOV de ADS si está activo (Fase 2)
	if is_ads:
		_apply_ads()

# ─── ADS (Aim Down Sights) — Fase 2 ──────────────────────────────
func toggle_ads() -> void:
	if is_dead:
		return
	if not active_weapon or not is_instance_valid(active_weapon):
		return
	# No ADS para melee o arrojadizas
	if active_weapon.categoria_municion in ["cuerpo_a_cuerpo", "arrojadiza"]:
		return
	is_ads = not is_ads
	_apply_ads()
	_sync_weapon_ads()
	ads_changed.emit(is_ads)

func _apply_ads() -> void:
	var active_cam: Camera3D = third_person_camera if is_third_person else camera
	if not active_cam:
		return
	if is_ads:
		_saved_fov = active_cam.fov
		active_cam.fov = ADS_FOV
	else:
		active_cam.fov = _saved_fov
	# Mantener sincronizado el estado ADS del arma
	_sync_weapon_ads()

# ─── Weapon aim with delay / inertia — Fase 4 ────────────────────

## Actualiza la rotación del arma en cada frame.
## El arma persigue la dirección de la cámara con interpolación suave,
## limitada por ángulos máximos respecto al cuerpo.
func _update_weapon_aim(delta: float) -> void:
	if not active_weapon or not is_instance_valid(active_weapon):
		return
	
	# 1. Dirección objetivo = hacia donde mira la cámara activa
	var cam: Camera3D = third_person_camera if is_third_person else camera
	if not cam:
		return
	var target_dir: Vector3 = -cam.global_transform.basis.z
	
	# 2. Clampear dirección respecto al cuerpo del jugador
	target_dir = _clamp_weapon_direction(target_dir)
	
	# 3. Crear basis objetivo ( -Z apunta a target_dir )
	var target_basis: Basis = Basis.looking_at(target_dir, Vector3.UP)
	
	# 4. Interpolar suavemente hacia el objetivo
	var rot_speed: float = _get_weapon_rotation_speed()
	var t: float = 1.0 - exp(-rot_speed * delta)
	# Ortonormalizar la base actual antes de slerp para evitar
	# acumulación de errores numéricos (Fase 7 - fix)
	var current_basis: Basis = active_weapon.global_transform.basis.orthonormalized()
	active_weapon.global_transform.basis = current_basis.slerp(target_basis, t)


## Clampea una dirección global respecto al forward del jugador.
## El arma no puede apuntar más allá de ±WEAPON_MAX_H_ANGLE° horizontal
## y ±WEAPON_MAX_V_ANGLE° vertical desde el eje -Z del Player.
func _clamp_weapon_direction(global_dir: Vector3) -> Vector3:
	var local_dir: Vector3 = global_transform.basis.inverse() * global_dir
	local_dir = local_dir.normalized()
	
	# Ángulos en espacio local del player (-Z es forward)
	var h_angle: float = atan2(local_dir.x, -local_dir.z)
	var v_angle: float = asin(clamp(local_dir.y, -1.0, 1.0))
	
	h_angle = clamp(h_angle, deg_to_rad(-WEAPON_MAX_H_ANGLE), deg_to_rad(WEAPON_MAX_H_ANGLE))
	v_angle = clamp(v_angle, deg_to_rad(-WEAPON_MAX_V_ANGLE), deg_to_rad(WEAPON_MAX_V_ANGLE))
	
	# Reconstruir dirección en local
	var clamped_local: Vector3 = Vector3(
		sin(h_angle) * cos(v_angle),
		sin(v_angle),
		-cos(h_angle) * cos(v_angle)
	).normalized()
	
	return global_transform.basis * clamped_local


## Multiplicador de velocidad de rotación según categoría del arma (Fase 7).
## Armas más pesadas rotan más lento.
const WEAPON_ROT_CATEGORY_MULTIPLIER: Dictionary = {
	"cuerpo_a_cuerpo": 1.3,  # Muy ligero
	"arrojadiza":      1.2,  # Ligero
	"bala":            1.0,  # Estándar (rifle, pistola)
	"plasma":          0.9,  # Ligeramente pesado
	"perdigones":      0.7,  # Pesado (escopeta)
	"explosiva":       0.55, # Muy pesado (bazooka, lanzagranadas)
}


## Retorna la velocidad de rotación del arma según el estado actual
## y la categoría del arma equipada.
func _get_weapon_rotation_speed() -> float:
	var base_speed: float = WEAPON_ROT_SPEED_IDLE
	if is_ads:
		base_speed = WEAPON_ROT_SPEED_ADS
	else:
		var speed_val: float = velocity.length()
		if speed_val < 0.5:
			base_speed = WEAPON_ROT_SPEED_IDLE
		elif speed_val < 4.0:
			base_speed = WEAPON_ROT_SPEED_WALK
		else:
			base_speed = WEAPON_ROT_SPEED_RUN
	
	# Aplicar multiplicador por categoría del arma
	if active_weapon and is_instance_valid(active_weapon):
		var cat: String = active_weapon.categoria_municion
		var mult: float = WEAPON_ROT_CATEGORY_MULTIPLIER.get(cat, 1.0)
		base_speed *= mult
	
	return base_speed


# ─── Body visibility (1st / 3rd person) ──────────────────────────
func _update_body_visibility() -> void:
	"""El modelo visual está siempre visible (1ª y 3ª persona).
	La cápsula placeholder y el visor están siempre ocultos.
	El arma equipada en ThirdPersonWeaponSocket se ve solo con arma equipada."""
	# Cápsula placeholder — oculta (el modelo real la reemplaza)
	if is_instance_valid(body_mesh):
		body_mesh.visible = false
	# Visor/cabeza placeholder — oculto
	if is_instance_valid(visor_mesh):
		visor_mesh.visible = false
	# Arma del sistema de armas en el socket 3P
	if is_instance_valid(third_person_weapon_socket):
		var equipped: bool = weapon_equip_state.is_equipped if weapon_equip_state else true
		third_person_weapon_socket.visible = equipped
	# Modelo visual visible SIEMPRE (1ª y 3ª persona)
	if is_instance_valid(skin_model):
		skin_model.visible = true

# ─── Teddy Animation Control ──────────────────────────────────────────
## Usa la cadena de fallback definida en el AnimationSet (animation_set_default.tres)
## para garantizar que siempre se reproduzca una animación válida.
func _resolve_animation(anim_name: String) -> String:
	if model_anim_player and model_anim_player.has_animation(anim_name):
		return anim_name
	if _current_anim_set is AnimationSet:
		var fb: String = _current_anim_set.get_fallback(anim_name)
		if fb and fb != anim_name and model_anim_player and model_anim_player.has_animation(fb):
			return fb
		# Intentar con el fallback de forma recursiva (máximo 3 saltos)
		if fb and fb != anim_name:
			var fb2: String = _resolve_animation(fb)
			if model_anim_player and model_anim_player.has_animation(fb2):
				return fb2
	if model_anim_player and model_anim_player.has_animation("idle"):
		return "idle"
	return anim_name

func _update_animation(delta: float = 0.0) -> void:
	"""Elige y reproduce la animación según el estado del personaje."""
	if not model_anim_player or not is_instance_valid(model_anim_player):
		return
	# Si no hay animaciones cargadas (ej: Teddy sin esqueleto), salir
	if model_anim_player.get_animation_list().is_empty():
		return
	var current_anim: String
	if model_anim_player.is_playing():
		current_anim = str(model_anim_player.current_animation)
	else:
		current_anim = ""
	var target_anim: String = "run"

	if is_dead:
		# La animación de muerte ya se disparó desde die()
		return
	
	# ── Prioridad 1: Hit reaction ──
	if _hit_timer > 0.0:
		_hit_timer = max(0.0, _hit_timer - delta)
		target_anim = _resolve_animation("hit")
		if current_anim != target_anim:
			model_anim_player.play(target_anim, 0.05)
		return
	
	if not is_on_floor():
		if velocity.y > 0.0:
			target_anim = _resolve_animation("jump")
		else:
			target_anim = _resolve_animation("jump_loop")
	elif is_crouching:
		if velocity.length() > 0.5:
			target_anim = _resolve_animation("walk_crouch")
		else:
			target_anim = _resolve_animation("idle_crouch")
	elif velocity.length() > 0.5:
		target_anim = _resolve_animation("run")
	else:
		target_anim = _resolve_animation("idle")

	if current_anim != target_anim:
		model_anim_player.play(target_anim, 0.15)

# _setup_third_person_weapon_visual() ELIMINADO (Fase 1) — el arma real
# se instancia directamente en ThirdPersonWeaponSocket.
# _clear_third_person_weapon_visual() ELIMINADO — el socket se limpia en setup_weapon().

# ══════════════════════════════════════════════════════════════════
# SISTEMA DE EQUIPAMIENTO DE ARMA (Fase 3)
# ══════════════════════════════════════════════════════════════════

## Sincroniza el bloqueo de equipamiento del arma activa con el
## estado actual del WeaponEquipState.
func _sync_weapon_equip_lock() -> void:
	if active_weapon and weapon_equip_state:
		active_weapon.set_equip_locked(not weapon_equip_state.is_equipped)


## Se ejecuta cuando WeaponEquipState cambia de estado.
## Actualiza el bloqueo interno del arma para que ni fire() ni
## start_reload() funcionen si el arma está guardada.
## Sincroniza el estado ADS del jugador con el arma activa.
## Cuando el jugador apunta (ADS), el arma reduce su dispersión.
func _sync_weapon_ads() -> void:
	if active_weapon and is_instance_valid(active_weapon):
		active_weapon.is_ads = is_ads

func _on_weapon_equip_state_changed(is_now_equipped: bool) -> void:
	if active_weapon:
		active_weapon.set_equip_locked(not is_now_equipped)
	# Actualizar visibilidad del arma según estado de equipamiento (Fase 1)
	if is_instance_valid(third_person_weapon_socket):
		third_person_weapon_socket.visible = is_now_equipped


# _update_weapon_holder_visibility() ELIMINADO (Fase 1)
# _strip_non_visual_nodes() ELIMINADO (Fase 1)


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
	# Velocidad: agachado → VD (disparando) → VA (arma equipada) → default 6.0
	# Si el arma está guardada (weapon_equip_state), se usa velocidad normal.
	var current_speed: float
	var arma_equipada: bool = active_weapon != null \
		and is_instance_valid(active_weapon) \
		and weapon_equip_state != null \
		and weapon_equip_state.is_equipped

	if is_crouching:
		current_speed = crouch_speed
	elif _is_firing and arma_equipada:
		current_speed = VelocidadesArmas.get_vd(active_weapon.weapon_name)
	elif arma_equipada:
		current_speed = VelocidadesArmas.get_va(active_weapon.weapon_name)
	else:
		current_speed = speed
	
	# ── ADS (Aim Down Sights): la velocidad se reduce a la mitad ──
	if is_ads:
		current_speed *= 0.5
	
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
	# Estilo RE4: la cámara se desplaza al hombro derecho en exploración,
	# y al apuntar (ADS) se centra más y se acerca para mejor puntería.
	if is_third_person:
		# 1. Rotación del pivote: pitch del Head (la cámara hereda el yaw
		#    del Player automáticamente por ser child del Player).
		third_person_pivot.rotation.x = head.rotation.x
		
		# 2. Offset lateral dinámico según ADS (RE4: más centrado al apuntar)
		var target_lateral: float = ads_lateral_offset if is_ads else third_person_lateral_offset
		spring_arm.position.x = target_lateral
		
		# 3. Distancia dinámica según ADS (más cerca al apuntar, sobre el hombro)
		var target_dist: float = ads_distance if is_ads else third_person_distance
		spring_arm.spring_length = target_dist
		
		# 4. Detectar geometría entre el pivote y la posición deseada
		wall_detector.target_position.z = target_dist
		wall_detector.force_raycast_update()

		var desired_z: float = target_dist
		if wall_detector.is_colliding():
			var hit_point: Vector3 = wall_detector.get_collision_point()
			var hit_dist: float = wall_detector.global_position.distance_to(hit_point)
			desired_z = max(hit_dist - spring_arm.margin, third_person_min_distance)

		# 5. Suavizado framerate-independent (ease-out)
		var current_z: float = third_person_camera.position.z
		var smooth_factor: float = 1.0 - exp(-third_person_smoothing * delta)
		third_person_camera.position.z = lerp(current_z, desired_z, smooth_factor)

		# 6. Ocultar visor si la cámara está muy cerca del pivot
		if is_instance_valid(visor_mesh):
			var too_close: bool = third_person_camera.position.z < 1.5
			visor_mesh.visible = not too_close

	# ── Animation update ──────────────────────────────────────────────
	_update_animation(delta)

func shoot() -> void:
	if not active_weapon:
		return
	if active_weapon.can_fire():
		var categoria: String = active_weapon.categoria_municion

		# ── El arma ya está apuntando gracias a _update_weapon_aim() (Fase 4) ──
		# La rotación con delay/inercia se actualiza cada frame en _process().
		# Al disparar, el arma ya mira aproximadamente hacia aim_target.

		# ── Disparar — sin overrides (Fase 3) ────────────────────────────
		# El arma usa su propio RayCast3D (hit-scan) o su cañón (proyectiles)
		# que ahora apuntan hacia aim_target porque rotamos el arma.
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
		# BotBase padre subiendo en el arbol.
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


# _aim_weapon_at() ELIMINADO (Fase 4) — reemplazado por _update_weapon_aim() en _process()

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
## NOTA: Ya no es llamado desde shoot() (Fase 3 — los proyectiles salen del cañón).
## Se mantiene como utilidad por si algún sistema externo lo necesita.
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
	# Disparar hit reaction (0.433s = duración de hit reaction.fbx)
	if not is_dead:
		_hit_timer = 0.433
	if current_health <= 0.0:
		die(killer_id)

func die(killer_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	
	# Reproducir animación de muerte (con fallback desde AnimationSet)
	if is_instance_valid(model_anim_player):
		var death_anim: String = _resolve_animation("death")
		if model_anim_player.has_animation(death_anim):
			model_anim_player.play(death_anim, 0.1)
	
	# Salir de ADS al morir (Fase 2)
	if is_ads:
		is_ads = false
		_apply_ads()
		ads_changed.emit(false)
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

func _process(delta: float) -> void:
	if is_dead:
		return
	
	# ── Sincronizar ADS con el arma activa ──────────────────────────
	if active_weapon and is_instance_valid(active_weapon):
		if active_weapon.is_ads != is_ads:
			_sync_weapon_ads()
	
	# ── Rotación del arma con delay/inercia (Fase 4) ─────────────────
	# El arma persigue la dirección de la cámara con interpolación suave
	if active_weapon and is_instance_valid(active_weapon) and third_person_weapon_socket.visible:
		_update_weapon_aim(delta)
	
	# ── Estado de disparo (para VD) ──────────────────────────────────
	_is_firing = Input.is_action_pressed("shoot") \
		and active_weapon != null \
		and is_instance_valid(active_weapon) \
		and weapon_equip_state \
		and weapon_equip_state.can_shoot() \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	# ── Manejar arma activa (disparo/recarga) ────────────────────────
	if active_weapon and weapon_equip_state:
		if Input.is_action_pressed("reload") and weapon_equip_state.can_reload():
			active_weapon.start_reload()
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if Input.is_action_pressed("shoot") and weapon_equip_state.can_shoot():
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
