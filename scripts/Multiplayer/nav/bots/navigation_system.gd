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

# ── Spatial Grid ──────────────────────────────────────────────
## Rejilla espacial para consultas O(c) vs O(n).
## Clave: "cx,cz" → Array[SemanticPoint] en esa celda.
static var _spatial_grid: Dictionary = {}
static var _grid_cell_size: float = 20.0

## Calcula la clave de celda para una posición.
static func _grid_key(pos: Vector3) -> String:
	var cx: int = floori(pos.x / _grid_cell_size)
	var cz: int = floori(pos.z / _grid_cell_size)
	return "%d,%d" % [cx, cz]

## Construye la rejilla espacial a partir de all_semantic_points.
static func _build_spatial_grid() -> void:
	_spatial_grid.clear()
	for sp in all_semantic_points:
		var key: String = _grid_key(sp.position)
		if not _spatial_grid.has(key):
			_spatial_grid[key] = []
		_spatial_grid[key].append(sp)


## Retorna los puntos en la celda de from_pos y sus 8 vecinas (3x3).
## Si no hay suficientes candidatos del tipo buscado, expande a 5x5.
## Si aun así está vacío, devuelve all_semantic_points como fallback.
static func _get_cell_points_for_type(from_pos: Vector3, point_type: int, team_filter: int) -> Array[SemanticPoint]:
	var cx: int = floori(from_pos.x / _grid_cell_size)
	var cz: int = floori(from_pos.z / _grid_cell_size)

	# Intentar 3x3 primero
	var result: Array[SemanticPoint] = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key: String = "%d,%d" % [cx + dx, cz + dz]
			if _spatial_grid.has(key):
				result.append_array(_spatial_grid[key])

	# Filtrar para ver si hay algo útil en 3x3
	var has_useful: bool = false
	for sp in result:
		if sp.point_type != point_type:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		has_useful = true
		break

	if has_useful:
		return result

	# Expandir a 5x5
	result.clear()
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key: String = "%d,%d" % [cx + dx, cz + dz]
			if _spatial_grid.has(key):
				result.append_array(_spatial_grid[key])

	# Verificar si 5x5 tiene algo útil
	for sp in result:
		if sp.point_type != point_type:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		return result

	# Fallback total: todos los puntos
	return all_semantic_points


## Busca todos los nodos SemanticPointMarker en el árbol y los registra
## como puntos semánticos. Se llama desde BotBase al iniciar.
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

	# Auto-asignar equipo a puntos neutrales según proximidad al core
	_assign_team_by_core_proximity()

	_semantic_points_loaded = true
	_build_spatial_grid()
	print("[NavigationSystem] Cargados %d puntos semánticos en %d celdas de rejilla" % [
		all_semantic_points.size(), _spatial_grid.size()])


## Retorna el punto semántico más cercano del tipo indicado,
## dentro del radio max_dist, filtrado por equipo.
static func get_nearest_point(point_type: int, from_pos: Vector3,
		team_filter: int = -1, max_dist: float = INF) -> SemanticPoint:
	if not _semantic_points_loaded or all_semantic_points.is_empty():
		return null

	var candidates: Array[SemanticPoint] = _get_cell_points_for_type(from_pos, point_type, team_filter)

	var nearest: SemanticPoint = null
	var nearest_dist_sq: float = max_dist * max_dist

	for sp in candidates:
		if sp.point_type != point_type:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		var d_sq: float = from_pos.distance_squared_to(sp.position)
		if d_sq < nearest_dist_sq:
			nearest_dist_sq = d_sq
			nearest = sp

	return nearest


## Retorna TODOS los puntos semánticos del tipo indicado,
## ordenados por distancia ascendente desde from_pos.
static func get_points_sorted(point_type: int, from_pos: Vector3,
		team_filter: int = -1, max_dist: float = INF) -> Array[SemanticPoint]:
	if not _semantic_points_loaded or all_semantic_points.is_empty():
		return []

	var candidates: Array[SemanticPoint] = _get_cell_points_for_type(from_pos, point_type, team_filter)

	var result: Array[SemanticPoint] = []
	var max_dist_sq: float = max_dist * max_dist
	for sp in candidates:
		if sp.point_type != point_type:
			continue
		if team_filter != -1 and sp.team != -1 and sp.team != team_filter:
			continue
		var d_sq: float = from_pos.distance_squared_to(sp.position)
		if d_sq <= max_dist_sq:
			result.append(sp)

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


## Asigna equipo a puntos semánticos neutrales según el core más cercano.
static func _assign_team_by_core_proximity() -> void:
	if not is_instance_valid(GameState):
		return

	var blue_pos: Vector3 = Vector3.ZERO
	var blue_valid: bool = false
	var red_pos: Vector3 = Vector3.ZERO
	var red_valid: bool = false

	if is_instance_valid(GameStateMP.core_blue) and GameStateMP.core_blue is Node3D:
		blue_pos = (GameStateMP.core_blue as Node3D).global_position
		blue_valid = true
	if is_instance_valid(GameStateMP.core_red) and GameStateMP.core_red is Node3D:
		red_pos = (GameStateMP.core_red as Node3D).global_position
		red_valid = true

	if not blue_valid and not red_valid:
		var cores: Array[Node] = Engine.get_main_loop().get_nodes_in_group("core")
		for core_node in cores:
			if not is_instance_valid(core_node) or not (core_node is Node3D):
				continue
			var team_id: int = core_node.get("team") if "team" in core_node else -1
			if team_id == Enums.Equipo.AZUL:
				blue_pos = (core_node as Node3D).global_position
				blue_valid = true
			elif team_id == Enums.Equipo.ROJO:
				red_pos = (core_node as Node3D).global_position
				red_valid = true

	if not blue_valid and not red_valid:
		push_warning("[NavigationSystem] No se encontraron cores para auto-asignar equipos")
		return

	var assigned_count: int = 0
	for sp in all_semantic_points:
		if sp.team != -1:
			continue
		if blue_valid and red_valid:
			var dist_to_blue: float = sp.position.distance_squared_to(blue_pos)
			var dist_to_red: float = sp.position.distance_squared_to(red_pos)
			sp.team = Enums.Equipo.AZUL if dist_to_blue <= dist_to_red else Enums.Equipo.ROJO
		elif blue_valid:
			sp.team = Enums.Equipo.AZUL
		elif red_valid:
			sp.team = Enums.Equipo.ROJO
		assigned_count += 1

	if assigned_count > 0:
		print("[NavigationSystem] Auto-asignados %d puntos semánticos por proximidad al core" % assigned_count)


## Limpia todos los puntos (útil al cambiar de mapa).
static func clear_points() -> void:
	all_semantic_points.clear()
	_semantic_points_loaded = false
	_spatial_grid.clear()


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

## Referencia al bot dueño.
var bot: BotBase:
	get:
		if _bot == null:
			_bot = get_parent() as BotBase
		return _bot
var _bot: BotBase = null

## NavigationAgent del bot (buscado como hijo de BotBase).
var agent: NavigationAgent3D = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as BotBase
	if bot:
		agent = bot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D


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
