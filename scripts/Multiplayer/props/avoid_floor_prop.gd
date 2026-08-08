@tool
class_name AvoidFloorProp extends WorldMapProp

## Suelo tácticamente desfavorable: los bots evitan escogerlo como destino
## de roaming y abandonan el volumen si aparecen dentro de él.
## Para que el pathfinding también lo penalice entre dos puntos, el diseñador
## debe hornear una región de navegación separada con mayor travel_cost.

@export var avoidance_weight: float = 5.0
@export var local_bounds: Vector2 = Vector2(6.0, 6.0)
@export var exit_margin: float = 0.75


func is_position_inside(world_position: Vector3) -> bool:
	var local_position: Vector3 = _world_to_local(world_position)
	var half_bounds: Vector2 = local_bounds * 0.5
	return absf(local_position.x) <= half_bounds.x and absf(local_position.z) <= half_bounds.y


## Devuelve un punto fuera del volumen por el lado más cercano a `from_position`.
func get_detour_position(target_position: Vector3, from_position: Vector3) -> Vector3:
	if not is_position_inside(target_position):
		return target_position
	return get_exit_position(target_position, from_position)


## Devuelve una salida del volumen en dirección al objetivo deseado.
func get_exit_position(from_position: Vector3, toward_position: Vector3) -> Vector3:
	if not is_position_inside(from_position):
		return toward_position

	var local_from: Vector3 = _world_to_local(from_position)
	var local_toward: Vector3 = _world_to_local(toward_position)
	var direction: Vector2 = Vector2(
		local_toward.x - local_from.x,
		local_toward.z - local_from.z)
	if direction.length_squared() < 0.0001:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()

	var half_bounds: Vector2 = local_bounds * 0.5 + Vector2.ONE * maxf(exit_margin, 0.01)
	var distance_x: float = INF
	var distance_z: float = INF
	if absf(direction.x) > 0.0001:
		distance_x = (half_bounds.x - absf(local_from.x)) / absf(direction.x)
	if absf(direction.y) > 0.0001:
		distance_z = (half_bounds.y - absf(local_from.z)) / absf(direction.y)
	var exit_distance: float = maxf(minf(distance_x, distance_z), 0.01)
	var local_exit: Vector3 = Vector3(
		local_from.x + direction.x * exit_distance,
		local_from.y,
		local_from.z + direction.y * exit_distance)
	return _local_to_world(local_exit)


func _world_to_local(world_position: Vector3) -> Vector3:
	var active_transform: Transform3D = global_transform if is_inside_tree() else transform
	return active_transform.affine_inverse() * world_position


func _local_to_world(local_position: Vector3) -> Vector3:
	var active_transform: Transform3D = global_transform if is_inside_tree() else transform
	return active_transform * local_position


func get_avoidance_cost() -> float:
	return maxf(avoidance_weight, 1.0)
