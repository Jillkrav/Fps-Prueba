# scripts/ai/navigation/semantic_point_marker.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT MARKER — Marcador de punto semántico para el editor
#
# Coloca este nodo (hereda de Marker3D) en el mapa para definir
# un punto semántico que los bots usarán según su rol táctico.
#
# ── USO ──
# 1. Agrega un SemanticPointMarker como hijo del mapa
#    point_type=5 (DUAL) = cubo verde oscuro usable por ASSAULT y FLANKER
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

## Ruta al nodo punto_final_salto (solo para puntos OBJECTIVE).
## El bot irá a esta posición después de tocar el cubo azul.
## Arrastra aquí el nodo punto_final_salto colocado en el mapa.
@export var punto_final_salto_path: NodePath = NodePath()


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
		SemanticPoint.PointType.OBJECTIVE:
			warnings.append("Punto OBJETIVO (inicio salto) — Enlazar un punto_final_salto en el inspector")
			if punto_final_salto_path.is_empty():
				warnings.append("⚠ Sin punto_final_salto enlazado — el bot ignorará el cubo celeste")
		SemanticPoint.PointType.DUAL:
			warnings.append("Punto DUAL — Bots ASSAULT y FLANKER lo usarán")
		SemanticPoint.PointType.TERCER:
			warnings.append("Punto TERCER CAMINO — Bots ASSAULT y FLANKER lo usarán")
		_:
			warnings.append("Tipo de punto no reconocido: %d" % point_type)
	
	if team != -1:
		warnings.append("Team=%d — Solo bots de este equipo lo usarán" % team)
	
	return warnings


# ══════════════════════════════════════════════════════════════════
# CONVERSIÓN A SemanticPoint
# ══════════════════════════════════════════════════════════════════

## Convierte este marcador a un objeto SemanticPoint para uso interno.
## Si es OBJECTIVE y tiene un punto_final_salto_path enlazado, la posición
## de ese nodo se usa como secondary_position (destino celeste obligatorio).
func to_semantic_point() -> SemanticPoint:
	var sp: SemanticPoint = SemanticPoint.new(point_type, global_position, team, point_name)
	
	# Para puntos OBJECTIVE: resolver el punto_final_salto enlazado
	if point_type == SemanticPoint.PointType.OBJECTIVE and not punto_final_salto_path.is_empty():
		var final_node: Node = get_node_or_null(punto_final_salto_path)
		if final_node != null:
			sp.secondary_position = final_node.global_position
	
	return sp
