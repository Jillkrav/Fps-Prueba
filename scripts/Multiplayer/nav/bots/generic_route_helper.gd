# generic_route_helper.gd
# ──────────────────────────────────────────────────────────────────
# ATAJO SEGURO VÍA CAMINO GENERICO (trampolín).
#
# Utilidad compartida, 100% ADITIVA: si existe un camino GENERIC útil
# cerca del punto de SALIDA, devuelve un waypoint intermedio de ese
# camino hacia el objetivo. El bot lo usa como trampolín para no
# vagar/trabarse en el navmesh, y luego cubre el tramo final corto
# con su navegación normal.
#
# Si no hay camino generico útil → retorna Vector3.ZERO y el bot se
# comporta EXACTAMENTE como hoy (fallback), por lo que NUNCA se rompe
# el comportamiento existente.
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name GenericRouteHelper

## Radio máximo en el que un camino generico se consideraría útil para
## "ganar terreno" hacia el objetivo.
const SEARCH_RADIUS: float = 40.0
## Si el tramo final que cubriría el navmesh queda por debajo de esto,
## no vale la pena el desvío: el bot va directo.
const DIRECT_DISTANCE_THRESHOLD: float = 15.0
## Distancia mínima que debe acercar el waypoint al objetivo para
## considerarlo útil (evita trampolines que no aportan nada).
const MIN_PROGRESS: float = 3.0


## Retorna un waypoint de un camino generico cercano que acerque al bot
## desde `from_position` hacia `goal. Si no hay ninguno útil, Vector3.ZERO.
static func waypoint_toward(map_root: Node, from_position: Vector3, goal: Vector3) -> Vector3:
	if map_root == null or not is_instance_valid(map_root):
		return Vector3.ZERO
	if from_position.distance_to(goal) <= DIRECT_DISTANCE_THRESHOLD:
		return Vector3.ZERO

	var best_waypoint: Vector3 = Vector3.ZERO
	var best_direction_dist: float = INF

	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var route: CaminoBot = route_node as CaminoBot
		# Solo caminos genericos compartidos y útiles.
		if route == null or route.role != CaminoBot.Role.GENERIC or not route.is_usable():
			continue
		var start_dist: float = route.get_start_position().distance_to(from_position)
		if start_dist > SEARCH_RADIUS:
			continue

		var points: PackedVector3Array = route.get_global_waypoints()
		for local_point: Vector3 in points:
			var dist_to_goal: float = local_point.distance_to(goal)
			# Un waypoint solo sirve si está más cerca del objetivo que
			# la posición actual (avance real hacia adelante, no retroceso).
			if dist_to_goal >= from_position.distance_to(goal) - MIN_PROGRESS:
				continue
			var direct_dist: float = from_position.distance_to(local_point)
			if direct_dist > SEARCH_RADIUS:
				continue
			if dist_to_goal < best_direction_dist:
				best_direction_dist = dist_to_goal
				best_waypoint = local_point

	return best_waypoint


## Retorna el punto más cercano (sobre la línea) del camino generico más
## cercano a `from_position`. Sirve como "polo de atracción": si un bot no
## tiene ningún camino a mano, se dirige aquí para reengancharse con la red
## generica (que el autor conecta con los caminos específicos de cada rol).
## Si no hay camino generico util → Vector3.ZERO.
static func nearest_generic_point(map_root: Node, from_position: Vector3) -> Vector3:
	if map_root == null or not is_instance_valid(map_root):
		return Vector3.ZERO

	var best_point: Vector3 = Vector3.ZERO
	var best_distance_squared: float = INF

	var routes: Array[Node] = map_root.find_children("*", "CaminoBot", true, false)
	for route_node: Node in routes:
		var route: CaminoBot = route_node as CaminoBot
		if route == null or route.role != CaminoBot.Role.GENERIC or not route.is_usable():
			continue
		var points: PackedVector3Array = route.get_global_waypoints()
		for local_point: Vector3 in points:
			var d_sq: float = from_position.distance_squared_to(local_point)
			if d_sq < best_distance_squared:
				best_distance_squared = d_sq
				best_point = local_point

	return best_point
