# Política de roaming exclusivamente guiada por rutas authored.
# Los destinos libres/aleatorios se sustituyen por CaminoBot + NavigationAgent3D.
extends BotState
class_name StateRoamingPolicy

const ROUTE_ACQUIRE_TIMEOUT: float = 15.0
const RESOURCE_SEARCH_TIMEOUT: float = 15.0
const COVER_SEARCH_TIMEOUT: float = 10.0
const BASE_ARRIVAL_DISTANCE: float = 2.8
const ROUTE_REJOIN_DISTANCE: float = 1.6
const ROUTE_RECHECK_INTERVAL: float = 0.75

## Estados de circulación normal. No existe una fase de wander aleatorio.
enum RoamPhase {
	ACQUIRE_ROUTE,
	FOLLOW_ROUTE,
	RETURN_TO_ORIGIN,
}

## Desvíos de recursos no críticos que ocurren dentro de ROAMING.
enum ResourcePhase {
	NONE,
	SEEKING,
	RETURNING_TO_ORIGIN,
	SEEKING_FROM_ORIGIN,
	REJOINING_ROUTE,
}

var _route_navigator: BotAuthoredRouteNavigator = BotAuthoredRouteNavigator.new()
var _phase: int = RoamPhase.ACQUIRE_ROUTE
var _route_acquire_started_at: float = 0.0
var _next_route_search_at: float = 0.0

var _resource_phase: int = ResourcePhase.NONE
var _resource_phase_started_at: float = 0.0
var _resource_target: Node = null

## Se reutiliza para puestos estáticos de francotirador/defensor.
var _reserved_cover: Node = null
var _cover_search_started_at: float = 0.0


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


func enter(_previous_state: BotState) -> void:
	_route_navigator.clear()
	_phase = RoamPhase.ACQUIRE_ROUTE
	_route_acquire_started_at = _now_seconds()
	_next_route_search_at = 0.0
	_resource_phase = ResourcePhase.NONE
	_resource_phase_started_at = 0.0
	_resource_target = null
	_release_reserved_cover()
	_cover_search_started_at = 0.0
	movement_cmd.reset()
	if decision_system != null:
		decision_system.combat_command.cease_fire = true
	var stuck: StuckHandler = movement.stuck_handler if movement != null else null
	if stuck != null and not stuck.stuck_resolved.is_connected(_on_stuck_resolved):
		stuck.stuck_resolved.connect(_on_stuck_resolved)


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	if bot.is_frozen:
		movement_cmd.set_hold()
		combat_cmd.cease_fire = true
		return
	if _check_transitions():
		return
	if _execute_resource_cycle():
		return
	if _maintain_sniper_camp():
		return
	if _maintain_defender_post():
		return
	_aim_toward_enemy_base()
	if _execute_order():
		return
	if _check_defense_radius():
		return
	_execute_roam_cycle()


func exit(_next_state: BotState) -> void:
	_release_reserved_cover()
	_resource_target = null


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES Y ORIENTACIÓN
# ══════════════════════════════════════════════════════════════════

func _check_transitions() -> bool:
	if bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return true
	if perception != null and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return true
	if memory != null and memory.has_enemy_memory() and not perception.has_visible_enemies():
		change_state(BotState.StateType.HUNTING)
		return true
	if health_pct() < 0.25 and _distance_to_own_origin() < 15.0:
		change_state(BotState.StateType.RETREATING)
		return true
	return false


func _aim_toward_enemy_base() -> void:
	if bot == null or bot._enemy_core == null or not is_instance_valid(bot._enemy_core):
		return
	if not bot._enemy_core.is_inside_tree():
		return
	combat_cmd.set_aim(bot._enemy_core.global_position + Vector3.UP)


# ══════════════════════════════════════════════════════════════════
# CIRCULACIÓN SOLO POR CAMINOS AUTHORING
# ══════════════════════════════════════════════════════════════════

func _execute_roam_cycle() -> void:
	if _phase == RoamPhase.RETURN_TO_ORIGIN:
		if _move_to_own_origin():
			_begin_route_acquisition()
		return

	if _route_navigator.has_active_route():
		_phase = RoamPhase.FOLLOW_ROUTE
		if _advance_active_route():
			return
		_begin_route_acquisition()
		return

	if _route_acquire_started_at <= 0.0:
		_begin_route_acquisition()
	if _try_start_route_for_role():
		_phase = RoamPhase.FOLLOW_ROUTE
		return

	if _now_seconds() - _route_acquire_started_at >= ROUTE_ACQUIRE_TIMEOUT:
		_debug("Sin ruta authored durante %.1fs; retorno forzado a origen_base." % ROUTE_ACQUIRE_TIMEOUT)
		_begin_forced_return_to_origin()
		return

	# No se genera un destino aleatorio mientras se busca la ruta.
	movement_cmd.set_hold()


func _begin_route_acquisition() -> void:
	_phase = RoamPhase.ACQUIRE_ROUTE
	_route_acquire_started_at = _now_seconds()
	_next_route_search_at = 0.0
	if movement != null:
		movement.invalidate_navigation_target()


func _begin_forced_return_to_origin() -> void:
	_route_navigator.clear()
	_phase = RoamPhase.RETURN_TO_ORIGIN
	_route_acquire_started_at = 0.0
	_next_route_search_at = 0.0


func _move_to_own_origin() -> bool:
	var origin: Node3D = _get_own_base_origin()
	if origin == null or not is_instance_valid(origin) or not origin.is_inside_tree():
		movement_cmd.set_hold()
		return false
	if bot.global_position.distance_to(origin.global_position) <= BASE_ARRIVAL_DISTANCE:
		movement_cmd.set_hold()
		return true
	movement_cmd.set_navigate(origin.global_position, _role_speed(6.0))
	movement_cmd.sprint = true
	return false


func _try_start_route_for_role() -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var now: float = _now_seconds()
	if now < _next_route_search_at:
		return false
	_next_route_search_at = now + ROUTE_RECHECK_INTERVAL
	var map_root: Node = _get_map_root()
	var route_role: int = _get_route_role_for_bot()
	if map_root == null:
		return false
	var excluded: Dictionary = _route_navigator.get_completed_route_ids()
	var route: CaminoBot = null
	if route_role >= 0:
		route = _route_navigator.find_best_route(map_root, route_role, bot.global_position, excluded)
	# Emergencia segura: si faltan rutas de rol, el bot toma el camino authored
	# utilizable más cercano en vez de fabricar un destino de roam libre.
	if route == null:
		route = _route_navigator.find_nearest_usable_route(map_root, bot.global_position, excluded)
	if route == null or not _route_navigator.start_route(route, bot.global_position, route_role):
		return false
	return _navigate_current_route_target()


func _advance_active_route() -> bool:
	if bot == null:
		return false
	# Mientras el bot recorre una ruta GENÉRICA, se re-comprueba si ya hay una
	# ruta de su rol "cerca" por la que desviarse. Si la encuentra, cambia a ella.
	# Si no, continúa en la genérica hasta terminarla. Nunca interrumpe una ruta
	# de rol ya activa ni fabrica destinos libres.
	if _maybe_switch_to_role_route():
		return true
	_route_navigator.advance_if_reached(bot.global_position)
	if not _route_navigator.has_active_route():
		return false
	if movement != null:
		movement.invalidate_navigation_target()
	return _navigate_current_route_target()


## Evalúa periódicamente si, estando en una ruta genérica, ya hay una ruta del
## rol "cerca" por la que desviarse. Retorna true si se cambió de ruta.
func _maybe_switch_to_role_route() -> bool:
	# Guardas baratas primero: sin bot, sin ruta activa o con ruta no genérica,
	# no hay nada que evaluar (nunca interrumpe una ruta de rol ya activa).
	if bot == null:
		return false
	if not _route_navigator.has_active_route():
		return false
	var active_route: CaminoBot = _route_navigator.get_current_route()
	if active_route == null or active_route.role != CaminoBot.Role.GENERIC:
		return false
	if not bot.is_inside_tree():
		return false
	var now: float = _now_seconds()
	if now < _next_route_search_at:
		return false
	_next_route_search_at = now + ROUTE_RECHECK_INTERVAL
	var role: int = _get_route_role_for_bot()
	if role < 0:
		return false
	var map_root: Node = _get_map_root()
	if map_root == null:
		return false
	var excluded: Dictionary = _route_navigator.get_completed_route_ids()
	var role_route: CaminoBot = _route_navigator.find_best_route(map_root, role, bot.global_position, excluded)
	# find_best_route devuelve la genérica como arteria si la de rol está lejos;
	# solo nos interesa desviarnos cuando ya hay una ruta de rol "cerca".
	if role_route == null or role_route.role == CaminoBot.Role.GENERIC:
		return false
	if not _route_navigator.start_route(role_route, bot.global_position, role):
		return false
	_phase = RoamPhase.FOLLOW_ROUTE
	_debug("Camino genérico -> ruta de rol (%d) al detectarse cerca." % role)
	return _navigate_current_route_target()


func _navigate_current_route_target() -> bool:
	if bot == null or not _route_navigator.has_active_route():
		return false
	var target: Vector3 = _route_navigator.get_current_target()
	movement_cmd.set_navigate(target, _role_speed(4.8))
	movement_cmd.sprint = not bot.is_frozen
	return true


# ══════════════════════════════════════════════════════════════════
# RECURSOS NO CRÍTICOS: 15 s → origen_base → recurso → camino
# ══════════════════════════════════════════════════════════════════

func _execute_resource_cycle() -> bool:
	if bot == null or bot.tactical_sys == null:
		return false
	if _resource_phase == ResourcePhase.NONE:
		if not bot.tactical_sys.has_noncritical_resource_need():
			return false
		_resource_phase = ResourcePhase.SEEKING
		_resource_phase_started_at = _now_seconds()
		_resource_target = null
		# Un desvío a recursos es una excepción temporal a la ruta actual.
		_route_navigator.clear()

	match _resource_phase:
		ResourcePhase.SEEKING:
			if not bot.tactical_sys.has_noncritical_resource_need():
				_begin_resource_route_rejoin()
				return true
			if _now_seconds() - _resource_phase_started_at >= RESOURCE_SEARCH_TIMEOUT:
				_debug("Búsqueda de recurso agotó %.1fs; regreso a origen_base." % RESOURCE_SEARCH_TIMEOUT)
				_begin_resource_return_to_origin()
				return true
			_resource_target = bot.tactical_sys.get_priority_resource_source()
			if _is_valid_resource_target(_resource_target):
				_navigate_to_resource_target(_resource_target)
			else:
				movement_cmd.set_hold()
			return true

		ResourcePhase.RETURNING_TO_ORIGIN:
			_guard_weapon_for_resource_return()
			if _move_to_own_origin():
				_resource_phase = ResourcePhase.SEEKING_FROM_ORIGIN
				_resource_phase_started_at = _now_seconds()
				_resource_target = null
			return true

		ResourcePhase.SEEKING_FROM_ORIGIN:
			_guard_weapon_for_resource_return()
			if not bot.tactical_sys.has_noncritical_resource_need():
				_begin_resource_route_rejoin()
				return true
			if _now_seconds() - _resource_phase_started_at >= RESOURCE_SEARCH_TIMEOUT:
				_begin_resource_route_rejoin()
				return true
			_resource_target = bot.tactical_sys.get_priority_resource_source()
			if _is_valid_resource_target(_resource_target):
				_navigate_to_resource_target(_resource_target)
			else:
				movement_cmd.set_hold()
			return true

		ResourcePhase.REJOINING_ROUTE:
			if _rejoin_route_after_resource():
				return true
			_resource_phase = ResourcePhase.NONE
			_resource_target = null
			return false

	return false


func _begin_resource_return_to_origin() -> void:
	_resource_phase = ResourcePhase.RETURNING_TO_ORIGIN
	_resource_phase_started_at = _now_seconds()
	_resource_target = null
	_route_navigator.clear()


func _begin_resource_route_rejoin() -> void:
	_resource_phase = ResourcePhase.REJOINING_ROUTE
	_resource_phase_started_at = _now_seconds()
	_resource_target = null
	_route_navigator.clear()
	_next_route_search_at = 0.0


func _rejoin_route_after_resource() -> bool:
	if _route_navigator.has_active_route():
		var target: Vector3 = _route_navigator.get_current_target()
		if bot.global_position.distance_to(target) <= ROUTE_REJOIN_DISTANCE:
			return false
		return _navigate_current_route_target()
	if _try_start_route_for_role():
		return true
	if _now_seconds() - _resource_phase_started_at >= ROUTE_ACQUIRE_TIMEOUT:
		# Si ni desde la base se puede reenganchar, ROAMING ejecutará su propio
		# retorno seguro y nunca reemplazará la ruta por wander aleatorio.
		return false
	movement_cmd.set_hold()
	return true


func _is_valid_resource_target(candidate: Node) -> bool:
	return candidate != null and is_instance_valid(candidate) and candidate.is_inside_tree()


func _navigate_to_resource_target(target: Node) -> void:
	if not (target is Node3D):
		movement_cmd.set_hold()
		return
	var target_node: Node3D = target as Node3D
	movement_cmd.set_navigate(target_node.global_position, _role_speed(5.2))
	movement_cmd.sprint = true


func _guard_weapon_for_resource_return() -> void:
	if bot != null and bot.weapon_equip_state != null:
		bot.weapon_equip_state.unequip()


# ══════════════════════════════════════════════════════════════════
# PUESTOS DEFENSIVOS Y COBERTURA ESTÁTICA
# ══════════════════════════════════════════════════════════════════

func _maintain_sniper_camp() -> bool:
	var role: TacticalRole = _get_role()
	if role == null or role.type != Roles.Type.FRANCOTIRADOR:
		return false
	if not _ensure_static_cover(true):
		return false
	return _navigate_or_hold_static_cover()


func _maintain_defender_post() -> bool:
	var role: TacticalRole = _get_role()
	if role == null or role.type != Roles.Type.DEFENSOR:
		return false
	if not _ensure_static_cover(false):
		return false
	return _navigate_or_hold_static_cover()


func _ensure_static_cover(sniper_only: bool) -> bool:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.is_inside_tree():
		return true
	var candidate: Node = _find_static_cover(sniper_only)
	if candidate == null:
		return false
	_release_reserved_cover()
	if candidate.has_method("occupy"):
		candidate.occupy(bot)
	_reserved_cover = candidate
	_cover_search_started_at = _now_seconds()
	return true


func _find_static_cover(sniper_only: bool) -> Node:
	if bot == null or bot.tactical_sys == null or not bot.is_inside_tree():
		return null
	if sniper_only:
		return bot.tactical_sys.get_nearest_available_cover()
	var best_cover: Node = null
	var best_distance: float = INF
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	for cover: Node in covers:
		if cover == null or not is_instance_valid(cover) or not cover.is_inside_tree():
			continue
		if not bool(cover.get("is_defensive_post")):
			continue
		var owner_team: int = int(cover.get("defensive_team_id"))
		if owner_team >= 0 and owner_team != bot.equipo_id:
			continue
		if cover.has_method("is_available") and not cover.is_available(bot):
			continue
		var distance: float = bot.global_position.distance_to((cover as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best_cover = cover
	return best_cover


func _navigate_or_hold_static_cover() -> bool:
	if _reserved_cover == null or not is_instance_valid(_reserved_cover):
		return false
	if not _reserved_cover.has_method("get_cover_position"):
		_release_reserved_cover()
		return false
	var target: Vector3 = _reserved_cover.get_cover_position()
	if bot.global_position.distance_to(target) > ROUTE_REJOIN_DISTANCE:
		if _now_seconds() - _cover_search_started_at >= COVER_SEARCH_TIMEOUT:
			_debug("Puesto defensivo inaccesible tras %.1fs; vuelvo a ruta." % COVER_SEARCH_TIMEOUT)
			_release_reserved_cover()
			return false
		movement_cmd.set_navigate(target, _role_speed(3.4))
		return true
	# Francotiradores/defensores que llegaron a un puesto explícito no tienen
	# límite de permanencia. Los recursos y el combate siguen teniendo prioridad.
	movement_cmd.set_hold()
	_face_cover_front()
	return true


func _release_reserved_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.has_method("release"):
		_reserved_cover.release(bot)
	_reserved_cover = null
	_cover_search_started_at = 0.0


func _face_cover_front() -> void:
	if bot == null or _reserved_cover == null or not is_instance_valid(_reserved_cover):
		return
	if has_target():
		return
	var front: Vector3 = _cover_front_direction()
	if front.length_squared() < 0.001:
		return
	combat_cmd.aim_at_position = bot.global_position + front * 10.0


func _cover_front_direction() -> Vector3:
	if _reserved_cover == null or not is_instance_valid(_reserved_cover) or not (_reserved_cover is Node3D):
		return Vector3.ZERO
	var cover_node: Node3D = _reserved_cover as Node3D
	var basis: Basis = cover_node.global_transform.basis if cover_node.is_inside_tree() else cover_node.transform.basis
	return basis.z.normalized()


# ══════════════════════════════════════════════════════════════════
# ÓRDENES Y RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

func _execute_order() -> bool:
	if bot == null or not is_instance_valid(TeamAI):
		return false
	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = int(order_data.get("type", TeamAI.OrderType.FREELANCE))
	var role: TacticalRole = _get_role()
	if role != null and role.type not in [Roles.Type.DEFENSOR, Roles.Type.FRANCOTIRADOR]:
		if order_type == TeamAI.OrderType.DEFEND or order_type == TeamAI.OrderType.HOLD:
			order_type = TeamAI.OrderType.FREELANCE
	match order_type:
		TeamAI.OrderType.ATTACK, TeamAI.OrderType.PATROL:
			_execute_roam_cycle()
			return true
		TeamAI.OrderType.DEFEND:
			_execute_roam_cycle()
			return true
		TeamAI.OrderType.RETURN:
			_begin_forced_return_to_origin()
			_execute_roam_cycle()
			return true
		TeamAI.OrderType.HOLD:
			if role != null and role.type in [Roles.Type.DEFENSOR, Roles.Type.FRANCOTIRADOR]:
				movement_cmd.set_hold()
				return true
	return false


func _check_defense_radius() -> bool:
	var role: TacticalRole = _get_role()
	if role == null or role.base_defense_radius <= 0.0:
		return false
	if _route_navigator.has_active_route():
		var active_route: CaminoBot = _route_navigator.get_current_route()
		if active_route != null and active_route.role != CaminoBot.Role.GENERIC:
			return false
	if _distance_to_own_origin() <= role.base_defense_radius:
		return false
	_begin_forced_return_to_origin()
	_execute_roam_cycle()
	return true


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

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
	return -1


func _get_map_root() -> Node:
	if bot == null or not bot.is_inside_tree():
		return null
	var tree: SceneTree = bot.get_tree()
	var scene_root: Node = tree.current_scene
	# Fallback a la raíz del árbol si no hay una current_scene formal (p. ej.
	# ejecutando tests o un mapa lanzado sin envolver en un cambio de escena).
	if scene_root == null:
		scene_root = tree.root
	return scene_root


func _get_own_base_origin() -> Node3D:
	if bot == null:
		return null
	return bot._get_own_base_origin()


func _distance_to_own_origin() -> float:
	var origin: Node3D = _get_own_base_origin()
	if origin == null or not is_instance_valid(origin) or not origin.is_inside_tree() or bot == null:
		return INF
	return bot.global_position.distance_to(origin.global_position)


func _get_role() -> TacticalRole:
	return bot._tactical_role if bot != null else null


func _role_speed(base_speed: float) -> float:
	return bot._role_speed(bot._tactical_role, base_speed) if bot != null else base_speed


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _on_stuck_resolved() -> void:
	if bot == null:
		return
	if movement != null:
		movement.invalidate_navigation_target()
	if _route_navigator.reset_after_stuck(bot.global_position):
		_phase = RoamPhase.FOLLOW_ROUTE
		return
	_begin_route_acquisition()
