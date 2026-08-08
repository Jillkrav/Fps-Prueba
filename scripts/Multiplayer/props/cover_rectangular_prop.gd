@tool
class_name CoverRectangularProp extends WorldMapProp

## Caja rectangular de cobertura para variar siluetas y líneas de tiro.

@export var cover_priority: float = 1.1
@export var max_occupants: int = 2


func get_cover_side_count() -> int:
	return 2
