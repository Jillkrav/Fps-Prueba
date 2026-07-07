# scripts/ai/navigation/navigation_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE NAVEGACIÓN — Gestión del navmesh
#
# Responsabilidades:
# - Gestión del NavigationAgent3D (inicialización)
# - API de consulta de navegación (destino, siguiente posición)
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
# ╔══════════════════════════════════════════════════════════════╗
# ║  GESTIÓN GLOBAL DE PUNTOS SEMÁNTICOS                        ║
# ║  (estáticos — compartidos entre todos los bots)             ║
# ╚══════════════════════════════════════════════════════════════╝
# ══════════════════════════════════════════════════════════════════

## Todos los puntos semánticos cargados en el mapa actual.
static var all_semantic_points: Array[SemanticPoint] = []

## Flag: ¿ya se cargaron los puntos?
static var _semantic_points_loaded: bool = false


## Busca todos los nodos SemanticPointMarker en el árbol y los registra
## como puntos semánticos. Se llama desde NpcBase al iniciar.
static func load_semantic_points() -> void:
	all_semantic_points.clear()
	_semantic_points_loaded = false

	var tree: SceneTree = Engine.get_main_loop()
	if tree == null:
		return

	var markers: Array[Node] = []
	
	# 1. Buscar por grupo "semantic_points"
	var group_nodes: Array[Node] = tree.get_nodes_in_group("semantic_points")
	for group_node in group_nodes:
		if group_node is SemanticPointMarker:
			markers.append(group_node)
		else:
			for child in group_node.find_children("*", "SemanticPointMarker", true, false):
				if child is SemanticPointMarker and child not in markers:
					markers.append(child)
	
	# 2. Fallback: buscar por tipo en todo el árbol
	if markers.is_empty():
		var root: Window = tree.root
		var found: Array[Node] = root.find_children("*", "SemanticPointMarker", true, false)
		for n in found:
			if n is SemanticPointMarker:
				markers.append(n)

	for marker_node in markers:
		var marker: SemanticPointMarker = marker_node as SemanticPointMarker
		if marker == null:
			continue
		var sp: SemanticPoint = marker.to_semantic_point()
		all_semantic_points.append(sp)

	_semantic_points_loaded = true
	print("[NavigationSystem] Cargados %d puntos semánticos desde SemanticPointMarker" % all_semantic_points.size())


## Retorna el punto semántico más cercano del tipo indicado,
## dentro del radio max_dist, filtrado por equipo.
## Si team_filter es -1, ignora el filtro de equipo.
static func get_nearest_point(point_type: int, from_pos: Vector3,
		team_filter: int = -1, max_dist: float = INF) -> SemanticPoint:
	if not _semantic_points_loaded or all_semantic_points.is_empty():
		return null

	var nearest: SemanticPoint = null
	var nearest_dist: float = max_dist

	for sp in all_semantic_points:
		# Filtrar por tipo
		if sp.point_type != point_type:
			continue
		# Filtrar por equipo (si no es -1)
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		var d: float = from_pos.distance_squared_to(sp.position)
		if d < nearest_dist * nearest_dist:
			nearest_dist = sqrt(d)
			nearest = sp

	return nearest


## Retorna TODOS los puntos semánticos del tipo indicado,
## ordenados por distancia ascendente desde from_pos.
static func get_points_sorted(point_type: int, from_pos: Vector3,
		team_filter: int = -1, max_dist: float = INF) -> Array[SemanticPoint]:
	if not _semantic_points_loaded or all_semantic_points.is_empty():
		return []

	var result: Array[SemanticPoint] = []
	for sp in all_semantic_points:
		if sp.point_type != point_type:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		var d: float = from_pos.distance_squared_to(sp.position)
		if d <= max_dist * max_dist:
			result.append(sp)

	# Ordenar por distancia
	result.sort_custom(func(a: SemanticPoint, b: SemanticPoint) -> bool:
		var da: float = from_pos.distance_squared_to(a.position)
		var db: float = from_pos.distance_squared_to(b.position)
		return da < db
	)
	return result


## Retorna true si hay al menos un punto del tipo indicado
## dentro del radio especificado desde la posición dada.
static func has_point_nearby(point_type: int, from_pos: Vector3,
		team_filter: int = -1, radius: float = 8.0) -> bool:
	var nearest: SemanticPoint = get_nearest_point(point_type, from_pos, team_filter, radius)
	return nearest != null


## Limpia todos los puntos (útil al cambiar de mapa).
static func clear_points() -> void:
	all_semantic_points.clear()
	_semantic_points_loaded = false


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


## Resetea el estado de navegación (útil en respawn).
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
