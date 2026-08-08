# scripts/props/cover_point.gd
# ──────────────────────────────────────────────────────────────────
# COVER POINT — Punto de cobertura reutilizable para bots de IA.
#
# Marca una posición del mapa donde un bot puede refugiarse para
# evitar el fuego enemigo. Los bots lo consultan cuando reciben daño,
# tienen la salud baja o buscan ventaja táctica.
#
# Es un nodo ligero (Area3D) que no interfiere con la física ni con
# el jugador. Solo expone información de intención para la IA.
# ──────────────────────────────────────────────────────────────────
extends Node3D
class_name CoverPoint

## Grupo al que se añaden todos los puntos de cobertura del mapa.
const COVER_GROUP: StringName = &"cover_points"

## Tipo de cobertura (para darle semántica a la IA).
enum CoverType {
	FULL,      # Protege de todos los lados (caja cerrada)
	PARTIAL,   # Protege de un solo lado (esquina / pared)
	HIGH,      # Protege en altura (protección vertical)
	LOW,       # Protege en posición agachada
}

## Tipo de cobertura.
@export var cover_type: int = CoverType.PARTIAL

## Radio dentro del cual un bot considera válida esta cobertura
## como destino de refugio.
@export var coverage_radius: float = 3.0

## Prioridad de esta cobertura: más alto = se prefiere cuando hay
## varias opciones. Útil para marcar coberturas "buenas".
@export var priority: float = 1.0

## Dirección desde la que protege (usada para caminos de flanqueo).
## Normalmente apunta hacia el enemigo/objetivo.
@export var facing_direction: Vector3 = Vector3.FORWARD

## Si un bot ya está usando esta cobertura, no enviar más bots aquí.
@export var max_occupants: int = 1

## Radio de debug para visualizar la cobertura en el editor.
@export var show_debug: bool = false:
	set(value):
		show_debug = value
		call_deferred("_refresh_debug")

var occupants: Array[Node] = []


func _ready() -> void:
	add_to_group(COVER_GROUP)
	_refresh_debug()


## ¿Está libre para que `bot` la use?
func is_available(bot: Node) -> bool:
	if not bot or occupants.is_empty():
		return true
	if occupants.has(bot):
		return true
	return occupants.size() < max_occupants


func occupy(bot: Node) -> void:
	if bot and not occupants.has(bot):
		occupants.append(bot)


func release(bot: Node) -> void:
	occupants.erase(bot)


## Punto concreto desde el que el bot toma cobertura (un poco al lado).
func get_cover_position() -> Vector3:
	return _current_position()


## Posición del nodo, robusta incluso fuera del árbol (para pruebas/tools).
func _current_position() -> Vector3:
	return global_position if is_inside_tree() else (transform.origin + position)


func _refresh_debug() -> void:
	if not is_inside_tree():
		return
	var existing: MeshInstance3D = get_node_or_null("DebugCover")
	if existing:
		existing.queue_free()
	if not show_debug:
		return
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = "DebugCover"
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = coverage_radius
	cyl.bottom_radius = coverage_radius
	cyl.height = 0.1
	mesh_inst.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.9, 0.3, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	add_child(mesh_inst)
	if Engine.is_editor_hint():
		mesh_inst.owner = owner