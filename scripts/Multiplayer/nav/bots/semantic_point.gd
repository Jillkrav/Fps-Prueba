# scripts/ai/navigation/semantic_point.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT — Recurso de punto semántico para navegación táctica
#
# Cada punto semántico representa una posición de interés en el mapa
# que los bots pueden usar según su rol táctico. Los puntos se colocan
# manualmente en el editor con SemanticPointMarker y se cargan en
# NavigationSystem al iniciar la partida.
#
# ── TIPOS DE PUNTO ──
# ASSAULT    → Solo bots ASALTO
# DEFENSE    → Solo bots DEFENSOR
# ALTERNATE  → Solo bots FLANQUEADOR (rutas de flanqueo)
# PATH       → Solo bots PATRULLADOR (rondas de patrullaje)
# VERSATIL   → Solo bots VERSATIL
# OVERWATCH  → Solo bots FRANCOTIRADOR (posiciones de cobertura)
# SUPPORT    → Solo bots APOYO (posiciones de supresión)
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name SemanticPoint


# ══════════════════════════════════════════════════════════════════
# ENUM — Tipos de punto semántico
# ══════════════════════════════════════════════════════════════════

enum PointType {
	ASSAULT   = 0,
	DEFENSE   = 1,
	ALTERNATE = 2,
	PATH      = 3,
	VERSATIL  = 7,
	OVERWATCH = 8,
	SUPPORT   = 9,
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tipo de punto semántico.
var point_type: int = PointType.ASSAULT

## Posición global del punto en el mundo.
var position: Vector3 = Vector3.ZERO

## Equipo al que pertenece (-1 = neutral, auto-asignado por proximidad al core).
var team: int = -1

## Nombre descriptivo (para debug).
var name: String = ""


# ══════════════════════════════════════════════════════════════════
# CONSTRUCTOR
# ══════════════════════════════════════════════════════════════════

func _init(p_type: int = PointType.ASSAULT, p_position: Vector3 = Vector3.ZERO,
		   p_team: int = -1, p_name: String = "") -> void:
	point_type = p_type
	position = p_position
	team = p_team
	name = p_name


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func get_type_name() -> String:
	match point_type:
		PointType.ASSAULT:   return "ASSAULT"
		PointType.DEFENSE:   return "DEFENSE"
		PointType.ALTERNATE: return "ALTERNATE"
		PointType.PATH:      return "PATH"
		PointType.VERSATIL:  return "VERSATIL"
		PointType.OVERWATCH: return "OVERWATCH"
		PointType.SUPPORT:   return "SUPPORT"
		_:                   return "UNKNOWN"


func _to_string() -> String:
	return "[SemanticPoint type=%s pos=(%.1f, %.1f, %.1f) team=%d name=%s]" % [
		get_type_name(),
		position.x, position.y, position.z,
		team, name
	]
