@tool
extends Path3D
class_name CaminoBot

enum Role { ASSAULT, FLANKER, DEFENDER }

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

var _debug_mesh_instance: MeshInstance3D

func _ready() -> void:
	_refresh_debug_mesh()

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

func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh_instance == null:
		_debug_mesh_instance = MeshInstance3D.new()
		_debug_mesh_instance.name = "DebugRoute"
		add_child(_debug_mesh_instance)
		_debug_mesh_instance.owner = owner
	_debug_mesh_instance.visible = show_debug
	if not show_debug or curve == null:
		return

	var points := curve.get_baked_points()
	if points.size() < 2:
		return
	var line_mesh := ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		line_mesh.surface_add_vertex(point)
	line_mesh.surface_end()
	var material := StandardMaterial3D.new()
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
