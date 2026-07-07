# scripts/ai/navigation/semantic_point_marker.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT MARKER — Marcador de punto semántico para el editor
#
# Coloca este nodo (hereda de Marker3D) en el mapa para definir
# un punto semántico que los bots usarán según su rol táctico.
#
# ── USO ──
# 1. Agrega un SemanticPointMarker como hijo del mapa
# 2. Configura point_type según el tipo de punto deseado
# 3. Team = -1 (neutral) para que cualquier equipo lo use
# 4. Posiciónalo donde quieras que los bots naveguen
#
# ── VISUALIZACIÓN ──
# En el editor, el marcador se muestra con un gizmo de Marker3D
# y su color/forma cambia según el tipo de punto.
# ──────────────────────────────────────────────────────────────────
extends Marker3D
class_name SemanticPointMarker


# ══════════════════════════════════════════════════════════════════
# EXPORTS
# ══════════════════════════════════════════════════════════════════

## Tipo de punto semántico
@export var point_type: int = SemanticPoint.PointType.ASSAULT:
	set(val):
		point_type = val
		update_configuration_warnings()

## Equipo al que pertenece (-1 = neutral)
@export var team: int = -1

## Radio de activación: el bot debe estar a esta distancia para usar el punto
@export var activation_radius: float = 8.0

## Nombre descriptivo (opcional, para debug)
@export var point_name: String = ""


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Auto-registrarse en el grupo para que NavigationSystem.load_semantic_points()
	# pueda encontrar este marcador al recorrer los nodos del grupo "semantic_points".
	add_to_group("semantic_points")


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN EN EDITOR
# ══════════════════════════════════════════════════════════════════

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	match point_type:
		SemanticPoint.PointType.ASSAULT:
			warnings.append("Punto de ASALTO — Solo bots tipo ASSAULT lo usarán")
		SemanticPoint.PointType.DEFENSE:
			warnings.append("Punto DEFENSIVO — Solo bots DEFENDER lo usarán")
		SemanticPoint.PointType.ALTERNATE:
			warnings.append("Punto ALTERNO — Solo bots FLANKER lo usarán")
		SemanticPoint.PointType.PATH:
			warnings.append("Punto de PATRULLA — Solo bots PATROLLER lo usarán")
		_:
			warnings.append("Tipo de punto no reconocido: %d" % point_type)
	
	if team != -1:
		warnings.append("Team=%d — Solo bots de este equipo lo usarán" % team)
	
	return warnings


# ══════════════════════════════════════════════════════════════════
# CONVERSIÓN A SemanticPoint
# ══════════════════════════════════════════════════════════════════

## Convierte este marcador a un objeto SemanticPoint para uso interno.
func to_semantic_point() -> SemanticPoint:
	return SemanticPoint.new(point_type, global_position, team, point_name)
