# scripts/npc_base.gd
# Base class for all NPCs. Recreación avanzada de la lógica de UT1.
extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# EXPORTS & CONFIG
# ─────────────────────────────────────────

@export var equipo_id: int = int(Enums.Equipo.ROJO)
@export var nombre_arma: String = "USP"
@export var experiencia: int = int(Enums.Experiencia.MEDIA)
@export var rol: int = int(Enums.Rol.SOLDADO)

# Propiedades de UT1
var skill: float = 3.0
var accuracy: float = 0.5
var combat_style: float = 0.5
var jumpiness: float = 0.3

# ─────────────────────────────────────────
# STATE — Gestionado por BotBrain
# ─────────────────────────────────────────

## Referencia al cerebro modular (BotBrain). Se añade como hijo
## en _ready() y gestiona todos los comportamientos del bot.
var brain: BotBrain = null

## Referencia al sistema de percepción modular.
var perception_sys: PerceptionSystem = null

# Objetivo actual (sincronizado por PerceptionSystem)
var target_enemy: Node3D = null
var last_seen_position: Vector3 = Vector3.ZERO
var is_dead: bool = false
var max_health: float = 100.0
var current_health: float = 100.0
var is_invisible: bool = false # Para el modo espectador del bot

# Navigation target tracking (evitar reset del target cada frame)
var _nav_target: Vector3 = Vector3.ZERO

# ── Route Diversification ─────────────────────────────────────────
## RouteType seleccionado deterministicamente para este bot
## (se inicializa en _ready).
var _route_type: int = -1

## Waypoint intermedio de aproximacion (si la ruta no es DIRECT).
## El bot navega primero aqui, luego al destino real.
var _route_waypoint: Vector3 = Vector3.ZERO

## Fase de ruta: 0 = yendo al waypoint, 1 = yendo al destino final.
var _route_phase: int = 0

## Destino real (no el waypoint) para medir progreso y stuck detection.
var _route_target_pos: Vector3 = Vector3.ZERO

## Distancia a la que se considera el waypoint alcanzado.
const ROUTE_WAYPOINT_REACHED_DIST: float = 5.0

# ── Tactical Role ──────────────────────────────────────────────────────
## Perfil de comportamiento táctico (TacticalRole). Se inicializa en
## _ready() basado en el enum Enums.Rol exportado.
var _tactical_role: TacticalRole = null

# ── Stuck Detection v2 ──────────────────────────────────────────────
## Sistema de detección de atasco basado en progreso hacia el objetivo.
## Usa múltiples métricas para evitar falsos positivos durante combate.
## Configurable por comportamiento (behavior name).
## patrol/hunt usan umbrales más agresivos,
## combat es más permisivo (strafing activo).

# Constantes de configuración por comportamiento (behavior name)
const STUCK_PROGRESS_THRESHOLD: Dictionary = {
	"idle":   8.0,   # IDLE - no aplica (nunca se comprueba)
	"patrol": 2.5,   # PATROL - 2.5s sin avanzar hacia el objetivo
	"combat": 4.0,   # COMBAT - 4s (strafing activo, permisivo)
	"hunt":   2.0,   # HUNT - 2s (persecución rápida)
}
const STUCK_HISTORY_SIZE: int = 30

# Métrica 1: Inmovilidad absoluta (fallback)
var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO

# Métrica 2: Progreso hacia el objetivo (principal)
var _stuck_progress_timer: float = 0.0
var _last_dist_to_target: float = -1.0

# Fases de recuperación: 0=normal, 1=retroceder, 2=lateral, 3=reruta, 4=escalar
var _stuck_recovery_phase: int = 0
var _stuck_recovery_timer: float = 0.0
var _stuck_recovery_dir: Vector3 = Vector3.ZERO
var _stuck_origin: Vector3 = Vector3.ZERO
var _stuck_reroute_count: int = 0
var _stuck_attempted_dirs: Array[Vector3] = []

# Bloqueo por otro CharacterBody (bot o jugador)
var _stuck_blocking_bot: Node3D = null
var _stuck_blocked_duration: float = 0.0

# Core / objective system (UT99 Orders pattern)
var _enemy_core: Node3D = null
var _is_attacking_core: bool = false
var _team_objective: Vector3 = Vector3.ZERO

# Components
var _weapon: Weapon = null
const WEAPON_PLACEHOLDER: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")
const DROPPED_WEAPON: PackedScene = preload("res://scenes/pickups/dropped_weapon.tscn")
const DEBUG_OVERLAY: PackedScene = preload("res://scenes/npcs/bot_debug_overlay.tscn")

# Debug overlay instance
var _debug_overlay: Node3D = null

# Pickup system
var _pickup_target: Node = null
var _pickup_check_timer: float = 0.0

var _npc_id: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

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
	# Route diversification: cada bot recibe una ruta deterministica
	# basada en su identidad, rol, combat_style y skill.
	_route_type = RouteDiversifier.get_route_type_for_bot(self)
	add_to_group("npc")
	
	max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health
	
	_equipar_arma()
	_aplicar_color_equipo()
	
	# Ajustar skill (0 a 7 en UT1)
	skill = float(experiencia) * 2.5 + 1.0
	
	# ── Inicializar componentes modulares ────────────────────────
	# Crear el sistema de percepción ANTES que el brain para que
	# esté disponible cuando los behaviors se registren.
	perception_sys = PerceptionSystem.new()
	perception_sys.name = "PerceptionSystem"
	add_child(perception_sys)
	
	# Crear el cerebro modular que reemplaza la FSM tradicional
	brain = BotBrain.new()
	brain.name = "BotBrain"
	add_child(brain)
	
	# Encontrar core enemigo como objetivo principal
	call_deferred("_find_enemy_core")
	
	# ── Inicializar rol táctico ──
	_tactical_role = TacticalRole.for_npc(self)
	_debug("ROL TÁCTICO: %s" % _tactical_role.debug_string())

	_setup_debug_overlay()
	_debug("INICIALIZADO | Equipo=%s | Arma=%s | Brain=%s comportamientos" % [
		GameState.nombre_equipo(equipo_id), nombre_arma, brain.behaviors.size()])

func _physics_process(delta: float) -> void:
	if is_dead or not is_inside_tree():
		return
	
	# ── 1. Actualizar percepción (visión, memoria) ──────────────
	if perception_sys:
		perception_sys.update(delta)
	
	# ── 2. Verificar proximidad al core enemigo ──────────────────
	_check_core_proximity()
	
	# ── 3. El cerebro modular evalúa comportamientos y ejecuta ──
	if brain:
		brain.process(delta)
	
	# ── 4. Detección de atasco (maneja recuperación activa) ─────
	var stuck_handled: bool = _check_stuck(delta)
	
	if not stuck_handled and brain and brain.current_behavior:
		# El behavior ya ha ejecutado su movimiento. Solo
		# actualizar si el behavior no manejó el movimiento.
		pass
	
	if not is_on_floor():
		velocity.y -= _gravity * delta
	
	move_and_slide()

# ─────────────────────────────────────────
# SISTEMA DE PICKUPS
# ─────────────────────────────────────────

## Busca pickups cercanos y navega hacia el más útil.
## Retorna true si está yendo hacia un pickup.
func _check_for_pickups(delta: float) -> bool:
	# Solo buscar cada 2 segundos para no saturar
	_pickup_check_timer -= delta
	if _pickup_check_timer > 0.0:
		# Si ya tenemos un target de pickup, seguirlo
		if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
			_move_to_pickup(delta)
			return true
		return false
	_pickup_check_timer = 2.0
	
	# Si ya tenemos un pickup como objetivo, seguimos yendo
	if _pickup_target and is_instance_valid(_pickup_target) and _pickup_target.is_inside_tree():
		_move_to_pickup(delta)
		return true
	
	_pickup_target = null
	
	# Prioridad 1: Si no tenemos arma, buscar un arma
	if not _weapon or not is_instance_valid(_weapon):
		var weapon_pickup = _pickup_manager.get_nearest_pickup(
			global_position, 0, 8.0
		)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup(delta)
			return true
		return false
	
	# Prioridad 2: Baja munición — buscar arma (cambiar)
	var ammo_pct: float = 1.0
	if _weapon and _weapon.max_ammo > 0:
		ammo_pct = float(_weapon.ammo_in_mag + _weapon.reserve_ammo) / float(_weapon.max_ammo + _weapon.clip_size)

	# Umbral de recogida según el rol. Asaltos solo recogen si están
	# muy bajos, patrulleros recogen siempre que puedan.
	var should_pickup: bool = false
	if _tactical_role:
		should_pickup = _tactical_role.should_pickup_instead_of_objective(
			current_health / max_health, ammo_pct
		)
	else:
		should_pickup = ammo_pct < 0.2

	if should_pickup and ammo_pct < 0.5:
		var search_radius: float = 10.0
		# Los defensores buscan más cerca, flanqueadores más lejos
		if _tactical_role:
			match _tactical_role.movement_profile:
				TacticalRole.MovementProfile.DEFENSIVE:
					search_radius = 8.0
				TacticalRole.MovementProfile.FLANKING:
					search_radius = 14.0
				TacticalRole.MovementProfile.PATROL:
					search_radius = 12.0
		var weapon_pickup = _pickup_manager.get_nearest_pickup(
			global_position, 0, search_radius
		)
		if weapon_pickup:
			_pickup_target = weapon_pickup
			_move_to_pickup(delta)
			return true

	return false

## Navega hacia el pickup objetivo.
func _move_to_pickup(delta: float) -> void:
	if not _pickup_target or not is_instance_valid(_pickup_target) or not _pickup_target.is_inside_tree():
		_pickup_target = null
		return
	
	var target_pos: Vector3 = _pickup_target.global_position
	
	# Si estamos muy cerca, el Area3D del pickup detectará el contacto
	var dist: float = global_position.distance_to(target_pos)
	if dist < 1.5:
		_move_to_target(delta, 2.0, target_pos)
	else:
		_move_to_target(delta, 5.0, target_pos)
	
	# Apuntar hacia el pickup mientras nos acercamos
	_aim_at_target(target_pos)

## Llamado por el Pickup cuando este NPC entra en su área de recogida.
func _on_pickup_area_entered(pickup: Node) -> void:
	if is_dead:
		return
	if not is_instance_valid(pickup):
		return
	# El NPC recoge el pickup — el WeaponPickup._on_picked_up llamará
	# a pickup_weapon() con los datos correspondientes
	pickup.pick_up(self)

## Recibe un arma recogida del suelo y la equipa.
func pickup_weapon(data: Dictionary) -> void:
	var weapon_name: String = data.get("tipo_arma", "")
	if weapon_name == "":
		return
	
	var balas_cargador: int = data.get("balas_cargador", 0)
	var balas_reserva: int = data.get("balas_reserva", 0)
	
	# Limpiar referencia al pickup objetivo
	_pickup_target = null
	
	# Si ya tiene esta arma, sumar munición
	if _weapon and is_instance_valid(_weapon):
		if _weapon.weapon_name.to_lower() == weapon_name.to_lower():
			_weapon.ammo_in_mag += balas_cargador
			_weapon.ammo_in_mag = min(_weapon.ammo_in_mag, _weapon.clip_size)
			_weapon.reserve_ammo += balas_reserva
			_weapon.reserve_ammo = min(_weapon.reserve_ammo, _weapon.max_ammo)
			_debug("Recogió munición de %s" % weapon_name)
			return
	
	# Arma diferente: reemplazar
	nombre_arma = weapon_name
	
	# Destruir el arma anterior
	if _weapon and is_instance_valid(_weapon):
		_weapon.queue_free()
		_weapon = null
	
	# Equipar nueva arma
	_equipar_arma()
	if _weapon:
		_weapon.ammo_in_mag = balas_cargador
		_weapon.reserve_ammo = balas_reserva
		_debug("Equipó %s del suelo (cargador=%d reserva=%d)" % [weapon_name, balas_cargador, balas_reserva])

# ─────────────────────────────────────────
# ACCIONES
# ─────────────────────────────────────────

func _aim_at_target(target_pos: Vector3) -> void:
	# Rotación horizontal (Cuerpo)
	var look_pos: Vector3 = target_pos
	look_pos.y = global_position.y
	if global_position.distance_to(look_pos) > 0.1:
		look_at(look_pos, Vector3.UP)
	
	# Rotación vertical (Cabeza)
	if head:
		head.look_at(target_pos, Vector3.UP)
		head.rotation.y = 0 # Mantener solo rotación vertical
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-60), deg_to_rad(60))

func _move_to_target(delta: float, speed: float, target: Vector3 = Vector3.ZERO) -> void:
	# Solo actualizar target_position si cambio. Si se envia el mismo valor
	# cada frame, el NavigationAgent reinicia el calculo de ruta continuamente.
	if target != Vector3.ZERO and target != navigation_agent.target_position:
		navigation_agent.target_position = target
	elif target == Vector3.ZERO:
		# Usar el target actual del agente como referencia
		target = navigation_agent.target_position
	
	# Verificar que el mapa de navegación esté sincronizado antes de consultar
	var nav_map_rid: RID = navigation_agent.get_navigation_map()
	var map_iter: int = NavigationServer3D.map_get_iteration_id(nav_map_rid)
	if map_iter == 0:
		# Mapa no listo aún — mantener velocidad actual, no frenar
		return
	
	var nav_finished: bool = navigation_agent.is_navigation_finished()
	
	if nav_finished:
		# La navegación terminó. Si hemos llegado al destino, frenar.
		# Si no hemos llegado, el NavigationAgent aun esta calculando la ruta.
		# NO usar fallback en linea recta porque choca contra paredes.
		# Solo esperar a que el agente tenga la ruta lista.
		if target != Vector3.ZERO:
			var dist_to_target: float = global_position.distance_to(target)
			if dist_to_target <= navigation_agent.target_desired_distance:
				# Llegamos al destino — frenar suavemente
				velocity.x = move_toward(velocity.x, 0.0, speed * delta * 3.0)
				velocity.z = move_toward(velocity.z, 0.0, speed * delta * 3.0)
				return
		# No hemos llegado, esperar a que el agente calcule la ruta
		return
	
	var next_pos: Vector3 = navigation_agent.get_next_path_position()
	var dir: Vector3 = (next_pos - global_position).normalized()
	
	# Si la dirección es ~cero (next_pos == global_position), no frenar abruptamente
	if dir.length_squared() < 0.001:
		return
	
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

# ─────────────────────────────────────────
# ROUTE DIVERSIFICATION
# ─────────────────────────────────────────

## Establece un nuevo destino de navegacion usando el sistema de
## diversificacion de rutas. Si la ruta del bot lo permite, genera
## un waypoint intermedio que lo hace aproximarse desde otro angulo,
## forzando al NavigationAgent a calcular una ruta alternativa.
##
## Llamar esto cuando se quiere que el bot vaya a un sitio NUEVO
## (no cada frame). El seguimiento se hace con _navigate_with_route().
func _set_route_target(new_target: Vector3) -> void:
	_route_target_pos = new_target

	# ── Elegir tipo de ruta según el rol táctico ─────────────────
	var effective_route_type: int = _route_type
	if _tactical_role:
		effective_route_type = _tactical_role.get_preferred_route_type(_route_type)

	var nav_map_rid: RID = navigation_agent.get_navigation_map()
	var waypoint: Vector3 = RouteDiversifier.get_approach_waypoint(
		global_position, new_target, effective_route_type, nav_map_rid
	)

	_nav_target = waypoint
	navigation_agent.target_position = waypoint

	if waypoint != new_target:
		# Ruta con waypoint intermedio
		_route_waypoint = waypoint
		_route_phase = 0
		# _debug("[Ruta] %s → waypoint %s" % [
		# 	RouteDiversifier.get_route_name(_route_type),
		# 	str(waypoint.round())
		# ])
	else:
		# DIRECT o fallback: sin waypoint
		_route_waypoint = Vector3.ZERO
		_route_phase = 1


## Navega hacia target_pos respetando la fase de ruta actual.
##
## Fase 0: navega hacia el waypoint intermedio. Cuando lo alcanza,
##         transiciona a fase 1 y redirige al destino real.
## Fase 1: navega directamente al destino final.
##
## Llamar esto CADA FRAME en lugar de _move_to_target() para que el
## sistema de rutas funcione correctamente.
func _navigate_with_route(delta: float, speed: float, target_pos: Vector3) -> void:
	# ── Fase 0: Ir al waypoint intermedio ──
	if _route_phase == 0 and _route_waypoint != Vector3.ZERO:
		var dist_to_wp: float = global_position.distance_to(_route_waypoint)
		if dist_to_wp <= ROUTE_WAYPOINT_REACHED_DIST:
			# Waypoint alcanzado: transicionar al destino final
			_route_phase = 1
			_route_waypoint = Vector3.ZERO
			_nav_target = target_pos
			navigation_agent.target_position = target_pos
			# _debug("[Ruta] Waypoint alcanzado, yendo a destino final")
		else:
			# Seguir navegando hacia el waypoint
			_move_to_target(delta, speed, _route_waypoint)
			return

	# ── Fase 1: Ir al destino final ──
	# Actualizar target si el destino se movio (enemigo en ATTACKING)
	if _route_target_pos != target_pos:
		_route_target_pos = target_pos
		# Solo recalcular si el cambio es significativo
		if RouteDiversifier.should_recalculate_route(_nav_target, target_pos):
			_route_waypoint = Vector3.ZERO
			_route_phase = 1
			_nav_target = target_pos
			navigation_agent.target_position = target_pos

	_move_to_target(delta, speed, target_pos)

func _shoot() -> void:
	if not _weapon: return
	
	var killer_id: int = -1
	if is_instance_valid(MatchManager):
		killer_id = MatchManager.get_player_id_by_pawn(self)
	
	var hits: Array = _weapon.fire()
	for hit in hits:
		var col: Node = hit["collider"]
		if not col: continue
		var target: Node = col
		if target is Area3D: target = target.get_parent()
		while target and not target.has_method("take_damage"):
			target = target.get_parent()
		
		if target and target.has_method("take_damage"):
			if target is Player: target.take_damage(hit["damage_vs_player"], "Torso", killer_id)
			else: target.take_damage(hit["damage_vs_npc"], "Torso", killer_id)

# ─────────────────────────────────────────
# SISTEMA DE DAÑO & EQUIPOS
# ─────────────────────────────────────────

func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1) -> void:
	if is_dead: return
	var mult: float = 1.0
	if zone == "Cabeza": mult = 2.0
	current_health -= amount * mult
	
	# UT1: Retaliación inmediata si no tenemos objetivo (y no estamos atacando core)
	# NOTA: El BotBrain maneja automáticamente la transición a COMBAT
	# cuando perception_sys detecta al atacante en el próximo frame.
	# No necesitamos forzar estado aquí.
	if target_enemy == null and not _is_attacking_core:
		# Forzar detección inmediata del atacante apuntando a la
		# dirección del daño recibido
		pass
		
	if current_health <= 0:
		die(killer_id)

func die(killer_id: int = -1) -> void:
	if is_dead: return
	is_dead = true
	_drop_weapon()
	
	# Reportar muerte al MatchManager
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(self, killer_id)  # Estadisticas
		MatchManager.reportar_muerte_bot(self)          # Respawn timer + contadores
	
	# ── Nuevo comportamiento: NO destruir el bot ──
	# Deshabilitar fisicas, proceso, colisiones y visibilidad
	# El MatchManager se encarga del respawn reutilizando esta misma instancia
	set_physics_process(false)
	set_process(false)
	hide()
	
	# Deshabilitar colision
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = true
	
	# Detener navegacion
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	_debug("MUERTO - esperando respawn...")

func _drop_weapon() -> void:
	if not DROPPED_WEAPON or not _weapon:
		return
	if not is_inside_tree():
		return
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
	target_enemy = null
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_nav_target = Vector3.ZERO
	_route_waypoint = Vector3.ZERO
	_route_phase = 0
	_route_target_pos = Vector3.ZERO
	_reset_stuck_state()
	if perception_sys:
		perception_sys.reset()
	# El BotBrain seleccionará automáticamente PATROL o IDLE
	# según los comportamientos disponibles

# ─────────────────────────────────────────
# CORE DETECTION & STUCK HANDLING
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
	
	# Si no encontro core, reintentar
	get_tree().create_timer(1.0).timeout.connect(_find_enemy_core)

func _check_core_proximity() -> void:
	if not _enemy_core or not is_instance_valid(_enemy_core) or not _enemy_core.is_inside_tree():
		_find_enemy_core()
		return
	if _enemy_core.get("is_destroyed") == true:
		_enemy_core = null
		_is_attacking_core = false
		# El BotBrain maneja la transición a PATROL automáticamente
		return
	
	# Si ya estamos en combate con un personaje, no cambiar al core
	if target_enemy and target_enemy is CharacterBody3D and not target_enemy.get("is_dead"):
		return
	
	var dist: float = global_position.distance_to(_enemy_core.global_position)
	if dist > 25.0:
		return
	
	# Verificar linea de vision con el core
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
		if not _is_attacking_core or target_enemy != _enemy_core:
			_is_attacking_core = true
			target_enemy = _enemy_core
			# El BotBrain seleccionará COMBAT porque is_attacking_core
			# es true y el behavior_combat tiene prioridad
			_debug("ATACANDO CORE enemigo! Distancia: %.1f" % dist)
	else:
		if _is_attacking_core:
			_is_attacking_core = false
			target_enemy = null
			# El BotBrain vuelve a PATROL automáticamente

func _get_current_behavior_name() -> String:
	## Helper: obtiene el nombre del comportamiento activo, o "unknown"
	if brain and brain.current_behavior:
		return brain.current_behavior.behavior_name
	return "idle"

func _check_stuck(delta: float) -> bool:
	var beh_name: String = _get_current_behavior_name()
	
	# ── No comprobar atasco en idle o muerto ──
	if beh_name == "idle" or is_dead:
		_reset_stuck_state()
		_last_position = global_position
		return false
	
	# ── Si estamos en fase de recuperación activa, ejecutarla ──
	if _stuck_recovery_phase > 0:
		return _handle_stuck_recovery(delta)
	
	# ── Métrica 1: Progreso hacia el objetivo ─────────────────────
	# Mide si la distancia al destino se reduce con el tiempo.
	# En COMBAT el bot strafea lateralmente sin usar NavigationAgent.
	var goal_pos: Vector3 = _get_stuck_goal_position()
	var has_goal: bool = goal_pos != Vector3.ZERO
	
	if has_goal:
		var dist_to_goal: float = global_position.distance_to(goal_pos)
		
		if _last_dist_to_target >= 0.0:
			var progress_made: float = _last_dist_to_target - dist_to_goal
			# Avance menor a 0.05 uds → sin progreso
			if progress_made < 0.05:
				_stuck_progress_timer += delta
			else:
				# Avanzando bien: reducir rápido el timer
				_stuck_progress_timer = max(0.0, _stuck_progress_timer - delta * 3.0)
		_last_dist_to_target = dist_to_goal
	else:
		# Sin objetivo definido: reducir timer gradualmente
		_stuck_progress_timer = max(0.0, _stuck_progress_timer - delta * 2.0)
	
	# ── Métrica 2: Inmovilidad absoluta (fallback) ────────────────
	# Detecta si el bot literalmente no puede moverse (pared, abismo, etc.)
	var moved: float = global_position.distance_to(_last_position)
	if moved < 0.02:
		_stuck_timer += delta
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)
	
	# ── Detectar bloqueo activo por otro CharacterBody ────────────
	_check_bot_blocking(delta)
	
	# ── Decisión: ¿estamos realmente atascados? ───────────────────
	var threshold: float = _get_stuck_threshold_for_behavior(beh_name)
	var is_stuck: bool = false
	
	# Criterio principal: sin progreso hacia el objetivo durante X segundos
	if has_goal and _stuck_progress_timer >= threshold:
		is_stuck = true
	
	# Criterio secundario: completamente inmóvil (sin goal o con goal)
	if moved < 0.02 and _stuck_timer >= threshold + 2.0:
		is_stuck = true
	
	if is_stuck:
		_debug("ATASCADO! [%s] prog=%.1fs inm=%.1fs umbral=%.1fs intento=%d%s" % [
			beh_name,
			_stuck_progress_timer, _stuck_timer, threshold,
			_stuck_reroute_count + 1,
			" BLOQ=BOT" if _stuck_blocking_bot else ""])
		
		# Iniciar recuperación en fases
		_stuck_recovery_phase = 1
		_stuck_recovery_timer = 0.4
		_stuck_origin = global_position
		_stuck_reroute_count += 1
		_init_recovery_direction()
		return true  # Salta el movimiento del estado este frame
	
	# ── Actualizar tracking ──
	_last_position = global_position
	return false


func _reset_stuck_state() -> void:
	## Reinicia todas las variables del sistema de atasco.
	_stuck_timer = 0.0
	_stuck_progress_timer = 0.0
	_last_dist_to_target = -1.0
	_stuck_recovery_phase = 0
	_stuck_recovery_timer = 0.0
	_stuck_blocking_bot = null
	_stuck_blocked_duration = 0.0
	# Limpiar historial de direcciones si crece demasiado
	if _stuck_attempted_dirs.size() > 10:
		_stuck_attempted_dirs.clear()


func _get_stuck_goal_position() -> Vector3:
	## Devuelve la posición del objetivo relevante para medir progreso,
	## o Vector3.ZERO si no hay objetivo en este comportamiento.
	##
	## Con diversificación de rutas, _route_target_pos contiene el destino
	## real (no el waypoint intermedio). Usar ese para medir progreso.
	var beh_name: String = _get_current_behavior_name()
	
	match beh_name:
		"patrol", "hunt":
			if _route_target_pos != Vector3.ZERO:
				return _route_target_pos
			if _nav_target != Vector3.ZERO:
				return _nav_target
		"combat":
			if target_enemy and is_instance_valid(target_enemy):
				return target_enemy.global_position
	return Vector3.ZERO


func _get_stuck_threshold_for_behavior(beh_name: String) -> float:
	## Devuelve el umbral de tiempo sin progreso antes de considerar
	## el bot atascado. Varía según el comportamiento para evitar
	## falsos positivos durante combate.
	return STUCK_PROGRESS_THRESHOLD.get(beh_name, 4.0)


func _init_recovery_direction() -> void:
	## Calcula la dirección de retroceso: opuesta al objetivo.
	## Si hay un bot bloqueando, la dirección se aleja de él.
	var away_dir: Vector3
	var goal: Vector3 = _get_stuck_goal_position()
	
	if _stuck_blocking_bot and is_instance_valid(_stuck_blocking_bot):
		# Alejarse del bot que nos bloquea
		away_dir = (global_position - _stuck_blocking_bot.global_position).normalized()
	elif goal != Vector3.ZERO:
		# Alejarse del objetivo (retroceder)
		away_dir = (global_position - goal).normalized()
	else:
		# Dirección aleatoria como última opción
		away_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.001:
		away_dir = Vector3(1.0, 0.0, 0.0)
	_stuck_recovery_dir = away_dir.normalized()


func _handle_stuck_recovery(delta: float) -> bool:
	## Ejecuta la fase activa de recuperación y devuelve true para
	## que el estado no ejecute su movimiento este frame.
	## Fases: 1=retroceder → 2=desplazamiento lateral → 3=reruta
	
	match _stuck_recovery_phase:
		1: # ── FASE 1: Retroceder ──
			_stuck_recovery_timer -= delta
			var speed: float = 4.5
			
			# Si hay un bot bloqueando, saltar para despegarse
			if _stuck_blocking_bot and is_instance_valid(_stuck_blocking_bot):
				if is_on_floor():
					velocity.y = jumpiness * 12.0 + 3.0
				speed = 5.5
			
			velocity.x = _stuck_recovery_dir.x * speed
			velocity.z = _stuck_recovery_dir.z * speed
			
			if _stuck_recovery_timer <= 0.0:
				_stuck_recovery_phase = 2
				_stuck_recovery_timer = 0.3
				# Dirección lateral (perpendicular al retroceso)
				var side_dir: Vector3 = Vector3(
					-_stuck_recovery_dir.z, 0.0, _stuck_recovery_dir.x)
				# Alternar entre izquierda/derecha en cada intento
				if _stuck_reroute_count % 2 == 0:
					side_dir = -side_dir
				_stuck_recovery_dir = side_dir.normalized()
			return true
		
		2: # ── FASE 2: Desplazamiento lateral ──
			_stuck_recovery_timer -= delta
			velocity.x = _stuck_recovery_dir.x * 3.5
			velocity.z = _stuck_recovery_dir.z * 3.5
			
			if _stuck_recovery_timer <= 0.0:
				_stuck_recovery_phase = 3
				_stuck_recovery_timer = 0.0
				# Forzar recálculo de ruta
				_force_path_recalculation()
			return true
		
		3: # ── FASE 3: Transición — la FSM retoma el control ──
			_stuck_recovery_phase = 0
			_stuck_timer = 0.0
			_stuck_progress_timer = 0.0
			_last_dist_to_target = -1.0
			_stuck_blocking_bot = null
			_stuck_blocked_duration = 0.0
			
			# Registrar dirección intentada para diversificar
			_stuck_attempted_dirs.append(_stuck_recovery_dir)
			
			# Si hemos re-ruteado muchas veces al mismo sitio, escalar
			if _stuck_reroute_count >= 3:
				_stuck_reroute_count = 0
				_escalate_stuck_recovery()
			
			return false  # La FSM maneja el movimiento este frame
	
	return false


func _force_path_recalculation() -> void:
	## Limpia la ruta actual y fuerza al NavigationAgent a
	## recalcular en el próximo frame. El `_nav_target = ZERO`
	## hace que _state_roaming() genere un nuevo destino.
	_nav_target = Vector3.ZERO
	if navigation_agent and is_instance_valid(navigation_agent):
		# Apuntar a la posición actual para invalidar la ruta vieja
		navigation_agent.target_position = global_position


func _escalate_stuck_recovery() -> void:
	## Cuando el bot se atasca repetidamente en la misma zona,
	## elige un destino completamente diferente en el navmesh.
	_debug("ESCALANDO: nuevo destino aleatorio lejano")
	var nav_map_rid: RID = navigation_agent.get_navigation_map()
	if NavigationServer3D.map_is_active(nav_map_rid):
		var raw_target: Vector3 = global_position + Vector3(
			randf_range(-25.0, 25.0), 0, randf_range(-25.0, 25.0))
		var valid_target: Vector3 = NavigationServer3D.map_get_closest_point(
			nav_map_rid, raw_target)
		_nav_target = valid_target
		navigation_agent.target_position = valid_target
	_stuck_attempted_dirs.clear()


func _check_bot_blocking(delta: float) -> void:
	## Detecta si hay otro CharacterBody3D (bot o jugador) muy cerca
	## en la dirección de avance. Usa AreaVision (radio 30) filtrando
	## por distancia cercana (< 2 unidades).
	var bodies: Array = area_vision.get_overlapping_bodies()
	var closest_blocker: Node3D = null
	var min_dist: float = 2.0
	
	for body in bodies:
		if body == self:
			continue
		if not body is CharacterBody3D:
			continue
		if not body.is_inside_tree():
			continue
		
		var dist: float = global_position.distance_to(body.global_position)
		if dist < min_dist:
			closest_blocker = body
			min_dist = dist
	
	if closest_blocker:
		if closest_blocker == _stuck_blocking_bot:
			_stuck_blocked_duration += delta
		else:
			_stuck_blocking_bot = closest_blocker
			_stuck_blocked_duration = 0.0
	else:
		_stuck_blocking_bot = null
		_stuck_blocked_duration = 0.0

func _equipar_arma() -> void:
	if nombre_arma == "": return
	var weapon_instance: Node3D = WEAPON_PLACEHOLDER.instantiate()
	# Añadir al nodo Head para que apunte con la mirada vertical
	if head:
		head.add_child(weapon_instance)
		_weapon = weapon_instance as Weapon
		if _weapon:
			_weapon.initialize_from_name(nombre_arma)

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

## Llamado por MatchManager para reutilizar esta instancia tras un respawn.
## Restaura el bot a su estado operativo completo.
func respawn() -> void:
	is_dead = false
	current_health = max_health
	
	# Re-habilitar proceso y visibilidad
	set_physics_process(true)
	set_process(true)
	show()
	
	# Re-habilitar colision
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = false
	
	# Restaurar estado — resetear TODO lo que dependa del equipo
	target_enemy = null
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_nav_target = Vector3.ZERO
	_route_waypoint = Vector3.ZERO
	_route_phase = 0
	_route_target_pos = Vector3.ZERO
	_reset_stuck_state()
	_pickup_target = null
	_pickup_check_timer = 0.0
	
	# Resetear percepción (olvidar enemigos)
	if perception_sys:
		perception_sys.reset()
	
	# Re-inicializar rol táctico (por si cambió en caliente)
	_tactical_role = TacticalRole.for_npc(self)
	
	# Re-equipar arma
	_equipar_arma()
	_aplicar_color_equipo()
	
	# Re-crear overlay de depuración si está activo
	_setup_debug_overlay()
	
	# Buscar core enemigo y re-evaluar
	call_deferred("_find_enemy_core")
	
	_debug("RESPAWNEADO")

# ─────────────────────────────────────────
# HELPERS DEL SISTEMA DE ROLES TÁCTICOS
# ─────────────────────────────────────────

## Devuelve la velocidad de movimiento ajustada por el rol.
## base_speed: velocidad base para el estado actual.
func _role_speed(role: TacticalRole, base_speed: float) -> float:
	if role:
		return base_speed * role.speed_multiplier
	return base_speed


## Devuelve el radio de deambulación para roaming según el rol.
## Defensores: radio corto (no se alejan). Asalto: radio largo.
## Patrulleros: radio medio. Flanqueadores: radio largo.
func _role_wander_radius(role: TacticalRole) -> float:
	if not role:
		return 20.0
	match role.movement_profile:
		TacticalRole.MovementProfile.DEFENSIVE:
			return 10.0  # Poco radio: se queda cerca
		TacticalRole.MovementProfile.AGGRESSIVE:
			return 25.0  # Radio grande: busca el frente
		TacticalRole.MovementProfile.FLANKING:
			return 22.0  # Radio amplio: busca ángulos
		TacticalRole.MovementProfile.PATROL:
			return 18.0  # Radio medio: recorre sin alejarse
		_:
			return 20.0


## Obtiene el core del equipo del bot (su propia base) para
## calcular distancias defensivas.
func _get_own_core() -> Node:
	if equipo_id == int(Enums.Equipo.AZUL):
		return GameState.core_blue if is_instance_valid(GameState.core_blue) else null
	elif equipo_id == int(Enums.Equipo.ROJO):
		return GameState.core_red if is_instance_valid(GameState.core_red) else null
	return null


## Devuelve la distancia del bot a su propio core (base).
## Retorna 0.0 si no hay core registrado.
func _get_dist_to_own_core() -> float:
	var core: Node = _get_own_core()
	if core and is_instance_valid(core) and core.is_inside_tree():
		return global_position.distance_to(core.global_position)
	return 0.0


# ─────────────────────────────────────────
# DEBUG OVERLAY
# ─────────────────────────────────────────

## Crea o destruye el overlay de depuración según el estado global.
func _setup_debug_overlay() -> void:
	if BotDebugOverlay.enabled:
		_add_debug_overlay()
	else:
		_remove_debug_overlay()

## Agrega el overlay de depuración como hijo.
func _add_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return
	if not DEBUG_OVERLAY:
		return
	var overlay: Node3D = DEBUG_OVERLAY.instantiate()
	add_child(overlay)
	_debug_overlay = overlay

## Elimina el overlay de depuración.
func _remove_debug_overlay() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
		_debug_overlay = null

## Alterna el estado global del overlay y actualiza todos los NPCs.
static func toggle_debug_overlay_all() -> void:
	BotDebugOverlay.enabled = not BotDebugOverlay.enabled
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var npcs: Array[Node] = tree.get_nodes_in_group("npc")
	for npc in npcs:
		if npc is NpcBase:
			npc._setup_debug_overlay()
	print("[NpcBase] Debug overlay %s para %d NPCs" % [
		"ACTIVADO" if BotDebugOverlay.enabled else "DESACTIVADO", npcs.size()
	])

func _debug(msg: String) -> void:
	print("[NPC #%d | %s] %s" % [_npc_id, GameState.nombre_equipo(equipo_id), msg])
