# Estado de supervivencia: el bot guarda el arma y prioriza escapar hacia recursos.
extends BotState
class_name StateFleeing

const FLEE_SPEED: float = 7.0
const ARRIVAL_DISTANCE: float = 1.6
const SPAWN_ARRIVAL_DISTANCE: float = 2.8

var _target_pickup: Node = null
var _reserved_cover: Node = null


func _init() -> void:
	state_type = StateType.FLEEING
	state_name = "fleeing"


func enter(_previous_state: BotState) -> void:
	_target_pickup = null
	_release_reserved_cover()
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
	
	if bot.tactical_sys.should_detour_to_spawn():
		var spawn_target: Vector3 = bot.tactical_sys.get_nearest_own_spawn_position()
		if spawn_target != Vector3.ZERO:
			movement_cmd.set_navigate(spawn_target, _role_speed(FLEE_SPEED))
			movement_cmd.sprint = true
			if bot.global_position.distance_to(spawn_target) <= SPAWN_ARRIVAL_DISTANCE:
				bot.tactical_sys.mark_spawn_reached()
			return
	
	_target_pickup = bot.tactical_sys.get_priority_pickup()
	if _target_pickup != null and is_instance_valid(_target_pickup) and _target_pickup.is_inside_tree():
		_release_reserved_cover()
		var pickup_target: Vector3 = _target_pickup.global_position
		movement_cmd.set_navigate(pickup_target, _role_speed(FLEE_SPEED))
		movement_cmd.sprint = true
		return
	
	# Si no hay recurso disponible, la cobertura es un refugio temporal mientras
	# el sistema vuelve a comprobar el registro de pickups.
	if _reserve_fallback_cover():
		var cover_target: Vector3 = _reserved_cover.get_cover_position()
		if bot.global_position.distance_to(cover_target) <= ARRIVAL_DISTANCE:
			movement_cmd.set_hold()
		else:
			movement_cmd.set_navigate(cover_target, _role_speed(FLEE_SPEED))
			movement_cmd.sprint = true
		return
	
	var fallback_spawn: Vector3 = bot.tactical_sys.get_nearest_own_spawn_position()
	if fallback_spawn != Vector3.ZERO:
		movement_cmd.set_navigate(fallback_spawn, _role_speed(FLEE_SPEED))
		movement_cmd.sprint = true
	else:
		movement_cmd.set_hold()


func exit(_next_state: BotState) -> void:
	_target_pickup = null
	_release_reserved_cover()


func _exit_after_recovery() -> void:
	if perception != null and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
	else:
		change_state(BotState.StateType.ROAMING)


func _guard_weapon() -> void:
	if bot != null and bot.weapon_equip_state != null:
		bot.weapon_equip_state.unequip()


func _reserve_fallback_cover() -> bool:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.is_inside_tree():
		return true
	if bot == null or bot.tactical_sys == null:
		return false
	var cover: Node = bot.tactical_sys.get_nearest_available_cover()
	if cover == null:
		return false
	if cover.has_method("occupy"):
		cover.occupy(bot)
	_reserved_cover = cover
	return true


func _release_reserved_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and _reserved_cover.has_method("release"):
		_reserved_cover.release(bot)
	_reserved_cover = null


func _role_speed(base_speed: float) -> float:
	if bot != null:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed
