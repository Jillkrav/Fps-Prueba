@tool
class_name MapWallProp extends WorldMapProp

## Pared modular sólida para perímetros, habitaciones y edificios.

@export var wall_category: StringName = &"building"
@export var supports_openings: bool = true


func is_structural_wall() -> bool:
	return true
