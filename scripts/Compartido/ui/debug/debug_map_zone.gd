## Área visual de depuración para delimitar sectores semánticos del mapa.
## Su Area3D nunca participa en física: layer y mask se dejan en cero en la escena.
extends Area3D
class_name DebugMapZone

const DEBUG_ZONE_GROUP: StringName = &"map_debug_zones"

## Identificador estable para logs, herramientas y futuros modos de juego.
@export var zone_id: StringName

## Estado inicial de la malla de depuración. El área se mantiene activa pero sin colisión.
@export var display_enabled: bool = false

@onready var _visual: MeshInstance3D = get_node_or_null("Visual") as MeshInstance3D


func _ready() -> void:
	add_to_group(DEBUG_ZONE_GROUP)
	set_display_enabled(display_enabled)


## Muestra u oculta únicamente el volumen visual; no modifica física ni navegación.
func set_display_enabled(enabled: bool) -> void:
	display_enabled = enabled
	if _visual != null:
		_visual.visible = display_enabled


func is_display_enabled() -> bool:
	return display_enabled


## Ajusta el volumen sin escalar nodos de colisión. Aunque el Area3D no tiene
## capas ni máscara, esto evita advertencias y mantiene el tamaño visual exacto.
func set_zone_size(size: Vector3) -> void:
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.shape is BoxShape3D:
		var box_shape: BoxShape3D = (collision_shape.shape as BoxShape3D).duplicate() as BoxShape3D
		box_shape.size = size
		collision_shape.shape = box_shape
	if _visual != null and _visual.mesh is BoxMesh:
		var box_mesh: BoxMesh = (_visual.mesh as BoxMesh).duplicate() as BoxMesh
		box_mesh.size = size
		_visual.mesh = box_mesh
