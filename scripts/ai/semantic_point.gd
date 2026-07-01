# scripts/ai/semantic_point.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT — Punto de navegación semántica (FASE 7)
#
# Define ubicaciones en el mapa con significado táctico para que
# los bots tomen decisiones avanzadas: emboscadas, defensa, rutas
# alternativas, ubicaciones de items, etc.
#
# ── TIPOS ──
#   PATH:       Punto de patrulla / ruta
#   AMBUSH:     Punto de emboscada (flanqueo)
#   DEFENSE:    Punto defensivo (proteger base/core)
#   ALTERNATE:  Ruta alternativa (evitar zona peligrosa)
#   LIFT:       Punto de elevador / plataforma
#   ITEM:       Ubicación de item importante
#   SNIPER:     Punto de francotirador
# ──────────────────────────────────────────────────────────────────
extends Resource
class_name SemanticPoint


# ══════════════════════════════════════════════════════════════════
# ENUM — Tipos de punto semántico
# ══════════════════════════════════════════════════════════════════

enum PointType {
	PATH = 0,        # Punto de patrulla / ruta genérica
	AMBUSH = 1,      # Punto de emboscada (flanqueo/sorpresa)
	DEFENSE = 2,     # Punto defensivo
	ALTERNATE = 3,   # Ruta alternativa
	LIFT = 4,        # Elevador / plataforma
	ITEM = 5,        # Ubicación de item
	SNIPER = 6,      # Punto de francotirador
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES EXPORTADAS
# ══════════════════════════════════════════════════════════════════

@export var position: Vector3

## Tipo de punto semántico
@export var point_type: PointType = PointType.PATH

## Equipo dueño (-1 = neutral, 0 = espectador, 1 = azul, 2 = rojo, etc.)
@export var team: int = -1

## Prioridad (mayor = más importante)
@export var priority: int = 0

## Dirección hacia dónde mirar (para puntos de defensa/emboscada)
@export var look_direction: Vector3 = Vector3.FORWARD

## Radio de visión/efectividad desde este punto
@export var sight_radius: float = 50.0

## Coste extra de pathfinding (útil para desincentivar rutas)
@export var extra_cost: float = 0.0

## Tags para filtrado semántico (ej: "flank_left", "high_ground")
@export var tags: Array[String] = []

## ¿Es un puesto de francotirador?
@export var is_sniper_spot: bool = false

## ¿Es de un solo sentido? (útil para drops/descensos)
@export var is_one_way: bool = false

## Radio de cobertura (distancia máxima a la que un bot
## puede usar este punto como referencia útil)
@export var coverage_radius: float = 20.0


# ══════════════════════════════════════════════════════════════════
# MÉTODOS DE CONSULTA
# ══════════════════════════════════════════════════════════════════

## ¿Este punto es útil para el equipo dado?
func is_for_team(team_id: int) -> bool:
	return team == -1 or team == team_id


## ¿Este punto es del tipo indicado?
func is_type(type_id: int) -> bool:
	return point_type == type_id


## Distancia desde una posición a este punto.
func distance_from(pos: Vector3) -> float:
	return pos.distance_to(position)


## ¿La posición dada está dentro del radio de cobertura?
func covers_position(pos: Vector3) -> bool:
	return pos.distance_to(position) <= coverage_radius


## String para debug
func debug_string() -> String:
	var type_name: String = PointType.keys()[point_type] if point_type < PointType.size() else "?"
	return "[%s] pos=%s team=%d prio=%d" % [type_name, str(position.round()), team, priority]
