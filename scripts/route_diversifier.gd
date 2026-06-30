# scripts/route_diversifier.gd
# RouteDiversifier - Sistema de diversificación de rutas para NPCs.
#
# Evita que todos los bots usen la misma ruta hacia un destino generando
# waypoints de aproximación alternativos. Cada bot selecciona una ruta
# basada en su identidad (npc_id, rol, combat_style, skill).
#
# Las rutas son DETERMINISTAS: el mismo bot elige siempre la misma ruta
# hacia el mismo destino, produciendo comportamiento consistente.
#
# ── TIPOS DE RUTA ──────────────────────
# DIRECT (0):    Camino más corto (sin waypoint)
# LEFT (1):      Aproximación por la izquierda del objetivo
# RIGHT (2):     Aproximación por la derecha del objetivo
# WIDE_LEFT (3): Flanqueo amplio por la izquierda
# WIDE_RIGHT (4): Flanqueo amplio por la derecha
#
# ── ARQUITECTURA EXTENSIBLE ────────────
# Preparado para sistemas de flanqueo más avanzados:
#   - RouteFlanker (futuro): flanqueo coordinado por equipo
#   - RoutePlanner (futuro): planificación multicamino con NavMesh
#   - RouteOverride (futuro): rutas dinámicas basadas en eventos
#
# Uso:
#   var route_type = RouteDiversifier.get_route_type_for_bot(self)
#   var wp = RouteDiversifier.get_approach_waypoint(
#       global_position, target_pos, route_type, nav_map_rid
#   )

extends RefCounted
class_name RouteDiversifier


# ══════════════════════════════════════════
# TIPOS DE RUTA
# ══════════════════════════════════════════

enum RouteType {
	DIRECT = 0,       # Ruta directa: camino más corto
	LEFT = 1,         # Aproximación lateral izquierda
	RIGHT = 2,        # Aproximación lateral derecha
	WIDE_LEFT = 3,    # Flanqueo amplio izquierda
	WIDE_RIGHT = 4,   # Flanqueo amplio derecha
}

## Número total de tipos de ruta disponibles.
const ROUTE_COUNT: int = 5


# ══════════════════════════════════════════
# CONSTANTES DE CONFIGURACIÓN
# ══════════════════════════════════════════

## Distancia lateral del waypoint para rutas normales (LEFT/RIGHT).
const APPROACH_LATERAL_NORMAL: float = 8.0
## Distancia lateral del waypoint para rutas amplias (WIDE_*).
const APPROACH_LATERAL_WIDE: float = 14.0
## Retroceso adicional para rutas amplias (aleja el waypoint del target).
const WIDE_BACKOFF: float = 5.0
## Distancia máxima permitida entre waypoint y target (para validar).
const MAX_WAYPOINT_RADIUS: float = 30.0


# ══════════════════════════════════════════
# INTERFAZ PÚBLICA
# ══════════════════════════════════════════

## Devuelve el RouteType que este bot usará para todas sus rutas.
##
## Determinístico: mismo bot → mismo RouteType.
## Factores:
##   - npc_id:       base (0-4) mediante módulo
##   - rol:          desplaza hacia flanqueo (EXPLORADOR) o directo (SOLDADO)
##   - combat_style: agresivo flanquea más, cauteloso va directo
##   - skill:        bajo = simplifica, alto = usa cualquier ruta
static func get_route_type_for_bot(bot: Node) -> int:
	# get() returns null for non-existent properties — usar fallback
	var npc_id_val = bot.get("_npc_id")
	var npc_id: int = npc_id_val if npc_id_val != null else 0
	var rol_val = bot.get("rol")
	var rol: int = rol_val if rol_val != null else int(Enums.Rol.SOLDADO)
	var cs_val = bot.get("combat_style")
	var combat_style: float = cs_val if cs_val != null else 0.5
	var skill_val = bot.get("skill")
	var skill: float = skill_val if skill_val != null else 3.0

	# ── Base: npc_id determina la ruta primaria ──
	# Distribución uniforme entre los 5 tipos.
	var base_route: int = npc_id % ROUTE_COUNT

	# ── Modulación por rol ──
	# Cada rol tiene tendencias naturales de aproximación.
	var rol_shift: int = 0
	match rol:
		Enums.Rol.EXPLORADOR:
			rol_shift = 2   # Flanqueo amplio (WIDE_*)
		Enums.Rol.FRANCOTIRADOR:
			rol_shift = 1   # Rutas medias (LEFT/RIGHT)
		Enums.Rol.APOYO:
			rol_shift = 0   # Neutro
		Enums.Rol.COMANDANTE:
			rol_shift = -1  # Tiende a DIRECT (va al frente)
		_: # SOLDADO
			rol_shift = 1   # Ligeramente flanqueo

	# ── Modulación por combat_style ──
	# 0.0 = cauteloso (prefiere DIRECT), 1.0 = agresivo (prefiere flanqueo)
	var style_shift: int = 0
	if combat_style > 0.7:
		style_shift = 2     # Prefiere WIDE_LEFT/WIDE_RIGHT
	elif combat_style > 0.5:
		style_shift = 1     # Prefiere LEFT/RIGHT
	elif combat_style < 0.3:
		style_shift = -2    # Prefiere DIRECT

	# ── Modulación por skill ──
	# Bots novatos usan rutas simples para no atascarse.
	# Bots expertos pueden ejecutar cualquier ruta.
	var skill_shift: int = 0
	if skill < 3.0:
		skill_shift = -2    # Simplifica: DIRECT o LEFT/RIGHT
	elif skill > 5.0:
		skill_shift = 1     # Puede ejecutar cualquier ruta

	# ── Combinar ──
	var final_route: int = base_route + rol_shift + style_shift + skill_shift
	# Normalizar a [0, ROUTE_COUNT-1] con wrapping
	final_route = final_route % ROUTE_COUNT
	if final_route < 0:
		final_route += ROUTE_COUNT

	return final_route


## Devuelve true si este tipo de ruta usa un waypoint intermedio
## (todo excepto DIRECT).
static func uses_waypoint(route_type: int) -> bool:
	return route_type != RouteType.DIRECT


## Devuelve el nombre descriptivo de un RouteType (para debug).
static func get_route_name(route_type: int) -> String:
	match route_type:
		RouteType.DIRECT:
			return "DIRECT"
		RouteType.LEFT:
			return "LEFT"
		RouteType.RIGHT:
			return "RIGHT"
		RouteType.WIDE_LEFT:
			return "WIDE_LEFT"
		RouteType.WIDE_RIGHT:
			return "WIDE_RIGHT"
		_:
			return "UNKNOWN"


# ══════════════════════════════════════════
# GENERACIÓN DE WAYPOINTS
# ══════════════════════════════════════════

## Genera un waypoint de aproximación intermedio para el bot.
##
## El waypoint se posiciona en un punto desplazado lateralmente respecto
## a la línea bot→target. Esto fuerza al NavigationAgent a calcular una
## ruta diferente, haciendo que el bot se aproxime desde otro ángulo.
##
## Parámetros:
##   bot_pos:     Posición actual del bot (Vector3)
##   target_pos:  Posición del destino final (Vector3)
##   route_type:  RouteType del bot (0-4)
##   nav_map_rid: RID del NavigationServer (para snap al NavMesh)
##
## Retorna:
##   Vector3 del waypoint (snappeado al NavMesh).
##   Si la ruta es DIRECT o no se puede generar, retorna target_pos.
static func get_approach_waypoint(
	bot_pos: Vector3,
	target_pos: Vector3,
	route_type: int,
	nav_map_rid: RID
) -> Vector3:
	# DIRECT: sin waypoint, ir directo al target
	if route_type == RouteType.DIRECT:
		return target_pos

	# ── Calcular dirección horizontal bot → target ──
	var to_target: Vector3 = target_pos - bot_pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		# Ya estamos en el target o muy cerca
		return target_pos
	to_target = to_target.normalized()

	# ── Direcciones perpendiculares (laterales) ──
	var perp_left: Vector3 = to_target.cross(Vector3.UP).normalized()
	var perp_right: Vector3 = -perp_left

	# ── Calcular offset del waypoint según tipo de ruta ──
	var approach_lateral: float
	var backoff: float

	match route_type:
		RouteType.LEFT:
			approach_lateral = APPROACH_LATERAL_NORMAL
			backoff = 2.0
		RouteType.RIGHT:
			approach_lateral = -APPROACH_LATERAL_NORMAL
			backoff = 2.0
		RouteType.WIDE_LEFT:
			approach_lateral = APPROACH_LATERAL_WIDE
			backoff = WIDE_BACKOFF
		RouteType.WIDE_RIGHT:
			approach_lateral = -APPROACH_LATERAL_WIDE
			backoff = WIDE_BACKOFF
		_:
			return target_pos

	# Offset = lateral + ligero retroceso
	var waypoint_offset: Vector3
	if approach_lateral >= 0:
		waypoint_offset = perp_left * approach_lateral - to_target * backoff
	else:
		waypoint_offset = perp_right * (-approach_lateral) - to_target * backoff

	var raw_waypoint: Vector3 = target_pos + waypoint_offset
	raw_waypoint.y = target_pos.y  # Mantener misma altura

	# ── Snap al NavMesh y validar ──
	if NavigationServer3D.map_is_active(nav_map_rid):
		var snapped_pos: Vector3 = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_waypoint)
		var snap_dist: float = snapped_pos.distance_to(raw_waypoint)

		# Validar que el snap no esté demasiado lejos
		# (indicaría que el waypoint cayó fuera del NavMesh)
		if snap_dist < MAX_WAYPOINT_RADIUS and snapped_pos.distance_to(target_pos) < MAX_WAYPOINT_RADIUS:
			return snapped_pos

	# Fallback: si no hay NavMesh activo o el waypoint es inválido,
	# ir directo al target.
	return target_pos


## Determina si el bot debe actualizar su ruta actual basándose en
## el movimiento del objetivo. Útil para ATTACKING donde el enemigo
## se mueve: si el enemigo se desplazó significativamente, recalcula.
##
## threshold: distancia mínima para considerar que el objetivo se movió.
static func should_recalculate_route(
	current_target: Vector3,
	new_target_pos: Vector3,
	threshold: float = 3.0
) -> bool:
	return current_target.distance_to(new_target_pos) > threshold
