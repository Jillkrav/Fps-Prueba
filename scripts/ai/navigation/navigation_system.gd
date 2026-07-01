# scripts/ai/navigation/navigation_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE NAVEGACIÓN — Gestión de navmesh + puntos semánticos
#
# Responsabilidades (Fase 8 - Limpieza de Legacy):
# - Gestión del NavigationAgent3D (inicialización)
# - Puntos semánticos (SemanticPoints) para decisiones tácticas
# - API de consulta de puntos por tipo, equipo, distancia
#
# NO responsable de:
# - Movimiento físico → MovementSystem
# - Detección de atasco → MovementSystem
# - Route diversification → MovementSystem
# - Auto-jump → MovementSystem
# - Evitación entre NPCs → MovementSystem
# ──────────────────────────────────────────────────────────────────
extends Node
class_name NavigationSystem


# ══════════════════════════════════════════════════════════════════
# SEMANTIC POINTS — Navegación semántica (FASE 7)
# ══════════════════════════════════════════════════════════════════

## Lista global de todos los SemanticPoints del mapa actual.
static var all_semantic_points: Array[SemanticPoint] = []

## Flag: ¿Ya se cargaron los puntos semánticos?
static var _semantic_points_loaded: bool = false

## Lista filtrada por tipo (caché para consultas rápidas).
static var _points_by_type: Dictionary = {}  # PointType → Array[SemanticPoint]


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

## Referencia al bot dueño.
var bot: NpcBase:
	get:
		if _bot == null:
			_bot = get_parent() as NpcBase
		return _bot
var _bot: NpcBase = null

## NavigationAgent del bot (buscado como hijo de NpcBase).
var agent: NavigationAgent3D = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as NpcBase
	if bot:
		agent = bot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Puntos semánticos
# ══════════════════════════════════════════════════════════════════

## Carga puntos semánticos desde los SemanticPointMarker del scene tree.
## Busca nodos en el grupo "semantic_points" y extrae sus SemanticPoint.
static func load_semantic_points() -> void:
	all_semantic_points.clear()
	_points_by_type.clear()
	_semantic_points_loaded = false

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return

	var markers: Array[Node] = tree.get_nodes_in_group("semantic_points")
	for marker in markers:
		if marker.has_method("get_semantic_point"):
			var sp: SemanticPoint = marker.get_semantic_point()
			if sp:
				all_semantic_points.append(sp)

	_index_points_by_type()
	_semantic_points_loaded = true


## Re-indexa los puntos semánticos por tipo.
static func _index_points_by_type() -> void:
	_points_by_type.clear()
	for sp in all_semantic_points:
		var type_key: int = sp.point_type as int
		if not _points_by_type.has(type_key):
			var typed_arr: Array[SemanticPoint] = []
			_points_by_type[type_key] = typed_arr
		_points_by_type[type_key].append(sp)


## Obtiene el punto semántico más cercano a position que cumpla los filtros.
## - point_type: tipo de punto (-1 para cualquier tipo)
## - position: posición de referencia
## - team: filtro de equipo (-1 para ignorar)
## - max_dist: distancia máxima de búsqueda
static func get_nearest_point(
	point_type: int, position: Vector3, team: int = -1, max_dist: float = INF
) -> SemanticPoint:
	if not _semantic_points_loaded:
		return null

	var candidates: Array[SemanticPoint]
	if point_type == -1 or not _points_by_type.has(point_type):
		candidates = all_semantic_points
	else:
		candidates = _points_by_type.get(point_type, all_semantic_points)
	if candidates.is_empty():
		candidates = all_semantic_points

	var best: SemanticPoint = null
	var best_dist: float = max_dist

	for sp in candidates:
		if point_type != -1 and sp.point_type != point_type:
			continue
		if team != -1 and sp.team != -1 and sp.team != team:
			continue
		var d: float = position.distance_to(sp.position)
		if d < best_dist:
			best = sp
			best_dist = d

	return best


## Obtiene el punto semántico más cercano de un tipo específico.
## Alias de get_nearest_point con point_type específico.
static func get_nearest_point_of_type(
	point_type: int, position: Vector3, team: int = -1, max_dist: float = INF
) -> SemanticPoint:
	return get_nearest_point(point_type, position, team, max_dist)


## Obtiene todos los puntos semánticos de un tipo dentro de un radio.
static func get_points_in_radius(
	point_type: int, position: Vector3, radius: float, team: int = -1
) -> Array[SemanticPoint]:
	var result: Array[SemanticPoint] = []
	if not _semantic_points_loaded:
		return result

	var candidates: Array[SemanticPoint]
	if _points_by_type.has(point_type):
		candidates = _points_by_type.get(point_type, all_semantic_points)
	else:
		candidates = []
	if candidates.is_empty():
		candidates = []
	for sp in candidates:
		if team != -1 and sp.team != -1 and sp.team != team:
			continue
		if position.distance_to(sp.position) <= radius:
			result.append(sp)

	return result


## Devuelve todos los puntos semánticos cargados (útil para debug).
static func get_all_points() -> Array[SemanticPoint]:
	return all_semantic_points.duplicate()


## Establece los puntos semánticos desde un Array genérico.
## Útil para que NpcBase pueda cargar puntos sin referenciar SemanticPoint.
static func set_points_from_array(points: Array) -> void:
	all_semantic_points.clear()
	for p in points:
		if p is SemanticPoint:
			all_semantic_points.append(p as SemanticPoint)
	_index_points_by_type()
	_semantic_points_loaded = true


## Resetea el estado de navegación (útil en respawn).
## Los puntos semánticos son globales, no se resetean por bot.
func reset() -> void:
	pass


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Consultas de navegación
# ══════════════════════════════════════════════════════════════════

## ¿La navegación actual ha llegado a su destino?
func is_navigation_finished() -> bool:
	if agent == null:
		return true
	return agent.is_navigation_finished()


## Obtiene la siguiente posición en el camino calculado.
func get_next_path_position() -> Vector3:
	if agent == null:
		return Vector3.ZERO
	return agent.get_next_path_position()


## Establece el destino del NavigationAgent3D.
func set_destination(target: Vector3) -> void:
	if agent == null:
		return
	agent.target_position = target
