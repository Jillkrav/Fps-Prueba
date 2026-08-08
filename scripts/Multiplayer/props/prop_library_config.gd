class_name PropLibraryConfig extends Resource

## Configuración compartida de la biblioteca de props multijugador.
## Se guarda como recurso .tres en config/ y puede asignarse a cada prop.

@export_category("Colisión predeterminada")
## Capa física donde se publican los props estáticos del mapa.
@export var default_collision_layer: int = 1

## Máscara de colisión del StaticBody3D. Los props estáticos no escanean cuerpos.
@export var default_collision_mask: int = 0

@export_category("IA y navegación")
## Altura libre mínima recomendada para que los bots pasen junto a un prop.
@export var bot_clearance_height: float = 1.8

## Radio de la cápsula de los bots actual. Útil al diseñar pasillos.
@export var bot_clearance_radius: float = 0.65

## Distancia extra para colocar puntos de cobertura detrás de la geometría.
@export var cover_standoff_distance: float = 0.9

## Peso por defecto para un suelo tácticamente desfavorable.
@export var default_avoidance_weight: float = 5.0
