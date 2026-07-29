# scripts/ai/navigation/semantic_point_marker.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT MARKER — Marcador de punto semántico para el editor
#
# Coloca este nodo (hereda de Marker3D) en el mapa para definir
# un punto semántico que los bots usarán según su rol táctico.
#
# ── USO ──
# 1. Agrega un SemanticPointMarker como hijo del mapa.
# 2. Configura point_type según el rol que debe usar el punto.
# 3. team = -1 para auto-asignación por proximidad al core.
# 4. Posiciónalo donde quieras que los bots naveguen.
# ──────────────────────────────────────────────────────────────────
extends Marker3D
class_name SemanticPointMarker


# ══════════════════════════════════════════════════════════════════
# EXPORTS
# ══════════════════════════════════════════════════════════════════

## Tipo de punto semántico.
@export var point_type: int = SemanticPoint.PointType.ASSAULT:
	set(val):
		point_type = val
		update_configuration_warnings()

## Equipo al que pertenece (-1 = neutral, auto-asignado por proximidad al core).
@export var team: int = -1

## Radio de activación: el bot debe estar a esta distancia para usar el punto.
@export var activation_radius: float = 8.0

## Nombre descriptivo (opcional, para debug).
@export var point_name: String = ""


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("semantic_points")


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN EN EDITOR
# ══════════════════════════════════════════════════════════════════

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	match point_type:
		SemanticPoint.PointType.ASSAULT:   warnings.append("Punto ASALTO — Solo bots ASALTO")
		SemanticPoint.PointType.DEFENSE:   warnings.append("Punto DEFENSA — Solo bots DEFENSOR")
		SemanticPoint.PointType.ALTERNATE: warnings.append("Punto ALTERNO — Solo bots FLANQUEADOR")
		SemanticPoint.PointType.PATH:      warnings.append("Punto PATRULLA — Solo bots PATRULLADOR")
		SemanticPoint.PointType.VERSATIL:  warnings.append("Punto VERSATIL — Solo bots VERSATIL")
		SemanticPoint.PointType.OVERWATCH: warnings.append("Punto COBERTURA — Solo bots FRANCOTIRADOR")
		SemanticPoint.PointType.SUPPORT:   warnings.append("Punto SUPRESIÓN — Solo bots APOYO")
		_: warnings.append("Tipo de punto no reconocido: %d" % point_type)
	if team != -1:
		warnings.append("Team=%d — Solo bots de este equipo" % team)
	return warnings


# ══════════════════════════════════════════════════════════════════
# CONVERSIÓN A SemanticPoint
# ══════════════════════════════════════════════════════════════════

## Convierte este marcador a un objeto SemanticPoint para uso interno.
func to_semantic_point() -> SemanticPoint:
	return SemanticPoint.new(point_type, global_position, team, point_name)
