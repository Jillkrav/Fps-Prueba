# scripts/ai/states/state_roaming.gd
# ──────────────────────────────────────────────────────────────────
# STATE_ROAMING — Deambular / Patrullar
#
# Estado por defecto cuando no hay enemigos, objetivos urgentes
# ni situación de peligro. El bot navega hacia el core enemigo
# (objetivo principal) o deambula si no hay core disponible.
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

## Cooldown corto cuando el bot no pudo llegar al punto (navegación fallida).
const FAILED_COOLDOWN: float = 10.0

## Tiempo máximo permitido navegando sin llegar al destino antes de
## considerar la navegación fallida y forzar re-ruta. Evita bots
## bloqueados silenciosamente cuando el agente no reporta finished.
const NAV_TIMEOUT: float = 12.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO

# Dict: "x,y,z" → timestamp de expiración de cooldown semántico
var _semantic_cooldowns: Dictionary = {}

# Tipo del punto semántico actual (-1 = no es cubo semántico)
var _last_semantic_type: int = -1

# Timestamp en que se fijó _nav_target (para timeout de navegación)
var _nav_target_set_time: float = 0.0

# Cache de resultado de backtrack: pos → {result, time}
# Evita recalcular map_get_path() cada tick para el mismo candidato.
var _backtrack_cache: Dictionary = {}
const BACKTRACK_CACHE_TTL: float = 3.0


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	_last_semantic_type = -1
	_nav_target_set_time = 0.0
	_backtrack_cache.clear()
	movement_cmd.reset()
	if decision_system:
		decision_system.combat_command.cease_fire = true


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── ¿Congelado? ──
	if bot.is_frozen:
		movement_cmd.set_hold()
		combat_cmd.cease_fire = true
		return

	# ── Timeout de navegación: si llevamos demasiado tiempo sin llegar, forzar re-ruta ──
	if _nav_target != Vector3.ZERO and _nav_target_set_time > 0.0:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - _nav_target_set_time
		if elapsed > NAV_TIMEOUT:
			_debug("Timeout de navegación (%.1fs) — forzando re-ruta" % elapsed)
			if _last_semantic_type >= 0:
				_add_semantic_cooldown(_nav_target, _last_semantic_type, true)
			_nav_target = Vector3.ZERO
			_nav_target_set_time = 0.0
			_last_semantic_type = -1

	# ── Verificar transiciones prioritarias ──
	if _check_transitions():
		return

	# ── 1. Ejecutar según orden de TeamAI ──
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

func _check_transitions() -> bool:
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
	if bot and is_instance_valid(bot):
		return bot._check_for_pickups(0.0)
	return false


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
	var dist_to_core: float = bot.global_position.distance_to(core.global_position)

	if dist_to_core < 4.0:
		_objective_reached = true

	if _nav_target == Vector3.ZERO or _objective_reached or _is_nav_finished():
		# Aplicar cooldown al punto anterior si corresponde
		if _nav_target != Vector3.ZERO and _last_semantic_type >= 0:
			var nav_failed: bool = _is_nav_finished() and bot.global_position.distance_to(_nav_target) > 5.0
			_add_semantic_cooldown(_nav_target, _last_semantic_type, nav_failed)

		# Elegir punto semántico según el rol
		var role: TacticalRole = _get_role()
		var target_point: SemanticPoint = null
		var point_label: String = ""

		if role != null:
			var point_type: int = SemanticPointRules.get_point_type_for_role(role.type)
			target_point = _get_semantic_point_nearby(point_type, role)
			if target_point != null:
				point_label = SemanticPointRules.get_point_type_name(point_type)

		if target_point != null:
			_nav_target = target_point.position
			_last_semantic_type = target_point.point_type
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			_debug("Punto %s: navegando a (%.1f, %.1f, %.1f)" % [
				point_label, target_point.position.x,
				target_point.position.y, target_point.position.z])
			_objective_reached = false
		else:
			# Sin punto semántico → ir directo al core
			_nav_target = core.global_position
			_last_semantic_type = -1
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			_objective_reached = false

	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))
	if not bot.is_frozen:
		movement_cmd.sprint = true


func _wander() -> void:
	var wander_radius: float = _get_wander_radius()

	if _nav_target == Vector3.ZERO or _is_nav_finished():
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

		_nav_target_set_time = Time.get_ticks_msec() / 1000.0

	movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
	movement_cmd.sprint = true


# ══════════════════════════════════════════════════════════════════
# PUNTOS SEMÁNTICOS
# ══════════════════════════════════════════════════════════════════

func _get_semantic_point_nearby(point_type: int, role: TacticalRole) -> SemanticPoint:
	if role == null:
		return null

	if not SemanticPointRules.is_role_allowed(point_type, role.type):
		return null

	if not NavigationSystem._semantic_points_loaded:
		NavigationSystem.load_semantic_points()

	var points: Array[SemanticPoint] = NavigationSystem.get_points_sorted(
		point_type,
		bot.global_position,
		bot.equipo_id,
		99999.0
	)
	if points.is_empty():
		return null

	var enemy_core: Node = bot._enemy_core if bot else null
	var own_core_dir: Node = _get_own_core()
	var bot_to_core: float
	if enemy_core and is_instance_valid(enemy_core):
		bot_to_core = bot.global_position.distance_to(enemy_core.global_position)
	else:
		bot_to_core = -1.0

	var now: float = Time.get_ticks_msec() / 1000.0
	var use_spread: bool = role.flanking_bias > 0.5

	var scored: Array[Dictionary] = []
	for p in points:
		var key: String = str(p.position)
		# Filtrar puntos en cooldown
		if _semantic_cooldowns.has(key) and _semantic_cooldowns[key] > now:
			continue
		# Filtrar puntos que están más lejos del core que el bot
		if bot_to_core >= 0.0:
			var p_to_core: float = p.position.distance_to(enemy_core.global_position)
			if p_to_core > bot_to_core + 5.0:
				continue
		# Filtrar backtrack usando cache (evitar map_get_path cada tick)
		if _requires_backtrack_cached(p.position, now):
			continue

		var score: float
		if use_spread:
			var dist_to_bot: float = bot.global_position.distance_to(p.position)
			var dist_from_ally: float = 0.0
			if own_core_dir and is_instance_valid(own_core_dir):
				dist_from_ally = p.position.distance_to(own_core_dir.global_position)
			score = dist_to_bot - role.spread_weight * dist_from_ally
		else:
			score = bot.global_position.distance_to(p.position)

		scored.append({"point": p, "score": score})

	if scored.is_empty():
		return null

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.score < b.score
	)

	if scored.size() >= 2 and randf() < 0.5:
		return scored[1].point

	return scored[0].point


# ══════════════════════════════════════════════════════════════════
# BACKTRACK — con cache para no llamar map_get_path cada tick
# ══════════════════════════════════════════════════════════════════

## Versión cacheada de _requires_backtrack.
## Reutiliza el resultado anterior si no ha expirado (TTL = 3s).
## Esto evita llamar NavigationServer3D.map_get_path() para cada
## candidato semántico en cada tick de IA con 100 bots activos.
func _requires_backtrack_cached(pos: Vector3, now: float) -> bool:
	var key: String = str(pos)
	if _backtrack_cache.has(key):
		var entry: Dictionary = _backtrack_cache[key]
		if now - entry.time < BACKTRACK_CACHE_TTL:
			return entry.result
	var result: bool = _requires_backtrack(pos)
	_backtrack_cache[key] = {"result": result, "time": now}
	return result


## Verifica si navegar a pos requiere retroceder respecto al core enemigo.
## Solo se llama via _requires_backtrack_cached para evitar overhead.
func _requires_backtrack(pos: Vector3) -> bool:
	var enemy_core: Node = bot._enemy_core if bot else null
	if not enemy_core or not is_instance_valid(enemy_core):
		return false

	var nav_map: RID
	if navigation and navigation.agent:
		nav_map = navigation.agent.get_navigation_map()
	elif bot and bot.navigation_agent:
		nav_map = bot.navigation_agent.get_navigation_map()

	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		return false

	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map, bot.global_position, pos, true
	)
	if path.size() < 2:
		return false

	var first_step_dir: Vector3 = (path[1] - path[0]).normalized()
	var to_core_dir: Vector3 = (enemy_core.global_position - bot.global_position).normalized()
	return first_step_dir.dot(to_core_dir) < -0.3


# ══════════════════════════════════════════════════════════════════
# COOLDOWN SEMÁNTICO
# ══════════════════════════════════════════════════════════════════

func _add_semantic_cooldown(pos: Vector3, point_type: int, failed: bool = false) -> void:
	var duration: float = FAILED_COOLDOWN if failed else SemanticPointRules.get_cooldown(point_type)
	var now: float = Time.get_ticks_msec() / 1000.0
	var key: String = str(pos)
	_semantic_cooldowns[key] = now + duration
	# Invalidar cache de backtrack para este punto al ponerlo en cooldown
	_backtrack_cache.erase(key)
	_debug("Cubo en cooldown por %.0fs (failed=%s): (%.1f, %.1f, %.1f)" % [
		duration, failed, pos.x, pos.y, pos.z])


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _get_role() -> TacticalRole:
	if bot:
		return bot._tactical_role
	return null

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


# ══════════════════════════════════════════════════════════════════
# ÓRDENES DE EQUIPO
# ══════════════════════════════════════════════════════════════════

func _execute_order() -> bool:
	if not is_instance_valid(TeamAI):
		return false
	if bot == null:
		return false

	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = order_data.get("type", TeamAI.OrderType.FREELANCE)

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
			_wander()
			return true
		TeamAI.OrderType.RETURN:
			_return_to_base()
			return true
		TeamAI.OrderType.FREELANCE:
			return false
		_:
			return false


func _attack_target() -> void:
	if _has_valid_core():
		_advance_to_core()
	else:
		var target_pos: Vector3 = bot.get_order_target_position()
		if target_pos != Vector3.ZERO:
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				_nav_target = target_pos
				_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
		else:
			_wander()


func _defend_position() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist_to_base: float = bot.global_position.distance_to(own_core.global_position)
		var defense_range: float = 12.0
		if dist_to_base < defense_range:
			var wander_radius: float = 8.0
			if _nav_target == Vector3.ZERO or _is_nav_finished():
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
				_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			movement_cmd.set_navigate(_nav_target, _role_speed(3.5))
		else:
			_nav_target = own_core.global_position
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			movement_cmd.set_navigate(_nav_target, _role_speed(5.0))
	else:
		_wander()


func _execute_hold() -> void:
	var order_data: Dictionary = bot.get_current_order()
	var hold_pos: Vector3 = order_data.get("target_position", bot.global_position)
	var dist_to_hold: float = bot.global_position.distance_to(hold_pos)
	if dist_to_hold > 2.0:
		if _nav_target == Vector3.ZERO:
			_nav_target = hold_pos
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
		movement_cmd.set_navigate(_nav_target, _role_speed(3.0))
	else:
		movement_cmd.set_hold()


func _return_to_base() -> void:
	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
		var dist: float = bot.global_position.distance_to(own_core.global_position)
		if dist > 4.0:
			_nav_target = own_core.global_position
			_nav_target_set_time = Time.get_ticks_msec() / 1000.0
			movement_cmd.set_navigate(_nav_target, _role_speed(5.5))
		else:
			_wander()
	else:
		_wander()
