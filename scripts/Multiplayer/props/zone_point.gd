# scripts/props/zone_point.gd
# ──────────────────────────────────────────────────────────────────
# ZONE POINT — Zona reutilizable para objetivos de IA.
#
# Representa una región del mapa con un propósito semántico:
#   - Punto de captura (Rey de la colina / Atacar los puntos)
#   - Punto de escolta (Empujar la carga)
#   - Zona especial (futuro: torretas, armas, eventos)
#
# Los bots consultan estas zonas como objetivos cuando el modo de
# juego lo requiere. Es un nodo ligero (Area3D) de intención de IA.
# ──────────────────────────────────────────────────────────────────
extends Area3D
class_name ZonePoint

## Grupo de todas las zonas del mapa.
const ZONE_GROUP: StringName = &"zone_points"

## Semántica de la zona.
enum ZoneType {
	CAPTURE,  # Punto que se captura
	ESCORT,   # Punto de paso de la carga
	SPECIAL,  # Zona especial (torretas, armas, eventos)
	DEFENSE,  # Zona que un equipo debe defender
}

## Tipo de zona.
@export var zone_type: int = ZoneType.CAPTURE

## Identificador único de la zona (para objetivos/detección).
@export var zone_id: StringName

## Equipo que controla/defiende la zona (-1 = neutral).
@export var team: int = -1

## Radio de la zona (para que la IA sepa dónde "estar dentro").
@export var zone_radius: float = 5.0

## Prioridad de la zona como objetivo.
@export var zone_priority: float = 1.0

## ¿La zona está activa como objetivo?
@export var is_active: bool = true

## ¿Está actualmente controlada por el equipo `team`?
var is_controlled: bool = false


func _ready() -> void:
	add_to_group(ZONE_GROUP)
	# La detección de control se maneja externamente (GameMode).
	# Este nodo solo expone el área y su semántica.


## ¿Contiene la posición `pos` dentro de su radio?
func contains_position(pos: Vector3) -> bool:
	return _current_position().distance_to(pos) <= zone_radius


## Punto de entrada preferido hacia la zona (para aproximarse).
func get_approach_position() -> Vector3:
	return _current_position()


## Posición del nodo, robusta incluso fuera del árbol (para pruebas/tools).
func _current_position() -> Vector3:
	return global_position if is_inside_tree() else (transform.origin + position)