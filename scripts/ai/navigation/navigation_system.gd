# scripts/ai/navigation/navigation_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE NAVEGACIÓN — Movimiento físico de bots
#
# Responsable únicamente de CÓMO llegar a un destino.
# NO decide qué hacer (eso es BotBrain + Behaviors).
# NO almacena conocimiento (eso es MemorySystem).
#
# ── RESPONSABILIDADES ──
# - Pathfinding hacia un destino (NavigationAgent3D)
# - Movimiento por vector directo (strafe, retreat)
# - Detección de atasco (progreso, inmovilidad, bots bloqueando)
# - Recuperación de atasco (retroceder, lateral, reruta)
# - Frenado intencional (hold)
# - Supresión de stuck detection (para combate, disparo, etc.)
#
# ── NO RESPONSABILIDADES ──
# - Strafing de combate (lo deciden Behaviors)
# - Retirada táctica (lo deciden Behaviors)
# - Flanqueo (lo deciden Behaviors)
# - Decisiones de comportamiento
#
# ── API PARA BEHAVIORS (vía BotBrain) ──
#   navigation.move_to(target, speed)        → pathfinding
#   navigation.move_direction(vec, speed)    → vector directo
#   navigation.hold_position()               → quieto intencional
#   navigation.suppress_stuck(reason)        → sin falsos positivos
#   navigation.resume_stuck()                → reactiva detección
#   navigation.is_stuck()                    → consulta estado
#   navigation.is_navigation_finished()      → ¿ruta completa?
# ──────────────────────────────────────────────────────────────────
extends Node
class_name NavigationSystem


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

# Umbrales de stuck detection por comportamiento
const STUCK_PROGRESS_THRESHOLD: Dictionary = {
	"idle":   8.0,
	"patrol": 2.5,
	"combat": 4.0,
	"hunt":   2.0,
}

const STUCK_HISTORY_SIZE: int = 30
const ROUTE_WAYPOINT_REACHED_DIST: float = 5.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Referencia al bot dueño
var bot: NpcBase:
	get:
		if _bot == null:
			_bot = get_parent() as NpcBase
		return _bot
var _bot: NpcBase = null

## NavigationAgent del bot (buscado como hijo de NpcBase)
var agent: NavigationAgent3D = null

# ── Estado de navegación ─────────────────────────────────────────
var _nav_target: Vector3 = Vector3.ZERO
var _route_type: int = -1
var _route_waypoint: Vector3 = Vector3.ZERO
var _route_phase: int = 0
var _route_target_pos: Vector3 = Vector3.ZERO

# ── Estado de stuck detection ────────────────────────────────────
var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _stuck_progress_timer: float = 0.0
var _last_dist_to_target: float = -1.0
var _stuck_recovery_phase: int = 0
var _stuck_recovery_timer: float = 0.0
var _stuck_recovery_dir: Vector3 = Vector3.ZERO
var _stuck_origin: Vector3 = Vector3.ZERO
var _stuck_reroute_count: int = 0
var _stuck_attempted_dirs: Array[Vector3] = []
var _stuck_blocking_bot: Node3D = null
var _stuck_blocked_duration: float = 0.0

# ── Supresión de stuck ───────────────────────────────────────────
var _stuck_suppressed: bool = false
var _stuck_suppress_reason: String = ""
var _stuck_suppress_timer: float = 0.0


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as NpcBase
	if bot:
		agent = bot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		_route_type = RouteDiversifier.get_route_type_for_bot(bot)
		_last_position = bot.global_position


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Intenciones de movimiento
# ══════════════════════════════════════════════════════════════════

## Navega hacia un destino usando pathfinding (NavigationAgent3D).
## Compatible con la API antigua: maneja ruta diversificada y fases.
func move_to(target: Vector3, speed: float, delta: float = 0.0) -> void:
	if agent == null or bot == null:
		return
	
	# Si estamos en recuperación de atasco, no intervenir
	if _stuck_recovery_phase > 0:
		return
	
	# Si el destino cambió significativamente, recalcular ruta
	if _route_target_pos != target:
		_route_target_pos = target
		if RouteDiversifier.should_recalculate_route(_nav_target, target):
			_set_route_target(target)
	
	# Seguir la ruta con fases (waypoint → destino final)
	_navigate_with_route(delta, speed, target)


## Aplica un vector de movimiento directo (sin pathfinding).
## Usado para strafe, retreat y movimientos controlados por behaviors.
func move_direction(direction: Vector3, speed: float) -> void:
	if bot == null:
		return
	if _stuck_recovery_phase > 0:
		return
	
	var dir: Vector3 = direction
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		bot.velocity.x = dir.x * speed
		bot.velocity.z = dir.z * speed


## Detiene el bot intencionalmente y suprime stuck detection.
func hold_position() -> void:
	if bot == null:
		return
	bot.velocity.x = move_toward(bot.velocity.x, 0.0, 10.0)
	bot.velocity.z = move_toward(bot.velocity.z, 0.0, 10.0)
	# No suprimimos stuck aquí automáticamente — el behavior debe
	# llamar suppress_stuck() si quiere evitar detección. HOLD solo frena.


## Establece un destino de navegación con ruta diversificada.
func set_destination(target: Vector3) -> void:
	_set_route_target(target)


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Control de stuck detection
# ══════════════════════════════════════════════════════════════════

## Suprime la detección de atasco (el bot está ocupado: disparando,
## apuntando, defendiendo, etc.).
func suppress_stuck(reason: String) -> void:
	_stuck_suppressed = true
	_stuck_suppress_reason = reason
	_stuck_suppress_timer = 0.0


## Suprime la detección por una duración específica.
func suppress_stuck_for(duration: float, reason: String) -> void:
	_stuck_suppressed = true
	_stuck_suppress_reason = reason
	_stuck_suppress_timer = duration


## Reactiva la detección de atasco.
func resume_stuck() -> void:
	_stuck_suppressed = false
	_stuck_suppress_reason = ""
	_stuck_suppress_timer = 0.0


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Consultas de estado
# ══════════════════════════════════════════════════════════════════

## ¿El bot está actualmente en recuperación de atasco?
func is_stuck() -> bool:
	return _stuck_recovery_phase > 0

## ¿El bot está en medio de una maniobra de recuperación?
func is_recovering() -> bool:
	return _stuck_recovery_phase > 0

## ¿La navegación actual ha llegado a su destino?
func is_navigation_finished() -> bool:
	if agent == null:
		return true
	return agent.is_navigation_finished()

## ¿Hay supresión de stuck activa?
func is_stuck_suppressed() -> bool:
	return _stuck_suppressed


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado desde NpcBase._physics_process()
# ══════════════════════════════════════════════════════════════════

## Actualiza el sistema de navegación cada frame.
## 1. Gestiona supresión temporal de stuck
## 2. Detecta atasco (si no está suprimido)
## 3. Ejecuta recuperación si es necesario
func update(delta: float) -> bool:
	if bot == null or bot.is_dead:
		return false
	
	# ── Gestión de supresión temporal ──
	if _stuck_suppressed and _stuck_suppress_timer > 0.0:
		_stuck_suppress_timer -= delta
		if _stuck_suppress_timer <= 0.0:
			resume_stuck()
	
	# ── Si estamos en recuperación, ejecutarla ──
	if _stuck_recovery_phase > 0:
		return _handle_stuck_recovery(delta)
	
	# ── Si no hay supresión, detectar atasco ──
	if not _stuck_suppressed:
		return _check_stuck(delta)
	
	return false


## Resetea todo el estado de navegación (útil en respawn).
func reset() -> void:
	_nav_target = Vector3.ZERO
	_route_waypoint = Vector3.ZERO
	_route_phase = 0
	_route_target_pos = Vector3.ZERO
	_reset_stuck_state()
	_last_position = bot.global_position if bot else Vector3.ZERO
	resume_stuck()


# ══════════════════════════════════════════════════════════════════
# INTERNO — Ruta diversificada
# ══════════════════════════════════════════════════════════════════

func _set_route_target(new_target: Vector3) -> void:
	_route_target_pos = new_target
	
	var effective_route_type: int = _route_type
	if bot and bot._tactical_role:
		effective_route_type = bot._tactical_role.get_preferred_route_type(_route_type)
	
	if agent == null:
		_nav_target = new_target
		_route_phase = 1
		return
	
	var nav_map_rid: RID = agent.get_navigation_map()
	var waypoint: Vector3 = RouteDiversifier.get_approach_waypoint(
		bot.global_position, new_target, effective_route_type, nav_map_rid
	)
	
	_nav_target = waypoint
	agent.target_position = waypoint
	
	if waypoint != new_target:
		_route_waypoint = waypoint
		_route_phase = 0
	else:
		_route_waypoint = Vector3.ZERO
		_route_phase = 1


func _navigate_with_route(delta: float, speed: float, target_pos: Vector3) -> void:
	if agent == null:
		return
	
	if _route_phase == 0 and _route_waypoint != Vector3.ZERO:
		var dist_to_wp: float = bot.global_position.distance_to(_route_waypoint)
		if dist_to_wp <= ROUTE_WAYPOINT_REACHED_DIST:
			_route_phase = 1
			_route_waypoint = Vector3.ZERO
			_nav_target = target_pos
			agent.target_position = target_pos
		else:
			_move_to_target(delta, speed, _route_waypoint)
			return
	
	if _route_target_pos != target_pos:
		_route_target_pos = target_pos
		if RouteDiversifier.should_recalculate_route(_nav_target, target_pos):
			_route_waypoint = Vector3.ZERO
			_route_phase = 1
			_nav_target = target_pos
			agent.target_position = target_pos
	
	_move_to_target(delta, speed, target_pos)


func _move_to_target(delta: float, speed: float, target: Vector3 = Vector3.ZERO) -> void:
	if agent == null or bot == null:
		return
	
	if target != Vector3.ZERO and target != agent.target_position:
		agent.target_position = target
	elif target == Vector3.ZERO:
		target = agent.target_position
	
	var nav_map_rid: RID = agent.get_navigation_map()
	var map_iter: int = NavigationServer3D.map_get_iteration_id(nav_map_rid)
	if map_iter == 0:
		return
	
	var nav_finished: bool = agent.is_navigation_finished()
	
	if nav_finished:
		if target != Vector3.ZERO:
			var dist_to_target: float = bot.global_position.distance_to(target)
			if dist_to_target <= agent.target_desired_distance:
				bot.velocity.x = move_toward(bot.velocity.x, 0.0, speed * delta * 3.0)
				bot.velocity.z = move_toward(bot.velocity.z, 0.0, speed * delta * 3.0)
				return
		return
	
	var next_pos: Vector3 = agent.get_next_path_position()
	var dir: Vector3 = (next_pos - bot.global_position).normalized()
	
	if dir.length_squared() < 0.001:
		return
	
	bot.velocity.x = dir.x * speed
	bot.velocity.z = dir.z * speed


# ══════════════════════════════════════════════════════════════════
# INTERNO — Stuck Detection
# ══════════════════════════════════════════════════════════════════

func _check_stuck(delta: float) -> bool:
	if bot == null:
		return false
	
	var beh_name: String = _get_current_behavior_name()
	
	if beh_name == "idle" or bot.is_dead:
		_reset_stuck_state()
		_last_position = bot.global_position
		return false
	
	# Métrica 1: Progreso hacia el objetivo
	var goal_pos: Vector3 = _get_stuck_goal_position()
	var has_goal: bool = goal_pos != Vector3.ZERO
	
	if has_goal:
		var dist_to_goal: float = bot.global_position.distance_to(goal_pos)
		
		if _last_dist_to_target >= 0.0:
			var progress_made: float = _last_dist_to_target - dist_to_goal
			if progress_made < 0.05:
				_stuck_progress_timer += delta
			else:
				_stuck_progress_timer = max(0.0, _stuck_progress_timer - delta * 3.0)
		_last_dist_to_target = dist_to_goal
	else:
		_stuck_progress_timer = max(0.0, _stuck_progress_timer - delta * 2.0)
	
	# Métrica 2: Inmovilidad absoluta
	var moved: float = bot.global_position.distance_to(_last_position)
	if moved < 0.02:
		_stuck_timer += delta
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)
	
	# Detectar bloqueo por otro bot
	_check_bot_blocking(delta)
	
	# Decisión
	var threshold: float = _get_stuck_threshold_for_behavior(beh_name)
	var stuck_detected: bool = false
	
	if has_goal and _stuck_progress_timer >= threshold:
		stuck_detected = true
	
	if moved < 0.02 and _stuck_timer >= threshold + 2.0:
		stuck_detected = true
	
	if stuck_detected:
		_stuck_recovery_phase = 1
		_stuck_recovery_timer = 0.4
		_stuck_origin = bot.global_position
		_stuck_reroute_count += 1
		_init_recovery_direction()
		return true
	
	_last_position = bot.global_position
	return false


func _reset_stuck_state() -> void:
	_stuck_timer = 0.0
	_stuck_progress_timer = 0.0
	_last_dist_to_target = -1.0
	_stuck_recovery_phase = 0
	_stuck_recovery_timer = 0.0
	_stuck_blocking_bot = null
	_stuck_blocked_duration = 0.0
	if _stuck_attempted_dirs.size() > 10:
		_stuck_attempted_dirs.clear()


func _get_stuck_goal_position() -> Vector3:
	var beh_name: String = _get_current_behavior_name()
	
	match beh_name:
		"patrol", "hunt":
			if _route_target_pos != Vector3.ZERO:
				return _route_target_pos
			if _nav_target != Vector3.ZERO:
				return _nav_target
		"combat":
			if bot and bot.target_enemy and is_instance_valid(bot.target_enemy):
				return bot.target_enemy.global_position
	return Vector3.ZERO


func _get_stuck_threshold_for_behavior(beh_name: String) -> float:
	return STUCK_PROGRESS_THRESHOLD.get(beh_name, 4.0)


func _get_current_behavior_name() -> String:
	if bot and bot.brain and bot.brain.current_behavior:
		return bot.brain.current_behavior.behavior_name
	return "idle"


func _check_bot_blocking(delta: float) -> void:
	if bot == null:
		return
	var bodies: Array = bot.area_vision.get_overlapping_bodies()
	var closest_blocker: Node3D = null
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
			closest_blocker = body
			min_dist = dist
	
	if closest_blocker:
		if closest_blocker == _stuck_blocking_bot:
			_stuck_blocked_duration += delta
		else:
			_stuck_blocking_bot = closest_blocker
			_stuck_blocked_duration = 0.0
	else:
		_stuck_blocking_bot = null
		_stuck_blocked_duration = 0.0


# ══════════════════════════════════════════════════════════════════
# INTERNO — Stuck Recovery
# ══════════════════════════════════════════════════════════════════

func _init_recovery_direction() -> void:
	if bot == null:
		return
	var away_dir: Vector3
	
	if _stuck_blocking_bot and is_instance_valid(_stuck_blocking_bot):
		away_dir = (bot.global_position - _stuck_blocking_bot.global_position).normalized()
	elif _get_stuck_goal_position() != Vector3.ZERO:
		away_dir = (bot.global_position - _get_stuck_goal_position()).normalized()
	else:
		away_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.001:
		away_dir = Vector3(1.0, 0.0, 0.0)
	_stuck_recovery_dir = away_dir.normalized()


func _handle_stuck_recovery(delta: float) -> bool:
	if bot == null:
		return false
	
	match _stuck_recovery_phase:
		1:
			_stuck_recovery_timer -= delta
			var speed: float = 4.5
			
			if _stuck_blocking_bot and is_instance_valid(_stuck_blocking_bot):
				if bot.is_on_floor():
					bot.velocity.y = bot.jumpiness * 12.0 + 3.0
				speed = 5.5
			
			bot.velocity.x = _stuck_recovery_dir.x * speed
			bot.velocity.z = _stuck_recovery_dir.z * speed
			
			if _stuck_recovery_timer <= 0.0:
				_stuck_recovery_phase = 2
				_stuck_recovery_timer = 0.3
				var side_dir: Vector3 = Vector3(-_stuck_recovery_dir.z, 0.0, _stuck_recovery_dir.x)
				if _stuck_reroute_count % 2 == 0:
					side_dir = -side_dir
				_stuck_recovery_dir = side_dir.normalized()
			return true
		
		2:
			_stuck_recovery_timer -= delta
			bot.velocity.x = _stuck_recovery_dir.x * 3.5
			bot.velocity.z = _stuck_recovery_dir.z * 3.5
			
			if _stuck_recovery_timer <= 0.0:
				_stuck_recovery_phase = 3
				_stuck_recovery_timer = 0.0
				_force_path_recalculation()
			return true
		
		3:
			_stuck_recovery_phase = 0
			_stuck_timer = 0.0
			_stuck_progress_timer = 0.0
			_last_dist_to_target = -1.0
			_stuck_blocking_bot = null
			_stuck_blocked_duration = 0.0
			
			_stuck_attempted_dirs.append(_stuck_recovery_dir)
			
			if _stuck_reroute_count >= 3:
				_stuck_reroute_count = 0
				_escalate_stuck_recovery()
			
			return false
	
	return false


func _force_path_recalculation() -> void:
	_nav_target = Vector3.ZERO
	if agent and is_instance_valid(agent):
		agent.target_position = bot.global_position if bot else Vector3.ZERO


func _escalate_stuck_recovery() -> void:
	if bot == null or agent == null:
		return
	var nav_map_rid: RID = agent.get_navigation_map()
	if NavigationServer3D.map_is_active(nav_map_rid):
		var raw_target: Vector3 = bot.global_position + Vector3(
			randf_range(-25.0, 25.0), 0, randf_range(-25.0, 25.0))
		var valid_target: Vector3 = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		_nav_target = valid_target
		agent.target_position = valid_target
	_stuck_attempted_dirs.clear()


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func debug_string() -> String:
	var status: String = "ok"
	if _stuck_recovery_phase > 0:
		status = "recovery(%d)" % _stuck_recovery_phase
	if _stuck_suppressed:
		status = "suppressed(%s)" % _stuck_suppress_reason
	return "Nav[status=%s target=%s]" % [status, str(_route_target_pos.round())]
