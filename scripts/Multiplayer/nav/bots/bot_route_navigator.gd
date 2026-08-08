extends RefCounted
class_name BotAuthoredRouteNavigator

const WAYPOINT_REACHED_DISTANCE: float = 1.5

var _route: CaminoBot = null
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoint_index: int = -1
var _direction: int = 1
var _completed_route_ids: Dictionary = {}


func find_best_route(map_root: Node, desired_role: int, from_position: Vector3, excluded_route_ids: Dictionary = {}) -> CaminoBot:
	if map_root == null or not is_instance_valid(map_root):
		return null

	var best_route: CaminoBot = null
	var best_distance_squared: float = INF
	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var candidate: CaminoBot = route_node as CaminoBot
		if candidate == null or not candidate.is_usable() or candidate.role != desired_role:
			continue
		if excluded_route_ids.has(candidate.get_instance_id()):
			continue
		var distance_squared: float = _distance_to_nearest_endpoint_squared(candidate, from_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_route = candidate
	return best_route


func start_route(route: CaminoBot, from_position: Vector3) -> bool:
	clear()
	if route == null or not is_instance_valid(route) or not route.is_usable():
		return false

	var points: PackedVector3Array = route.get_global_waypoints()
	if points.size() < 2:
		return false

	_completed_route_ids.erase(route.get_instance_id())
	_route = route
	_waypoints = points
	_direction = route.get_preferred_direction(from_position)
	_waypoint_index = 0 if _direction > 0 else _waypoints.size() - 1
	return true


func has_active_route() -> bool:
	return _route != null and is_instance_valid(_route) and _waypoint_index >= 0 and _waypoint_index < _waypoints.size()


func get_current_route() -> CaminoBot:
	return _route if has_active_route() else null


func get_current_target() -> Vector3:
	if not has_active_route():
		return Vector3.ZERO
	return _waypoints[_waypoint_index]


## Avanza al siguiente waypoint. Retorna true cuando todavía existe un destino válido.
func advance_if_reached(current_position: Vector3, reach_distance: float = WAYPOINT_REACHED_DISTANCE) -> bool:
	if not has_active_route():
		return false

	var safe_reach_distance: float = maxf(reach_distance, 0.01)
	var last_reached_position: Vector3 = get_current_target()
	if current_position.distance_to(last_reached_position) > safe_reach_distance:
		return true

	_waypoint_index += _direction
	while _waypoint_index >= 0 and _waypoint_index < _waypoints.size() \
			and current_position.distance_to(_waypoints[_waypoint_index]) <= safe_reach_distance:
		last_reached_position = _waypoints[_waypoint_index]
		_waypoint_index += _direction
	if _waypoint_index >= 0 and _waypoint_index < _waypoints.size():
		return true
	return _continue_or_finish(last_reached_position)


func reset_after_stuck(current_position: Vector3) -> bool:
	if not has_active_route():
		return false
	var closest_index: int = _find_closest_waypoint_index(current_position)
	if closest_index < 0:
		clear()
		return false

	_waypoint_index = closest_index
	var current_target: Vector3 = get_current_target()
	if current_position.distance_to(current_target) <= WAYPOINT_REACHED_DISTANCE:
		_waypoint_index += _direction
		if _waypoint_index < 0 or _waypoint_index >= _waypoints.size():
			return _continue_or_finish(current_position)
	return has_active_route()


func get_completed_route_ids() -> Dictionary:
	return _completed_route_ids.duplicate()


func clear() -> void:
	_route = null
	_waypoints = PackedVector3Array()
	_waypoint_index = -1
	_direction = 1
	_completed_route_ids.clear()


func _continue_or_finish(current_position: Vector3) -> bool:
	if _route == null or not is_instance_valid(_route):
		clear()
		return false

	var completed_route: CaminoBot = _route
	_completed_route_ids[completed_route.get_instance_id()] = true
	var next_path: NodePath = completed_route.get_next_path()
	if next_path != NodePath():
		var next_node: Node = completed_route.get_node_or_null(next_path)
		var next_route: CaminoBot = next_node as CaminoBot
		if next_route != null and next_route.is_usable() and next_route.enabled \
				and not _completed_route_ids.has(next_route.get_instance_id()):
			return start_route(next_route, current_position)

	_route = null
	_waypoints = PackedVector3Array()
	_waypoint_index = -1
	_direction = 1
	return false


func _distance_to_nearest_endpoint_squared(route: CaminoBot, from_position: Vector3) -> float:
	var start_distance: float = from_position.distance_squared_to(route.get_start_position())
	if not route.reverse_allowed:
		return start_distance
	var end_distance: float = from_position.distance_squared_to(route.get_end_position())
	return minf(start_distance, end_distance)


func _find_closest_waypoint_index(current_position: Vector3) -> int:
	if _waypoints.is_empty():
		return -1
	var closest_index: int = 0
	var closest_distance_squared: float = current_position.distance_squared_to(_waypoints[0])
	for index: int in range(1, _waypoints.size()):
		var distance_squared: float = current_position.distance_squared_to(_waypoints[index])
		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_index = index
	return closest_index
