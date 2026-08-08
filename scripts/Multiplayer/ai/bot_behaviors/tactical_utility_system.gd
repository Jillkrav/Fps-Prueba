# Sistema táctico de supervivencia para bots.
# Centraliza las necesidades de recursos, la presión enemiga y el modo Huir.
extends Node
class_name TacticalUtilitySystem

enum NeedLevel {
	NONE = 0,
	LOW = 1,
	MEDIUM = 2,
	HIGH = 3,
}

enum UnderAttackLevel {
	NONE = 0,
	FIGHT = 1,
	RELOAD_COVER = 2,
	FLEE = 3,
}

enum FleeReason {
	NONE = 0,
	AMMO = 1,
	HEALTH = 2,
	NO_WEAPON = 3,
}

const LOW_THRESHOLD: float = 0.70
const MEDIUM_THRESHOLD: float = 0.44
const HIGH_THRESHOLD: float = 0.10
const MAGAZINE_COVER_THRESHOLD: float = 0.15
const DAMAGE_MEMORY_SECONDS: float = 2.5
const PICKUP_SEARCH_RADIUS: float = 250.0

var bot: BotBase = null
var ammo_search_level: int = NeedLevel.NONE
var health_search_level: int = NeedLevel.NONE
var under_attack_level: int = UnderAttackLevel.NONE
var flee_reason: int = FleeReason.NONE
var flee_mode_active: bool = false
var coward_mode_active: bool = false

var _last_damage_time: float = -INF
var _last_attacker: Node3D = null
var _base_detour_pending: bool = false


func _ready() -> void:
	bot = get_parent() as BotBase


func update(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	ammo_search_level = _level_from_ratio(get_ammo_ratio())
	health_search_level = _level_from_ratio(get_health_ratio())
	under_attack_level = _calculate_under_attack_level()


func notify_damage(attacker: Node3D) -> void:
	_last_damage_time = _now_seconds()
	_last_attacker = attacker


func reset() -> void:
	ammo_search_level = NeedLevel.NONE
	health_search_level = NeedLevel.NONE
	under_attack_level = UnderAttackLevel.NONE
	flee_reason = FleeReason.NONE
	flee_mode_active = false
	_base_detour_pending = false
	_last_damage_time = -INF
	_last_attacker = null
	set_coward_mode(false)


func should_force_flee() -> bool:
	return under_attack_level == UnderAttackLevel.FLEE


func begin_flee() -> void:
	if flee_mode_active:
		return
	flee_mode_active = true
	flee_reason = _get_highest_flee_reason()
	_base_detour_pending = randf() < 0.10
	if _base_detour_pending:
		set_coward_mode(true)


func end_flee() -> void:
	flee_mode_active = false
	flee_reason = FleeReason.NONE
	_base_detour_pending = false
	set_coward_mode(false)


func should_detour_to_spawn() -> bool:
	return flee_mode_active and _base_detour_pending


func mark_spawn_reached() -> void:
	_base_detour_pending = false
	set_coward_mode(false)


func set_coward_mode(enabled: bool) -> void:
	if coward_mode_active == enabled:
		return
	coward_mode_active = enabled
	if bot != null:
		bot.set_coward_visual(enabled)


func notify_resource_collected(pickup_type: int) -> void:
	if pickup_type == int(Pickup.Type.AMMO) and flee_reason == FleeReason.AMMO:
		end_flee()
	elif pickup_type == int(Pickup.Type.HEALTH) and flee_reason == FleeReason.HEALTH:
		end_flee()
	elif pickup_type == int(Pickup.Type.WEAPON) and flee_reason == FleeReason.NO_WEAPON:
		end_flee()


func get_health_ratio() -> float:
	if bot == null or bot.max_health <= 0.0:
		return 1.0
	return clampf(bot.current_health / bot.max_health, 0.0, 1.0)


func get_ammo_ratio() -> float:
	var weapon: Weapon = _get_weapon()
	if weapon == null:
		return 0.0
	var capacity: int = weapon.clip_size + weapon.max_ammo
	if capacity <= 0:
		return 1.0
	return clampf(float(weapon.ammo_in_mag + weapon.reserve_ammo) / float(capacity), 0.0, 1.0)


func get_magazine_ratio() -> float:
	var weapon: Weapon = _get_weapon()
	if weapon == null or weapon.clip_size <= 0:
		return 0.0
	return clampf(float(weapon.ammo_in_mag) / float(weapon.clip_size), 0.0, 1.0)


func has_noncritical_resource_need() -> bool:
	return ammo_search_level in [NeedLevel.LOW, NeedLevel.MEDIUM] \
		or health_search_level in [NeedLevel.LOW, NeedLevel.MEDIUM]


func requires_cover_for_reload() -> bool:
	if under_attack_level != UnderAttackLevel.RELOAD_COVER:
		return false
	var weapon: Weapon = _get_weapon()
	if weapon == null:
		return false
	return weapon.reserve_ammo > 0 and weapon.ammo_in_mag < weapon.clip_size


func get_priority_pickup() -> Node:
	if bot == null:
		return null
	if flee_mode_active:
		match flee_reason:
			FleeReason.AMMO:
				return get_nearest_pickup(int(Pickup.Type.AMMO))
			FleeReason.HEALTH:
				return get_nearest_pickup(int(Pickup.Type.HEALTH))
			FleeReason.NO_WEAPON:
				return get_nearest_pickup(int(Pickup.Type.WEAPON))
			_:
				return null
	
	if health_search_level == NeedLevel.NONE and ammo_search_level == NeedLevel.NONE:
		return null
	if health_search_level > ammo_search_level:
		return get_nearest_pickup(int(Pickup.Type.HEALTH))
	if ammo_search_level > health_search_level:
		return get_nearest_pickup(int(Pickup.Type.AMMO))
	
	# Con la misma prioridad, resuelve por el déficit relativo y no por azar.
	if get_health_ratio() <= get_ammo_ratio():
		return get_nearest_pickup(int(Pickup.Type.HEALTH))
	return get_nearest_pickup(int(Pickup.Type.AMMO))


func get_nearest_pickup(pickup_type: int) -> Node:
	if bot == null or not bot.is_inside_tree():
		return null
	var pickup_manager: Node = get_node_or_null("/root/PickupManager")
	if pickup_manager == null or not pickup_manager.has_method("get_nearest_pickup"):
		return null
	return pickup_manager.get_nearest_pickup(bot.global_position, pickup_type, PICKUP_SEARCH_RADIUS) as Node


## Devuelve una cobertura disponible con preferencias explícitas por rol.
## `excluded_cover_ids` permite a un estado evitar un punto que resultó
## inaccesible, sin bloquear los demás puntos del mapa.
func get_nearest_available_cover(excluded_cover_ids: Dictionary = {}) -> Node:
	if bot == null or not bot.is_inside_tree() or not _role_may_use_cover_now():
		return null
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	var best_cover: Node = null
	var best_score: float = INF
	for cover: Node in covers:
		if cover == null or not is_instance_valid(cover) or not cover.is_inside_tree():
			continue
		if excluded_cover_ids.has(cover.get_instance_id()):
			continue
		if not _cover_matches_role_policy(cover):
			continue
		if cover.has_method("is_available") and not cover.is_available(bot):
			continue
		var priority: float = maxf(float(cover.get("priority")), 0.1)
		var distance: float = bot.global_position.distance_to(cover.global_position)
		var score: float = distance / priority
		if _role_prefers_cover_props() and _is_cover_prop_point(cover):
			score *= 0.55
		if score < best_score:
			best_score = score
			best_cover = cover
	return best_cover


## Asalto y flanqueo solo consultan coberturas durante combate/recarga.
## Los demás roles pueden hacerlo cuando su estado táctico lo requiera.
func _role_may_use_cover_now() -> bool:
	if bot == null:
		return false
	if bot.rol not in [Roles.Type.ASALTO, Roles.Type.FLANQUEADOR]:
		return true
	if bot.decision_sys == null:
		return false
	return bot.decision_sys.is_in_state(BotState.StateType.COMBAT) \
		or bot.decision_sys.is_in_state(BotState.StateType.COVER_RELOAD)


## El francotirador solo reserva el lado seguro de los one_way_low_wall.
func _cover_matches_role_policy(cover: Node) -> bool:
	if bot == null or bot.rol != Roles.Type.FRANCOTIRADOR:
		return true
	return _is_one_way_low_wall_cover(cover)


func _role_prefers_cover_props() -> bool:
	return bot != null and bot.rol in [Roles.Type.PATRULLADOR, Roles.Type.DEFENSOR]


func _is_cover_prop_point(cover: Node) -> bool:
	var parent: Node = cover.get_parent()
	return parent != null and parent.is_in_group(&"cover_props")


func _is_one_way_low_wall_cover(cover: Node) -> bool:
	var parent: Node = cover.get_parent()
	return parent != null and parent.has_method("supports_one_way_cover") \
		and bool(parent.call("supports_one_way_cover"))


func get_nearest_own_spawn_position() -> Vector3:
	if bot == null:
		return Vector3.ZERO
	var match_manager: Node = get_node_or_null("/root/MatchManager")
	if match_manager == null or not match_manager.has_method("get_spawn_points_for_team"):
		return Vector3.ZERO
	var spawn_points: Array[Marker3D] = match_manager.get_spawn_points_for_team(bot.equipo_id)
	var best_position: Vector3 = Vector3.ZERO
	var best_distance: float = INF
	for point: Marker3D in spawn_points:
		if point == null or not is_instance_valid(point) or not point.is_inside_tree():
			continue
		var distance: float = bot.global_position.distance_to(point.global_position)
		if distance < best_distance:
			best_distance = distance
			best_position = point.global_position
	return best_position


func _calculate_under_attack_level() -> int:
	if ammo_search_level == NeedLevel.HIGH or health_search_level == NeedLevel.HIGH:
		return UnderAttackLevel.FLEE
	if _get_weapon() == null:
		return UnderAttackLevel.FLEE
	if not _has_combat_pressure():
		return UnderAttackLevel.NONE
	if _is_reloading() or get_magazine_ratio() <= MAGAZINE_COVER_THRESHOLD:
		return UnderAttackLevel.RELOAD_COVER
	return UnderAttackLevel.FIGHT


func _get_highest_flee_reason() -> int:
	if health_search_level == NeedLevel.HIGH and get_health_ratio() <= get_ammo_ratio():
		return FleeReason.HEALTH
	if ammo_search_level == NeedLevel.HIGH:
		return FleeReason.AMMO
	if health_search_level == NeedLevel.HIGH:
		return FleeReason.HEALTH
	return FleeReason.NO_WEAPON


func _has_combat_pressure() -> bool:
	if bot == null:
		return false
	if _now_seconds() - _last_damage_time <= DAMAGE_MEMORY_SECONDS:
		return true
	if bot.perception_sys != null and bot.perception_sys.has_visible_enemies():
		return true
	if bot.decision_sys != null:
		return bot.decision_sys.is_in_state(BotState.StateType.COMBAT) \
			or bot.decision_sys.is_in_state(BotState.StateType.COVER_RELOAD)
	return false


func _is_reloading() -> bool:
	return bot != null and bot.weapon_sys != null and bot.weapon_sys.is_reloading()


func _get_weapon() -> Weapon:
	if bot == null:
		return null
	var weapon: Weapon = bot.get_current_weapon()
	if weapon == null or not is_instance_valid(weapon):
		return null
	return weapon


func _level_from_ratio(ratio: float) -> int:
	if ratio <= HIGH_THRESHOLD:
		return NeedLevel.HIGH
	if ratio <= MEDIUM_THRESHOLD:
		return NeedLevel.MEDIUM
	if ratio <= LOW_THRESHOLD:
		return NeedLevel.LOW
	return NeedLevel.NONE


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
