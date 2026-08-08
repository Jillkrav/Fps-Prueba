# scripts/ai/states/state_roaming.gd
# ──────────────────────────────────────────────────────────────────
# STATE_ROAMING — Deambular / Patrullar
#
# Estado por defecto cuando no hay enemigos, objetivos urgentes
# ni situación de peligro. El bot navega hacia el core enemigo
# (objetivo principal) o deambula si no hay core disponible.
#
# Comportamiento migrado de BehaviorPatrol.
#
# ── TRANSICIONES DE SALIDA ──
# → HUNTING:      Si hay memoria de posición enemiga
# → COMBAT:       Si hay enemigos visibles
# → RETREATING:   Si la salud es baja y hay core aliado cerca
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateRoaming


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

const PRIORITY_PATROL: float = 10.0
const ROUTE_RECHECK_INTERVAL: float = 1.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO

## Cobertura actualmente reservada por este estado. Se libera al cambiar
## de objetivo/estado para evitar que un punto quede bloqueado indefinidamente.
var _reserved_cover: Node = null

## Seguimiento de los caminos authored del mapa actual.
var _route_navigator: BotAuthoredRouteNavigator = BotAuthoredRouteNavigator.new()
var _next_route_search_time: float = 0.0

# (FloorRouter removido — LinkJump3D eliminado del proyecto)


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	_release_reserved_cover()
	_route_navigator.clear()
	_next_route_search_time = 0.0
	movement_cmd.reset()
	if decision_system:
		decision_system.combat_command.cease_fire = true

	var stuck: StuckHandler = movement.stuck_handler if movement else null
	if stuck != null and not stuck.stuck_resolved.is_connected(_on_stuck_resolved):
		stuck.stuck_resolved.connect(_on_stuck_resolved)


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── ¿Congelado? (sistema unificado BotBase) ──
	if bot.is_frozen:
		# Quieto: no moverse ni disparar
		movement_cmd.set_hold()
		combat_cmd.cease_fire = true
		return

	# ── Verificar transiciones prioritarias ──
	if _check_transitions():
		return

	# El francotirador ocupa siempre una cobertura de un solo sentido y se
	# mantiene allí hasta que aparezca un enemigo visible. Si el mapa no tiene
	# una, conserva el comportamiento normal como fallback seguro.
	if _maintain_sniper_camp():
		return

	# ── 1. Ejecutar según orden de TeamAI (FASE 6) ──
	if _execute_order():
		return

	# ── 2. Radio defensivo: volver a la base si nos alejamos ──
	if _check_defense_radius():
		return

	# ── 3. Pickups cercanos ──
	if _check_pickups():
		return

	# ── 4. Decidir: ir al core enemigo o deambular ──
	if _has_valid_core() and not _should_patrol_instead():
		_advance_to_core()
	else:
		_wander()


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

## Verifica si debemos salir de Roaming por eventos externos.
## Retorna true si transicionó a otro estado.
func _check_transitions() -> bool:
	if bot != null and bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return true
	# ── ¿Enemigo visible? → COMBAT ──
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return true

	# ── ¿Memoria de enemigo? → HUNTING ──
	if memory and memory.has_enemy_memory() and not perception.has_visible_enemies():
		change_state(BotState.StateType.HUNTING)
		return true

	# ── ¿Salud baja y cerca de base? → RETREATING ──
	if health_pct() < 0.25 and _dist_to_own_core() < 15.0:
		change_state(BotState.StateType.RETREATING)
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

func _check_defense_radius() -> bool:
	var role: TacticalRole = _get_role()
	if role and role.base_defense_radius > 0.0:
		var own_core: Node = _get_own_core()
		if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
			var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
			if dist_to_base > role.base_defense_radius:
				_nav_target = own_core.global_position
				movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
				movement_cmd.sprint = true
				return true
	return false


# ══════════════════════════════════════════════════════════════════
# PICKUPS
# ══════════════════════════════════════════════════════════════════

func _check_pickups() -> bool:
	# Las necesidades de nivel 1 y 2 son objetivos oportunistas: no bloquean
	# combate ni rutas, pero se atienden durante patrulla.
	if bot == null or not is_instance_valid(bot) or bot.tactical_sys == null:
		return false
	if not bot.tactical_sys.has_noncritical_resource_need():
		return false
	var pickup: Node = bot.tactical_sys.get_priority_pickup()
	if pickup == null or not is_instance_valid(pickup) or not pickup.is_inside_tree():
		return false
	_nav_target = pickup.global_position
	movement_cmd.set_navigate(_nav_target, _role_speed(4.8))
	movement_cmd.sprint = true
	return true


# ══════════════════════════════════════════════════════════════════
# DECISIÓN: AVANZAR AL CORE VS DEAMBULAR
# ══════════════════════════════════════════════════════════════════

func _has_valid_core() -> bool:
	if bot == null:
		return false
	var core: Node = bot._enemy_core
	return core != null and is_instance_valid(core) and core.is_inside_tree() \
		and not core.get("is_destroyed")


func _should_patrol_instead() -> bool:
	var role: TacticalRole = _get_role()
	if role == null:
		return randf() < 0.3
	match role.movement_profile:
		Roles.MovementProfile.PATROL:
			return randf() < 0.4
		Roles.MovementProfile.DEFENSIVE:
			return randf() < 0.3
		_:
			return randf() < 0.2


func _advance_to_core() -> void:
	if bot == null or bot._enemy_core == null:
		_wander()
		return

	var core: Node = bot._enemy_core
	if bot.global_position.distance_to(core.global_position) < 4.0:
		_objective_reached = true

	if _follow_authored_route():
		return

	# Con salud baja, buscar cobertura antes que seguir avanzando.
	if _get_health_pct() < 0.35 and _seek_cover():
		return
	_release_reserved_cover()

	# Fallback seguro para mapas que todavía no tienen caminos configurados.
	if _nav_target == Vector3.ZERO or _objective_reached or _is_nav_finished():
		# El offset de aproximación puede caer fuera del NavMesh (sobre una
		# pared, un hueco o fuera de límites). Si dejáramos ese punto sin
		# corregir, el bot elegiría un destino inalcanzable y se quedaría
		# parado reeligiendo el mismo cada tick ("pegado" al avanzar).
		var raw_target: Vector3 = core.global_position + _get_core_approach_offset()
		_nav_target = _snap_to_navmesh(raw_target, core.global_position)
		_objective_reached = false

	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	if not bot.is_frozen:
		movement_cmd.sprint = true


func _follow_authored_route() -> bool:
	if bot == null:
		return false

	var now: float = Time.get_ticks_msec() / 1000.0
	if _route_navigator.has_active_route():
		_route_navigator.advance_if_reached(bot.global_position)
		if _route_navigator.has_active_route():
			_nav_target = _route_navigator.get_current_target()
			movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
			movement_cmd.sprint = not bot.is_frozen
			return true

	if now < _next_route_search_time:
		return false
	_next_route_search_time = now + ROUTE_RECHECK_INTERVAL

	var map_root: Node = _get_map_root()
	var route_role: int = _get_route_role_for_bot()
	if map_root == null or route_role < 0:
		return false

	var excluded_route_ids: Dictionary = _route_navigator.get_completed_route_ids()
	var route: CaminoBot = _route_navigator.find_best_route(map_root, route_role, bot.global_position, excluded_route_ids)
	if route == null or not _route_navigator.start_route(route, bot.global_position):
		return false

	_nav_target = _route_navigator.get_current_target()
	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	movement_cmd.sprint = not bot.is_frozen
	_debug("Camino %s seleccionado" % _get_route_label(route))
	return true


func _get_route_role_for_bot() -> int:
	var role: TacticalRole = _get_role()
	if role == null:
		return -1
	match role.type:
		Roles.Type.ASALTO:
			return CaminoBot.Role.ASSAULT
		Roles.Type.FLANQUEADOR:
			return CaminoBot.Role.FLANKER
		Roles.Type.DEFENSOR:
			return CaminoBot.Role.DEFENDER
		Roles.Type.VERSATIL:
			return CaminoBot.Role.FLANKER if role.flanking_bias > 0.5 else CaminoBot.Role.ASSAULT
		Roles.Type.PATRULLADOR, Roles.Type.FRANCOTIRADOR, Roles.Type.APOYO:
			return CaminoBot.Role.DEFENDER
		_:
			return -1


func _get_map_root() -> Node:
	if bot == null or not bot.is_inside_tree():
		return null
	var current_node: Node = bot
	var scene_root: Node = bot.get_tree().current_scene
	while current_node.get_parent() != null and current_node != scene_root:
		current_node = current_node.get_parent()
	return scene_root if scene_root != null else current_node


## Offset de aproximación al core según el rol y con dispersión real.
## FLANQUEADOR intenta atacar por los lados; DEFENSOR/APOYO se mantienen
## a distancia; VERSÁTIL mezcla. El offset es determinista por bot (para
## que sea estable entre ticks) pero varía ampliamente según el rol.
func _get_core_approach_offset() -> Vector3:
	var bot_seed: int = bot.get_instance_id() if bot else 0
	var role: TacticalRole = _get_role()

	# Radio base de dispersión (más amplio que el antiguo ±4).
	var spread_base: float = 8.0
	var lateral_bias: float = 0.0
	var distance_bias: float = 0.0

	if role:
		match role.movement_profile:
			Roles.MovementProfile.FLANKING:
				# Flanquea por los costados: gran desplazamiento lateral.
				lateral_bias = 6.0
				spread_base = 10.0
			Roles.MovementProfile.DEFENSIVE:
				# Se mantiene a distancia: menos lateral, más lejos.
				distance_bias = 6.0
				spread_base = 7.0
			Roles.MovementProfile.PATROL:
				distance_bias = 3.0
				spread_base = 8.0
			_:
				# AGGRESSIVE: adelante con algo de lateral.
				lateral_bias = 3.0
				spread_base = 8.0

	# Variación determinista por bot (evita que todos se apilen).
	var x_variation: float = float((bot_seed * 17) % int(spread_base * 2.0) - spread_base)
	var z_variation: float = float((bot_seed * 31) % int(spread_base * 2.0) - spread_base)

	# Lateral según sesgo de flanqueo del rol (si existe).
	if role and role.flanking_bias > 0.0:
		lateral_bias += role.flanking_bias * 4.0

	# Elegir lado: derecha o izquierda según el seed del bot.
	var side: float = 1.0 if (bot_seed % 2 == 0) else -1.0

	return Vector3(
		x_variation + side * lateral_bias,
		0.0,
		z_variation - distance_bias
	)


## Busca la cobertura más cercana disponible y navega hacia ella.
## Retorna true si encontró y se dirigió a una cobertura.
## El francotirador convierte los one_way_low_wall en puestos de tiro fijos.
## No persigue el core ni genera wander mientras se desplaza o permanece en
## su punto reservado. Al aparecer un enemigo, _check_transitions() conserva
## prioridad y cambia a COMBAT normalmente.
func _maintain_sniper_camp() -> bool:
	var role: TacticalRole = _get_role()
	if role == null or role.type != Roles.Type.FRANCOTIRADOR:
		return false
	if _reserved_cover == null or not is_instance_valid(_reserved_cover) or not _reserved_cover.is_inside_tree():
		if bot == null or bot.tactical_sys == null:
			return false
		var camp: Node = bot.tactical_sys.get_nearest_available_cover()
		if camp == null:
			return false
		_release_reserved_cover()
		if camp.has_method("occupy"):
			camp.occupy(bot)
		_reserved_cover = camp
		_nav_target = camp.get_cover_position()
	
	var camp_target: Vector3 = _reserved_cover.get_cover_position()
	if bot.global_position.distance_to(camp_target) > 1.5:
		movement_cmd.set_navigate(camp_target, _role_speed(3.2))
		return true
	movement_cmd.set_hold()
	return true


func _seek_cover() -> bool:
	if bot == null or not bot.is_inside_tree() or bot.tactical_sys == null:
		return false
	# Centralizar la selección aquí evita que el fallback de poca salud salte
	# las reglas por rol (asalto/flanqueo) o las preferencias de props.
	var best: Node = bot.tactical_sys.get_nearest_available_cover()
	if best == null:
		return false

	if best != _reserved_cover:
		_release_reserved_cover()
		if best.has_method("occupy"):
			best.occupy(bot)
		_reserved_cover = best
	_nav_target = best.get_cover_position()
	movement_cmd.set_navigate(_nav_target, _role_speed(4.0))
	movement_cmd.sprint = true
	_debug("Cobertura %s seleccionada" % best.name)
	return true


func exit(_next_state: BotState) -> void:
	_release_reserved_cover()


func _release_reserved_cover() -> void:
	if _reserved_cover != null and is_instance_valid(_reserved_cover) and "release" in _reserved_cover:
		_reserved_cover.release(bot)
	_reserved_cover = null


func _get_route_label(route: CaminoBot) -> String:
	if route.route_id != StringName():
		return str(route.route_id)
	return route.name


func _wander() -> void:
	var wander_radius: float = _get_wander_radius()

	if _nav_target == Vector3.ZERO or _is_nav_finished():
		# ── Patrulla con propósito: recorrer coberturas/zonas del mapa ──
		if _wander_to_cover_waypoint():
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
			movement_cmd.sprint = true
			return

		# ── Posición aleatoria en el navmesh ──
		var nav_map_rid: RID
		if navigation and navigation.agent:
			nav_map_rid = navigation.agent.get_navigation_map()
		elif bot and bot.navigation_agent:
			nav_map_rid = bot.navigation_agent.get_navigation_map()
		else:
			nav_map_rid = RID()

		var raw_target: Vector3 = bot.global_position + Vector3(
			randf_range(-wander_radius, wander_radius), 0,
			randf_range(-wander_radius, wander_radius))

		if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
			_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		else:
			_nav_target = raw_target

	movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
	movement_cmd.sprint = true  # Wander también en sprint


## Patrulla con propósito: recorre puntos relevantes del mapa (coberturas,
## zonas) en vez de deambular sin rumbo. Retorna true si encontró un punto.
func _wander_to_cover_waypoint() -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var role: TacticalRole = _get_role()
	# Asalto y flanqueo no convierten props de cobertura en waypoints de ruta:
	# solo los emplean desde COMBAT/COVER_RELOAD cuando realmente lo necesitan.
	if role != null and role.type in [Roles.Type.ASALTO, Roles.Type.FLANQUEADOR]:
		return false
	var points: Array[Node] = []

	# Reunir coberturas y zonas activas como puntos de patrulla.
	# Duck-typing: CoverPoint/ZonePoint son props opcionales; usamos grupos.
	# Los puntos de troneras/muros bajos reciben duplicación ponderada para que
	# los bots los prefieran cuando no hay un objetivo más urgente.
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	for cover: Node in covers:
		if cover != null and is_instance_valid(cover):
			points.append(cover)
			var cover_parent: Node = cover.get_parent()
			# Patrulladores y defensores prefieren puntos publicados por props
			# reutilizables, pero la prioridad sigue siendo opcional: las zonas y
			# otros CoverPoint continúan siendo destinos válidos.
			if role != null and role.type in [Roles.Type.PATRULLADOR, Roles.Type.DEFENSOR] \
			and cover_parent != null and cover_parent.is_in_group(&"cover_props"):
				points.append(cover)
				points.append(cover)
			if cover.is_in_group(&"peek_cover_points"):
				points.append(cover)
				points.append(cover)
	var zones: Array[Node] = bot.get_tree().get_nodes_in_group(&"zone_points")
	for zone: Node in zones:
		if zone != null and is_instance_valid(zone) and zone.get("is_active"):
			points.append(zone)

	if points.is_empty():
		return false

	# Elegir un punto distinto al actual (para no quedarse fijo).
	var target: Node = points[randi() % points.size()]
	if target.is_inside_tree():
		_nav_target = target.global_position
		return true
	return false


# (Freeze unificado en BotBase — FASE 4. El bot reanuda naturalmente
#  al descongelarse porque execute() corre cada tick de decisión.)
















# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _get_role() -> TacticalRole:
	if bot:
		return bot._tactical_role
	return null


## Porcentaje de salud del bot (0.0 a 1.0).
func _get_health_pct() -> float:
	if bot and bot.max_health > 0.0:
		return float(bot.current_health) / float(bot.max_health)
	return 1.0

func _get_own_core() -> Node:
	if bot:
		return bot._get_own_core()
	return null

func _dist_to_own_core() -> float:
	if bot:
		return bot._get_dist_to_own_core()
	return 0.0

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed

func _get_wander_radius() -> float:
	var role: TacticalRole = _get_role()
	if not role:
		return 20.0
	match role.movement_profile:
		Roles.MovementProfile.DEFENSIVE:
			return 10.0
		Roles.MovementProfile.AGGRESSIVE:
			return 25.0
		Roles.MovementProfile.FLANKING:
			return 22.0
		Roles.MovementProfile.PATROL:
			return 18.0
		_:
			return 20.0

func _is_nav_finished() -> bool:
	if navigation:
		return navigation.is_navigation_finished()
	if bot and bot.navigation_agent:
		return bot.navigation_agent.is_navigation_finished()
	return true


## Devuelve el punto más cercano navegable a `raw_target` en el NavMesh.
## Si el NavMesh no está disponible o el punto corregido queda muy lejos del
## original (p. ej. el objetivo estaba fuera del mapa), cae a `fallback`.
## Evita que los bots elijan destinos inalcanzables y se queden parados.
func _snap_to_navmesh(raw_target: Vector3, fallback: Vector3) -> Vector3:
	var nav_map_rid: RID
	if navigation and navigation.agent:
		nav_map_rid = navigation.agent.get_navigation_map()
	elif bot and bot.navigation_agent:
		nav_map_rid = bot.navigation_agent.get_navigation_map()
	if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
		var punto_corregido: Vector3 = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		# Si el punto corregido no está razonablemente cerca del objetivo
		# original, el destino buscado no era navegable: usar el fallback.
		if punto_corregido.distance_to(raw_target) <= 4.0:
			return punto_corregido
	return fallback


## Reanuda el camino desde el punto más cercano después de una recuperación.
func _on_stuck_resolved() -> void:
	if bot == null:
		return
	if _route_navigator.reset_after_stuck(bot.global_position):
		_nav_target = _route_navigator.get_current_target()
	else:
		_nav_target = Vector3.ZERO
	_next_route_search_time = 0.0


# ══════════════════════════════════════════════════════════════════
# ÓRDENES DE EQUIPO — FASE 6
# ══════════════════════════════════════════════════════════════════

## Ejecuta la orden actual del bot según TeamAI.
## Retorna true si la orden fue procesada (el bot tiene una orden activa).
##
## ▶ ASALTO y FLANQUEADOR NUNCA defienden: si reciben orden DEFEND o HOLD,
##   las ignoran y se comportan como FREELANCE (avanzan al frente).
func _execute_order() -> bool:
	if not is_instance_valid(TeamAI):
		return false
	if bot == null:
		return false

	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = order_data.get("type", TeamAI.OrderType.FREELANCE)

	# ── Solo DEFENSOR se queda quieto defendiendo.
	#    Los demas roles ignoran ordenes defensivas.
	var role: TacticalRole = _get_role()
	if role != null and role.type != Roles.Type.DEFENSOR:
		if order_type == TeamAI.OrderType.DEFEND or order_type == TeamAI.OrderType.HOLD:
			order_type = TeamAI.OrderType.FREELANCE

	match order_type:
		TeamAI.OrderType.ATTACK:
			_attack_target()
			return true

		TeamAI.OrderType.DEFEND:
			_defend_position()
			return true

		TeamAI.OrderType.HOLD:
			_execute_hold()
			return true

		TeamAI.OrderType.PATROL:
			if _follow_authored_route():
				return true
			_wander()
			return true

		TeamAI.OrderType.RETURN:
			_return_to_base()
			return true

		TeamAI.OrderType.FREELANCE:
			# FREELANCE: el bot decide por sí mismo
			# Continúa con el comportamiento por defecto (wander/core)
			return false

		_:
			return false


## Ejecuta orden ATTACK: navegar hacia el core enemigo.
func _attack_target() -> void:
	if _has_valid_core():
		_advance_to_core()
	else:
		# Si no hay core enemigo, ir hacia la posición de la orden
		var target_pos: Vector3 = bot.get_order_target_position()
		if target_pos != Vector3.ZERO:
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				_nav_target = target_pos
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
		else:
			_wander()


## Ejecuta orden DEFEND: patrullar cerca del core propio.
func _defend_position() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
		var defense_range: float = 12.0

		# Si está cerca de la base, priorizar un camino defensivo si existe.
		if dist_to_base < defense_range:
			if _follow_authored_route():
				return
			# Defensa prefiere cubrir el perímetro, sin volverlo obligatorio:
			# las rutas y la patrulla aleatoria siguen siendo alternativas válidas.
			if (_nav_target == Vector3.ZERO or _is_nav_finished()) and randf() < 0.65 and _seek_cover():
				return
			var wander_radius: float = 8.0
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				# Wander aleatorio dentro del radio defensivo
				var raw_target: Vector3 = own_core.global_position + Vector3(
					randf_range(-wander_radius, wander_radius), 0,
					randf_range(-wander_radius, wander_radius))
				var nav_map_rid: RID
				if navigation and navigation.agent:
					nav_map_rid = navigation.agent.get_navigation_map()
				elif bot and bot.navigation_agent:
					nav_map_rid = bot.navigation_agent.get_navigation_map()
				else:
					nav_map_rid = RID()
				if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
					_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
				else:
					_nav_target = raw_target
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
		else:
			# Está lejos de la base, regresar
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
	else:
		_wander()


## Ejecuta orden HOLD: mantener la posición actual.
func _execute_hold() -> void:
	var order_data: Dictionary = bot.get_current_order()
	var hold_pos: Vector3 = order_data.get("target_position", bot.global_position)

	var dist_to_hold: float = bot.global_position.distance_to(hold_pos)
	if dist_to_hold > 2.0:
		# Volver a la posición de hold
		if _nav_target == Vector3.ZERO:
			_nav_target = hold_pos
		movement_cmd.set_navigate(_nav_target, _role_speed(3.0))
	else:
		# Ya en posición, quieto
		movement_cmd.set_hold()


## Ejecuta orden RETURN: regresar a la base.
func _return_to_base() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist: float = bot.global_position.distance_to(own_core.global_position)
		if dist > 4.0:
			_nav_target = own_core.global_position
			movement_cmd.set_navigate(_nav_target, _role_speed(5.5))
		else:
			# Ya en base, quedarse quieto o patrullar
			_wander()
	else:
		_wander()
