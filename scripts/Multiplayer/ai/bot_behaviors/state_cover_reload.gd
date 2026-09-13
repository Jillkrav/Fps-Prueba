# Estado táctico de cobertura para recargar bajo presión enemiga.
extends BotState
class_name StateCoverReload

const COVER_SPEED: float = 5.8
const COVER_ARRIVAL_DISTANCE: float = 1.5
const COVER_SEARCH_TIMEOUT: float = 10.0
const COVER_USE_TIMEOUT: float = 15.0
const NO_COVER_RETREAT_SPEED: float = 6.2

## Si no queda cobertura disponible, no se queda inmóvil expuesto: se repliega
## al origen propio mientras espera el watchdog de búsqueda o una cobertura libre.
enum CoverPhase {
	SEARCHING,
	USING,
	FALLBACK_RETREAT,
}

var _phase: int = CoverPhase.SEARCHING
var _phase_started_at: float = 0.0
var _reserved_cover: Node = null
var _has_requested_reload: bool = false
var _failed_cover_ids: Dictionary = {}
var _cover_attempt_started_at: float = 0.0
var _last_distance_to_cover: float = INF


func _init() -> void:
	state_type = StateType.COVER_RELOAD
	state_name = "cover_reload"
	# Los límites se aplican por fase usando reloj monotónico, no por tick de IA.
	max_duration = INF


func enter(_previous_state: BotState) -> void:
	_phase = CoverPhase.SEARCHING
	_phase_started_at = _now_seconds()
	_has_requested_reload = false
	_failed_cover_ids.clear()
	_cover_attempt_started_at = 0.0
	_last_distance_to_cover = INF
	if bot != null and bot.weapon_equip_state != null:
		bot.weapon_equip_state.equip()
	_reserve_cover()


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead or bot.tactical_sys == null:
		return

	combat_cmd.cease_fire = true
	if bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return
	if not bot.tactical_sys.requires_cover_for_reload():
		_exit_cover_state()
		return

	# El límite sigue activo tanto buscando como replegándose sin cobertura.
	# Solo se pausa cuando el bot ya alcanzó una cobertura y está recargando.
	if _phase != CoverPhase.USING and _now_seconds() - _phase_started_at >= COVER_SEARCH_TIMEOUT:
		_exit_to_route_re_evaluation("No encontró cobertura en %.1fs" % COVER_SEARCH_TIMEOUT)
		return

	if not _reserve_cover():
		# Mantener la búsqueda, pero sin dejar al bot quieto bajo fuego. El origen
		# propio es el fallback semántico estable de todos los mapas compatibles.
		_phase = CoverPhase.FALLBACK_RETREAT
		_move_to_safe_origin()
		return

	if _phase == CoverPhase.FALLBACK_RETREAT:
		_phase = CoverPhase.SEARCHING
	var cover_target: Vector3 = _reserved_cover.get_cover_position()
	var distance_to_cover: float = bot.global_position.distance_to(cover_target)
	if distance_to_cover > COVER_ARRIVAL_DISTANCE:
		if _cover_is_unreachable(distance_to_cover):
			_abandon_current_cover()
			return
		_last_distance_to_cover = distance_to_cover
		movement_cmd.set_navigate(cover_target, _role_speed(COVER_SPEED))
		movement_cmd.sprint = true
		return

	if _phase != CoverPhase.USING:
		_phase = CoverPhase.USING
		_phase_started_at = _now_seconds()

	# Llegó al punto exacto: inmovilizarse evita la inquietud junto al prop.
	movement_cmd.set_hold()
	# Encarar el frente de la cobertura (hacia el enemigo) en vez de quedarse
	# de espaldas a la amenaza mientras recarga.
	_face_cover_front()
	_request_reload_if_possible()
	if _reload_finished():
		_exit_cover_state()
		return
	if _now_seconds() - _phase_started_at >= COVER_USE_TIMEOUT:
		_exit_to_route_re_evaluation("Uso de cobertura agotó %.1fs" % COVER_USE_TIMEOUT)


func exit(_next_state: BotState) -> void:
	_release_cover()
	_has_requested_reload = false


func on_take_damage(_amount: float, _attacker: Node3D) -> void:
	# El cambio a Huir por daño crítico lo resuelve execute() mediante TacticalUtilitySystem.
	pass


## Repliegue conservador mientras no exista cobertura asignable. Si el origen
## falta en un mapa antiguo, HOLD sigue siendo el fallback seguro sin inventar
## un destino libre en el NavMesh.
func _move_to_safe_origin() -> void:
	if bot == null:
		return
	var origin: Node3D = bot._get_own_base_origin()
	if origin == null or not is_instance_valid(origin) or not origin.is_inside_tree():
		movement_cmd.set_hold()
		return
	movement_cmd.set_navigate(origin.global_position, _role_speed(NO_COVER_RETREAT_SPEED))
	movement_cmd.sprint = true


func _reserve_cover() -> bool:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.is_inside_tree():
		return true
	if bot == null or bot.tactical_sys == null:
		return false
	var cover: Node = bot.tactical_sys.get_nearest_available_cover(_failed_cover_ids)
	if cover == null:
		return false
	if cover.has_method("occupy"):
		cover.occupy(bot)
	_reserved_cover = cover
	_cover_attempt_started_at = Time.get_ticks_msec() / 1000.0
	_last_distance_to_cover = INF
	return true


## No deja al bot en HOLD si una cobertura no quedó conectada al NavMesh.
## Tras un intento razonable se libera y se busca otro punto disponible.
func _cover_is_unreachable(distance_to_cover: float) -> bool:
	if bot == null:
		return true
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _cover_attempt_started_at
	var agent: NavigationAgent3D = bot.navigation_agent
	# Esperar una breve sincronización del NavigationServer antes de interpretar
	# una ruta vacía como inalcanzable.
	if elapsed >= 0.4 and agent != null and not agent.is_target_reachable():
		return true
	var no_progress: bool = distance_to_cover >= _last_distance_to_cover - 0.15
	return elapsed >= 2.5 and no_progress


func _abandon_current_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover):
		_failed_cover_ids[_reserved_cover.get_instance_id()] = true
	_release_cover()
	_cover_attempt_started_at = 0.0
	_last_distance_to_cover = INF


func _release_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.has_method("release"):
		_reserved_cover.release(bot)
	_reserved_cover = null


## Orienta al bot hacia el frente de la cobertura (el lado de la amenaza)
## mientras recarga apostado. Sin esto, si el bot no tiene un objetivo vivo
## (p.ej. se escondió para recargar), conserva la orientación con la que
## llegó al punto y puede quedar de espaldas al enemigo tras un muro de
## un sentido. El CombatSystem es el dueño del facing, así que le indicamos
## el punto a mirar vía el comando (con cease_fire solo orienta, no dispara).
func _face_cover_front() -> void:
	if bot == null or _reserved_cover == null or not is_instance_valid(_reserved_cover):
		return
	# Si hay un objetivo vivo, el CombatSystem ya lo encara vía
	# _aim_at_target_entity() (aim_at_position queda ZERO). No interferir.
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
	var node: Node3D = cover as Node3D
	# En el árbol usamos la orientación global (respeta props rotados); fuera
	# del árbol (tests) la local suele bastar y evita errores de get_global_transform.
	var basis: Basis = node.global_transform.basis if node.is_inside_tree() else node.transform.basis
	return basis.z.normalized()


func _request_reload_if_possible() -> void:
	if _has_requested_reload or bot == null or bot.weapon_sys == null:
		return
	if bot.weapon_sys.request_reload():
		_has_requested_reload = true


func _reload_finished() -> bool:
	if bot == null or bot.weapon_sys == null:
		return true
	if bot.weapon_sys.is_reloading():
		return false
	var weapon: Weapon = bot.get_current_weapon()
	if weapon == null:
		return true
	return _has_requested_reload and weapon.ammo_in_mag >= weapon.clip_size


func _exit_cover_state() -> void:
	if perception != null and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
	else:
		change_state(BotState.StateType.ROAMING)


## El flujo de ROAMING retoma inmediatamente una ruta authored y reevalúa la
## necesidad táctica. No se hace wander ni se reserva la cobertura expirada.
func _exit_to_route_re_evaluation(reason: String) -> void:
	_debug(reason + "; regreso a ruta y reevaluación.")
	_release_cover()
	change_state(BotState.StateType.ROAMING)


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _debug(message: String) -> void:
	if bot != null:
		bot._debug("[cover_reload] " + message)


func _role_speed(base_speed: float) -> float:
	if bot != null:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed
