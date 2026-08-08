# Estado táctico de cobertura para recargar bajo presión enemiga.
extends BotState
class_name StateCoverReload

const COVER_SPEED: float = 5.8
const COVER_ARRIVAL_DISTANCE: float = 1.5

var _reserved_cover: Node = null
var _has_requested_reload: bool = false
var _failed_cover_ids: Dictionary = {}
var _cover_attempt_started_at: float = 0.0
var _last_distance_to_cover: float = INF


func _init() -> void:
	state_type = StateType.COVER_RELOAD
	state_name = "cover_reload"


func enter(_previous_state: BotState) -> void:
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
	
	if not _reserve_cover():
		# No hay cobertura libre. La condición crítica la sigue controlando el
		# modo Huir; en otro caso, el combate puede continuar sin bloquearse.
		_exit_cover_state()
		return
	
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
	
	# Llegó al punto exacto: inmovilizarse evita la inquietud junto al prop.
	movement_cmd.set_hold()
	_request_reload_if_possible()
	if _reload_finished():
		_exit_cover_state()


func exit(_next_state: BotState) -> void:
	_release_cover()
	_has_requested_reload = false


func on_take_damage(_amount: float, _attacker: Node3D) -> void:
	# El cambio a Huir por daño crítico lo resuelve execute() mediante TacticalUtilitySystem.
	pass


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


func _role_speed(base_speed: float) -> float:
	if bot != null:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed
