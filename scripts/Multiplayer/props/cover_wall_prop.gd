@tool
class_name CoverWallProp extends WorldMapProp

## Muro alto de cobertura. Los hijos CoverPoint indican posiciones concretas
## desde ambos lados para que la IA no navegue hacia el centro de la pared.

@export var cover_priority: float = 1.25
@export var max_occupants_per_side: int = 1


func provides_full_height_cover() -> bool:
	return true
