# scripts/ai/states/state_roaming.gd
# ──────────────────────────────────────────────────────────────────
# STATE_ROAMING — Deambular / Patrullar
#
# Estado por defecto cuando no hay enemigos, objetivos urgentes
# ni situación de peligro. El bot navega hacia la base enemiga
# (objetivo semántico) o deambula si no hay un marcador disponible.
#
# Comportamiento migrado de BehaviorPatrol.
#
# ── TRANSICIONES DE SALIDA ──
# → HUNTING:      Si hay memoria de posición enemiga
# → COMBAT:       Si hay enemigos visibles
# → RETREATING:   Si la salud es baja y hay core aliado cerca
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateRoaming


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

const PRIORITY_PATROL: float = 10.0
const ROUTE_RECHECK_INTERVAL: float = 1.0

## Enfriamiento tras completar un camino para roles agresivos (asalto/flanqueo):
## no pueden volver a tomar otro camino durante este tiempo, para evitar que
## reencaucen un camino que los devuelva hacia su propia base.
const ROUTE_COOLDOWN_AGGRESSIVE: float = 30.0

## Tiempo máximo (segundos) que un rol agresivo (asalto/flanqueo) puede estar
## fuera de un camino authored de forma "idle" (deambulando/campeando por su
## cuenta) antes de que el watchdog lo fuerce a volver al camino más cercano
## disponible y re-evaluar. El empuje al core tras completar un camino (cooldown
## post-ruta) y las ocasiones especiales (combate, buscar recursos/cobertura)
## NO cuentan como tiempo fuera de ruta.
const OFF_ROUTE_MAX_DURATION: float = 10.0

## Duración mínima y máxima del barrido local antes de buscar un camino.
const ROAM_MIN_TIME: float = 2.0
const ROAM_MAX_TIME: float = 5.0

## Distancia en unidades bajo la cual un camino del rol se considera "cerca"
## y, por tanto, prioritario sobre el generico. Si el camino de rol está más
## lejos, el bot recorre el generico como arteria para re-acercarse.
const ROLE_NEAR_RADIUS: float = 15.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO

## Cobertura actualmente reservada por este estado. Se libera al cambiar
## de objetivo/estado para evitar que un punto quede bloqueado indefinidamente.
var _reserved_cover: Node = null

## Seguimiento de los caminos authored del mapa actual.
var _route_navigator: BotAuthoredRouteNavigator = BotAuthoredRouteNavigator.new()
var _next_route_search_time: float = 0.0

## Sub-fase del ciclo roaming: barrido local (ROAM) o seguir un camino (ROUTE).
enum RoamPhase { ROAM, ROUTE }

## Fase actual del ciclo roaming.
var _phase: int = RoamPhase.ROAM

## Tiempo restante del barrido local antes de buscar un camino.
var _roam_timer: float = 0.0

## Indica que acabamos de completar un camino (para roles agresivos empujar al core).
var _just_completed_path: bool = false

## Instante (segundos, Time.get_ticks_msec) hasta el cual un rol agresivo no
## puede volver a tomar un camino authored tras completar uno.
var _route_cooldown_until: float = 0.0

## Tiempo acumulado (segundos) que un rol agresivo lleva sin seguir un camino
## authored de forma idle. El watchdog usa esto para volverlo al camino más
## cercano si se desorienta por el mapa. Solo aplica a asalto/flanqueo.
var _off_route_time: float = 0.0

# (FloorRouter removido — LinkJump3D eliminado del proyecto)


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	_release_reserved_cover()
	_route_navigator.clear()
	_next_route_search_time = 0.0
	_phase = RoamPhase.ROAM
	_just_completed_path = false
	_route_cooldown_until = 0.0
	_off_route_time = 0.0
	_roam_timer = _make_roam_duration()
	movement_cmd.reset()
	if decision_system:
		decision_system.combat_command.cease_fire = true

	var stuck: StuckHandler = movement.stuck_handler if movement else null
	if stuck != null and not stuck.stuck_resolved.is_connected(_on_stuck_resolved):
		stuck.stuck_resolved.connect(_on_stuck_resolved)


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── ¿Congelado? (sistema unificado BotBase) ──
	if bot.is_frozen:
		# Quieto: no moverse ni disparar
		movement_cmd.set_hold()
		combat_cmd.cease_fire = true
		return

	# ── Verificar transiciones prioritarias ──
	if _check_transitions():
		return

	# ── Prioridad de recursos (problema 2) ──
	# Si no hay enemigo visible ni combate, reponer vida/municiones tiene
	# prioridad sobre campar, órdenes de TeamAI o el radio defensivo. Así un bot
	# idle con poca vida o balas va a recargarlas antes que quedarse quieto.
	if _check_pickups():
		return

	# El francotirador ocupa siempre una cobertura de un solo sentido y se
	# mantiene allí hasta que aparezca un enemigo visible. Si el mapa no tiene
	# una, conserva el comportamiento normal como fallback seguro.
	if _maintain_sniper_camp():
		return

	# Sin amenaza confirmada, la orientación por defecto es la base enemiga.
	# La atención periférica o por daño se aplica después en DecisionSystem y
	# tiene prioridad temporal sobre este comando base.
	_aim_toward_enemy_base()

	# ── 1. Ejecutar según orden de TeamAI (FASE 6) ──
	if _execute_order():
		return

	# ── 2. Radio defensivo: volver a la base si nos alejamos ──
	if _check_defense_radius():
		return

	# ── 3. Ciclo roaming: barrido local → buscar camino ──
	_execute_roam_cycle(_delta)


## Mantiene la cámara hacia la base enemiga cuando no hay un enemigo en POV.
func _aim_toward_enemy_base() -> void:
	if bot == null or bot._enemy_core == null or not is_instance_valid(bot._enemy_core):
		return
	if not bot._enemy_core.is_inside_tree():
		return
	combat_cmd.set_aim(bot._enemy_core.global_position + Vector3.UP * 1.0)


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

## Verifica si debemos salir de Roaming por eventos externos.
## Retorna true si transicionó a otro estado.
func _check_transitions() -> bool:
	if bot != null and bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return true
	# ── ¿Enemigo visible? → COMBAT ──
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return true

	# ── ¿Memoria de enemigo? → HUNTING ──
	if memory and memory.has_enemy_memory() and not perception.has_visible_enemies():
		change_state(BotState.StateType.HUNTING)
		return true

	# ── ¿Salud baja y cerca de base? → RETREATING ──
	if health_pct() < 0.25 and _dist_to_own_core() < 15.0:
		change_state(BotState.StateType.RETREATING)
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

func _check_defense_radius() -> bool:
	var role: TacticalRole = _get_role()
	if role and role.base_defense_radius > 0.0:
		# Si el bot ya sigue una ruta authored DE ROL, esa ruta tiene prioridad
		# sobre el radio defensivo. Sin esto, un PATRULLADOR (radio 40) cuya ruta
		# recorre todo el mapa es arrastrado de vuelta a la base cada vez que
		# supera el radio y luego reanuda la ruta: avanza y retrocede en bucle.
		# En cambio, una ruta GENERICA (circulación para re-agruparse) NO
		# exonera: un defensor no debe abandonar su muro/base por pasear por un
		# camino generico lejano, así que el radio defensivo lo trae de vuelta.
		if _route_navigator.has_active_route():
			var active_route: CaminoBot = _route_navigator.get_current_route()
			if active_route != null and active_route.role == CaminoBot.Role.GENERIC:
				return _return_to_base_from_defense_radius(role)
			return false
		return _return_to_base_from_defense_radius(role)
	return false


## Navega de vuelta al core propio si el bot ha superado su radio defensivo.
## Retorna true si realmente había que volver (y ya navega hacia la base).
func _return_to_base_from_defense_radius(role: TacticalRole) -> bool:
	if bot == null:
		return false
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
		if dist_to_base > role.base_defense_radius:
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
			movement_cmd.sprint = true
			return true
	return false


# ══════════════════════════════════════════════════════════════════
# PICKUPS
# ══════════════════════════════════════════════════════════════════

func _check_pickups() -> bool:
	# Las necesidades de nivel 1 y 2 son objetivos oportunistas: no bloquean
	# combate ni rutas, pero se atienden durante patrulla.
	if bot == null or not is_instance_valid(bot) or bot.tactical_sys == null:
		return false
	if not bot.tactical_sys.has_noncritical_resource_need():
		return false
	var pickup: Node = bot.tactical_sys.get_priority_pickup()
	if pickup == null or not is_instance_valid(pickup) or not pickup.is_inside_tree():
		return false
	_nav_target = pickup.global_position
	movement_cmd.set_navigate(_nav_target, _role_speed(4.8))
	movement_cmd.sprint = true
	# Buscar recursos es una ocasión especial permitida: no cuenta como tiempo
	# fuera de ruta para asalto/flanqueo.
	if _role_is_aggressive():
		_off_route_time = 0.0
	return true


# ══════════════════════════════════════════════════════════════════
# DECISIÓN: AVANZAR A LA BASE VS DEAMBULAR
# ══════════════════════════════════════════════════════════════════

## Nombre histórico para compatibilidad: valida el marcador de base enemigo.
func _has_valid_core() -> bool:
	if bot == null:
		return false
	var base_anchor: Node3D = bot._enemy_core
	return base_anchor != null and is_instance_valid(base_anchor) and base_anchor.is_inside_tree()


func _should_patrol_instead() -> bool:
	var role: TacticalRole = _get_role()
	if role == null:
		return randf() < 0.3
	match role.movement_profile:
		Roles.MovementProfile.PATROL:
			return randf() < 0.4
		Roles.MovementProfile.DEFENSIVE:
			return randf() < 0.3
		_:
			return randf() < 0.2


## Nombre histórico para compatibilidad: avanza hacia el marcador de base enemigo.
func _advance_to_core() -> void:
	if bot == null or bot._enemy_core == null:
		_wander()
		return

	var base_anchor: Node3D = bot._enemy_core
	if bot.global_position.distance_to(base_anchor.global_position) < 4.0:
		_objective_reached = true

	if _follow_authored_route():
		return

	# Con salud baja, buscar cobertura antes que seguir avanzando.
	if _get_health_pct() < 0.35 and _seek_cover():
		return
	_release_reserved_cover()

	# Fallback seguro para mapas que todavía no tienen caminos configurados.
	if _nav_target == Vector3.ZERO or _objective_reached or _is_nav_finished():
		# El offset de aproximación puede caer fuera del NavMesh (sobre una
		# pared, un hueco o fuera de límites). Si dejáramos ese punto sin
		# corregir, el bot elegiría un destino inalcanzable y se quedaría
		# parado reeligiendo el mismo cada tick ("pegado" al avanzar).
		var raw_target: Vector3 = base_anchor.global_position + _get_core_approach_offset()
		_nav_target = _snap_to_navmesh(raw_target, base_anchor.global_position)
		_objective_reached = false

	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	if not bot.is_frozen:
		movement_cmd.sprint = true


func _follow_authored_route() -> bool:
	if bot == null:
		return false

	# Durante el enfriamiento post-camino, los roles agresivos NO vuelven a
	# tomar un camino (evita reencauzar y devolverse hacia la base).
	if _role_is_aggressive() and _route_cooldown_active():
		return false

	var now: float = Time.get_ticks_msec() / 1000.0
	if _route_navigator.has_active_route():
		_route_navigator.advance_if_reached(bot.global_position)
		if _route_navigator.has_active_route():
			_nav_target = _route_navigator.get_current_target()
			movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
			movement_cmd.sprint = not bot.is_frozen
			return true

	if now < _next_route_search_time:
		return false
	_next_route_search_time = now + ROUTE_RECHECK_INTERVAL

	var map_root: Node = _get_map_root()
	var route_role: int = _get_route_role_for_bot()
	if map_root == null or route_role < 0:
		return false

	var excluded_route_ids: Dictionary = _route_navigator.get_completed_route_ids()
	var route: CaminoBot = _route_navigator.find_best_route(map_root, route_role, bot.global_position, excluded_route_ids)
	if route == null or not _route_navigator.start_route(route, bot.global_position, route_role):
		return false

	_nav_target = _route_navigator.get_current_target()
	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	movement_cmd.sprint = not bot.is_frozen
	_debug("Camino %s seleccionado" % _get_route_label(route))
	return true


func _get_route_role_for_bot() -> int:
	var role: TacticalRole = _get_role()
	if role == null:
		return -1
	match role.type:
		Roles.Type.ASALTO:
			return CaminoBot.Role.ASSAULT
		Roles.Type.FLANQUEADOR:
			return CaminoBot.Role.FLANKER
		Roles.Type.DEFENSOR, Roles.Type.FRANCOTIRADOR:
			return CaminoBot.Role.DEFENDER
		Roles.Type.VERSATIL:
			return CaminoBot.Role.FLANKER if role.flanking_bias > 0.5 else CaminoBot.Role.ASSAULT
		Roles.Type.PATRULLADOR:
			return CaminoBot.Role.PATROL
		Roles.Type.APOYO:
			return CaminoBot.Role.SUPPORT
		_:
			return -1


func _make_roam_duration() -> float:
	return randf_range(ROAM_MIN_TIME, ROAM_MAX_TIME)


func _start_roam_phase() -> void:
	_phase = RoamPhase.ROAM
	_roam_timer = _make_roam_duration()


func _role_is_aggressive() -> bool:
	var role: TacticalRole = _get_role()
	return role != null and role.type in [Roles.Type.ASALTO, Roles.Type.FLANQUEADOR]


## Inicia el enfriamiento que impide a un rol agresivo tomar otro camino
## durante ROUTE_COOLDOWN_AGGRESSIVE segundos tras completar el anterior.
## El contador SOLO arranca si el bot está más cerca de la base ENEMIGA que de
## la propia (está terminando una ruta en territorio hostil y debe empujar al
## core). Si está más cerca de su propia base, no se activa y puede tomar otra
## ruta de inmediato sin devolverse.
func _start_route_cooldown() -> void:
	if not _is_closer_to_enemy_base():
		return
	_route_cooldown_until = (Time.get_ticks_msec() / 1000.0) + ROUTE_COOLDOWN_AGGRESSIVE


## Retorna true si el bot está más cerca de la base enemiga MÁS PRÓXIMA que de la
## base propia MÁS PRÓXIMA, según los props "base_origins" ("Origen base azul" /
## "Origen base roja"). Soporta varias bases por equipo (usa la más cercana de
## cada uno). Si un lado no tiene prop, hace fallback a las bases/cores actuales
## para no romper mapas que aún no tengan estos marcadores.
func _is_closer_to_enemy_base() -> bool:
	var bot_ref: BotBase = bot
	if bot_ref == null or not is_instance_valid(bot_ref):
		return false
	var own_team: int = bot_ref.equipo_id
	var enemy_team: int = bot_ref._get_enemy_team_id()
	if own_team < 0 or enemy_team < 0:
		return false
	var tree: SceneTree = bot_ref.get_tree()
	if tree == null or bot_ref.is_inside_tree() == false:
		return false

	var pos: Vector3 = bot_ref.global_position
	var origins: Array[Node] = tree.get_nodes_in_group(&"base_origins")
	var own_dist: float = INF
	var enemy_dist: float = INF
	for origin: Node in origins:
		if not is_instance_valid(origin) or not origin is Node3D:
			continue
		var oteam: int = int(origin.get("team_id"))
		var d: float = pos.distance_to((origin as Node3D).global_position)
		if oteam == own_team:
			own_dist = minf(own_dist, d)
		elif oteam == enemy_team:
			enemy_dist = minf(enemy_dist, d)

	# Fallback: si un lado no tiene prop de origen, usar la base/core actual.
	if own_dist == INF:
		var own_core: Node = bot_ref._get_own_core()
		if own_core != null and is_instance_valid(own_core):
			own_dist = pos.distance_to(own_core.global_position)
	if enemy_dist == INF:
		var enemy_core: Node = bot_ref._enemy_core
		if enemy_core != null and is_instance_valid(enemy_core):
			enemy_dist = pos.distance_to(enemy_core.global_position)

	if own_dist == INF or enemy_dist == INF:
		return false
	return enemy_dist < own_dist


## Retorna true si el rol agresivo sigue dentro del enfriamiento post-camino.
func _route_cooldown_active() -> bool:
	return (Time.get_ticks_msec() / 1000.0) < _route_cooldown_until


## Barrido local corto: recorre coberturas/zonas cercanas mientras espera
## el fin del temporizador. Reutiliza el deambular por puntos del mapa.
func _local_sweep() -> void:
	_wander()


## Ejecuta el ciclo roaming <-> camino.
func _execute_roam_cycle(delta: float) -> void:
	# ── Seguimiento de tiempo fuera de ruta (problema 3: asalto/flanqueo) ──
	# Estar "sobre un camino" o en una ocasión especial (empuje al core justo tras
	# completar una ruta, o buscar recursos/cobertura vía _check_pickups) reinicia
	# el contador. En cualquier otro caso (deambular/campar idle) el tiempo
	# acumula y, al superar OFF_ROUTE_MAX_DURATION, se fuerza volver a un camino.
	if _route_navigator.has_active_route():
		_off_route_time = 0.0
	elif _role_is_aggressive() and _route_cooldown_active():
		# Empuje al core tras completar un camino: ocasión especial, no cuenta.
		_off_route_time = 0.0
	else:
		_off_route_time += delta

	# ── Watchdog: volver a un camino antes de desorientarse por el mapa. ──
	if _role_is_aggressive() and _off_route_time >= OFF_ROUTE_MAX_DURATION:
		_off_route_time = 0.0
		if _try_force_return_to_route():
			return

	# ── Si hay un camino activo, seguirlo. ──
	if _route_navigator.has_active_route():
		if not _advance_active_route():
			_just_completed_path = true
			_start_route_cooldown()
		return

	# ── Sin camino activo: ¿barrido local en curso? ──
	if _phase == RoamPhase.ROAM:
		_roam_timer -= delta
		if _roam_timer > 0.0:
			_local_sweep()
			return

	# ── Enfriamiento post-camino: los roles agresivos NO toman otro camino y
	#    empujan directo al core enemigo, para no devolverse hacia la base. ──
	if _role_is_aggressive() and _route_cooldown_active():
		_advance_to_core()
		return

	# ── Buscar un camino ahora. ──
	if _try_start_route_for_role():
		_just_completed_path = false
		return

	# ── No hay camino disponible. ──
	if _just_completed_path and _role_is_aggressive():
		# Asalto/flanqueo: al terminar su camino y no hallar otro, empujan
		# directo al core enemigo en lugar de deambular sin rumbo.
		_just_completed_path = false
		_advance_to_core()
		return
	_just_completed_path = false

	# ── Fallback: recomponerse hacia la red generica antes de vagar. ──
	# Si el bot no tiene camino a mano, va al camino generico más cercano para
	# reengancharse (el autor conecta los genericos con los específicos del rol).
	if not _just_completed_path and _try_go_to_nearest_generic():
		_off_route_time = 0.0
		return

	# ── Fallback final: barrido local (seguir vagando). ──
	_start_roam_phase()
	_local_sweep()


## Dirige al bot hacia el punto más cercano de la red generica (camino que
## cualquier rol comparte). Retorna true si consiguió un destino que seguir.
## Es ADITIVO y con fallback: si no hay camino generico, no cambia nada.
func _try_go_to_nearest_generic() -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var map_root: Node = _get_map_root()
	if map_root == null:
		return false
	var target: Vector3 = GenericRouteHelper.nearest_generic_point(map_root, bot.global_position)
	if target == Vector3.ZERO:
		return false
	# No molestarse si ya estamos encima del camino generico.
	if bot.global_position.distance_to(target) <= 1.5:
		return false
	_nav_target = target
	movement_cmd.set_navigate(target, _role_speed(4.2))
	movement_cmd.sprint = not bot.is_frozen
	_debug("Sin camino: yendo a camino generico más cercano")
	return true


## Avanza por el camino activo. Retorna true si todavía queda camino.
func _advance_active_route() -> bool:
	_route_navigator.advance_if_reached(bot.global_position)
	if _route_navigator.has_active_route():
		_nav_target = _route_navigator.get_current_target()
		movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
		movement_cmd.sprint = not bot.is_frozen
		return true
	return false


## Watchdog (problema 3): fuerza a un rol agresivo a volver al camino disponible
## más cercano cuando lleva demasiado tiempo sin seguir uno (desorientación).
## Retorna true si logró encauzar en un camino.
func _try_force_return_to_route() -> bool:
	if bot == null:
		return false
	var map_root: Node = _get_map_root()
	var route_role: int = _get_route_role_for_bot()
	if map_root == null or route_role < 0:
		return false
	var excluded: Dictionary = _route_navigator.get_completed_route_ids()
	var candidates: Array[CaminoBot] = _collect_route_candidates(map_root, route_role, excluded)
	if candidates.is_empty():
		return false
	var route: CaminoBot = _pick_route_nearest(candidates, bot.global_position)
	if route == null or not _route_navigator.start_route(route, bot.global_position, route_role):
		return false
	_nav_target = _route_navigator.get_current_target()
	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	movement_cmd.sprint = not bot.is_frozen
	_phase = RoamPhase.ROUTE
	_just_completed_path = false
	_debug("Watchdog fuera de ruta >%ss: volviendo a camino %s" % [
		OFF_ROUTE_MAX_DURATION, _get_route_label(route)])
	return true


## Busca e inicia un camino para el rol del bot. Retorna true si lo inició.
func _try_start_route_for_role() -> bool:
	var map_root: Node = _get_map_root()
	var route_role: int = _get_route_role_for_bot()
	if map_root == null or route_role < 0:
		return false
	var excluded: Dictionary = _route_navigator.get_completed_route_ids()
	var candidates: Array[CaminoBot] = _collect_route_candidates(map_root, route_role, excluded)
	if candidates.is_empty():
		return false
	var route: CaminoBot
	if _role_is_aggressive():
		route = _pick_route_forward(candidates, bot.global_position)
	else:
		route = _pick_route_nearest(candidates, bot.global_position)
	if route == null or not _route_navigator.start_route(route, bot.global_position, route_role):
		return false
	_nav_target = _route_navigator.get_current_target()
	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	movement_cmd.sprint = not bot.is_frozen
	_phase = RoamPhase.ROUTE
	_debug("Camino %s seleccionado" % _get_route_label(route))
	return true


func _collect_route_candidates(map_root: Node, route_role: int, excluded: Dictionary) -> Array[CaminoBot]:
	var role_candidates: Array[CaminoBot] = []
	var generic_candidates: Array[CaminoBot] = []
	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var candidate: CaminoBot = route_node as CaminoBot
		if candidate == null or not candidate.is_usable() or not candidate.is_compatible(route_role):
			continue
		# Los caminos de rol una vez recorridos se excluyen (evita repetirlos
		# en bucle). Los genericos NO se excluyen: son "arterias de circulación"
		# que cualquier bot puede re-pasear para re-agruparse y conectar con su
		# camino de rol (vía next_paths del autor).
		if candidate.role != CaminoBot.Role.GENERIC and excluded.has(candidate.get_instance_id()):
			continue
		# Separamos específicos del rol y genericos (compartidos).
		if candidate.role == route_role:
			role_candidates.append(candidate)
		elif candidate.role == CaminoBot.Role.GENERIC:
			generic_candidates.append(candidate)

	# Prioridad del rol "solo si está cerca": si el bot tiene un camino de su
	# rol a una distancia razonable, lo toma (es el que mejor lo define). En
	# cambio, si su camino de rol está lejos, recorre el camino generico más
	# cercano como arteria de circulación para re-acercarse, y luego conecta
	# con su camino de rol vía next_paths del autor. Es ADITIVO: si no hay
	# genericos, cae al rol aunque esté lejos (única opción).
	if not _has_role_candidate_nearby(role_candidates, bot.global_position):
		if not generic_candidates.is_empty():
			return generic_candidates
	return role_candidates


## Retorna true si existe algún camino del rol a distancia menor que
## ROLE_NEAR_RADIUS del bot (se considera "cerca" y, por tanto, prioritario).
func _has_role_candidate_nearby(role_candidates: Array[CaminoBot], from_position: Vector3) -> bool:
	for route: CaminoBot in role_candidates:
		if _route_distance_sq(route, from_position) <= ROLE_NEAR_RADIUS * ROLE_NEAR_RADIUS:
			return true
	return false


func _pick_route_nearest(candidates: Array[CaminoBot], from_position: Vector3) -> CaminoBot:
	var best: CaminoBot = null
	var best_dist: float = INF
	for route: CaminoBot in candidates:
		var d: float = _route_distance_sq(route, from_position)
		if d < best_dist:
			best_dist = d
			best = route
	return best


## Para roles agresivos: elige el más cercano PERO con sesgo hacia adelante,
## prefiriendo el camino cuyo extremo acerque más al core enemigo (empuje del objetivo).
func _pick_route_forward(candidates: Array[CaminoBot], from_position: Vector3) -> CaminoBot:
	var nearest: CaminoBot = _pick_route_nearest(candidates, from_position)
	if nearest == null:
		return null
	var nearest_dist: float = _route_distance_sq(nearest, from_position)
	var threshold: float = nearest_dist * 1.35
	var core_position: Vector3 = _enemy_core_position(from_position)
	var best: CaminoBot = nearest
	var best_progress: float = -INF
	for route: CaminoBot in candidates:
		if _route_distance_sq(route, from_position) <= threshold:
			var progress: float = _route_forward_progress(route, from_position, core_position)
			if progress > best_progress:
				best_progress = progress
				best = route
	return best


func _route_distance_sq(route: CaminoBot, from_position: Vector3) -> float:
	var start_sq: float = from_position.distance_squared_to(route.get_start_position())
	if not route.reverse_allowed:
		return start_sq
	var end_sq: float = from_position.distance_squared_to(route.get_end_position())
	return minf(start_sq, end_sq)


func _route_forward_progress(route: CaminoBot, from_position: Vector3, core_position: Vector3) -> float:
	var end_progress: float = from_position.distance_to(core_position) - route.get_end_position().distance_to(core_position)
	if route.reverse_allowed:
		var start_progress: float = from_position.distance_to(core_position) - route.get_start_position().distance_to(core_position)
		return maxf(start_progress, end_progress)
	return end_progress


func _enemy_core_position(fallback: Vector3) -> Vector3:
	if bot == null or bot._enemy_core == null:
		return fallback
	var base_anchor: Node3D = bot._enemy_core
	if is_instance_valid(base_anchor) and base_anchor.is_inside_tree():
		return base_anchor.global_position
	return fallback


func _get_map_root() -> Node:
	if bot == null or not bot.is_inside_tree():
		return null
	var current_node: Node = bot
	var scene_root: Node = bot.get_tree().current_scene
	while current_node.get_parent() != null and current_node != scene_root:
		current_node = current_node.get_parent()
	return scene_root if scene_root != null else current_node


## Offset de aproximación al core según el rol y con dispersión real.
## FLANQUEADOR intenta atacar por los lados; DEFENSOR/APOYO se mantienen
## a distancia; VERSÁTIL mezcla. El offset es determinista por bot (para
## que sea estable entre ticks) pero varía ampliamente según el rol.
func _get_core_approach_offset() -> Vector3:
	var bot_seed: int = bot.get_instance_id() if bot else 0
	var role: TacticalRole = _get_role()

	# Radio base de dispersión (más amplio que el antiguo ±4).
	var spread_base: float = 8.0
	var lateral_bias: float = 0.0
	var distance_bias: float = 0.0

	if role:
		match role.movement_profile:
			Roles.MovementProfile.FLANKING:
				# Flanquea por los costados: gran desplazamiento lateral.
				lateral_bias = 6.0
				spread_base = 10.0
			Roles.MovementProfile.DEFENSIVE:
				# Se mantiene a distancia: menos lateral, más lejos.
				distance_bias = 6.0
				spread_base = 7.0
			Roles.MovementProfile.PATROL:
				distance_bias = 3.0
				spread_base = 8.0
			_:
				# AGGRESSIVE: adelante con algo de lateral.
				lateral_bias = 3.0
				spread_base = 8.0

	# Variación determinista por bot (evita que todos se apilen).
	var x_variation: float = float((bot_seed * 17) % int(spread_base * 2.0) - spread_base)
	var z_variation: float = float((bot_seed * 31) % int(spread_base * 2.0) - spread_base)

	# Lateral según sesgo de flanqueo del rol (si existe).
	if role and role.flanking_bias > 0.0:
		lateral_bias += role.flanking_bias * 4.0

	# Elegir lado: derecha o izquierda según el seed del bot.
	var side: float = 1.0 if (bot_seed % 2 == 0) else -1.0

	return Vector3(
		x_variation + side * lateral_bias,
		0.0,
		z_variation - distance_bias
	)


## Busca la cobertura más cercana disponible y navega hacia ella.
## Retorna true si encontró y se dirigió a una cobertura.
## El francotirador convierte los one_way_low_wall en puestos de tiro fijos.
## No persigue el core ni genera wander mientras se desplaza o permanece en
## su punto reservado. Al aparecer un enemigo, _check_transitions() conserva
## prioridad y cambia a COMBAT normalmente.
func _maintain_sniper_camp() -> bool:
	var role: TacticalRole = _get_role()
	if role == null or role.type != Roles.Type.FRANCOTIRADOR:
		return false
	if _reserved_cover == null or not is_instance_valid(_reserved_cover) or not _reserved_cover.is_inside_tree():
		if bot == null or bot.tactical_sys == null:
			return false
		var camp: Node = bot.tactical_sys.get_nearest_available_cover()
		if camp == null:
			return false
		_release_reserved_cover()
		if camp.has_method("occupy"):
			camp.occupy(bot)
		_reserved_cover = camp
		_nav_target = camp.get_cover_position()
	
	var camp_target: Vector3 = _reserved_cover.get_cover_position()
	if bot.global_position.distance_to(camp_target) > 1.5:
		movement_cmd.set_navigate(camp_target, _role_speed(3.2))
		return true
	movement_cmd.set_hold()
	# Re-encarar el frente de la cobertura (el lado del enemigo) mientras el
	# francotirador permanece apostado. Sin esto, al estar quieto sin objetivo
	# el barrido de vigilancia de 360° rota el cuerpo libremente y el bot puede
	# quedar apuntando hacia atrás tras un muro de un sentido.
	_face_cover_front()
	return true


## Orienta al bot hacia el frente de la cobertura (el lado de la amenaza)
## mientras campea apostado. Si hay un objetivo vivo, el CombatSystem ya lo
## encara vía _aim_at_target_entity() (aim_at_position queda ZERO), así que
## no interferimos.
func _face_cover_front() -> void:
	if bot == null or _reserved_cover == null or not is_instance_valid(_reserved_cover):
		return
	if has_target():
		return
	var front: Vector3 = _cover_front_direction()
	if front.length_squared() < 0.001:
		return
	combat_cmd.aim_at_position = bot.global_position + front * 10.0


## Dirección global hacia el frente de la cobertura (lado del que protege).
## Convención: el eje local +Z del CoverPoint apunta hacia el frente. Para el
## muro bajo de un sentido, el CoverBack queda en el lado seguro (-Z) y su +Z
## señala hacia el frente/enemigo (+Z).
func _cover_front_direction() -> Vector3:
	var cover: Node = _reserved_cover
	if cover == null or not is_instance_valid(cover) or not (cover is Node3D):
		return Vector3.ZERO
	var cover_node: Node3D = cover as Node3D
	var basis: Basis = cover_node.global_transform.basis if cover_node.is_inside_tree() \
		else cover_node.transform.basis
	return basis.z.normalized()


func _seek_cover() -> bool:
	if bot == null or not bot.is_inside_tree() or bot.tactical_sys == null:
		return false
	# Centralizar la selección aquí evita que el fallback de poca salud salte
	# las reglas por rol (asalto/flanqueo) o las preferencias de props.
	var best: Node = bot.tactical_sys.get_nearest_available_cover()
	if best == null:
		return false

	if best != _reserved_cover:
		_release_reserved_cover()
		if best.has_method("occupy"):
			best.occupy(bot)
		_reserved_cover = best
	var cover_target: Vector3 = best.get_cover_position()
	# Trampolín opcional vía camino generico hacia la cobertura. Si no hay
	# camino útil, configuración directa por navmesh (comportamiento actual).
	var via: Vector3 = GenericRouteHelper.waypoint_toward(
		_get_map_root(), bot.global_position, cover_target)
	if via != Vector3.ZERO and bot.global_position.distance_to(cover_target) > 20.0:
		_nav_target = via
		movement_cmd.set_navigate(via, _role_speed(4.5))
		movement_cmd.sprint = true
		_debug("Cobertura %s vía camino generico" % best.name)
	else:
		_nav_target = cover_target
		movement_cmd.set_navigate(cover_target, _role_speed(4.0))
		movement_cmd.sprint = true
		_debug("Cobertura %s seleccionada" % best.name)
	return true


func exit(_next_state: BotState) -> void:
	_release_reserved_cover()


func _release_reserved_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and "release" in _reserved_cover:
		_reserved_cover.release(bot)
	_reserved_cover = null


func _get_route_label(route: CaminoBot) -> String:
	if route.route_id != StringName():
		return str(route.route_id)
	return route.name


func _wander() -> void:
	var wander_radius: float = _get_wander_radius()

	if _nav_target == Vector3.ZERO or _is_nav_finished():
		# ── Patrulla con propósito: recorrer coberturas/zonas del mapa ──
		if _wander_to_cover_waypoint():
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
			movement_cmd.sprint = true
			return

		# ── Posición aleatoria en el navmesh ──
		var nav_map_rid: RID
		if navigation and navigation.agent:
			nav_map_rid = navigation.agent.get_navigation_map()
		elif bot and bot.navigation_agent:
			nav_map_rid = bot.navigation_agent.get_navigation_map()
		else:
			nav_map_rid = RID()

		var raw_target: Vector3 = bot.global_position + Vector3(
			randf_range(-wander_radius, wander_radius), 0,
			randf_range(-wander_radius, wander_radius))

		if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
			_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		else:
			_nav_target = raw_target

	movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
	movement_cmd.sprint = true  # Wander también en sprint


## Patrulla con propósito: recorre puntos relevantes del mapa (coberturas,
## zonas) en vez de deambular sin rumbo. Retorna true si encontró un punto.
func _wander_to_cover_waypoint() -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var role: TacticalRole = _get_role()
	# Asalto y flanqueo no convierten props de cobertura en waypoints de ruta:
	# solo los emplean desde COMBAT/COVER_RELOAD cuando realmente lo necesitan.
	if role != null and role.type in [Roles.Type.ASALTO, Roles.Type.FLANQUEADOR]:
		return false
	var points: Array[Node] = []

	# Reunir coberturas y zonas activas como puntos de patrulla.
	# Duck-typing: CoverPoint/ZonePoint son props opcionales; usamos grupos.
	# Los puntos de troneras/muros bajos reciben duplicación ponderada para que
	# los bots los prefieran cuando no hay un objetivo más urgente.
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	for cover: Node in covers:
		if cover != null and is_instance_valid(cover):
			points.append(cover)
			var cover_parent: Node = cover.get_parent()
			# Solo defensores prefieren detenerse en muros bajos reutilizables.
			# El patrullador NO debe campear un muro: recorre su ruta de patrullaje.
			if role != null and role.type == Roles.Type.DEFENSOR \
			and cover_parent != null and cover_parent.is_in_group(&"cover_props"):
				points.append(cover)
				points.append(cover)
			if cover.is_in_group(&"peek_cover_points"):
				points.append(cover)
				points.append(cover)
	var zones: Array[Node] = bot.get_tree().get_nodes_in_group(&"zone_points")
	for zone: Node in zones:
		if zone != null and is_instance_valid(zone) and zone.get("is_active"):
			points.append(zone)

	if points.is_empty():
		return false

	# Elegir un punto distinto al actual (para no quedarse fijo).
	var target: Node = points[randi() % points.size()]
	if target.is_inside_tree():
		_nav_target = target.global_position
		return true
	return false


# (Freeze unificado en BotBase — FASE 4. El bot reanuda naturalmente
#  al descongelarse porque execute() corre cada tick de decisión.)
















# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _get_role() -> TacticalRole:
	if bot:
		return bot._tactical_role
	return null


## Porcentaje de salud del bot (0.0 a 1.0).
func _get_health_pct() -> float:
	if bot and bot.max_health > 0.0:
		return float(bot.current_health) / float(bot.max_health)
	return 1.0

func _get_own_core() -> Node:
	if bot:
		return bot._get_own_core()
	return null

func _dist_to_own_core() -> float:
	if bot:
		return bot._get_dist_to_own_core()
	return 0.0

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed

func _get_wander_radius() -> float:
	var role: TacticalRole = _get_role()
	if not role:
		return 20.0
	match role.movement_profile:
		Roles.MovementProfile.DEFENSIVE:
			return 10.0
		Roles.MovementProfile.AGGRESSIVE:
			return 25.0
		Roles.MovementProfile.FLANKING:
			return 22.0
		Roles.MovementProfile.PATROL:
			return 18.0
		_:
			return 20.0

func _is_nav_finished() -> bool:
	if navigation:
		return navigation.is_navigation_finished()
	if bot and bot.navigation_agent:
		return bot.navigation_agent.is_navigation_finished()
	return true


## Devuelve el punto más cercano navegable a `raw_target` en el NavMesh.
## Si el NavMesh no está disponible o el punto corregido queda muy lejos del
## original (p. ej. el objetivo estaba fuera del mapa), cae a `fallback`.
## Evita que los bots elijan destinos inalcanzables y se queden parados.
func _snap_to_navmesh(raw_target: Vector3, fallback: Vector3) -> Vector3:
	var nav_map_rid: RID
	if navigation and navigation.agent:
		nav_map_rid = navigation.agent.get_navigation_map()
	elif bot and bot.navigation_agent:
		nav_map_rid = bot.navigation_agent.get_navigation_map()
	if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
		var punto_corregido: Vector3 = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		# Si el punto corregido no está razonablemente cerca del objetivo
		# original, el destino buscado no era navegable: usar el fallback.
		if punto_corregido.distance_to(raw_target) <= 4.0:
			return punto_corregido
	return fallback


## Reanuda el camino desde el punto más cercano después de una recuperación.
func _on_stuck_resolved() -> void:
	if bot == null:
		return
	if _route_navigator.reset_after_stuck(bot.global_position):
		_nav_target = _route_navigator.get_current_target()
	else:
		_nav_target = Vector3.ZERO
	_next_route_search_time = 0.0


# ══════════════════════════════════════════════════════════════════
# ÓRDENES DE EQUIPO — FASE 6
# ══════════════════════════════════════════════════════════════════

## Ejecuta la orden actual del bot según TeamAI.
## Retorna true si la orden fue procesada (el bot tiene una orden activa).
##
## ▶ ASALTO y FLANQUEADOR NUNCA defienden: si reciben orden DEFEND o HOLD,
##   las ignoran y se comportan como FREELANCE (avanzan al frente).
func _execute_order() -> bool:
	if not is_instance_valid(TeamAI):
		return false
	if bot == null:
		return false

	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = order_data.get("type", TeamAI.OrderType.FREELANCE)

	# ── Solo DEFENSOR se queda quieto defendiendo.
	#    Los demas roles ignoran ordenes defensivas.
	var role: TacticalRole = _get_role()
	if role != null and role.type != Roles.Type.DEFENSOR:
		if order_type == TeamAI.OrderType.DEFEND or order_type == TeamAI.OrderType.HOLD:
			order_type = TeamAI.OrderType.FREELANCE

	match order_type:
		TeamAI.OrderType.ATTACK:
			_attack_target()
			return true

		TeamAI.OrderType.DEFEND:
			_defend_position()
			return true

		TeamAI.OrderType.HOLD:
			_execute_hold()
			return true

		TeamAI.OrderType.PATROL:
			if _follow_authored_route():
				return true
			_wander()
			return true

		TeamAI.OrderType.RETURN:
			_return_to_base()
			return true

		TeamAI.OrderType.FREELANCE:
			# FREELANCE: el bot decide por sí mismo
			# Continúa con el comportamiento por defecto (wander/core)
			return false

		_:
			return false


## Ejecuta orden ATTACK: navegar hacia el marcador de base enemiga.
func _attack_target() -> void:
	if _has_valid_core():
		_advance_to_core()
	else:
		# Si no hay marcador de base enemigo, ir hacia la posición de la orden
		var target_pos: Vector3 = bot.get_order_target_position()
		if target_pos != Vector3.ZERO:
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				_nav_target = target_pos
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
		else:
			_wander()


## Ejecuta orden DEFEND: patrullar cerca del core propio.
func _defend_position() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
		var defense_range: float = 12.0

		# Prioridad: seguir un camino authored (rol si está cerca, genérico como
		# arteria de re-acercamiento). Mantiene al defensor sobre la red y evita
		# el wander corto sin rumbo que se veía como "se mueve un poco" sin
		# respetar caminos. La defensa se mantiene: el camino de rol (defensa/
		# patrulla) está cerca de la base, y si no, se re-engancha al genérico.
		if _follow_authored_route():
			return

		# Sin camino activo: acercarse a la red generica más cercana ANTES de
		# deambular, para re-engancharse con un camino del propio rol.
		if _try_go_to_nearest_generic():
			return

		# Si está cerca de la base, cubrir el perímetro (solo si no hay camino).
		if dist_to_base < defense_range:
			if (_nav_target == Vector3.ZERO or _is_nav_finished()) and randf() < 0.65 and _seek_cover():
				return
			var wander_radius: float = 8.0
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				# Wander aleatorio dentro del radio defensivo
				var raw_target: Vector3 = own_core.global_position + Vector3(
					randf_range(-wander_radius, wander_radius), 0,
					randf_range(-wander_radius, wander_radius))
				var nav_map_rid: RID
				if navigation and navigation.agent:
					nav_map_rid = navigation.agent.get_navigation_map()
				elif bot and bot.navigation_agent:
					nav_map_rid = bot.navigation_agent.get_navigation_map()
				else:
					nav_map_rid = RID()
				if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
					_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
				else:
					_nav_target = raw_target
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
		else:
			# Está lejos de la base, regresar (por la red cuando es posible)
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
	else:
		_wander()


## Ejecuta orden HOLD: mantener la posición actual.
func _execute_hold() -> void:
	var order_data: Dictionary = bot.get_current_order()
	var hold_pos: Vector3 = order_data.get("target_position", bot.global_position)

	var dist_to_hold: float = bot.global_position.distance_to(hold_pos)
	if dist_to_hold > 2.0:
		# Volver a la posición de hold
		if _nav_target == Vector3.ZERO:
			_nav_target = hold_pos
		movement_cmd.set_navigate(_nav_target, _role_speed(3.0))
	else:
		# Ya en posición, quieto
		movement_cmd.set_hold()


## Ejecuta orden RETURN: regresar a la base.
func _return_to_base() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist: float = bot.global_position.distance_to(own_core.global_position)
		if dist > 4.0:
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.5))
		else:
			# Ya en base, quedarse quieto o patrullar
			_wander()
	else:
		_wander()
