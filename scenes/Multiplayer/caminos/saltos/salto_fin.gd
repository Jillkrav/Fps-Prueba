@tool
extends Area3D
class_name SaltoFin

@export var jump_id: StringName
@export var enabled: bool = true
@export var next_paths: Array[NodePath] = []
@export var next_path_weights: Array[float] = []

func _on_body_entered(body: Node3D) -> void:
	if not enabled or not body.has_method("finish_authored_jump"):
		return
	body.finish_authored_jump(self, get_next_path())

func get_next_path() -> NodePath:
	if next_paths.is_empty():
		return NodePath()
	var total_weight := 0.0
	for index in next_paths.size():
		total_weight += maxf(_get_weight(index), 0.0)
	if total_weight <= 0.0:
		return next_paths.pick_random()
	var roll := randf() * total_weight
	for index in next_paths.size():
		roll -= maxf(_get_weight(index), 0.0)
		if roll <= 0.0:
			return next_paths[index]
	return next_paths.back()

func _get_weight(index: int) -> float:
	return next_path_weights[index] if index < next_path_weights.size() else 1.0
