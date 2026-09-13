@tool
class_name WorldMapProp extends PropBase

## Base liviana para todos los props estáticos reutilizables de mapas.
## La geometría visible, el material y la colisión se pueden sustituir desde
## el Inspector sin cambiar la lógica táctica del prop.

const MAP_PROP_GROUP: StringName = &"map_props"
const MAP_WALL_GROUP: StringName = &"map_walls"
const WALKABLE_SURFACE_GROUP: StringName = &"walkable_surfaces"
const AVOID_SURFACE_GROUP: StringName = &"avoid_surfaces"
const COVER_PROP_GROUP: StringName = &"cover_props"
const LOW_COVER_PROP_GROUP: StringName = &"low_cover_props"
const PEEK_COVER_PROP_GROUP: StringName = &"peek_cover_props"

enum TacticalUse {
	NONE,
	WALKABLE_SURFACE,
	AVOID_SURFACE,
	COVER,
	LOW_COVER,
	PEEK_COVER,
}

@export_category("Identidad")
## Identificador estable para herramientas de mapas o futuras estadísticas.
@export var prop_id: StringName = &"map_prop"

## Propósito táctico publicado mediante grupos de escena.
@export var tactical_use: int = TacticalUse.NONE

## Configuración compartida ubicada en config/Multiplayer/props/.
@export var library_config: PropLibraryConfig

@export_category("Reutilización visual")
## Malla alternativa. Si se deja vacía se conserva la malla de la escena.
@export var visual_mesh_override: Mesh:
	set(value):
		visual_mesh_override = value
		call_deferred("_refresh_geometry")

## Skin/material alternativo. Se aplica como material_override a Visual.
@export var skin_material: Material:
	set(value):
		skin_material = value
		call_deferred("_refresh_geometry")

@export_category("Colisión")
## Permite aplicar los layers definidos por el recurso de configuración.
@export var apply_library_collision_defaults: bool = true

## Tamaño opcional del BoxShape3D principal. Vector3.ZERO conserva el tamaño de escena.
@export var collision_size: Vector3 = Vector3.ZERO:
	set(value):
		collision_size = Vector3(
			maxf(value.x, 0.0),
			maxf(value.y, 0.0),
			maxf(value.z, 0.0))
		call_deferred("_refresh_geometry")


func _ready() -> void:
	super()
	add_to_group(MAP_PROP_GROUP)
	_publish_tactical_groups()
	_apply_library_defaults()
	_refresh_geometry()


## Devuelve la prioridad de diseño para herramientas de selección futuras.
func get_tactical_use() -> int:
	return tactical_use


## Indica si el prop necesita volver a hornearse en el NavMesh tras moverlo.
func affects_navigation_bake() -> bool:
	return tactical_use != TacticalUse.NONE


func _publish_tactical_groups() -> void:
	match tactical_use:
		TacticalUse.WALKABLE_SURFACE:
			add_to_group(WALKABLE_SURFACE_GROUP)
		TacticalUse.AVOID_SURFACE:
			add_to_group(AVOID_SURFACE_GROUP)
		TacticalUse.COVER:
			add_to_group(COVER_PROP_GROUP)
		TacticalUse.LOW_COVER:
			add_to_group(COVER_PROP_GROUP)
			add_to_group(LOW_COVER_PROP_GROUP)
		TacticalUse.PEEK_COVER:
			add_to_group(COVER_PROP_GROUP)
			add_to_group(PEEK_COVER_PROP_GROUP)

	if prop_id.begins_with("wall"):
		add_to_group(MAP_WALL_GROUP)


func _apply_library_defaults() -> void:
	if not apply_library_collision_defaults or library_config == null:
		return
	collision_layer = library_config.default_collision_layer
	collision_mask = library_config.default_collision_mask


func _refresh_geometry() -> void:
	var visuals: Array[Node] = find_children("Visual*", "MeshInstance3D", true, false)
	if visuals.is_empty():
		var named_visual: MeshInstance3D = get_node_or_null("Visual") as MeshInstance3D
		if named_visual != null:
			visuals.append(named_visual)
	for visual_node: Node in visuals:
		var visual: MeshInstance3D = visual_node as MeshInstance3D
		if visual == null:
			continue
		if visual_mesh_override != null and visual == visuals[0]:
			visual.mesh = visual_mesh_override
		if skin_material != null:
			visual.material_override = skin_material

	if collision_size == Vector3.ZERO:
		return
	var collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var shape: BoxShape3D = collision.shape as BoxShape3D
		shape.size = collision_size
