@tool
class_name CoverCubeProp extends WorldMapProp

## Caja cúbica de cobertura con puntos de cobertura en sus cuatro caras.

@export var cover_priority: float = 1.0
@export var max_occupants: int = 4


func get_cover_side_count() -> int:
	return 4
