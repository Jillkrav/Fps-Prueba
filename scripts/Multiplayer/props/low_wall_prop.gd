@tool
class_name LowWallProp extends WorldMapProp

## Muro bajo: cubre el cuerpo mientras deja una línea de tiro por encima.

@export var cover_height: float = 1.2
@export var peek_priority: float = 1.6


func supports_standing_peek() -> bool:
	return true
