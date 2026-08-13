extends RefCounted
class_name BotAuthoredRouteNavigator

const WAYPOINT_REACHED_DISTANCE: float = 1.5

## Separación mínima entre waypoints usados para navegar. Las curvas de autor
## pueden hornearse con miles de puntos casi yuxtapuestos (a fracciones de metro);
## navegar de micro-waypoint en micro-waypoint produce el jitter "avanza un pelín
## cada pocos segundos". Este umbral adelgaza la polilínea para que el bot recorra
## la curva con saltos de metros (movimiento fluido), conservando ambos extremos.
const WAYPOINT_MIN_SPACING: float = 2.0

## Distancia en unidades bajo la cual un camino del rol se considera "cerca"
## y, por tanto, prioritario sobre el generico (mismo criterio que state_roaming).
const ROLE_NEAR_RADIUS: float = 15.0

var _route: CaminoBot = null
var _waypoints: PackedVector3Array = PackedVector3Array()
var _waypoint_index: int = -1
var _direction: int = 1
var _completed_route_ids: Dictionary = {}

## Mantiene el rol de circulación durante una cadena de rutas. Los hubs
## GENERIC pueden tener varias salidas, pero solo encadenan una compatible con
## la intención con la que el bot entró a la red authored.
var _requested_route_role: int = -1


func find_best_route(map_root: Node, desired_role: int, from_position: Vector3, excluded_route_ids: Dictionary = {}) -> CaminoBot:
	if map_root == null or not is_instance_valid(map_root):
		return null

	# Prioridad del rol "solo si está cerca", compartida con state_roaming: el
	# camino específico del rol se toma si está a una distancia razonable; si
	# está lejos, se usa el generico (compartido) como arteria para re-acercarse.
	var role_best_route: CaminoBot = null
	var generic_best_route: CaminoBot = null
	var role_best_distance_squared: float = INF
	var generic_best_distance_squared: float = INF

	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var candidate: CaminoBot = route_node as CaminoBot
		if candidate == null or not candidate.is_usable() or not candidate.is_compatible(desired_role):
			continue
		# Los genericos no se excluyen nunca: son arterias de circulación que
		# cualquier bot puede re-pasear para re-agruparse con su camino de rol.
		if candidate.role != CaminoBot.Role.GENERIC and excluded_route_ids.has(candidate.get_instance_id()):
			continue
		var distance_squared: float = _distance_to_nearest_endpoint_squared(candidate, from_position)
		if candidate.role == desired_role:
			if distance_squared < role_best_distance_squared:
				role_best_distance_squared = distance_squared
				role_best_route = candidate
		elif candidate.role == CaminoBot.Role.GENERIC:
			if distance_squared < generic_best_distance_squared:
				generic_best_distance_squared = distance_squared
				generic_best_route = candidate

	# Si hay camino de rol CERCANO, se prefiere el rol. Si no, el generico
	# (arteria de re-acercamiento). Si no hay generico, cae al rol (única opción).
	if role_best_route != null and role_best_distance_squared <= ROLE_NEAR_RADIUS * ROLE_NEAR_RADIUS:
		return role_best_route
	if generic_best_route != null:
		return generic_best_route
	return role_best_route


## Fallback estrictamente authored: retorna cualquier CaminoBot utilizable más
## cercano. Se usa únicamente cuando el autor todavía no dibujó una ruta del rol;
## nunca fabrica un destino aleatorio sobre el NavMesh.
func find_nearest_usable_route(map_root: Node, from_position: Vector3, excluded_route_ids: Dictionary = {}) -> CaminoBot:
	if map_root == null or not is_instance_valid(map_root):
		return null
	var best_route: CaminoBot = null
	var best_distance_squared: float = INF
	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var candidate: CaminoBot = route_node as CaminoBot
		if candidate == null or not candidate.is_usable():
			continue
		if candidate.role != CaminoBot.Role.GENERIC and excluded_route_ids.has(candidate.get_instance_id()):
			continue
		var distance_squared: float = _distance_to_nearest_endpoint_squared(candidate, from_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_route = candidate
	return best_route


func start_route(route: CaminoBot, from_position: Vector3, requested_role: int = -1) -> bool:
	_clear_active_route()
	if route == null or not is_instance_valid(route) or not route.is_usable():
		return false

	# El fallback de ROAMING puede iniciar temporalmente un camino authored de
	# otro tipo cuando un mapa aún no define la ruta del rol. Conservamos el rol
	# solicitado para filtrar sus enlaces posteriores; no bloqueamos ese inicio.
	var points: PackedVector3Array = route.get_global_waypoints()
	if points.size() < 2:
		return false

	if requested_role >= 0:
		_requested_route_role = requested_role
	_completed_route_ids.erase(route.get_instance_id())
	_route = route
	_waypoints = _decimate_waypoints(points)
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


## Limpia la ruta que se está recorriendo y conserva el historial de rutas
## acabadas. Esto evita que una transición next_paths borre las exclusiones y
## haga que el bot vuelva a iniciar la misma ruta en un bucle.
func _clear_active_route() -> void:
	_route = null
	_waypoints = PackedVector3Array()
	_waypoint_index = -1
	_direction = 1


## Limpieza total, reservada para entrar/salir de ROAMING o respawn.
func clear() -> void:
	_clear_active_route()
	_completed_route_ids.clear()
	_requested_route_role = -1


func _continue_or_finish(current_position: Vector3) -> bool:
	if _route == null or not is_instance_valid(_route):
		clear()
		return false

	var completed_route: CaminoBot = _route
	_completed_route_ids[completed_route.get_instance_id()] = true
	var next_route: CaminoBot = _get_next_compatible_route(completed_route)
	if next_route != null and not _completed_route_ids.has(next_route.get_instance_id()):
		return start_route(next_route, current_position, _requested_route_role)

	_clear_active_route()
	return false


## Elige una continuación authored compatible con el rol que inició la cadena.
## Así un hub GENERIC puede tener ramas de asalto y flanco sin enviar un bot al
## comportamiento de otro rol. Los pesos siguen siendo responsabilidad de
## CaminoBot.get_next_path(), pero se filtran antes por compatibilidad.
func _get_next_compatible_route(route: CaminoBot) -> CaminoBot:
	if route == null or not is_instance_valid(route):
		return null
	var compatible_paths: Array[NodePath] = []
	var compatible_weights: Array[float] = []
	for index: int in range(route.next_paths.size()):
		var path: NodePath = route.next_paths[index]
		if path == NodePath():
			continue
		var candidate: CaminoBot = route.get_node_or_null(path) as CaminoBot
		if candidate == null or not candidate.is_usable() or not candidate.enabled:
			continue
		if _completed_route_ids.has(candidate.get_instance_id()):
			continue
		if _requested_route_role >= 0 and not candidate.is_compatible(_requested_route_role):
			continue
		compatible_paths.append(path)
		compatible_weights.append(route.next_path_weights[index] if index < route.next_path_weights.size() else 1.0)
	if compatible_paths.is_empty():
		return null
	var selected_index: int = _pick_weighted_index(compatible_weights)
	return route.get_node_or_null(compatible_paths[selected_index]) as CaminoBot


func _pick_weighted_index(weights: Array[float]) -> int:
	if weights.is_empty():
		return -1
	var total_weight: float = 0.0
	for weight: float in weights:
		total_weight += maxf(weight, 0.0)
	if total_weight <= 0.0:
		return randi() % weights.size()
	var roll: float = randf() * total_weight
	for index: int in range(weights.size()):
		roll -= maxf(weights[index], 0.0)
		if roll <= 0.0:
			return index
	return weights.size() - 1


func _distance_to_nearest_endpoint_squared(route: CaminoBot, from_position: Vector3) -> float:
	var start_distance: float = from_position.distance_squared_to(route.get_start_position())
	if not route.reverse_allowed:
		return start_distance
	var end_distance: float = from_position.distance_squared_to(route.get_end_position())
	return minf(start_distance, end_distance)


## Adelgaza una polilínea densa conservando puntos que disten al menos
## WAYPOINT_MIN_SPACING entre sí. Siempre conserva el primero y el último
## punto para no deformar la ruta ni sus extremos (sentido inicio→fin y fin→inicio).
func _decimate_waypoints(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 3:
		return points

	var decimated: PackedVector3Array = PackedVector3Array()
	decimated.append(points[0])
	var last_kept: Vector3 = points[0]
	for index: int in range(1, points.size() - 1):
		if last_kept.distance_to(points[index]) >= WAYPOINT_MIN_SPACING:
			decimated.append(points[index])
			last_kept = points[index]
	var last_original: Vector3 = points[points.size() - 1]
	if last_kept.distance_to(last_original) > 0.01:
		decimated.append(last_original)
	return decimated


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
