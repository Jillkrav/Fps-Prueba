@tool
class_name OneWayLowWallProp extends WorldMapProp

## Muro bajo orientado: el frente es únicamente visual/semántico y la IA usa
## exclusivamente el CoverBack, cuyo límite permite como máximo dos bots.

@export var cover_height: float = 1.2
@export var max_rear_occupants: int = 2


func supports_one_way_cover() -> bool:
	return true


func get_rear_cover_point() -> CoverPoint:
	return get_node_or_null("CoverBack") as CoverPoint
