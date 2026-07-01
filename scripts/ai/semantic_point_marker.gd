# scripts/ai/semantic_point_marker.gd
# ──────────────────────────────────────────────────────────────────
# SEMANTIC POINT MARKER — Nodo de marcado para puntos semánticos
#
# Adjuntar a nodos Marker3D en el mapa para definir puntos de
# navegación semántica. Cada marcador lleva un recurso SemanticPoint
# que describe su tipo y propiedades tácticas.
#
# El NavigationSystem escanea estos marcadores automáticamente
# desde NpcBase._ready() via NavigationSystem.load_semantic_points().
# ──────────────────────────────────────────────────────────────────
extends Marker3D
class_name SemanticPointMarker


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## El recurso SemanticPoint que define este punto táctico.
@export var semantic_point: SemanticPoint = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Auto-registrar como punto semántico en el NavigationSystem
	if semantic_point:
		# Actualizar posición desde el nodo
		semantic_point.position = global_position
		
		# Añadir a la lista global si ya está cargada
		if NavigationSystem.all_semantic_points != null:
			var already_exists: bool = false
			for existing in NavigationSystem.all_semantic_points:
				if existing == semantic_point:
					already_exists = true
					break
			if not already_exists:
				NavigationSystem.all_semantic_points.append(semantic_point)
		
		# Configurar gizmo de debug
		_update_gizmo()
	
	# Ocultar en runtime (solo son datos para los bots)
	visible = false


## Configura un color/cubo gizmo según el tipo de punto.
func _update_gizmo() -> void:
	if not semantic_point:
		return
	
	match semantic_point.point_type:
		SemanticPoint.PointType.PATH:
			gizmo_color = Color(1, 1, 1)  # Blanco
		SemanticPoint.PointType.AMBUSH:
			gizmo_color = Color(1, 0.5, 0)  # Naranja
		SemanticPoint.PointType.DEFENSE:
			gizmo_color = Color(0, 0.5, 1)  # Azul claro
		SemanticPoint.PointType.ALTERNATE:
			gizmo_color = Color(1, 0, 1)  # Magenta
		SemanticPoint.PointType.LIFT:
			gizmo_color = Color(0, 1, 0.5)  # Verde agua
		SemanticPoint.PointType.ITEM:
			gizmo_color = Color(1, 1, 0)  # Amarillo
		SemanticPoint.PointType.SNIPER:
			gizmo_color = Color(1, 0, 0)  # Rojo
