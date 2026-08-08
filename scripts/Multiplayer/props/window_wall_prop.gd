@tool
class_name WindowWallProp extends WorldMapProp

## Pared con tronera central. Sus puntos de cobertura se registran también como
## peek_cover_points para que los comportamientos tácticos puedan priorizarlos.

@export var opening_size: Vector2 = Vector2(2.0, 1.4)
@export var peek_priority: float = 2.5


func _ready() -> void:
	super()
	var children: Array[Node] = get_children()
	for child: Node in children:
		if child.name.begins_with("Peek"):
			child.add_to_group(&"peek_cover_points")


func get_peek_position() -> Vector3:
	var peek_point: Node3D = get_node_or_null("PeekFront") as Node3D
	if peek_point != null:
		return peek_point.global_position if peek_point.is_inside_tree() else peek_point.position
	return global_position if is_inside_tree() else position
