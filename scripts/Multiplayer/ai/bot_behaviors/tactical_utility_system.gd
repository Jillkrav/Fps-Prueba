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
const COVER_PROTECTION_BONUS: float = 35.0
const COVER_EXPOSURE_PENALTY: float = 18.0
const COVER_FACING_BONUS: float = 8.0

## Enfriamiento tras abandonar un intento de huir: durante este tiempo el bot
## no vuelve a forzar FLEEING, para evitar un bucle FLEEING → ROAMING → FLEEING
## cuando no hay un recurso disponible que recoger. El bot deambula y reaprovecha
## la recogida oportunista de pickups en ROAMING.
const FLEE_ABANDON_COOLDOWN: float = 6.0

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
var _last_flee_abandoned_at: float = -INF


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
	_last_flee_abandoned_at = -INF
	set_coward_mode(false)


func should_force_flee() -> bool:
	# Enfriamiento tras abandonar un intento de huir: evitar re-entrada inmediata.
	if _now_seconds() - _last_flee_abandoned_at < FLEE_ABANDON_COOLDOWN:
		return false
	return under_attack_level == UnderAttackLevel.FLEE


## El bot renunció a un intento de huir (por ejemplo, tras el watchdog de
## FLEEING). Termina el modo huir y mete un enfriamiento para evitar el bucle
## FLEEING → ROAMING → FLEEING cuando no hay recurso que recoger.
func abandon_flee() -> void:
	end_flee()
	_last_flee_abandoned_at = _now_seconds()


func begin_flee() -> void:
	if flee_mode_active:
		return
	flee_mode_active = true
	flee_reason = _get_highest_flee_reason()
	# La retirada crítica ya tiene una política determinista de 15s →
	# origen_base. Se retira el desvío aleatorio a spawn para no sacar bots de
	# la red authored ni competir con el retorno forzado.
	_base_detour_pending = false
	set_coward_mode(false)


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


## ResupplyBox restaura simultáneamente salud y munición. Por eso finaliza
## cualquier causa de FLEEING sin necesitar simular dos pickups distintos.
func notify_resupply_collected() -> void:
	if flee_mode_active:
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
				return _nearest_resource_candidate(int(Pickup.Type.AMMO), true)
			FleeReason.HEALTH:
				return _nearest_resource_candidate(int(Pickup.Type.HEALTH), true)
			FleeReason.NO_WEAPON:
				return get_nearest_pickup(int(Pickup.Type.WEAPON))
			_:
				return null
	
	if health_search_level == NeedLevel.NONE and ammo_search_level == NeedLevel.NONE:
		return null
	if health_search_level > ammo_search_level:
		return _nearest_resource_candidate(int(Pickup.Type.HEALTH), true)
	if ammo_search_level > health_search_level:
		return _nearest_resource_candidate(int(Pickup.Type.AMMO), true)
	
	# Con la misma prioridad, resuelve por el déficit relativo y no por azar.
	if get_health_ratio() <= get_ammo_ratio():
		return _nearest_resource_candidate(int(Pickup.Type.HEALTH), true)
	return _nearest_resource_candidate(int(Pickup.Type.AMMO), true)


## Fuente de recurso unificada para estados que no deben conocer la clase
## concreta: ResupplyBox activo, ammo o health según la necesidad actual.
func get_priority_resource_source() -> Node:
	return get_priority_pickup()


## Prefiere una ResupplyBox activa cuando resuelve la necesidad solicitada,
## pero mantiene AmmoPack/Medkit como alternativas si la caja está más lejos.
func _nearest_resource_candidate(pickup_type: int, allow_resupply: bool) -> Node:
	var best_candidate: Node = get_nearest_pickup(pickup_type)
	var best_distance_squared: float = INF
	if best_candidate != null and is_instance_valid(best_candidate):
		best_distance_squared = bot.global_position.distance_squared_to(best_candidate.global_position)
	if not allow_resupply or bot == null or not bot.is_inside_tree():
		return best_candidate
	var boxes: Array[Node] = bot.get_tree().get_nodes_in_group(&"resupply_boxes")
	for box: Node in boxes:
		if box == null or not is_instance_valid(box) or not box.is_inside_tree():
			continue
		if not bool(box.get("is_active")):
			continue
		if not (box is Node3D):
			continue
		var distance_squared: float = bot.global_position.distance_squared_to((box as Node3D).global_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_candidate = box
	return best_candidate


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
## Cuando se conoce la última amenaza, prefiere puntos con bloqueo físico de
## línea de tiro en vez de elegir únicamente el CoverPoint más cercano.
func get_nearest_available_cover(excluded_cover_ids: Dictionary = {}) -> Node:
	if bot == null or not bot.is_inside_tree() or not _role_may_use_cover_now():
		return null
	var threat_position: Vector3 = get_recent_threat_position()
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
		var score: float = _score_cover_candidate(cover, threat_position)
		if score < best_score:
			best_score = score
			best_cover = cover
	return best_cover


## La amenaza reciente procede primero del atacante que dañó al bot. Si no hubo
## daño, usa el objetivo confirmado; si tampoco existe, la cobertura conserva la
## heurística histórica de distancia/prioridad.
func get_recent_threat_position() -> Vector3:
	if bot == null:
		return Vector3.ZERO
	if _last_attacker != null and is_instance_valid(_last_attacker) and _last_attacker.is_inside_tree():
		if _now_seconds() - _last_damage_time <= DAMAGE_MEMORY_SECONDS:
			return _last_attacker.global_position + Vector3.UP * 0.9
	if bot.decision_sys != null and bot.decision_sys.has_target():
		var target: Node3D = bot.decision_sys.target_entity
		if target != null and is_instance_valid(target) and target.is_inside_tree():
			return target.global_position + Vector3.UP * 0.9
	return Vector3.ZERO


func _score_cover_candidate(cover: Node, threat_position: Vector3) -> float:
	if bot == null or not (cover is Node3D):
		return INF
	var priority: float = maxf(float(cover.get("priority")), 0.1)
	var cover_node: Node3D = cover as Node3D
	var cover_position: Vector3 = cover.get_cover_position() if cover.has_method("get_cover_position") else (cover_node.global_position if cover_node.is_inside_tree() else cover_node.position)
	var bot_position: Vector3 = bot.global_position if bot.is_inside_tree() else bot.position
	var score: float = bot_position.distance_to(cover_position) / priority
	if _role_prefers_cover_props() and _is_cover_prop_point(cover):
		score *= 0.55
	if threat_position == Vector3.ZERO:
		return score
	if _cover_blocks_threat(cover_position, threat_position):
		score -= COVER_PROTECTION_BONUS
	else:
		score += COVER_EXPOSURE_PENALTY
	if _cover_faces_threat(cover, cover_position, threat_position):
		score -= COVER_FACING_BONUS
	return score


## Raycast físico liviano: una cobertura solo obtiene el bonus fuerte si una
## geometría estática realmente separa amenaza y punto de refugio. El bot y la
## amenaza se excluyen, y un ray sin impacto significa exposición.
func _cover_blocks_threat(cover_position: Vector3, threat_position: Vector3) -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var start: Vector3 = threat_position
	var end: Vector3 = cover_position + Vector3.UP * 0.8
	if start.distance_squared_to(end) <= 0.01:
		return false
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = bot.collision_mask
	query.exclude = [bot]
	if _last_attacker != null and is_instance_valid(_last_attacker):
		query.exclude.append(_last_attacker)
	var result: Dictionary = bot.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider: Object = result.get("collider", null) as Object
	return collider is StaticBody3D or collider is CSGShape3D


## Un punto orientado hacia la amenaza suele ofrecer un peek natural y evita
## premiar la parte incorrecta de muros de un solo sentido.
func _cover_faces_threat(cover: Node, cover_position: Vector3, threat_position: Vector3) -> bool:
	if not (cover is Node3D):
		return false
	var node: Node3D = cover as Node3D
	var basis: Basis = node.global_transform.basis if node.is_inside_tree() else node.transform.basis
	var facing: Vector3 = basis.z.normalized()
	var to_threat: Vector3 = threat_position - cover_position
	to_threat.y = 0.0
	if facing.length_squared() <= 0.001 or to_threat.length_squared() <= 0.001:
		return false
	return facing.dot(to_threat.normalized()) > 0.25


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
		or bot.decision_sys.is_in_state(BotState.StateType.COVER_RELOAD) \
		or bot.decision_sys.is_in_state(BotState.StateType.FLEEING)


## El francotirador solo reserva el lado seguro de los one_way_low_wall.
func _cover_matches_role_policy(cover: Node) -> bool:
	if bot == null or bot.rol != Roles.Type.FRANCOTIRADOR:
		return true
	return _is_one_way_low_wall_cover(cover)


## Solo defensores (y francotiradores vía su campeo propio) prefieren muros
## como cobertura. El patrullador NO debe campear un muro: debe recorrerlo.
func _role_prefers_cover_props() -> bool:
	return bot != null and bot.rol in [Roles.Type.DEFENSOR]


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
