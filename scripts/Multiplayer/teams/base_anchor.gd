## Marcador semántico de una base para navegación y orientación de IA.
## No tiene malla ni colisión: los modos de juego pueden existir sin un núcleo.
extends Marker3D
class_name BaseAnchor

const BASE_ANCHOR_GROUP: StringName = &"base_anchors"

## Equipo propietario de esta base. Usa Enums.Equipo.AZUL / Enums.Equipo.ROJO.
@export var team: int = -1

## Permite desactivar temporalmente el marcador sin borrarlo del mapa.
@export var is_active: bool = true


func _ready() -> void:
	add_to_group(BASE_ANCHOR_GROUP)


func is_available_for_team(requesting_team: int) -> bool:
	return is_active and team == requesting_team
