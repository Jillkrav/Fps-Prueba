@tool
class_name NormalFloorProp extends WorldMapProp

## Suelo normal transitable. La colisión soporta a bots y jugador;
## el NavMesh debe hornearse al colocarlo dentro de un mapa.

@export var navigation_priority: float = 1.0


func is_preferred_walkable_surface() -> bool:
	return true
