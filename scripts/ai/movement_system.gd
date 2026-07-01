# scripts/ai/movement_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE MOVIMIENTO MODULAR — FASE 2 REFACTORIZACIÓN
#
# ÚNICO escritor de velocity en todo el NPC.
# Lee movement_command (de DecisionSystem / BotBrain) y lo traduce
# a velocity + navegación.
#
# ── PROPIETARIO DE (solo él escribe) ──
#   bot.velocity (todo: x, y, z)
#   navigation tracking (nav_target, route_*)
#   stuck_state
#
# ── LECTURA DE ──
#   movement_command (DecisionContext / MovementCommand)
#   NavigationAgent3D (Godot nativo)
#   NavigationSystem (stuck detection, avoidance)
#
# ── NUNCA ESCRIBE ──
#   target_entity, combat_command, weapon_state
# ──────────────────────────────────────────────────────────────────
extends Node
class_name MovementSystem


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando el bot llega a su destino.
signal destination_reached(position: Vector3)

## Se emite cuando se detecta atasco.
signal stuck_detected(phase: int, cause: String)

## Se emite cuando el atasco se resuelve.
signal stuck_resolved()

## Se emite cuando el camino está bloqueado por un obstáculo.
signal path_blocked(remaining_distance: float)


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

# Gravedad (inicializada en _ready para evitar parse error con const)
var _gravity: float = 9.8

# Stuck detection thresholds
const STUCK_PROGRESS_THRESHOLD: Dictionary = {
	"idle":   8.0,
	"patrol": 2.5,
	"combat": 2.5,
	"hunt":   2.0,
}

const STUCK_BLOCKED_TRIGGER_TIME: float = 1.5
const RECOVERY_PHASE1_DURATION: float = 0.5
const RECOVERY_PHASE2_DURATION: float = 0.3
const ROUTE_WAYPOINT_REACHED_DIST: float = 5.0

# RVO avoidance (nativo de NavigationServer3D)
var _rvo_safe_velocity: Vector3 = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Referencia al bot dueño
var bot: NpcBase = null

## Comando de movimiento actual (escrito por DecisionSystem/BotBrain)
var command: MovementCommand = MovementCommand.new()

## Referencia al NavigationAgent3D
var agent: NavigationAgent3D = null

## Referencia al NavigationSystem (para pathfinding helper)
var nav_system: NavigationSystem = null

# ── Auto-jump (solicitado por NavigationSystem) ──
var auto_jump_pending: bool = false
var auto_jump_velocity: float = 7.0

# ── Stuck detection state ──
var stuck_timer: float = 0.0
var stuck_progress_timer: float = 0.0
var last_dist_to_target: float = -1.0
var last_position: Vector3 = Vector3.ZERO
var stuck_recovery_phase: int = 0
var stuck_recovery_timer: float = 0.0
var stuck_recovery_dir: Vector3 = Vector3.ZERO
var stuck_blocking_bot: Node3D = null
var stuck_blocked_duration: float = 0.0
var stuck_reroute_count: int = 0
var is_stuck_flag: bool = false

# ── "Cede el paso" state ──
var _yield_timer: float = 0.0
var _is_yielding: bool = false
const YIELD_DURATION: float = 0.5

# ── Navigation tracking ──
var nav_target: Vector3 = Vector3.ZERO
var route_waypoint: Vector3 = Vector3.ZERO
var route_phase: int = 0
var route_target_pos: Vector3 = Vector3.ZERO
var last_agent_target: Vector3 = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	bot = get_parent() as NpcBase
	agent = bot.navigation_agent if bot and bot.has_node("NavigationAgent3D") else null
	nav_system = get_node_or_null("../NavigationSystem") as NavigationSystem
	last_position = bot.global_position if bot else Vector3.ZERO
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	# Conectar RVO avoidance signal
	if agent:
		agent.velocity_computed.connect(_on_agent_velocity_computed)


## Procesa el movimiento y ESCRIBE velocity (único lugar).
## Llamar ANTES de move_and_slide().
func process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	# ── 1. Leer comando de movimiento ──
	var move_mode: int = command.mode
	var move_speed: float = command.speed
	var move_target: Vector3 = command.target_position
	var move_dir: Vector3 = command.direction
	
	# ── 2. Ejecutar según modo ──
	match move_mode:
		MovementCommand.Mode.NAVIGATE:
			_execute_navigate(delta, move_target, move_speed)
		
		MovementCommand.Mode.DIRECT:
			_execute_direct(delta, move_dir, move_speed)
		
		MovementCommand.Mode.HOLD:
			_execute_hold(delta)
		
		MovementCommand.Mode.DODGE:
			_execute_dodge(delta)
		
		MovementCommand.Mode.STOP:
			_execute_stop(delta)
		
		MovementCommand.Mode.NONE:
			# Sin comando activo. No interferir con velocity.
			# Comportamientos legacy (API antigua) escriben velocity
			# directamente. MovementSystem solo aplica gravedad y
			# saltos para mantener consistencia durante la transición.
			# ⚠ En Fase 5+ todos los behaviors migrarán a MovementCommand.
			pass
	
	# ── 3. Aplicar gravedad (SIEMPRE, único lugar) ──
	if not bot.is_on_floor():
		bot.velocity.y -= _gravity * delta
	
	# ── 4. Aplicar salto si está solicitado ──
	if auto_jump_pending and bot.is_on_floor():
		bot.velocity.y = auto_jump_velocity
		auto_jump_pending = false
	
	if command.jump and bot.is_on_floor():
		bot.velocity.y = command.jump_velocity
		command.jump = false  # Consumir el salto
	
	# ── 5. Aplicar "cede el paso" si está activo ──
	if _is_yielding:
		_yield_timer -= delta
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, 20.0 * delta)
		bot.velocity.z = move_toward(bot.velocity.z, 0.0, 20.0 * delta)
		if _yield_timer <= 0.0:
			_is_yielding = false
	
	# ── 6. Aplicar stuck recovery si está activo ──
	if stuck_recovery_phase > 0:
		_handle_stuck_recovery(delta)
	
	# ── 6. Limpiar comando (solo si no es frame persistente) ──
	if move_mode != MovementCommand.Mode.NONE:
		command.reset()


## Post-procesa después de move_and_slide().
## Verifica stuck, llegada a destino, etc.
func post_process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	# ── Detectar stuck ──
	_check_stuck(delta)
	
	# Nota: Estado de stuck se reporta vía señales (stuck_detected)
	# ya no se sincroniza con BotBrain (eliminado en Fase 8)


# ══════════════════════════════════════════════════════════════════
# EJECUCIÓN POR MODO
# ══════════════════════════════════════════════════════════════════

## Navega usando NavigationAgent3D hacia un destino.
func _execute_navigate(delta: float, target: Vector3, speed: float) -> void:
	if agent == null:
		return
	
	# Actualizar target del agente si cambió
	if target != Vector3.ZERO and target != last_agent_target:
		agent.target_position = target
		last_agent_target = target
		nav_target = target
		route_target_pos = target
	
	# Verificar que el mapa de navegación esté listo
	var nav_map_rid: RID = agent.get_navigation_map()
	var map_iter: int = NavigationServer3D.map_get_iteration_id(nav_map_rid)
	if map_iter == 0:
		return  # Mapa no listo aún
	
	if agent.is_navigation_finished():
		# Llegamos al destino — frenar suavemente
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, speed * delta * 3.0)
		bot.velocity.z = move_toward(bot.velocity.z, 0.0, speed * delta * 3.0)
		destination_reached.emit(bot.global_position)
		return
	
	var next_pos: Vector3 = agent.get_next_path_position()
	var dir: Vector3 = (next_pos - bot.global_position).normalized()
	
	if dir.length_squared() < 0.001:
		return
	
	# Calcular velocidad
	var desired: Vector3 = dir * speed
	
	# RVO avoidance nativo (NavigationServer3D)
	if agent.avoidance_enabled:
		agent.set_velocity(desired)
		bot.velocity.x = _rvo_safe_velocity.x
		bot.velocity.z = _rvo_safe_velocity.z
	else:
		bot.velocity.x = desired.x
		bot.velocity.z = desired.z


## Movimiento por vector directo (strafe, retreat).
func _execute_direct(delta: float, dir: Vector3, speed: float) -> void:
	if dir.length_squared() < 0.001:
		_execute_hold(delta)
		return
	
	var normalized_dir: Vector3 = dir.normalized()
	normalized_dir.y = 0.0
	
	var desired: Vector3 = normalized_dir * speed
	
	# RVO avoidance nativo (NavigationServer3D)
	if agent and agent.avoidance_enabled:
		agent.set_velocity(desired)
		bot.velocity.x = _rvo_safe_velocity.x
		bot.velocity.z = _rvo_safe_velocity.z
	else:
		bot.velocity.x = desired.x
	bot.velocity.z = desired.z


## Quieto intencional — frenar suavemente.
func _execute_hold(delta: float) -> void:
	bot.velocity.x = move_toward(bot.velocity.x, 0.0, 10.0 * delta)
	bot.velocity.z = move_toward(bot.velocity.z, 0.0, 10.0 * delta)


## Evasión — impulso lateral instantáneo.
func _execute_dodge(delta: float) -> void:
	var dir: Vector3 = command.dodge_direction.normalized()
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		bot.velocity.x = dir.x * command.dodge_impulse
		bot.velocity.z = dir.z * command.dodge_impulse
	else:
		_execute_hold(delta)


## Frenada inmediata.
func _execute_stop(_delta: float) -> void:
	bot.velocity.x = 0.0
	bot.velocity.z = 0.0


# ══════════════════════════════════════════════════════════════════
# RVO AVOIDANCE — Nativo de NavigationServer3D
# ══════════════════════════════════════════════════════════════════

## Recibe la velocidad segura calculada por el NavigationServer3D (RVO).
## Se llama automáticamente cada frame cuando avoidance_enabled = true.
func _on_agent_velocity_computed(safe_velocity: Vector3) -> void:
	_rvo_safe_velocity = safe_velocity
	# Aplicar al bot si está vivo y el movimiento lo usa
	if bot and not bot.is_dead:
		bot.velocity.x = safe_velocity.x
		bot.velocity.z = safe_velocity.z


# ══════════════════════════════════════════════════════════════════
# STUCK DETECTION
# ══════════════════════════════════════════════════════════════════

func _check_stuck(delta: float) -> void:
	var beh_name: String = _get_current_behavior_name()
	
	if beh_name == "idle" or bot.is_dead:
		_reset_stuck_state()
		last_position = bot.global_position
		return
	
	# Si hay recuperación activa, ejecutarla
	if stuck_recovery_phase > 0:
		return  # _handle_stuck_recovery se llama en process()
	
	# Métrica 1: Progreso hacia el objetivo
	var goal_pos: Vector3 = _get_stuck_goal_position()
	var has_goal: bool = goal_pos != Vector3.ZERO
	
	if has_goal:
		var dist_to_goal: float = bot.global_position.distance_to(goal_pos)
		if last_dist_to_target >= 0.0:
			var progress: float = last_dist_to_target - dist_to_goal
			if progress < 0.05:
				stuck_progress_timer += delta
			else:
				stuck_progress_timer = max(0.0, stuck_progress_timer - delta * 3.0)
		last_dist_to_target = dist_to_goal
	else:
		stuck_progress_timer = max(0.0, stuck_progress_timer - delta * 2.0)
	
	# Métrica 2: Inmovilidad absoluta
	var moved: float = bot.global_position.distance_to(last_position)
	if moved < 0.02:
		stuck_timer += delta
	else:
		stuck_timer = max(0.0, stuck_timer - delta * 2.0)
	
	# Métrica 3: Bloqueo entre bots
	_check_bot_blocking(delta)
	
	# Decisión
	var threshold: float = STUCK_PROGRESS_THRESHOLD.get(beh_name, 4.0)
	is_stuck_flag = false
	
	if has_goal and stuck_progress_timer >= threshold:
		is_stuck_flag = true
	
	if moved < 0.02 and stuck_timer >= threshold + 2.0:
		is_stuck_flag = true
	
	if stuck_blocking_bot and stuck_blocked_duration >= STUCK_BLOCKED_TRIGGER_TIME:
		is_stuck_flag = true
	
	if is_stuck_flag:
		stuck_recovery_phase = 1
		stuck_recovery_timer = 0.4
		stuck_reroute_count += 1
		_init_recovery_direction()
		emit_signal("stuck_detected", stuck_recovery_phase, "progress=%.1fs" % stuck_progress_timer)
	
	last_position = bot.global_position


func _handle_stuck_recovery(delta: float) -> void:
	match stuck_recovery_phase:
		1: # Retroceder — buscar espacio libre
			stuck_recovery_timer -= delta
			var speed: float = 4.5
			
			# Buscar dirección libre con raycast (evitar paredes)
			var free_dir: Vector3 = _find_free_direction(stuck_recovery_dir)
			if free_dir != Vector3.ZERO:
				stuck_recovery_dir = free_dir
			
			# Ya no salta automáticamente — el salto es solo para Problema 2
			# si no hay espacio lateral tras 2s
			bot.velocity.x = stuck_recovery_dir.x * speed
			bot.velocity.z = stuck_recovery_dir.z * speed
			if stuck_recovery_timer <= 0.0:
				stuck_recovery_phase = 2
				stuck_recovery_timer = 0.4
				# Dirección lateral para fase 2 (alternar lado cada intento)
				var side_dir: Vector3 = Vector3(-stuck_recovery_dir.z, 0.0, stuck_recovery_dir.x)
				if stuck_reroute_count % 2 == 0:
					side_dir = -side_dir
				stuck_recovery_dir = side_dir.normalized()
		
		2: # Lateral — buscar espacio a los lados
			stuck_recovery_timer -= delta
			# Re-verificar dirección lateral con raycast
			var lateral_free: Vector3 = _find_free_direction(stuck_recovery_dir)
			if lateral_free != Vector3.ZERO:
				stuck_recovery_dir = lateral_free
			bot.velocity.x = stuck_recovery_dir.x * 3.5
			bot.velocity.z = stuck_recovery_dir.z * 3.5
			if stuck_recovery_timer <= 0.0:
				stuck_recovery_phase = 3
				_force_path_recalculation()
		
		3: # Transición — fin de recuperación
			stuck_recovery_phase = 0
			_reset_stuck_state()
			emit_signal("stuck_resolved")


func _init_recovery_direction() -> void:
	var away_dir: Vector3
	var goal: Vector3 = _get_stuck_goal_position()
	
	if stuck_blocking_bot and is_instance_valid(stuck_blocking_bot):
		away_dir = (bot.global_position - stuck_blocking_bot.global_position).normalized()
	elif goal != Vector3.ZERO:
		away_dir = (bot.global_position - goal).normalized()
	else:
		away_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.001:
		away_dir = Vector3(1.0, 0.0, 0.0)
	
	# Verificar con raycast que la dirección no tenga pared
	var checked_dir: Vector3 = _find_free_direction(away_dir.normalized())
	if checked_dir != Vector3.ZERO:
		stuck_recovery_dir = checked_dir
	else:
		stuck_recovery_dir = away_dir.normalized()


## Busca una dirección libre usando raycasts.
## Prueba la dirección preferida y 4 alternativas en abanico (45°, 90°).
## Retorna Vector3.ZERO si todo está bloqueado.
func _find_free_direction(preferred_dir: Vector3) -> Vector3:
	if bot == null or not bot.is_inside_tree():
		return preferred_dir
	
	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var origin: Vector3 = bot.global_position + Vector3.UP * 0.5
	var check_distance: float = 2.0
	
	# Direcciones a probar: preferida, luego laterales en abanico
	var directions: Array[Vector3] = [
		preferred_dir,
		preferred_dir.rotated(Vector3.UP, 0.785),  # 45°
		preferred_dir.rotated(Vector3.UP, -0.785),  # -45°
		preferred_dir.rotated(Vector3.UP, 1.571),   # 90°
		preferred_dir.rotated(Vector3.UP, -1.571),  # -90°
	]
	
	for dir in directions:
		var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * check_distance)
		query.collision_mask = 1  # Capa 1 = paredes/obstáculos (excluye NPCs)
		query.exclude = [bot]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return dir.normalized()
	
	return Vector3.ZERO


func _force_path_recalculation() -> void:
	nav_target = Vector3.ZERO
	if agent and is_instance_valid(agent):
		agent.target_position = bot.global_position


func _reset_stuck_state() -> void:
	stuck_timer = 0.0
	stuck_progress_timer = 0.0
	last_dist_to_target = -1.0
	stuck_recovery_phase = 0
	stuck_recovery_timer = 0.0
	stuck_blocking_bot = null
	stuck_blocked_duration = 0.0
	is_stuck_flag = false
	_is_yielding = false
	_yield_timer = 0.0


func _check_bot_blocking(delta: float) -> void:
	if bot == null or not bot.is_inside_tree():
		return
	var bodies: Array = bot.area_vision.get_overlapping_bodies() if bot.has_node("AreaVision") else []
	var closest: Node3D = null
	var min_dist: float = 2.0
	
	for body in bodies:
		if body == bot:
			continue
		if not body is CharacterBody3D:
			continue
		if not body.is_inside_tree():
			continue
		var dist: float = bot.global_position.distance_to(body.global_position)
		if dist < min_dist:
			closest = body
			min_dist = dist
	
	if closest:
		if closest == stuck_blocking_bot:
			stuck_blocked_duration += delta
			# Emitir path_blocked si lleva bloqueado suficiente tiempo
			if abs(stuck_blocked_duration - STUCK_BLOCKED_TRIGGER_TIME) < delta:
				var dist: float = _get_stuck_goal_position().distance_to(bot.global_position) if _get_stuck_goal_position() != Vector3.ZERO else 0.0
				path_blocked.emit(dist)
			
			# ── Sistema "cede el paso" ──
			# Si llevamos > 1.5s bloqueados por otro bot, el de menor prioridad cede
			if stuck_blocked_duration > 1.5 and not _is_yielding:
				if _should_yield_to(closest):
					_is_yielding = true
					_yield_timer = YIELD_DURATION
		else:
			stuck_blocking_bot = closest
			stuck_blocked_duration = 0.0
			# Si estábamos cediendo pero el bloqueador cambió, resetear
			if _is_yielding:
				_is_yielding = false
	else:
		stuck_blocking_bot = null
		stuck_blocked_duration = 0.0
		if _is_yielding:
			_is_yielding = false


## Determina si este bot debería ceder el paso a otro bot.
## Prioridad: el que está en combate tiene prioridad sobre el que no.
## Si ambos están en el mismo estado, el de mayor _npc_id (spawneado después) cede.
func _should_yield_to(other_bot: Node3D) -> bool:
	if other_bot == null:
		return false
	
	var my_combat: bool = _is_in_combat()
	var other_combat: bool = other_bot.get("_in_combat") if "_in_combat" in other_bot else false
	
	# Si el otro está en combate y yo no, yo cedo
	if other_combat and not my_combat:
		return true
	# Si yo estoy en combate y el otro no, no cedo
	if my_combat and not other_combat:
		return false
	
	# Ambos en mismo estado: el de mayor _npc_id (menos prioridad) cede
	var my_id: int = bot._npc_id if "_npc_id" in bot else 0
	var other_id: int = other_bot.get("_npc_id") if "_npc_id" in other_bot else 0
	return my_id > other_id


func _is_in_combat() -> bool:
	if bot and bot.decision_sys and bot.decision_sys.current_state:
		return bot.decision_sys.current_state.state_name == "combat"
	return false


func _get_stuck_goal_position() -> Vector3:
	var beh_name: String = _get_current_behavior_name()
	match beh_name:
		"patrol", "hunt":
			if route_target_pos != Vector3.ZERO:
				return route_target_pos
			if nav_target != Vector3.ZERO:
				return nav_target
		"combat":
			if bot and bot.decision_sys and bot.decision_sys.target_entity \
			and is_instance_valid(bot.decision_sys.target_entity):
				return bot.decision_sys.target_entity.global_position
	return Vector3.ZERO


func _get_current_behavior_name() -> String:
	# Usar DecisionSystem si está disponible
	if bot and bot.decision_sys and bot.decision_sys.current_state:
		return bot.decision_sys.current_state.state_name
	return "unknown"


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA
# ══════════════════════════════════════════════════════════════════

## Establece el comando de movimiento desde BotBrain/DecisionSystem.
func set_command(cmd: MovementCommand) -> void:
	command = cmd


## ¿Está atascado?
func is_stuck() -> bool:
	return stuck_recovery_phase > 0


## Resetea todo el estado de movimiento (útil en respawn).
func reset() -> void:
	command.reset()
	_reset_stuck_state()
	nav_target = Vector3.ZERO
	route_waypoint = Vector3.ZERO
	route_phase = 0
	route_target_pos = Vector3.ZERO
	last_agent_target = Vector3.ZERO
	if agent:
		agent.target_position = bot.global_position if bot else Vector3.ZERO
	last_position = bot.global_position if bot else Vector3.ZERO
