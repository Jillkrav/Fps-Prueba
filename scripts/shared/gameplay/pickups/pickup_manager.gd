# scripts/pickup_manager.gd
# Singleton que gestiona todos los Pickups activos en el mundo.
# Proporciona consultas para que jugadores y bots encuentren pickups cercanos.
# Diseñado para ser reutilizado con cualquier tipo de pickup (armas, vida, munición, etc.)
extends Node

var _pickups: Array = []

func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func register(pickup: Node) -> void:
	if pickup not in _pickups:
		_pickups.append(pickup)

func unregister(pickup: Node) -> void:
	_pickups.erase(pickup)

## Devuelve todos los pickups dentro de un radio desde una posición.
## type_filter: -1 = cualquier tipo, o usar Pickup.Type.WEAPON, etc.
func get_nearby_pickups(position: Vector3, radius: float, type_filter: int = -1) -> Array:
	var result: Array = []
	var radius_sq: float = radius * radius
	for p in _pickups:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		if type_filter >= 0 and p.pickup_type != type_filter:
			continue
		if p.global_position.distance_squared_to(position) <= radius_sq:
			result.append(p)
	return result

## Devuelve el pickup más cercano de un tipo específico, dentro de un radio máximo.
func get_nearest_pickup(position: Vector3, type_filter: int = -1, max_radius: float = INF):
	var nearest: Node = null
	var min_dist_sq: float = max_radius * max_radius
	for p in _pickups:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		if type_filter >= 0 and p.pickup_type != type_filter:
			continue
		var dist_sq: float = p.global_position.distance_squared_to(position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			nearest = p
	return nearest

func get_all_pickups() -> Array:
	return _pickups.duplicate()
