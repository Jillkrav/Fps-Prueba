# scripts/MP/nav/bots/stuck_handler.gd
# ──────────────────────────────────────────────────────────────────
# MANEJADOR DE ATASCOS Y EVASIÓN — UNIFICADO (FASE 2)
#
# Fusiona ObstacleEvader (evasión reactiva a colisiones) con
# StuckRecovery (detección por falta de progreso) en un solo sistema.
#
# ── PRINCIPIOS ──
# 1. COLISIÓN DIRECTA → evasión reactiva inmediata (ObstacleEvader)
#    - Gira la dirección 45° → 90° → 135° en hasta 4 intentos
#    - Si logra avanzar (≥ 0.05u) → éxito, se detiene
#    - Si falla 4 intentos → inicia stuck recovery como fallback
#
# 2. FALTA DE PROGRESO → stuck recovery progresivo (StuckRecovery)
#    - 3 métricas: progreso < 0.05u, inmovilidad < 0.02u, bloqueo entre bots
#    - Fase 1: retroceder 0.5s
#    - Fase 2: lateral 0.3s
#    - Fase 3: reruta vía NavigationAgent3D
#
# 3. COEXISTENCIA: si la evasión reactiva falla, stuck recovery toma
#    el control como fallback. Stuck recovery también se activa por
#    timeout si no hay colisión pero el bot no progresa.
# ──────────────────────────────────────────────────────────────────
extends Node
class_name StuckHandler


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando se detecta atasco.
signal stuck_detected(phase: int, cause: String)

## Se emite cuando el atasco se resuelve.
signal stuck_resolved()

## Se emite cuando el camino está bloqueado por otro bot.
signal path_blocked(remaining_distance: float)


# ══════════════════════════════════════════════════════════════════
# CONSTANTES — De ObstacleEvader
# ══════════════════════════════════════════════════════════════════

## Duración en segundos de cada intento de evasión reactiva.
const REACTIVE_EVASION_DURATION: float = 0.7
## Tiempo mínimo entre una maniobra reactiva y la siguiente.
const REACTIVE_EVASION_COOLDOWN: float = 1.5
## Desplazamiento mínimo para considerar que el bot logró avanzar.
const REACTIVE_MIN_MOVE: float = 0.05
## Número máximo de intentos reactivos antes de pasar a stuck recovery.
const REACTIVE_MAX_ATTEMPTS: int = 4


# ══════════════════════════════════════════════════════════════════
# CONSTANTES — De StuckRecovery (MovementSystem)
# ══════════════════════════════════════════════════════════════════

## Thresholds de progreso por estado FSM.
const STUCK_PROGRESS_THRESHOLD: Dictionary = {
	"idle":     8.0,
	"roaming":  1.5,  # FASE 6: era 2.5
	"combat":   1.5,  # FASE 6: era 2.5
	"hunting":  1.2,  # FASE 6: era 2.0
}

const STUCK_BLOCKED_TRIGGER_TIME: float = 1.5
const RECOVERY_PHASE1_DURATION: float = 0.5
const RECOVERY_PHASE2_DURATION: float = 0.3


# ══════════════════════════════════════════════════════════════════
# ESTADO — Evasión Reactiva (ex ObstacleEvader)
# ══════════════════════════════════════════════════════════════════

## ¿Está ejecutando evasión reactiva? (colisión detectada)
var is_evading: bool = false
## Intento actual (1-4) dentro de la evasión reactiva.
var _reactive_attempt: int = 1
## Temporizador del intento actual.
var _reactive_timer: float = 0.0
## Posición al comenzar el intento actual.
var _reactive_start_pos: Vector3 = Vector3.ZERO
## Timestamp de la última evasión reactiva (para cooldown).
var _reactive_last_time: float = 0.0
## Lado de giro preferido (asignado aleatoriamente).
var _dodge_side: int = 0  # 0 = LEFT, 1 = RIGHT


# ══════════════════════════════════════════════════════════════════
# ESTADO — Stuck Recovery (ex MovementSystem)
# ══════════════════════════════════════════════════════════════════

## Temporizador de inmovilidad.
var stuck_timer: float = 0.0
## Temporizador de falta de progreso.
var stuck_progress_timer: float = 0.0
## Última distancia al objetivo (para medir progreso).
var last_dist_to_target: float = -1.0
## Última posición del bot (para medir inmovilidad).
var last_position: Vector3 = Vector3.ZERO

## Fase de stuck recovery (0 = inactivo, 1 = retroceder, 2 = lateral, 3 = reruta).
var recovery_phase: int = 0
## Temporizador de la fase actual.
var recovery_timer: float = 0.0
## Dirección de movimiento durante la recuperación.
var recovery_dir: Vector3 = Vector3.ZERO

## Otro bot que está bloqueando (si aplica).
var blocking_bot: Node3D = null
## Duración del bloqueo por otro bot.
var blocked_duration: float = 0.0
## Contador de re-ruteos (para alternar lado en fase 2).
var reroute_count: int = 0

## Referencia al bot dueño.
var _bot: BotBase = null


# ══════════════════════════════════════════════════════════════════
# INICIALIZACIÓN
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as BotBase
	if _bot == null:
		_bot = get_parent().get_parent() as BotBase  # Si StuckHandler es hijo de MovementSystem
	_dodge_side = 0 if randi() % 2 == 0 else 1
	last_position = _bot.global_position if _bot else Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA
# ══════════════════════════════════════════════════════════════════

## Procesa evasión reactiva Y stuck detection.
## Debe llamarse DESPUÉS de move_and_slide(), en post_process().
func post_process(delta: float) -> void:
	if _bot == null or _bot.is_dead:
		return
	
	# ── 1. Detectar colisiones (ObstacleEvader legacy) ──
	_check_collisions()
	
	# ── 2. Actualizar evasión reactiva si está activa ──
	if is_evading:
		_update_reactive_evasion(delta)
	
	# ── 3. Detectar stuck por falta de progreso ──
	if recovery_phase == 0:
		_check_stuck(delta)


## Devuelve la dirección de movimiento modificada por evasión reactiva.
## Si no está evadiendo reactivamente, devuelve forward_dir sin cambios.
func get_evasion_direction(forward_dir: Vector3) -> Vector3:
	if not is_evading:
		return forward_dir
	
	var angle_deg: float
	match _reactive_attempt:
		1:
			angle_deg = 45.0
		2:
			angle_deg = 90.0
		3:
			angle_deg = 135.0
		_:
			return forward_dir  # No debería ocurrir
	
	var sign_multiplier := 1.0 if _dodge_side == 0 else -1.0
	var angle_rad := deg_to_rad(angle_deg * sign_multiplier)
	return forward_dir.rotated(Vector3.UP, angle_rad)


## ¿Está en stuck recovery (fase 1+)?
func is_in_recovery() -> bool:
	return recovery_phase > 0


## Procesa la recuperación de stuck (fases 1-3).
## Debe llamarse durante process(), antes de aplicar velocity.
## Retorna true si la recuperación está activa (movimiento overrideado).
func process_recovery(delta: float) -> bool:
	if recovery_phase == 0:
		return false
	
	_handle_stuck_recovery(delta)
	return true


## Obtiene la dirección de recuperación actual (para velocity override).
func get_recovery_velocity() -> Vector3:
	match recovery_phase:
		1:
			var speed: float = 4.5
			return Vector3(recovery_dir.x * speed, 0.0, recovery_dir.z * speed)
		2:
			var speed: float = 3.5
			return Vector3(recovery_dir.x * speed, 0.0, recovery_dir.z * speed)
		_:
			return Vector3.ZERO


## Resetea todo el estado (útil en respawn).
func reset() -> void:
	stuck_timer = 0.0
	stuck_progress_timer = 0.0
	last_dist_to_target = -1.0
	recovery_phase = 0
	recovery_timer = 0.0
	blocking_bot = null
	blocked_duration = 0.0
	reroute_count = 0
	is_evading = false
	_reactive_attempt = 1
	_reactive_timer = 0.0
	if _bot:
		last_position = _bot.global_position


# ══════════════════════════════════════════════════════════════════
# EVASIÓN REACTIVA (ex ObstacleEvader)
# ══════════════════════════════════════════════════════════════════

## Detecta colisiones contra geometría estática tras move_and_slide().
func _check_collisions() -> void:
	if _bot == null:
		return
	
	# No iniciar nueva evasión si ya estamos en una
	if is_evading:
		return
	
	# Cooldown wall-clock
	var now := Time.get_ticks_msec() / 1000.0
	if now - _reactive_last_time < REACTIVE_EVASION_COOLDOWN:
		return
	
	for i in _bot.get_slide_collision_count():
		var col := _bot.get_slide_collision(i)
		var collider := col.get_collider()
		
		if not is_instance_valid(collider):
			continue
		
		# Excluir personajes o actores de combate
		if collider.is_in_group("npc") \
				or collider.is_in_group("player") \
				or collider.has_method("take_damage"):
			continue
		
		# Geometría estática del escenario
		if collider is StaticBody3D or collider is CSGShape3D:
			_start_reactive_evasion()
			return


## Inicia evasión reactiva.
func _start_reactive_evasion() -> void:
	is_evading = true
	_reactive_attempt = 1
	_reactive_timer = 0.0


## Actualiza la evasión reactiva (temporizadores, evaluación de intentos).
func _update_reactive_evasion(delta: float) -> void:
	if not is_evading:
		return
	
	# Registrar posición inicial al primer frame
	if _reactive_timer == 0.0:
		_reactive_start_pos = _bot.global_position
	
	_reactive_timer += delta
	
	if _reactive_timer >= REACTIVE_EVASION_DURATION:
		_evaluate_reactive_attempt()


## Evalúa si el intento actual de evasión reactiva tuvo éxito.
func _evaluate_reactive_attempt() -> void:
	var distance_moved := _bot.global_position.distance_to(_reactive_start_pos)
	
	if distance_moved >= REACTIVE_MIN_MOVE:
		# ✅ Logró avanzar → evasión exitosa
		is_evading = false
		_reactive_attempt = 1
		_reactive_last_time = Time.get_ticks_msec() / 1000.0
		return
	
	# ❌ No avanzó → siguiente intento
	_reactive_attempt += 1
	
	if _reactive_attempt > REACTIVE_MAX_ATTEMPTS:
		# Se rinde la evasión reactiva → pasa a stuck recovery como fallback
		is_evading = false
		_reactive_last_time = Time.get_ticks_msec() / 1000.0
		_start_stuck_recovery("reactive_failed")
	else:
		# Reiniciar temporizador para el siguiente intento
		_reactive_timer = 0.0
		_reactive_start_pos = _bot.global_position


# ══════════════════════════════════════════════════════════════════
# STUCK DETECTION (ex MovementSystem._check_stuck)
# ══════════════════════════════════════════════════════════════════

func _check_stuck(delta: float) -> void:
	var beh_name: String = _get_current_behavior_name()
	
	if beh_name == "idle" or _bot.is_dead:
		_reset_stuck_state()
		last_position = _bot.global_position
		return
	
	# Métrica 1: Progreso hacia el objetivo
	var goal_pos: Vector3 = _get_stuck_goal_position()
	var has_goal: bool = goal_pos != Vector3.ZERO
	
	if has_goal:
		var dist_to_goal: float = _bot.global_position.distance_to(goal_pos)
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
	var moved: float = _bot.global_position.distance_to(last_position)
	if moved < 0.02:
		stuck_timer += delta
	else:
		stuck_timer = max(0.0, stuck_timer - delta * 2.0)
	
	# Métrica 3: Bloqueo entre bots
	_check_bot_blocking(delta)
	
	# Decisión
	var threshold: float = STUCK_PROGRESS_THRESHOLD.get(beh_name, 4.0)
	if _is_on_ramp():
		threshold *= 2.0
	
	var should_recover: bool = false
	var cause: String = ""
	
	if has_goal and stuck_progress_timer >= threshold:
		should_recover = true
		cause = "progress=%.1fs" % stuck_progress_timer
	
	if moved < 0.02 and stuck_timer >= threshold + 2.0:
		should_recover = true
		cause = "immobile=%.1fs" % stuck_timer
	
	if blocking_bot and blocked_duration >= STUCK_BLOCKED_TRIGGER_TIME:
		should_recover = true
		cause = "blocked_by_bot=%.1fs" % blocked_duration
	
	if should_recover:
		_start_stuck_recovery(cause)
	
	last_position = _bot.global_position


func _start_stuck_recovery(cause: String) -> void:
	recovery_phase = 1
	recovery_timer = RECOVERY_PHASE1_DURATION
	reroute_count += 1
	_init_recovery_direction()
	emit_signal("stuck_detected", recovery_phase, cause)


func _handle_stuck_recovery(delta: float) -> void:
	match recovery_phase:
		1:  # Retroceder
			recovery_timer -= delta
			var free_dir: Vector3 = _find_free_direction(recovery_dir)
			if free_dir != Vector3.ZERO:
				recovery_dir = free_dir
			if recovery_timer <= 0.0:
				recovery_phase = 2
				recovery_timer = RECOVERY_PHASE2_DURATION
				var side_dir: Vector3 = Vector3(-recovery_dir.z, 0.0, recovery_dir.x)
				if reroute_count % 2 == 0:
					side_dir = -side_dir
				recovery_dir = side_dir.normalized()
		
		2:  # Lateral
			recovery_timer -= delta
			var lateral_free: Vector3 = _find_free_direction(recovery_dir)
			if lateral_free != Vector3.ZERO:
				recovery_dir = lateral_free
			if recovery_timer <= 0.0:
				recovery_phase = 3
				_force_path_recalculation()
		
		3:  # Fin
			recovery_phase = 0
			_reset_stuck_state()
			emit_signal("stuck_resolved")


func _init_recovery_direction() -> void:
	var away_dir: Vector3
	var goal: Vector3 = _get_stuck_goal_position()
	
	if _is_on_ramp() and goal != Vector3.ZERO:
		away_dir = (goal - _bot.global_position).normalized()
		away_dir.y = 0.0
		if away_dir.length_squared() < 0.001:
			away_dir = Vector3(1.0, 0.0, 0.0)
		var ramp_dir: Vector3 = _find_free_direction(away_dir.normalized())
		recovery_dir = ramp_dir if ramp_dir != Vector3.ZERO else away_dir.normalized()
		return
	
	if blocking_bot and is_instance_valid(blocking_bot):
		away_dir = (_bot.global_position - blocking_bot.global_position).normalized()
	elif goal != Vector3.ZERO:
		away_dir = (_bot.global_position - goal).normalized()
	else:
		away_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
	
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.001:
		away_dir = Vector3(1.0, 0.0, 0.0)
	
	var checked_dir = _find_free_direction(away_dir.normalized())
	recovery_dir = checked_dir if checked_dir != Vector3.ZERO else away_dir.normalized()


func _find_free_direction(preferred_dir: Vector3) -> Vector3:
	if _bot == null or not _bot.is_inside_tree():
		return preferred_dir
	
	var space_state: PhysicsDirectSpaceState3D = _bot.get_world_3d().direct_space_state
	var origin: Vector3 = _bot.global_position + Vector3.UP * 0.5
	var check_distance: float = 2.0
	
	var directions: Array[Vector3] = [
		preferred_dir,
		preferred_dir.rotated(Vector3.UP, 0.785),   # 45°
		preferred_dir.rotated(Vector3.UP, -0.785),  # -45°
		preferred_dir.rotated(Vector3.UP, 1.571),   # 90°
		preferred_dir.rotated(Vector3.UP, -1.571),  # -90°
	]
	
	for dir in directions:
		var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * check_distance)
		query.collision_mask = 1  # Capa 1 = paredes
		query.exclude = [_bot]
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return dir.normalized()
	
	return Vector3.ZERO


func _force_path_recalculation() -> void:
	var agent: NavigationAgent3D = _bot.navigation_agent if _bot else null
	if agent and is_instance_valid(agent):
		agent.target_position = _bot.global_position


func _reset_stuck_state() -> void:
	stuck_timer = 0.0
	stuck_progress_timer = 0.0
	last_dist_to_target = -1.0
	blocking_bot = null
	blocked_duration = 0.0


func _check_bot_blocking(delta: float) -> void:
	if _bot == null or not _bot.is_inside_tree():
		return
	var bodies: Array = _bot.area_vision.get_overlapping_bodies() if _bot.has_node("AreaVision") else []
	var closest: Node3D = null
	var min_dist: float = 2.0
	
	for body in bodies:
		if body == _bot:
			continue
		if not body is CharacterBody3D:
			continue
		if not body.is_inside_tree():
			continue
		var dist: float = _bot.global_position.distance_to(body.global_position)
		if dist < min_dist:
			closest = body
			min_dist = dist
	
	if closest:
		if closest == blocking_bot:
			blocked_duration += delta
			if abs(blocked_duration - STUCK_BLOCKED_TRIGGER_TIME) < delta:
				var dist: float = 0.0
				var goal := _get_stuck_goal_position()
				if goal != Vector3.ZERO:
					dist = goal.distance_to(_bot.global_position)
				emit_signal("path_blocked", dist)
		else:
			blocking_bot = closest
			blocked_duration = 0.0
	else:
		blocking_bot = null
		blocked_duration = 0.0


func _get_stuck_goal_position() -> Vector3:
	var beh_name: String = _get_current_behavior_name()
	var movement_sys: MovementSystem = get_parent() as MovementSystem if get_parent() is MovementSystem else null
	if movement_sys == null:
		return Vector3.ZERO
	
	match beh_name:
		"roaming", "hunting":
			if movement_sys.route_target_pos != Vector3.ZERO:
				return movement_sys.route_target_pos
			if movement_sys.nav_target != Vector3.ZERO:
				return movement_sys.nav_target
		"combat":
			if _bot and _bot.decision_sys and _bot.decision_sys.target_entity \
			and is_instance_valid(_bot.decision_sys.target_entity) \
			and _bot.decision_sys.target_entity.is_inside_tree():
				return _bot.decision_sys.target_entity.global_position
	return Vector3.ZERO


func _get_current_behavior_name() -> String:
	if _bot and _bot.decision_sys and _bot.decision_sys.current_state:
		return _bot.decision_sys.current_state.state_name
	return "unknown"


func _is_on_ramp() -> bool:
	if _bot == null or not _bot.is_on_floor():
		return false
	var floor_normal: Vector3 = _bot.get_floor_normal()
	if floor_normal == Vector3.ZERO:
		return false
	var angle_rad: float = acos(clamp(floor_normal.dot(Vector3.UP), -1.0, 1.0))
	return angle_rad > deg_to_rad(5.0)
