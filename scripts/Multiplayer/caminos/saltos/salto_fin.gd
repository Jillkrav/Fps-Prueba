@tool
extends Area3D
class_name SaltoFin

@export var jump_id: StringName
## Activo por defecto: confirma al bot que alcanzó la zona de aterrizaje.
@export var enabled: bool = true
@export var next_paths: Array[NodePath] = []
@export var next_path_weights: Array[float] = []


func _on_body_entered(body: Node3D) -> void:
	if not enabled or not body.has_method("finish_authored_jump"):
		return
	body.finish_authored_jump(self, get_next_path())


func get_next_path() -> NodePath:
	var valid_indexes: Array[int] = []
	for index: int in range(next_paths.size()):
		if next_paths[index] != NodePath():
			valid_indexes.append(index)
	if valid_indexes.is_empty():
		return NodePath()

	var total_weight: float = 0.0
	for index: int in valid_indexes:
		total_weight += maxf(_get_weight(index), 0.0)
	if total_weight <= 0.0:
		var random_index: int = valid_indexes[randi() % valid_indexes.size()]
		return next_paths[random_index]

	var roll: float = randf() * total_weight
	for index: int in valid_indexes:
		roll -= maxf(_get_weight(index), 0.0)
		if roll <= 0.0:
			return next_paths[index]
	return next_paths[valid_indexes[valid_indexes.size() - 1]]


func _get_weight(index: int) -> float:
	return next_path_weights[index] if index < next_path_weights.size() else 1.0
