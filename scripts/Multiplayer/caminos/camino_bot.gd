@tool
extends Path3D
class_name CaminoBot

## Roles de ruta. No se comparan directamente con Roles.Type: usan enums distintos.
enum Role { ASSAULT, FLANKER, DEFENDER }

const ROUTE_GROUP: StringName = &"bot_routes"

@export var role: Role = Role.ASSAULT
@export var route_id: StringName
@export var enabled: bool = true
@export var reverse_allowed: bool = true
@export var next_paths: Array[NodePath] = []
@export var next_path_weights: Array[float] = []
@export var show_debug: bool = false:
	set(value):
		show_debug = value
		call_deferred("_refresh_debug_mesh")

var _debug_mesh_instance: MeshInstance3D = null


func _ready() -> void:
	add_to_group(ROUTE_GROUP)
	_refresh_debug_mesh()


## Una ruta solo es utilizable si está habilitada y define al menos un tramo.
func is_usable() -> bool:
	return enabled and curve != null and curve.get_baked_points().size() >= 2


## Devuelve los puntos horneados transformados al espacio global del mapa.
func get_global_waypoints() -> PackedVector3Array:
	var global_points: PackedVector3Array = PackedVector3Array()
	if curve == null:
		return global_points

	var local_points: PackedVector3Array = curve.get_baked_points()
	var route_transform: Transform3D = global_transform if is_inside_tree() else transform
	for local_point: Vector3 in local_points:
		global_points.append(route_transform * local_point)
	return global_points


func get_start_position() -> Vector3:
	var points: PackedVector3Array = get_global_waypoints()
	return points[0] if not points.is_empty() else global_position


func get_end_position() -> Vector3:
	var points: PackedVector3Array = get_global_waypoints()
	return points[points.size() - 1] if not points.is_empty() else global_position


## Elige el sentido cuyo extremo inicial quede más cerca de `from_position`.
## Retorna 1 para inicio → fin o -1 para fin → inicio.
func get_preferred_direction(from_position: Vector3) -> int:
	if not is_usable():
		return 1
	var start_distance: float = from_position.distance_squared_to(get_start_position())
	var end_distance: float = from_position.distance_squared_to(get_end_position())
	if reverse_allowed and end_distance < start_distance:
		return -1
	return 1


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


func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh_instance == null:
		_debug_mesh_instance = MeshInstance3D.new()
		_debug_mesh_instance.name = "DebugRoute"
		add_child(_debug_mesh_instance)
		if Engine.is_editor_hint():
			_debug_mesh_instance.owner = owner
	_debug_mesh_instance.visible = show_debug
	if not show_debug or curve == null:
		_debug_mesh_instance.mesh = null
		return

	var points: PackedVector3Array = curve.get_baked_points()
	if points.size() < 2:
		_debug_mesh_instance.mesh = null
		return
	var line_mesh: ImmediateMesh = ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point: Vector3 in points:
		line_mesh.surface_add_vertex(point)
	line_mesh.surface_end()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _get_role_color()
	line_mesh.surface_set_material(0, material)
	_debug_mesh_instance.mesh = line_mesh


func _get_role_color() -> Color:
	match role:
		Role.FLANKER:
			return Color.LIME_GREEN
		Role.DEFENDER:
			return Color.GOLD
		_:
			return Color.RED
