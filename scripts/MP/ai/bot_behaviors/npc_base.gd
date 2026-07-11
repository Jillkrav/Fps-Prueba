# scripts/npc_base.gd
# Base class for all NPCs. Orchestrator de sistemas modulares (Fase 8).
extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# EXPORTS & CONFIG
# ─────────────────────────────────────────

@export var equipo_id: int = int(Enums.Equipo.ROJO)
@export var nombre_arma: String = "USP"
@export var experiencia: int = int(Enums.Experiencia.MEDIA)
@export var rol: int = int(Enums.Rol.SOLDADO)

# ─────────────────────────────────────────
# REFERENCIAS A SISTEMAS MODULARES
# ─────────────────────────────────────────

## Sistema de percepción (FASE 1). ÚNICO escritor de sensor_data.
var perception_sys: PerceptionSystem = null

## Sistema de memoria (FASE 1). ÚNICO escritor de memory_store.
var memory_sys: MemorySystem = null

## Sistema de navegación. Gestiona el NavigationAgent3D.
var navigation_sys: NavigationSystem = null

## Sistema de movimiento (FASE 2). ÚNICO escritor de velocity.
var movement_sys: MovementSystem = null

## Sistema de decisión FSM (FASE 3). ÚNICO escritor de target_entity,
## movement_command y combat_command.
var decision_sys: DecisionSystem = null

## Sistema de combate (FASE 4). ÚNICO escritor de aim_rotation.
var combat_sys: CombatSystem = null

## Sistema de armas (FASE 5). Gestiona selección táctica y perfiles AI.
var weapon_sys: WeaponSystem = null

# ── Estado del NPC ────────────────────────
var is_dead: bool = false
var max_health: float = 100.0
var current_health: float = 100.0
var is_invisible: bool = false

# ── Freeze state ──────────────────────────
## El NPC está congelado (no se mueve, no procesa IA).
var is_frozen: bool = false
## Timer interno para descongelar automáticamente.
var _frozen_timer: SceneTreeTimer = null

# ── Jump-to-green-cube state ──────────────
## Posición inicial del salto hacia el green cube.
var _jump_start_pos: Vector3 = Vector3.ZERO
## Posición destino (green cube).
var _jump_target_pos: Vector3 = Vector3.ZERO
## Progreso del salto (0.0 → 1.0).
var _jump_progress: float = 0.0
## Duración total del salto en segundos.
var _jump_duration: float = 1.5
## Altura máxima del arco parabólico.
var _jump_arc_height: float = 3.0
## Si está realizando el salto hacia el green cube.
var _is_jumping_to_green: bool = false
## Si está realizando el salto hacia el yellow cube.
var _is_jumping_to_yellow: bool = false

# ── Core / Objective System ──────────────
var _enemy_core: Node3D = null
var _is_attacking_core: bool = false
var _team_objective: Vector3 = Vector3.ZERO

# ── TeamAI / Order System (FASE 6) ───────
# ── Tactical Role ────────────────────────
var _tactical_role = null

var current_order_type: int = -1
var current_order_name: String = "--"
var current_order_target: Vector3 = Vector3.ZERO

# ── Components ────────────────────────────
var _weapon: Weapon = null
const DROPPED_WEAPON: PackedScene = preload("res://scenes/pickups/dropped_weapon.tscn")
const DEBUG_OVERLAY: PackedScene = preload("res://scenes/npcs/bot_debug_overlay.tscn")
var _debug_overlay: Node3D = null

# ── Pickup system ─────────────────────────
var _pickup_target: Node = null
var _pickup_check_timer: float = 0.0

var _npc_id: int = 0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var area_vision: Area3D = $AreaVision
@onready var raycast_vision: RayCast3D = $RaycastVision
@onready var head: Node3D = $Head
@onready var _pickup_manager = get_node("/root/PickupManager")

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	_npc_id = randi() % 9000 + 1000
	add_to_group("npc")
	
	# ── Step-up: configurar CharacterBody3D para movimiento natural ────
	# El factor MÁS importante es el radio de la cápsula (0.65 en escena).
	# El step-up interno de move_and_slide() escala con el radio de la
	# forma de colisión. Radio 0.65 → step máximo ≈ 0.42 unidades.
	motion_mode = MotionMode.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(50.0)   # 50° para rampas de hasta ~48°
	floor_block_on_wall = false          # NO bloquearse en paredes — las caras
										 # laterales de rampas CSGBox3D no
										 # deben detener al NPC. El step-up
										 # nativo funciona sin este bloqueo.
	floor_constant_speed = true          # Velocidad constante en pendientes
	floor_stop_on_slope = true           # No deslizarse en pendientes
	max_slides = 8                       # Más iteraciones para mejor transición rampa↔piso
	
	max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health
	
	# ── Inicializar sistemas modulares ────────────────────────
	perception_sys = PerceptionSystem.new()
	perception_sys.name = "PerceptionSystem"
	add_child(perception_sys)
	
	memory_sys = MemorySystem.new()
	memory_sys.name = "MemorySystem"
	add_child(memory_sys)
	
	navigation_sys = NavigationSystem.new()
	navigation_sys.name = "NavigationSystem"
	add_child(navigation_sys)
	
	movement_sys = MovementSystem.new()
	movement_sys.name = "MovementSystem"
	add_child(movement_sys)
	
	decision_sys = DecisionSystem.new()
	decision_sys.name = "DecisionSystem"
	add_child(decision_sys)
	_add_fsm_states()
	
	# ── BUGFIX: Re-registrar estados FSM ────────────────────────
	# DecisionSystem._ready() ejecutó _register_child_states() antes
	# de que _add_fsm_states() añadiera los estados como hijos.
	# Sin esto, _states queda vacío y el bot NUNCA transiciona
	# a ningún estado (ni roaming, ni combat, ni dispara).
	if decision_sys.has_method("_register_child_states"):
		decision_sys._register_child_states()
		if decision_sys.current_state == null and decision_sys._states.size() > 0:
			decision_sys._change_state(BotState.StateType.ROAMING)
	
	weapon_sys = WeaponSystem.new()
	weapon_sys.name = "WeaponSystem"
	add_child(weapon_sys)
	
	combat_sys = CombatSystem.new()
	combat_sys.name = "CombatSystem"
	add_child(combat_sys)
	
	# ── Equipar arma y color (AHORA con weapon_sys disponible) ──
	_equipar_arma()
	_aplicar_color_equipo()
	
	# ── Conectar señales ─────────────────────────────────────
	_connect_decision_signals()
	
	# ── Inicializar rol táctico ──
	_tactical_role = TacticalRole.for_npc(self)
	
	# ── Cargar puntos semánticos del mapa ────────────────────
	# Los puntos semánticos (SemanticPointMarker) se cargan una
	# sola vez para todos los bots. El primer bot que se inicializa
	# los carga; los siguientes ya los encuentran cargados.
	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()
	
	# Encontrar core enemigo como objetivo principal
	call_deferred("_find_enemy_core")
	
	_setup_debug_overlay()


## Añade los estados de la FSM como hijos del DecisionSystem.
func _add_fsm_states() -> void:
	if decision_sys == null:
		return
	
	var roaming: BotState = load("res://Scripts/MP/ai/bot_behaviors/state_roaming.gd").new()
	roaming.name = "State_Roaming"
	decision_sys.add_child(roaming)
	
	var hunting: BotState = load("res://Scripts/MP/ai/bot_behaviors/state_hunting.gd").new()
	hunting.name = "State_Hunting"
	decision_sys.add_child(hunting)
	
	var combat: BotState = load("res://Scripts/MP/ai/bot_behaviors/state_combat.gd").new()
	combat.name = "State_Combat"
	decision_sys.add_child(combat)
	
	var retreating: BotState = load("res://Scripts/MP/ai/bot_behaviors/state_retreating.gd").new()
	retreating.name = "State_Retreating"
	decision_sys.add_child(retreating)
	


## Conecta las señales de percepción al DecisionSystem.
func _connect_decision_signals() -> void:
	if not perception_sys or not decision_sys:
		return
	
	if not perception_sys.is_connected("entity_detected", _on_decision_entity_detected):
		perception_sys.connect("entity_detected", _on_decision_entity_detected)
	if not perception_sys.is_connected("entity_lost", _on_decision_entity_lost):
		perception_sys.connect("entity_lost", _on_decision_entity_lost)


## Cuando PerceptionSystem detecta un nuevo enemigo prioritario.
func _on_decision_entity_detected(entity: Node3D, detected_pos: Vector3) -> void:
	if decision_sys:
		decision_sys.target_entity = entity
		decision_sys.focus_point = detected_pos
		decision_sys.notify_see_player(entity)


## Cuando PerceptionSystem pierde de vista al objetivo actual.
func _on_decision_entity_lost(entity: Node3D) -> void:
	if decision_sys:
		if decision_sys.target_entity == entity:
			pass  # MemorySystem maneja el HUNTING state


func _physics_process(delta: float) -> void:
	if is_dead or not is_inside_tree():
		return
	
	# ── CONGELADO: no hace nada hasta que se descongele ────────
	#    Si está saltando al green cube, anima la trayectoria.
	if is_frozen:
		if _is_jumping_to_green:
			_process_jump_to_green(delta)
		if _is_jumping_to_yellow:
			_process_jump_to_yellow(delta)
		else:
			velocity = Vector3.ZERO
			move_and_slide()
		if navigation_agent:
			navigation_agent.target_position = global_position
		return
	
	# ── FASE 1: Percepción y memoria ─────────────────────────
	if perception_sys:
		perception_sys.update(delta)
	if memory_sys:
		memory_sys.update(delta)
	
	# ── FASE 1b: Actualizar caché de orden de TeamAI (FASE 6) ─
	_update_order_cache()
	
	# ── FASE 2: Verificar proximidad al core enemigo ─────────
	_check_core_proximity()
	
	# ── FASE 3: Decisión (FSM escribe movement/combat commands) ─
	if decision_sys:
		decision_sys.process(delta)
	
	# ── FASE 4: Movimiento (MovementSystem ESCRIBE velocity) ──
	if movement_sys:
		movement_sys.process(delta)
	
	# ── FASE 5: Combate (CombatSystem ESCRIBE aim_rotation) ──
	if combat_sys:
		combat_sys.process(delta)
	
	# ── FASE 5b: Armas (WeaponSystem gestiona estado) ────────
	if weapon_sys:
		weapon_sys.process(delta)
	
	# ── FASE 6: Física (move_and_slide LEE velocity) ─────────
	move_and_slide()
	
	# ── FASE 7: Post-movimiento (stuck check, arrival check) ──
	if movement_sys:
		movement_sys.post_process(delta)


# ─────────────────────────────────────────
# SISTEMA DE PICKUPS
# ─────────────────────────────────────────

## Busca pickups cercanos y navega hacia el más útil.
func _check_for_pickups(delta: float) -> bool:
	_pickup_check_timer -= delta
	if _pickup_check_timer > 0.0:
		if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
			_move_to_pickup()
			return true
		return false
	_pickup_check_timer = 2.0
	
	if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
		_move_to_pickup()
		return true
	
	_pickup_target = null
	
	# Prioridad 1: Si no tenemos arma, buscar un arma
	if not _weapon or not is_instance_valid(_weapon):
		var weapon_pickup = _pickup_manager.get_nearest_pickup(global_position, 0, 8.0)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup()
			return true
		return false
	
	# Prioridad 2: Baja munición
	var ammo_pct: float = 1.0
	if _weapon and _weapon.max_ammo > 0:
		ammo_pct = float(_weapon.ammo_in_mag + _weapon.reserve_ammo) / float(_weapon.max_ammo + _weapon.clip_size)
	
	if ammo_pct < 0.5:
		var weapon_pickup = _pickup_manager.get_nearest_pickup(global_position, 0, 10.0)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup()
			return true
	
	return false


## Navega hacia el pickup objetivo usando MovementSystem.
func _move_to_pickup() -> void:
	if not _pickup_target or not is_instance_valid(_pickup_target) or not _pickup_target.is_inside_tree():
		_pickup_target = null
		return
	
	var target_pos: Vector3 = _pickup_target.global_position
	var dist: float = global_position.distance_to(target_pos)
	
	if movement_sys and movement_sys.command:
		movement_sys.command.set_navigate(target_pos, 5.0 if dist > 1.5 else 2.0)


## Llamado por el Pickup cuando este NPC entra en su área de recogida.
func _on_pickup_area_entered(pickup: Node) -> void:
	if is_dead:
		return
	if not is_instance_valid(pickup):
		return
	pickup.pick_up(self)


## Recibe un arma recogida del suelo y la equipa.
func pickup_weapon(data: Dictionary) -> void:
	var weapon_name: String = data.get("tipo_arma", "")
	if weapon_name == "":
		return
	
	var balas_cargador: int = data.get("balas_cargador", 0)
	var balas_reserva: int = data.get("balas_reserva", 0)
	
	_pickup_target = null
	
	# Si ya tiene esta arma, sumar munición
	if _weapon and is_instance_valid(_weapon):
		if _weapon.weapon_name.to_lower() == weapon_name.to_lower():
			_weapon.ammo_in_mag += balas_cargador
			_weapon.ammo_in_mag = min(_weapon.ammo_in_mag, _weapon.clip_size)
			_weapon.reserve_ammo += balas_reserva
			_weapon.reserve_ammo = min(_weapon.reserve_ammo, _weapon.max_ammo)
			return
	
	# Arma diferente: reemplazar
	nombre_arma = weapon_name
	
	if _weapon and is_instance_valid(_weapon):
		if weapon_sys:
			weapon_sys.unregister_weapon(_weapon)
		_weapon.queue_free()
		_weapon = null
	
	_equipar_arma()
	if _weapon:
		_weapon.ammo_in_mag = balas_cargador
		_weapon.reserve_ammo = balas_reserva


# ─────────────────────────────────────────
# SISTEMA DE DAÑO & EQUIPOS
# ─────────────────────────────────────────

func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1) -> void:
	if is_dead: return
	var mult: float = 2.0 if zone == "Cabeza" else 1.0
	current_health -= amount * mult
	
	if current_health <= 0:
		die(killer_id)


func die(killer_id: int = -1) -> void:
	if is_dead: return
	is_dead = true
	_drop_weapon()
	
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(self, killer_id)
		MatchManager.reportar_muerte_bot(self)
	
	set_physics_process(false)
	set_process(false)
	hide()
	
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = true
	
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	var killer_name: String = "desconocido"
	if is_instance_valid(MatchManager) and killer_id >= 0:
		var kd = MatchManager.get_player_data(killer_id)
		if kd:
			killer_name = kd.player_name
	_debug("MUERTO por %s - esperando respawn..." % killer_name)


func _drop_weapon() -> void:
	if not DROPPED_WEAPON or not _weapon:
		return
	if not is_inside_tree():
		return
	if weapon_sys and _weapon:
		weapon_sys.unregister_weapon(_weapon)
	var drop: Node = DROPPED_WEAPON.instantiate()
	if not drop: return
	get_parent().add_child(drop)
	drop.global_transform.origin = global_transform.origin + Vector3.UP * 0.5
	if drop.has_method("set_weapon_data"):
		drop.set_weapon_data({
			"tipo_arma": _weapon.weapon_name,
			"balas_cargador": _weapon.ammo_in_mag,
			"balas_reserva": _weapon.reserve_ammo,
			"capacidad_cargador": _weapon.clip_size
		})


func _re_evaluar_enemigos() -> void:
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	
	if decision_sys:
		decision_sys.target_entity = null
	if perception_sys:
		perception_sys.reset()


# ─────────────────────────────────────────
# CORE DETECTION
# ─────────────────────────────────────────

func _find_enemy_core() -> void:
	_enemy_core = null
	_is_attacking_core = false
	_team_objective = Vector3.ZERO
	
	var cores: Array[Node] = get_tree().get_nodes_in_group("core")
	for core in cores:
		if not is_instance_valid(core):
			continue
		if core.get("is_destroyed") == true:
			continue
		var core_team: int = core.get("team") if "team" in core else -1
		if GameState.son_enemigos(equipo_id, core_team):
			_enemy_core = core
			_team_objective = core.global_position
			_debug("OBJETIVO: Core %s en %s" % [GameState.nombre_equipo(core_team), str(_team_objective)])
			return
	
	get_tree().create_timer(1.0).timeout.connect(_find_enemy_core)


func _check_core_proximity() -> void:
	if not _enemy_core or not is_instance_valid(_enemy_core) or not _enemy_core.is_inside_tree():
		_find_enemy_core()
		return
	if _enemy_core.get("is_destroyed") == true:
		_enemy_core = null
		_is_attacking_core = false
		return
	
	var target_entity = decision_sys.target_entity if decision_sys else null
	if target_entity and target_entity is CharacterBody3D and not target_entity.get("is_dead"):
		return
	
	var dist: float = global_position.distance_to(_enemy_core.global_position)
	if dist > 25.0:
		return
	
	# Verificar línea de visión con el core
	var target_pos: Vector3 = _enemy_core.global_position + Vector3.UP * 0.7
	var local_target: Vector3 = to_local(target_pos)
	raycast_vision.target_position = local_target
	raycast_vision.force_raycast_update()
	
	var collider = raycast_vision.get_collider()
	var core_hit: bool = (collider == _enemy_core)
	if not core_hit and collider:
		var parent_check: Node = collider.get_parent()
		while parent_check:
			if parent_check == _enemy_core:
				core_hit = true
				break
			parent_check = parent_check.get_parent()
	
	if core_hit:
		if not _is_attacking_core:
			_is_attacking_core = true
			if decision_sys:
				decision_sys.target_entity = _enemy_core
			_debug("ATACANDO CORE enemigo! Distancia: %.1f" % dist)
	else:
		if _is_attacking_core:
			_is_attacking_core = false
			if decision_sys:
				decision_sys.target_entity = null


## Devuelve el nombre del estado FSM activo.
func _get_current_behavior_name() -> String:
	if decision_sys and decision_sys.current_state:
		return decision_sys.current_state.state_name
	return "unknown"


# ─────────────────────────────────────────
# EQUIPAMIENTO
# ─────────────────────────────────────────

func _equipar_arma() -> void:
	if nombre_arma == "":
		return

	# ── Limpiar arma anterior si existe ──
	if _weapon and is_instance_valid(_weapon):
		if weapon_sys:
			weapon_sys.unregister_weapon(_weapon)
		_weapon.queue_free()
		_weapon = null

	# Cargar escena en tiempo de ejecución para evitar problemas de
	# compilación encadenada con autoloads durante el escaneo de class_name.
	var weapon_scene: PackedScene = ResourceLoader.load(
		"res://scenes/weapons/weapon_placeholder.tscn",
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE
	) as PackedScene
	if not weapon_scene:
		push_error("_equipar_arma: No se pudo cargar weapon_placeholder.tscn")
		return
	var weapon_instance: Node3D = weapon_scene.instantiate()
	if not weapon_instance:
		push_error("_equipar_arma: weapon_scene.instantiate() devolvió null")
		return
	if head:
		head.add_child(weapon_instance)
		_weapon = weapon_instance as Weapon
		if _weapon:
			_weapon.initialize_from_name(nombre_arma)
			if weapon_sys:
				weapon_sys.register_weapon(_weapon)


func _aplicar_color_equipo() -> void:
	var color: Color = GameState.color_equipo(equipo_id)
	if has_node("MeshInstance3D"): _aplicar_color_a_mesh($MeshInstance3D, color)
	if has_node("Head/HeadMesh"): _aplicar_color_a_mesh($Head/HeadMesh, color)


func _aplicar_color_a_mesh(mesh: MeshInstance3D, color: Color) -> void:
	var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
	if not mat: mat = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if not mat: return
	mat = mat.duplicate()
	mat.albedo_color = color
	mesh.set_surface_override_material(0, mat)


# ─────────────────────────────────────────
# RESPAWN
# ─────────────────────────────────────────

func respawn() -> void:
	is_dead = false
	current_health = max_health
	
	set_physics_process(true)
	set_process(true)
	show()
	
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = false
	
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_pickup_target = null
	_pickup_check_timer = 0.0
	
	if perception_sys:
		perception_sys.reset()
	if memory_sys:
		memory_sys.clear_all()
	if decision_sys:
		decision_sys.target_entity = null
		decision_sys.movement_command.reset()
		decision_sys.combat_command.reset()
		decision_sys.change_state(BotState.StateType.ROAMING)
	if movement_sys:
		movement_sys.reset()
	
	_tactical_role = TacticalRole.for_npc(self)
	
	_equipar_arma()
	_aplicar_color_equipo()
	_setup_debug_overlay()
	
	call_deferred("_refresh_order")
	call_deferred("_find_enemy_core")
	


# ─────────────────────────────────────────
# CONGELACIÓN
# ─────────────────────────────────────────

## Congela al NPC por [duration] segundos.
## Mientras está congelado no se mueve, no procesa IA, no dispara.
func freeze(duration: float) -> void:
	if is_dead:
		return
	if is_frozen:
		return
	
	is_frozen = true
	
	# Detener cualquier navegación activa
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	# Detener movimiento
	velocity = Vector3.ZERO
	
	# Iniciar salto al green cube más cercano (si existe)
	_start_jump_to_green_cube()
	
	# Timer de descongelación
	_frozen_timer = get_tree().create_timer(duration)
	_frozen_timer.timeout.connect(_unfreeze)


## Congela al NPC por [duration] segundos y lo lanza hacia el yellow_cube más cercano.
func freeze_to_yellow(duration: float) -> void:
	if is_dead:
		return
	if is_frozen:
		return
	
	is_frozen = true
	
	# Detener cualquier navegación activa
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	# Detener movimiento
	velocity = Vector3.ZERO
	
	# Iniciar salto al yellow cube más cercano (si existe)
	_start_jump_to_yellow_cube()
	
	# Timer de descongelación
	_frozen_timer = get_tree().create_timer(duration)
	_frozen_timer.timeout.connect(_unfreeze)


## Descongela al NPC y reanuda su comportamiento normal.
func _unfreeze() -> void:
	if not is_frozen:
		return
	is_frozen = false
	_frozen_timer = null
	_is_jumping_to_green = false
	_is_jumping_to_yellow = false


# ── Salto al Green Cube ────────────────────

## Busca el green cube más cercano y inicia el salto parabólico.
func _start_jump_to_green_cube() -> void:
	if not is_inside_tree():
		return
	
	var target: Node3D = _find_nearest_green_cube()
	if target == null:
		return
	
	_jump_start_pos = global_position
	_jump_target_pos = target.global_position
	# Ajustar Y para aterrizar SOBRE el cubo (cubo 1.0 de alto, centro del cubo + 0.5 = tope)
	_jump_target_pos.y += 0.5
	
	# Calcular duración y altura según distancia horizontal
	var diff_xz: Vector2 = Vector2(
		_jump_target_pos.x - _jump_start_pos.x,
		_jump_target_pos.z - _jump_start_pos.z
	)
	var h_dist: float = diff_xz.length()
	_jump_duration = clamp(0.8 + h_dist * 0.08, 1.0, 2.5)
	_jump_arc_height = clamp(1.5 + h_dist * 0.15, 2.0, 6.0)
	
	_jump_progress = 0.0
	_is_jumping_to_green = true


## Busca el yellow cube más cercano y inicia el salto parabólico.
func _start_jump_to_yellow_cube() -> void:
	if not is_inside_tree():
		return
	
	var target: Node3D = _find_nearest_yellow_cube()
	if target == null:
		return
	
	_jump_start_pos = global_position
	_jump_target_pos = target.global_position
	# Ajustar Y para aterrizar SOBRE el cubo (cubo 1.0 de alto, centro del cubo + 0.5 = tope)
	_jump_target_pos.y += 0.5
	
	# Calcular duración y altura según distancia horizontal
	var diff_xz: Vector2 = Vector2(
		_jump_target_pos.x - _jump_start_pos.x,
		_jump_target_pos.z - _jump_start_pos.z
	)
	var h_dist: float = diff_xz.length()
	_jump_duration = clamp(0.8 + h_dist * 0.08, 1.0, 2.5)
	_jump_arc_height = clamp(1.5 + h_dist * 0.15, 2.0, 6.0)
	
	_jump_progress = 0.0
	_is_jumping_to_yellow = true


## Encuentra el GreenCube más cercano al bot.
func _find_nearest_green_cube() -> Node3D:
	var cubes: Array[Node] = get_tree().get_nodes_in_group("green_cube")
	var nearest: Node3D = null
	var nearest_dist: float = INF
	
	for cube in cubes:
		if not is_instance_valid(cube):
			continue
		var dist: float = global_position.distance_squared_to(cube.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cube as Node3D
	
	return nearest


## Encuentra el YellowCube más cercano al bot.
func _find_nearest_yellow_cube() -> Node3D:
	var cubes: Array[Node] = get_tree().get_nodes_in_group("yellow_cube")
	var nearest: Node3D = null
	var nearest_dist: float = INF
	
	for cube in cubes:
		if not is_instance_valid(cube):
			continue
		var dist: float = global_position.distance_squared_to(cube.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = cube as Node3D
	
	return nearest


## Procesa el movimiento parabólico hacia el green cube.
## El bot levita en un arco natural desde su posición hasta el green cube.
func _process_jump_to_green(delta: float) -> void:
	if not is_inside_tree():
		return
	
	_jump_progress += delta / _jump_duration
	
	var t: float = minf(_jump_progress, 1.0)
	
	# Interpolación horizontal (XZ) lineal
	var pos: Vector3 = _jump_start_pos.lerp(_jump_target_pos, t)
	
	# Arco parabólico en Y: 4 * h * t * (1 - t)
	#   t=0 → Y=0, t=0.5 → Y=h, t=1 → Y=0
	var base_y: float = lerpf(_jump_start_pos.y, _jump_target_pos.y, t)
	var arc_offset: float = _jump_arc_height * 4.0 * t * (1.0 - t)
	pos.y = base_y + arc_offset
	
	global_position = pos
	velocity = Vector3.ZERO
	
	# Pequeña rotación para dar sensación de movimiento
	var look_target: Vector3 = _jump_target_pos
	look_target.y = global_position.y
	if t < 1.0:
		var look_dir: Vector3 = (look_target - global_position).normalized()
		if look_dir.length_squared() > 0.001:
			var target_basis: Basis = Basis.looking_at(look_dir, Vector3.UP)
			var current_transform: Transform3D = global_transform
			var current_basis: Basis = current_transform.basis.orthonormalized()
			var slerp_weight: float = clampf(delta * 4.0, 0.0, 1.0)
			current_transform.basis = current_basis.slerp(target_basis, slerp_weight).orthonormalized()
			global_transform = current_transform
	
	# Finalizar el salto al llegar
	if _jump_progress >= 1.0:
		_is_jumping_to_green = false
		global_position = _jump_target_pos
		velocity = Vector3.ZERO
## Procesa el movimiento parabólico hacia el green cube.
## El bot levita en un arco natural desde su posición hasta el green cube.

func _process_jump_to_yellow(delta: float) -> void:
	if not is_inside_tree():
		return
	
	_jump_progress += delta / _jump_duration
	
	var t: float = minf(_jump_progress, 1.0)
	
	# Interpolación horizontal (XZ) lineal
	var pos: Vector3 = _jump_start_pos.lerp(_jump_target_pos, t)
	
	# Arco parabólico en Y: 4 * h * t * (1 - t)
	#   t=0 → Y=0, t=0.5 → Y=h, t=1 → Y=0
	var base_y: float = lerpf(_jump_start_pos.y, _jump_target_pos.y, t)
	var arc_offset: float = _jump_arc_height * 4.0 * t * (1.0 - t)
	pos.y = base_y + arc_offset
	
	global_position = pos
	velocity = Vector3.ZERO
	
	# Pequeña rotación para dar sensación de movimiento
	var look_target: Vector3 = _jump_target_pos
	look_target.y = global_position.y
	if t < 1.0:
		var look_dir: Vector3 = (look_target - global_position).normalized()
		if look_dir.length_squared() > 0.001:
			var target_basis: Basis = Basis.looking_at(look_dir, Vector3.UP)
			var current_transform: Transform3D = global_transform
			var current_basis: Basis = current_transform.basis.orthonormalized()
			var slerp_weight: float = clampf(delta * 4.0, 0.0, 1.0)
			current_transform.basis = current_basis.slerp(target_basis, slerp_weight).orthonormalized()
			global_transform = current_transform
	
	# Finalizar el salto al llegar
	if _jump_progress >= 1.0:
		_is_jumping_to_yellow = false
		global_position = _jump_target_pos
		velocity = Vector3.ZERO



# ─────────────────────────────────────────
# TEAMAI / ORDER SYSTEM (FASE 6)
# ─────────────────────────────────────────

func _refresh_order() -> void:
	if not is_instance_valid(TeamAI):
		return
	if equipo_id == int(Enums.Equipo.ESPECTADOR):
		return
	TeamAI.assign_order_by_role(self)


func _update_order_cache() -> void:
	if not is_instance_valid(TeamAI):
		return
	
	var order_data: Dictionary = TeamAI.get_order_for_bot(self)
	current_order_type = order_data.get("type", TeamAI.OrderType.FREELANCE)
	current_order_name = TeamAI.order_type_name(current_order_type)
	
	if order_data.get("is_temp", false):
		current_order_name += " [!]"
		current_order_target = order_data.get("target_position", Vector3.ZERO)
	elif current_order_type == TeamAI.OrderType.ATTACK:
		var enemy_core: Node = TeamAI._get_enemy_core(equipo_id)
		if enemy_core:
			current_order_target = enemy_core.global_position
	elif current_order_type == TeamAI.OrderType.DEFEND:
		var own_core: Node = TeamAI._get_own_core(equipo_id)
		if own_core:
			current_order_target = own_core.global_position


func get_current_order() -> Dictionary:
	if is_instance_valid(TeamAI):
		return TeamAI.get_order_for_bot(self)
	return {"type": TeamAI.OrderType.FREELANCE, "target_position": Vector3.ZERO,
		"target_node": NodePath(), "is_temp": false, "reason": ""}


func is_order_offensive() -> bool:
	match current_order_type:
		TeamAI.OrderType.ATTACK, TeamAI.OrderType.PATROL, TeamAI.OrderType.CAPTURE:
			return true
		TeamAI.OrderType.FREELANCE:
			return true
		_: return false


func is_order_defensive() -> bool:
	return current_order_type == TeamAI.OrderType.DEFEND or current_order_type == TeamAI.OrderType.HOLD


func get_order_target_position() -> Vector3:
	if current_order_type == TeamAI.OrderType.ATTACK:
		if _enemy_core and is_instance_valid(_enemy_core):
			return _enemy_core.global_position
	elif current_order_type == TeamAI.OrderType.DEFEND:
		var own_core: Node = _get_own_core()
		if own_core:
			return own_core.global_position
	return current_order_target


# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────

func _get_own_core() -> Node:
	if equipo_id == int(Enums.Equipo.AZUL):
		return GameState.core_blue if is_instance_valid(GameState.core_blue) else null
	elif equipo_id == int(Enums.Equipo.ROJO):
		return GameState.core_red if is_instance_valid(GameState.core_red) else null
	return null


func _get_dist_to_own_core() -> float:
	var core: Node = _get_own_core()
	if core and is_instance_valid(core) and core.is_inside_tree():
		return global_position.distance_to(core.global_position)
	return 0.0


func _role_speed(role, base_speed: float) -> float:
	if role and "speed_multiplier" in role:
		return base_speed * role.speed_multiplier
	return base_speed


func _role_wander_radius(role) -> float:
	if not role:
		return 20.0
	if "movement_profile" in role:
		match role.movement_profile:
			0: return 12.0  # DEFENSIVE
			1: return 30.0  # FLANKING
			2: return 20.0  # PATROL
	return 20.0


# ─────────────────────────────────────────
# DEBUG OVERLAY
# ─────────────────────────────────────────

func _setup_debug_overlay() -> void:
	if BotDebugOverlay.enabled:
		_add_debug_overlay()
	else:
		_remove_debug_overlay()


func _add_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return
	if not DEBUG_OVERLAY:
		return
	var overlay: Node3D = DEBUG_OVERLAY.instantiate()
	add_child(overlay)
	_debug_overlay = overlay


func _remove_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
		_debug_overlay = null


static func toggle_debug_overlay_all() -> void:
	BotDebugOverlay.enabled = not BotDebugOverlay.enabled
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if npc is NpcBase:
			npc._setup_debug_overlay()


## Devuelve la posición desde donde debe lanzarse un proyectil
## (desde la cabeza del bot, no desde el centro del cuerpo).
func get_projectile_launch_position() -> Vector3:
	if head and is_instance_valid(head):
		return head.global_position - head.global_transform.basis.z * 0.3
	return global_position + Vector3.UP * 0.8


func get_current_weapon() -> Weapon:
	if weapon_sys and is_instance_valid(weapon_sys) and weapon_sys.current_weapon:
		return weapon_sys.current_weapon
	return _weapon


func _debug(msg: String) -> void:
	print("[NPC #%d | %s] %s" % [_npc_id, GameState.nombre_equipo(equipo_id), msg])
