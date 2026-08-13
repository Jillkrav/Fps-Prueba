# Estado de supervivencia: el bot guarda el arma y prioriza escapar hacia recursos.
extends BotState
class_name StateFleeing

const FLEE_SPEED: float = 7.0
const ARRIVAL_DISTANCE: float = 1.6
const BASE_ARRIVAL_DISTANCE: float = 2.8
const RESOURCE_SEARCH_TIMEOUT: float = 15.0
const COVER_ARRIVAL_DISTANCE: float = 1.6
const COVER_HOLD_DURATION: float = 0.75
const COVER_APPROACH_TIMEOUT: float = 4.0

## FLEEING ya no usa un watchdog global: el límite de 15 s se aplica solo a
## buscar un recurso. Después se completa el retorno forzado a origen_base y
## desde allí se reinicia la adquisición segura de suministros.
enum FleePhase {
	SEEKING_COVER,
	HOLDING_COVER,
	SEEKING_RESOURCE,
	RETURNING_TO_ORIGIN,
	SEEKING_FROM_ORIGIN,
}

var _phase: int = FleePhase.SEEKING_RESOURCE
var _phase_started_at: float = 0.0
var _target_pickup: Node = null
var _reserved_cover: Node = null
var _failed_cover_ids: Dictionary = {}

## Trampolín authored opcional para recorrer la red genérica antes del tramo
## final a un recurso. No existe fallback a wander, cobertura ni spawn aleatorio.
var _generic_waypoint: Vector3 = Vector3.ZERO
var _generic_waypoint_goal: Vector3 = Vector3.ZERO


func _init() -> void:
	state_type = StateType.FLEEING
	state_name = "fleeing"
	max_duration = INF


func enter(_previous_state: BotState) -> void:
	_target_pickup = null
	_reserved_cover = null
	_failed_cover_ids.clear()
	_phase = FleePhase.SEEKING_COVER
	_phase_started_at = _now_seconds()
	_generic_waypoint = Vector3.ZERO
	_generic_waypoint_goal = Vector3.ZERO
	if bot != null and bot.tactical_sys != null:
		bot.tactical_sys.begin_flee()
	_guard_weapon()


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead or bot.tactical_sys == null:
		return
	_guard_weapon()
	combat_cmd.cease_fire = true

	if not bot.tactical_sys.flee_mode_active:
		_exit_after_recovery()
		return

	match _phase:
		FleePhase.SEEKING_COVER:
			if _try_take_cover_before_resource():
				return
			_phase = FleePhase.SEEKING_RESOURCE
			_phase_started_at = _now_seconds()
			return

		FleePhase.HOLDING_COVER:
			movement_cmd.set_hold()
			_face_cover_front()
			if _now_seconds() - _phase_started_at >= COVER_HOLD_DURATION:
				_release_cover()
				_phase = FleePhase.SEEKING_RESOURCE
				_phase_started_at = _now_seconds()
			return

		FleePhase.SEEKING_RESOURCE:
			if _now_seconds() - _phase_started_at >= RESOURCE_SEARCH_TIMEOUT:
				_begin_return_to_origin()
				return
			_target_pickup = bot.tactical_sys.get_priority_resource_source()
			if _is_valid_target(_target_pickup):
				_navigate_to_seeking((_target_pickup as Node3D).global_position, _role_speed(FLEE_SPEED))
			else:
				movement_cmd.set_hold()
			return

		FleePhase.RETURNING_TO_ORIGIN:
			if _move_to_own_origin():
				_phase = FleePhase.SEEKING_FROM_ORIGIN
				_phase_started_at = _now_seconds()
				_target_pickup = null
			return

		FleePhase.SEEKING_FROM_ORIGIN:
			_target_pickup = bot.tactical_sys.get_priority_resource_source()
			if _is_valid_target(_target_pickup):
				_navigate_to_seeking((_target_pickup as Node3D).global_position, _role_speed(FLEE_SPEED))
				return
			# Sin suministro activo desde la base: se espera allí y se reevalúa.
			movement_cmd.set_hold()
			return


func exit(_next_state: BotState) -> void:
	_target_pickup = null
	_release_cover()


func on_timeout_forced() -> void:
	# Compatibilidad defensiva: FLEEING no usa timeout global, pero si algún
	# sistema externo fuerza este hook no abandonamos el bot lejos del origen.
	_begin_return_to_origin()


## Da una oportunidad corta de ocultarse tras una cobertura que protege de la
## amenaza reciente. No crea un estado FSM adicional: es una subfase de FLEEING
## y luego continúa con el mismo flujo de recursos ya validado.
func _try_take_cover_before_resource() -> bool:
	if bot == null or bot.tactical_sys == null:
		return false
	if _reserved_cover == null or not is_instance_valid(_reserved_cover) or not _reserved_cover.is_inside_tree():
		_reserved_cover = bot.tactical_sys.get_nearest_available_cover(_failed_cover_ids)
		if _reserved_cover == null:
			return false
		if _reserved_cover.has_method("occupy"):
			_reserved_cover.occupy(bot)
		_phase_started_at = _now_seconds()
	var cover_position: Vector3 = _reserved_cover.get_cover_position()
	if bot.global_position.distance_to(cover_position) <= COVER_ARRIVAL_DISTANCE:
		_phase = FleePhase.HOLDING_COVER
		_phase_started_at = _now_seconds()
		movement_cmd.set_hold()
		_face_cover_front()
		return true
	if _now_seconds() - _phase_started_at >= COVER_APPROACH_TIMEOUT:
		_failed_cover_ids[_reserved_cover.get_instance_id()] = true
		_release_cover()
		return false
	movement_cmd.set_navigate(cover_position, _role_speed(FLEE_SPEED))
	movement_cmd.sprint = true
	return true


func _release_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.has_method("release"):
		_reserved_cover.release(bot)
	_reserved_cover = null


func _face_cover_front() -> void:
	if bot == null or _reserved_cover == null or not is_instance_valid(_reserved_cover):
		return
	var node: Node3D = _reserved_cover as Node3D
	if node == null:
		return
	var front: Vector3 = node.global_transform.basis.z.normalized()
	if front.length_squared() <= 0.001:
		return
	combat_cmd.set_aim(bot.global_position + front * 10.0)


func _exit_after_recovery() -> void:
	if perception != null and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
	else:
		change_state(BotState.StateType.ROAMING)


func _guard_weapon() -> void:
	if bot != null and bot.weapon_equip_state != null:
		bot.weapon_equip_state.unequip()


func _begin_return_to_origin() -> void:
	_phase = FleePhase.RETURNING_TO_ORIGIN
	_phase_started_at = _now_seconds()
	_target_pickup = null
	_generic_waypoint = Vector3.ZERO
	_generic_waypoint_goal = Vector3.ZERO
	_debug("Búsqueda crítica agotó %.1fs; retorno forzado a origen_base." % RESOURCE_SEARCH_TIMEOUT)


func _move_to_own_origin() -> bool:
	var origin: Node3D = bot._get_own_base_origin()
	if origin == null or not is_instance_valid(origin) or not origin.is_inside_tree():
		movement_cmd.set_hold()
		return false
	if bot.global_position.distance_to(origin.global_position) <= BASE_ARRIVAL_DISTANCE:
		movement_cmd.set_hold()
		return true
	movement_cmd.set_navigate(origin.global_position, _role_speed(FLEE_SPEED))
	movement_cmd.sprint = true
	return false


func _is_valid_target(candidate: Node) -> bool:
	return candidate != null and is_instance_valid(candidate) and candidate.is_inside_tree() and candidate is Node3D


func _role_speed(base_speed: float) -> float:
	if bot != null:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed


## Navega hacia un destino (pickup o cobertura) usando un trampolín opcional
## de camino generico. Si no hay camino útil, se comporta exactamente como
## antes (navegación directa por navmesh), por lo que nunca rompe nada.
func _navigate_to_seeking(goal: Vector3, speed: float) -> void:
	# Si ya tenemos un trampolín para este destino, seguirlo hasta llegar.
	if _generic_waypoint != Vector3.ZERO and goal.distance_to(_generic_waypoint_goal) < 0.5:
		if bot.global_position.distance_to(_generic_waypoint) > ARRIVAL_DISTANCE:
			movement_cmd.set_navigate(_generic_waypoint, speed)
			movement_cmd.sprint = true
			return
		# Trampolín alcanzado → continuar directo al destino.
		_generic_waypoint = Vector3.ZERO

	# Si el destino es cercano, ir directo (no vale la pena el desvío).
	if bot.global_position.distance_to(goal) <= GenericRouteHelper.DIRECT_DISTANCE_THRESHOLD:
		movement_cmd.set_navigate(goal, speed)
		movement_cmd.sprint = true
		return

	var via: Vector3 = GenericRouteHelper.waypoint_toward(_get_map_root(), bot.global_position, goal)
	if via != Vector3.ZERO:
		_generic_waypoint = via
		_generic_waypoint_goal = goal
		if bot.global_position.distance_to(via) > ARRIVAL_DISTANCE:
			movement_cmd.set_navigate(via, speed)
			movement_cmd.sprint = true
			return

	movement_cmd.set_navigate(goal, speed)
	movement_cmd.sprint = true


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _debug(message: String) -> void:
	if bot != null:
		bot._debug("[fleeing] " + message)


## Raíz del mapa para buscar caminos genericos.
func _get_map_root() -> Node:
	if bot == null or not bot.is_inside_tree():
		return null
	var scene_root: Node = bot.get_tree().current_scene
	var current: Node = bot
	while current.get_parent() != null and current != scene_root:
		current = current.get_parent()
	return scene_root if scene_root != null else current
