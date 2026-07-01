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


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO


func _init() -> void:
	state_type = StateType.ROAMING
	state_name = "roaming"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	movement_cmd.reset()
	if decision_system:
		decision_system.combat_command.cease_fire = true


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── Verificar transiciones prioritarias ──
	if _check_transitions():
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
				return true
	return false


# ══════════════════════════════════════════════════════════════════
# PICKUPS
# ══════════════════════════════════════════════════════════════════

func _check_pickups() -> bool:
	# Llamar directamente a NpcBase._check_for_pickups
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
		TacticalRole.MovementProfile.PATROL:
			return randf() < 0.4
		TacticalRole.MovementProfile.DEFENSIVE:
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

	if _nav_target == Vector3.ZERO or _objective_reached:
		_nav_target = core.global_position
		_objective_reached = false

	movement_cmd.set_navigate(_nav_target, _role_speed(4.5))


func _wander() -> void:
	var wander_radius: float = _get_wander_radius()

	if _nav_target == Vector3.ZERO or _is_nav_finished():
		# ── Intentar usar un punto semántico PATH o AMBUSH ──
		var use_semantic: bool = randf() < 0.6  # 60% prob de usar semantic points
		var sem_point: SemanticPoint = null
		
		if use_semantic and NavigationSystem._semantic_points_loaded:
			var team_filter: int = bot.equipo_id if bot else -1
			# Preferir PATH points, luego AMBUSH
			sem_point = NavigationSystem.get_nearest_point(
				SemanticPoint.PointType.PATH, bot.global_position, team_filter, wander_radius * 2)
			if sem_point == null:
				sem_point = NavigationSystem.get_nearest_point(
					SemanticPoint.PointType.AMBUSH, bot.global_position, team_filter, wander_radius * 2)
		
		if sem_point != null:
			# Ir al punto semántico
			_nav_target = sem_point.position
		else:
			# Fallback: posición aleatoria en el navmesh
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
		TacticalRole.MovementProfile.DEFENSIVE:
			return 10.0
		TacticalRole.MovementProfile.AGGRESSIVE:
			return 25.0
		TacticalRole.MovementProfile.FLANKING:
			return 22.0
		TacticalRole.MovementProfile.PATROL:
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
# ÓRDENES DE EQUIPO — FASE 6
# ══════════════════════════════════════════════════════════════════

## Ejecuta la orden actual del bot según TeamAI.
## Retorna true si la orden fue procesada (el bot tiene una orden activa).
func _execute_order() -> bool:
	if not is_instance_valid(TeamAI):
		return false
	if bot == null:
		return false

	var order_data: Dictionary = bot.get_current_order()
	var order_type: int = order_data.get("type", TeamAI.OrderType.FREELANCE)

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

		# ── Intentar usar punto DEFENSE semántico ──
		var defense_point: SemanticPoint = null
		if NavigationSystem._semantic_points_loaded:
			defense_point = NavigationSystem.get_nearest_point_of_type(
				SemanticPoint.PointType.DEFENSE, own_core.global_position,
				bot.equipo_id if bot else -1)

		# Si está cerca de la base, patrullar alrededor
		if dist_to_base < defense_range:
			var wander_radius: float = 8.0
			if _nav_target == Vector3.ZERO or _is_nav_finished():
				if defense_point != null:
					# Ir al punto de defensa
					_nav_target = defense_point.position
				else:
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
			if defense_point != null:
				_nav_target = defense_point.position
			else:
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
