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
# ASSAULT    → Solo bots con rol ASSAULT lo usan como waypoint
#               hacia la base enemiga
# DEFENSE    → Para bots DEFENDER (lo protegen)
# ALTERNATE  → Para bots FLANKER (rutas de flanqueo)
# PATH       → Para bots PATROLLER (rondas de patrullaje)
# OBJECTIVE  → Para bots ASSAULT y FLANKER (objetivo secundario azul)
# DUAL       → Para bots ASSAULT y FLANKER (punto compartido verde oscuro)
# TERCER     → Para bots ASSAULT y FLANKER (tercer camino verde oscuro)
# ──────────────────────────────────────────────────────────────────
extends RefCounted
class_name SemanticPoint


# ══════════════════════════════════════════════════════════════════
# ENUM — Tipos de punto semántico
# ══════════════════════════════════════════════════════════════════

enum PointType {
	ASSAULT   = 0,  # Punto de asalto: solo ASSAULT bots lo usan
	DEFENSE   = 1,  # Punto defensivo: solo DEFENDER bots
	ALTERNATE = 2,  # Ruta alterna: solo FLANKER bots
	PATH      = 3,  # Ruta de patrulla: solo PATROLLER bots
	OBJECTIVE = 4,  # Punto objetivo: bots ASSAULT y FLANKER lo usan
	DUAL      = 5,  # Punto dual: bots ASSAULT y FLANKER lo usan
	TERCER    = 6,  # Tercer camino: bots ASSAULT y FLANKER lo usan
}


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tipo de punto semántico (ASSAULT, DEFENSE, ALTERNATE, PATH, OBJECTIVE)
var point_type: int = PointType.ASSAULT

## Posición global del punto en el mundo
var position: Vector3 = Vector3.ZERO

## Equipo al que pertenece (-1 = neutral, cualquier equipo lo usa)
var team: int = -1

## Nombre descriptivo (para debug)
var name: String = ""

## Posición secundaria (para puntos OBJECTIVE: posición del cubo celeste
## al que el bot debe ir después de tocar el cubo azul).
var secondary_position: Vector3 = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# CONSTRUCTOR
# ══════════════════════════════════════════════════════════════════

func _init(p_type: int = PointType.ASSAULT, p_position: Vector3 = Vector3.ZERO,
		   p_team: int = -1, p_name: String = "", p_secondary: Vector3 = Vector3.ZERO) -> void:
	point_type = p_type
	position = p_position
	team = p_team
	name = p_name
	secondary_position = p_secondary


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

## Retorna el nombre del tipo de punto para debug.
func get_type_name() -> String:
	match point_type:
		PointType.ASSAULT:
			return "ASSAULT"
		PointType.DEFENSE:
			return "DEFENSE"
		PointType.ALTERNATE:
			return "ALTERNATE"
		PointType.PATH:
			return "PATH"
		PointType.OBJECTIVE:
			return "OBJECTIVE"
		PointType.DUAL:
			return "DUAL"
		PointType.TERCER:
			return "TERCER"
		_:
			return "UNKNOWN"


func _to_string() -> String:
	return "[SemanticPoint type=%s pos=(%.1f, %.1f, %.1f) team=%d name=%s]" % [
		get_type_name(),
		position.x, position.y, position.z,
		team, name
	]
