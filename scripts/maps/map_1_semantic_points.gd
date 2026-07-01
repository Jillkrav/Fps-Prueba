# scripts/maps/map_1_semantic_points.gd
# ──────────────────────────────────────────────────────────────────
# PUNTOS SEMÁNTICOS DEL MAPA — map_1.tscn (FASE 7)
#
# Define los puntos tácticos que los bots usan para navegación
# semántica. Se carga desde NavigationSystem.load_semantic_points()
# cuando el mapa es map_1.
#
# ── TIPOS DE PUNTO ──
#   PATH=0, AMBUSH=1, DEFENSE=2, ALTERNATE=3, LIFT=4, ITEM=5, SNIPER=6
# ──────────────────────────────────────────────────────────────────
extends Node
class_name MapSemanticPoints


## Retorna todos los puntos semánticos para map_1.
## Las posiciones están en coordenadas globales del mapa.
static func get_points() -> Array[SemanticPoint]:
	var points: Array[SemanticPoint] = []
	
	# ── DEFENSA (type=2) — Entradas de base ──────────────────────
	# Blue base front entrance
	points.append(_make_sp(
		2, 1, 10, Vector3(0, 0.5, -18), Vector3(0, 0, 1), 50.0, [], false, 20.0))
	# Blue base left flank
	points.append(_make_sp(
		2, 1, 8, Vector3(-20, 0.5, -24), Vector3(1, 0, 1), 50.0, [], false, 20.0))
	# Blue base right flank
	points.append(_make_sp(
		2, 1, 8, Vector3(20, 0.5, -24), Vector3(-1, 0, 1), 50.0, [], false, 20.0))
	# Red base front entrance
	points.append(_make_sp(
		2, 2, 10, Vector3(0, 0.5, 86), Vector3(0, 0, -1), 50.0, [], false, 20.0))
	# Red base left flank
	points.append(_make_sp(
		2, 2, 8, Vector3(-8, 0.5, 92), Vector3(1, 0, -1), 50.0, [], false, 20.0))
	# Red base right flank
	points.append(_make_sp(
		2, 2, 8, Vector3(22, 0.5, 92), Vector3(-1, 0, -1), 50.0, [], false, 20.0))
	
	# ── EMBOSCADA (type=1) — Coberturas y flancos ───────────────
	# Near Cover7 (front-left)
	points.append(_make_sp(
		1, -1, 7, Vector3(-20, 1, -8), Vector3(0, 0, 1), 50.0, [], false, 20.0))
	# Near Cover8 (front-right)
	points.append(_make_sp(
		1, -1, 7, Vector3(19, 1, -7), Vector3(0, 0, 1), 50.0, [], false, 20.0))
	# Near Cover5 (mid-left)
	points.append(_make_sp(
		1, -1, 7, Vector3(-20, 1, 56), Vector3(0, 0, -1), 50.0, [], false, 20.0))
	# Near Cover6 (mid-right)
	points.append(_make_sp(
		1, -1, 7, Vector3(21, 1, 55), Vector3(0, 0, -1), 50.0, [], false, 20.0))
	# Bridge center ambush
	points.append(_make_sp(
		1, -1, 6, Vector3(0, 0.5, 4), Vector3(1, 0, 0), 50.0, [], false, 20.0))
	
	# ── PATRULLA (type=0) — Rutas de navegación ─────────────────
	points.append(_make_sp(
		0, -1, 5, Vector3(0, 0.5, -28), Vector3(0, 0, 1), 50.0, [], false, 20.0))
	points.append(_make_sp(
		0, -1, 5, Vector3(0, 0.5, 14), Vector3(0, 0, 1), 50.0, [], false, 20.0))
	points.append(_make_sp(
		0, -1, 5, Vector3(10, 0.5, 86), Vector3(0, 0, -1), 50.0, [], false, 20.0))
	
	# ── RUTA ALTERNATIVA (type=3) — Flancos ─────────────────────
	points.append(_make_sp(
		3, -1, 6, Vector3(-22, 0.5, 30), Vector3(1, 0, 0), 50.0, [], false, 20.0))
	points.append(_make_sp(
		3, -1, 6, Vector3(22, 0.5, 30), Vector3(-1, 0, 0), 50.0, [], false, 20.0))
	
	# ── FRANCOTIRADOR (type=6) — Puntos elevados ───────────────
	points.append(_make_sp(
		6, 1, 9, Vector3(26, 2, -14), Vector3(0, 0, 1), 60.0, ["sniper", "high_ground"], true, 25.0))
	points.append(_make_sp(
		6, 2, 9, Vector3(-24, 2, 74), Vector3(0, 0, -1), 60.0, ["sniper", "high_ground"], true, 25.0))
	
	# ── ITEM (type=5) — Puntos de recursos ──────────────────────
	points.append(_make_sp(
		5, -1, 4, Vector3(10, 0.5, 33), Vector3(0, 0, -1), 50.0, ["resupply"], false, 15.0))
	
	return points


## Helper para crear un SemanticPoint con todos los campos.
static func _make_sp(
	type_val: int,
	team_val: int,
	priority_val: int,
	pos: Vector3,
	look_dir: Vector3,
	sight_radius: float = 50.0,
	tags: Array[String] = [],
	is_sniper: bool = false,
	coverage: float = 20.0
) -> SemanticPoint:
	var sp := SemanticPoint.new()
	sp.point_type = type_val as SemanticPoint.PointType
	sp.team = team_val
	sp.priority = priority_val
	sp.position = pos
	sp.look_direction = look_dir
	sp.sight_radius = sight_radius
	sp.tags = tags
	sp.is_sniper_spot = is_sniper
	sp.coverage_radius = coverage
	sp.extra_cost = 0.0
	sp.is_one_way = false
	return sp
