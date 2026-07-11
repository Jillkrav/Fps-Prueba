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

# ── Vertical movement & auto-jump ──
## Diferencia de altura mínima para aplicar velocidad vertical al seguir el path.
## 0.05 para capturar incluso pendientes suaves (rampas de ~5° con waypoints separados 0.5u).
const CLIMB_HEIGHT_THRESHOLD: float = 0.05
## Altura que activa auto-jump (debe superar el step-up máximo ~0.42u).
## 0.55 = step-up max (0.42) + margen (0.13) para evitar falsos positivos en rampas.
const AUTO_JUMP_HEIGHT: float = 0.55
## Altura máxima para auto-jump (evitar saltos imposibles sin impulso).
const AUTO_JUMP_MAX_HEIGHT: float = 1.8
## Velocidad vertical máxima al escalar rampas/desniveles.
const MAX_CLIMB_SPEED: float = 5.0
## Fracción de la velocidad deseada que se aplica al eje Y al subir.
## 1.2 para dar más empuje vertical en rampas pronunciadas.
const CLIMB_Y_FACTOR: float = 1.2
## Velocidad vertical para step-up assist (al subir escalones) y
## fuerza base para step-down assist (al bajar escalones).
const STEP_ASSIST_VELOCITY: float = 3.5
## Distancia máxima que el bot puede bajar de un escalón.
## Debe coincidir con agent_max_climb del NavMesh.
const STEP_DOWN_MAX_HEIGHT: float = 1.8

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

# ── Vault controller (step-up 2) ──
var _vault_controller: VaultController = null

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
	# ── Vault controller (step-up 2) ──
	_vault_controller = VaultController.new()
	_vault_controller.setup(bot)
	# Conectar RVO avoidance signal
	if agent:
		agent.velocity_computed.connect(_on_agent_velocity_computed)


## Procesa el movimiento y ESCRIBE velocity (único lugar).
## Llamar ANTES de move_and_slide().
func process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	# ── 0. Vault / Step-up 2: procesar si está en curso (antes de todo) ──
	if _vault_controller and _vault_controller.is_vaulting():
		_vault_controller.process_vault(delta, Time.get_ticks_msec() / 1000.0)
		return  # Saltar gravedad, saltos, etc.
	
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
	# Si vault está activo, saltar estos saltos (el vault controla velocity)
	if auto_jump_pending and bot.is_on_floor() and not (_vault_controller and _vault_controller.is_vaulting()):
		bot.velocity.y = auto_jump_velocity
		auto_jump_pending = false
	
	if command.jump and bot.is_on_floor() and not (_vault_controller and _vault_controller.is_vaulting()):
		bot.velocity.y = command.jump_velocity
		command.jump = false  # Consumir el salto
	
	
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
	
	# ── Detectar desnivel vertical entre el bot y el siguiente waypoint ──
	var height_diff: float = next_pos.y - bot.global_position.y
	var on_floor: bool = bot.is_on_floor()
	
	# ── DEBUG: registrar escalada de rampas (desactivado) ─────
	# Nota: este log se quitó por ser demasiado verboso.
	
	# ── Auto-jump solo para ESCALONES/OBSTÁCULOS (no rampas) ──
	# El step-up máximo de la cápsula (radio 0.65) es ≈ 0.42 unidades.
	# AUTO_JUMP_HEIGHT=0.55 para cubrir el gap entre 0.42 y 0.55.
	# CRÍTICO: Solo se activa si _detect_step_front encuentra una cara VERTICAL
	# (normal.y < 0.3). En rampas, la cara inclinada tiene normal.y ≈ 0.707
	# (> 0.3), así que el auto-jump NO se dispara y climb_y escala suavemente.
	# Sin este filtro, el auto-jump se dispara en CADA waypoint de rampa,
	# sobreescribiendo climb_y y haciendo que el bot salte en vez de escalar.
	# Doble verificación: _detect_ramp_ahead() asegura que no sea rampa.
	if on_floor and height_diff > AUTO_JUMP_HEIGHT and height_diff < AUTO_JUMP_MAX_HEIGHT \
	and _detect_step_front(dir) and not _detect_ramp_ahead(dir):
		auto_jump_pending = true
		# Velocidad de salto: sqrt(2*g*h) * 1.15 para compensar el frame de gravedad
		auto_jump_velocity = clamp(sqrt(2.0 * _gravity * height_diff) * 1.15, 5.0, 12.0)
	
	# ── Step-up assist: raycasts para escalones que el step-up nativo no alcanza ──
	# Similar al sistema del player, pero adaptado para bots.
	# Detecta caras verticales de escalones/rampas y aplica impulso vertical.
	# En rampas, _detect_step_front NO se activa porque el filtro normal.y < 0.3
	# excluye superficies inclinadas. _detect_ramp_ahead es el que detecta rampas.
	if on_floor and _detect_step_front(dir):
		bot.velocity.y = max(bot.velocity.y, STEP_ASSIST_VELOCITY)
	
	# ── Vault / Step-up 2: automático para bots ──────────────────────────
	# Para obstáculos más grandes que el step-up assist pero dentro del
	# rango vault (~0.78u a 1.56u). El VaultController detecta y ejecuta.
	if on_floor and _vault_controller and not _vault_controller.is_vaulting():
		var v_time: float = Time.get_ticks_msec() / 1000.0
		if _vault_controller.try_vault(dir, v_time):
			pass  # Vault iniciado, la velocidad la controla process_vault
	
	# ── Calcular dirección y velocidad deseada ──
	var desired: Vector3 = dir * speed
	
	# Incluir componente Y para que el bot sepa si el siguiente punto
	# del camino está arriba (rampa) o abajo. En terreno plano dir.y ≈ 0,
	# así que no afecta. En rampas dir.y > 0 da el empuje vertical necesario.
	# En rampas dir.y < 0 da el empuje hacia abajo para seguir el descenso.
	var climb_y: float = dir.y * speed * CLIMB_Y_FACTOR
	
	# ── Step-down assist: detectar escalones BAJABLES ──
	# Cuando el bot está en el borde de un escalón/plataforma y hay
	# superficie caminable más abajo, aplicar velocidad vertical negativa
	# para que el bot "baje" el escalón siguiendo el camino del NavMesh.
	# CRÍTICO: Solo se activa si:
	#   1. El siguiente waypoint del path está más abajo (height_diff < -threshold)
	#   2. O el step-down detection encuentra suelo más abajo
	#   3. El bot está en el suelo (para evitar activarse en caída libre)
	if on_floor:
		var is_descending: bool = height_diff < -CLIMB_HEIGHT_THRESHOLD
		var step_down_detected: bool = _detect_step_down(dir)
		if is_descending or step_down_detected:
			# Velocidad vertical hacia ABAJO (siempre negativa)
			# Si el path ya muestra descenso (climb_y negativo), seguir el path.
			# Si solo el raycast detectó escalón, aplicar fuerza suave hacia abajo.
			var descent_target: float = climb_y if is_descending and climb_y < 0.0 else -STEP_ASSIST_VELOCITY * 0.5
			bot.velocity.y = min(bot.velocity.y, descent_target)

	# RVO avoidance nativo (NavigationServer3D)
	if agent.avoidance_enabled:
		agent.set_velocity(desired)
		bot.velocity.x = _rvo_safe_velocity.x
		bot.velocity.z = _rvo_safe_velocity.z
		# Aplicar Y tanto para SUBIR (height_diff > 0) como BAJAR (height_diff < 0)
		# rampas. Abs() permite ambos sentidos.
		if on_floor and abs(height_diff) > CLIMB_HEIGHT_THRESHOLD:
			bot.velocity.y = clamp(climb_y, -MAX_CLIMB_SPEED, MAX_CLIMB_SPEED)
	else:
		bot.velocity.x = desired.x
		bot.velocity.z = desired.z
		# Aplicar Y tanto para SUBIR como BAJAR rampas
		if on_floor and abs(height_diff) > CLIMB_HEIGHT_THRESHOLD:
			bot.velocity.y = clamp(climb_y, -MAX_CLIMB_SPEED, MAX_CLIMB_SPEED)


## Movimiento por vector directo (strafe, retreat).
func _execute_direct(delta: float, dir: Vector3, speed: float) -> void:
	if dir.length_squared() < 0.001:
		_execute_hold(delta)
		return
	
	var normalized_dir: Vector3 = dir.normalized()
	# Ya no aplanamos Y a 0 — el bot necesita la componente vertical
	# para moverse correctamente en rampas y pendientes.
	# normalized_dir.y = 0.0
	
	var desired: Vector3 = normalized_dir * speed
	
	# Step-up assist para movimento directo (strafe en rampas)
	if bot.is_on_floor() and _detect_step_front(normalized_dir):
		bot.velocity.y = max(bot.velocity.y, 3.0)
	
	# ── Vault / Step-up 2: automático para bots (strafe) ──
	if bot.is_on_floor() and _vault_controller and not _vault_controller.is_vaulting():
		var v_time: float = Time.get_ticks_msec() / 1000.0
		if _vault_controller.try_vault(normalized_dir, v_time):
			pass  # Vault iniciado
	
	# RVO avoidance nativo (NavigationServer3D)
	if agent and agent.avoidance_enabled:
		agent.set_velocity(desired)
		bot.velocity.x = _rvo_safe_velocity.x
		bot.velocity.z = _rvo_safe_velocity.z
		# NO usar RVO Y — preservar Y del sistema de movimiento
		if abs(desired.y) > 0.01:
			bot.velocity.y = desired.y
	else:
		bot.velocity.x = desired.x
		bot.velocity.z = desired.z
		bot.velocity.y = desired.y


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
## CRÍTICO: NO sobrescribir velocity.y — el sistema de movimiento la necesita
## para escalar rampas, step-up assist y auto-jump.
func _on_agent_velocity_computed(safe_velocity: Vector3) -> void:
	_rvo_safe_velocity = safe_velocity
	# Aplicar al bot si está vivo y el movimiento lo usa
	if bot and not bot.is_dead:
		var preserve_y: float = bot.velocity.y
		bot.velocity.x = safe_velocity.x
		bot.velocity.z = safe_velocity.z
		bot.velocity.y = preserve_y  # Preservar Y — NO sobrescribir


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
	# Si está en una rampa, duplicar el threshold para evitar falsos stuck
	# porque el progreso en pendiente es más lento y el detector se dispara
	# prematuramente mientras el bot está subiendo correctamente.
	if _is_on_ramp():
		threshold *= 2.0
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
	var checked_dir: Vector3
	
	# Si está en una rampa, la dirección de recuperación debe ser HACIA el objetivo
	# (seguir subiendo/bajando la rampa) en lugar de alejarse.
	# En rampas, el stuck suele ser por progreso lento, no por obstáculo real.
	if _is_on_ramp() and goal != Vector3.ZERO:
		away_dir = (goal - bot.global_position).normalized()
		away_dir.y = 0.0
		if away_dir.length_squared() < 0.001:
			away_dir = Vector3(1.0, 0.0, 0.0)
		# Verificar con raycast que la dirección no tenga pared
		checked_dir = _find_free_direction(away_dir.normalized())
		if checked_dir != Vector3.ZERO:
			stuck_recovery_dir = checked_dir
		else:
			stuck_recovery_dir = away_dir.normalized()
		return
	
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
	checked_dir = _find_free_direction(away_dir.normalized())
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
		else:
			stuck_blocking_bot = closest
			stuck_blocked_duration = 0.0
	else:
		stuck_blocking_bot = null
		stuck_blocked_duration = 0.0


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
			and is_instance_valid(bot.decision_sys.target_entity) \
			and bot.decision_sys.target_entity.is_inside_tree():
				return bot.decision_sys.target_entity.global_position
	return Vector3.ZERO


func _get_current_behavior_name() -> String:
	# Usar DecisionSystem si está disponible
	if bot and bot.decision_sys and bot.decision_sys.current_state:
		return bot.decision_sys.current_state.state_name
	return "unknown"


# ══════════════════════════════════════════════════════════════════
# STEP-UP ASSIST — Raycasts para escalones/rampas
# ══════════════════════════════════════════════════════════════════

## Detecta si hay un escalón/obstáculo subible delante del bot.
## Similar al step-up assist del player, pero simplificado.
## Retorna true si hay un escalón y el bot debe recibir impulso vertical.
func _detect_step_front(move_dir: Vector3) -> bool:
	if bot == null or move_dir.length_squared() < 0.01:
		return false
	
	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	if space_state == null:
		return false
	
	# Radio de cápsula (lee de CollisionShape3D si está disponible)
	var capsule_radius: float = 0.65
	if bot.has_node("CollisionShape3D"):
		var shape_node: CollisionShape3D = bot.get_node("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is CapsuleShape3D:
			capsule_radius = shape_node.shape.radius
	
	var check_dist: float = capsule_radius + 0.3
	
	# ── RAY BAJO: detecta cara vertical del escalón ──
	var low_origin: Vector3 = bot.global_position + Vector3(0, 0.15, 0)
	var low_end: Vector3 = low_origin + move_dir * check_dist
	var low_query = PhysicsRayQueryParameters3D.create(low_origin, low_end)
	low_query.collision_mask = bot.collision_mask
	low_query.exclude = [bot]
	var low_hit: Dictionary = space_state.intersect_ray(low_query)
	
	# ── RAY ALTO: verifica espacio libre arriba del escalón ──
	var top_h: float = capsule_radius * 1.2
	var high_origin: Vector3 = bot.global_position + Vector3(0, top_h, 0)
	var high_end: Vector3 = high_origin + move_dir * check_dist
	var high_query = PhysicsRayQueryParameters3D.create(high_origin, high_end)
	high_query.collision_mask = bot.collision_mask
	high_query.exclude = [bot]
	var high_hit: Dictionary = space_state.intersect_ray(high_query)
	
	# Step detectado: bajo impacta (cara vertical) Y alto NO impacta (paso libre)
	if not low_hit.is_empty() and high_hit.is_empty():
		if low_hit.normal.y < 0.3:  # Cara vertical
			return true
	
	return false


## Detecta si delante del bot hay una superficie inclinada (rampa)
## en lugar de un escalón vertical.
## Útil para diferenciar entre:
##   - Rampa (normal.y > 0.3): el bot debe escalar suavemente
##   - Escalón (normal.y < 0.3): el bot necesita step-up o salto
## Retorna true si delante hay una rampa/subida inclinada.
func _detect_ramp_ahead(move_dir: Vector3) -> bool:
	if bot == null or move_dir.length_squared() < 0.01:
		return false
	
	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	if space_state == null:
		return false
	
	# Radio de cápsula
	var capsule_radius: float = 0.65
	if bot.has_node("CollisionShape3D"):
		var shape_node: CollisionShape3D = bot.get_node("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is CapsuleShape3D:
			capsule_radius = shape_node.shape.radius
	
	var check_dist: float = capsule_radius + 0.3
	
	# Raycast desde el centro del bot hacia adelante
	var origin: Vector3 = bot.global_position + Vector3(0, capsule_radius * 0.5, 0)
	var end: Vector3 = origin + move_dir * check_dist
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = bot.collision_mask
	query.exclude = [bot]
	var hit: Dictionary = space_state.intersect_ray(query)
	
	if hit.is_empty():
		return false
	
	# Una rampa tiene normal con componente Y significante (> 0.3 = ~72° desde vertical)
	# Un escalón tiene normal.y < 0.3 (casi vertical)
	return hit.normal.y > 0.3


## Detecta si hay un escalón BAJABLE delante del bot.
## Dispara raycasts en diagonal hacia abajo para verificar:
## 1. Que haya un hueco vertical delante (espacio libre horizontal)
## 2. Que haya superficie caminable más abajo
## 3. Que la distancia de caída sea razonable (< STEP_DOWN_MAX_HEIGHT)
##
## Retorna true si hay un escalón bajable y el bot debe descender.
func _detect_step_down(move_dir: Vector3) -> bool:
	if bot == null or move_dir.length_squared() < 0.01:
		return false
	
	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	if space_state == null:
		return false
	
	# Radio de cápsula
	var capsule_radius: float = 0.65
	if bot.has_node("CollisionShape3D"):
		var shape_node: CollisionShape3D = bot.get_node("CollisionShape3D") as CollisionShape3D
		if shape_node and shape_node.shape is CapsuleShape3D:
			capsule_radius = shape_node.shape.radius
	
	var check_dist: float = capsule_radius + 0.3  # Distancia para detectar el borde
	
	# ── RAY 1: Horizontal desde media altura ──
	# Verifica que HAY una superficie/pared delante (el borde del escalón)
	var mid_origin: Vector3 = bot.global_position + Vector3(0, capsule_radius * 0.6, 0)
	var mid_end: Vector3 = mid_origin + move_dir * check_dist
	var mid_query = PhysicsRayQueryParameters3D.create(mid_origin, mid_end)
	mid_query.collision_mask = bot.collision_mask
	mid_query.exclude = [bot]
	var mid_hit: Dictionary = space_state.intersect_ray(mid_query)
	
	# Si no hay nada delante, es espacio vacío (no es escalón bajable)
	if mid_hit.is_empty():
		return false
	
	# ── RAY 2: Diagonal hacia abajo desde el borde ──
	# Busca suelo más abajo en la dirección de movimiento
	var edge_pos: Vector3 = mid_hit.position  # Punto de impacto del borde
	var down_dir: Vector3 = (move_dir * 0.3 + Vector3.DOWN * 0.5).normalized()
	var down_dist: float = STEP_DOWN_MAX_HEIGHT * 1.5
	var down_end: Vector3 = edge_pos + down_dir * down_dist
	var down_query = PhysicsRayQueryParameters3D.create(edge_pos, down_end)
	down_query.collision_mask = bot.collision_mask
	down_query.exclude = [bot]
	var down_hit: Dictionary = space_state.intersect_ray(down_query)
	
	if down_hit.is_empty():
		return false  # No hay suelo abajo
	
	# ── RAY 3: Vertical descendente ──
	# Verifica la altura exacta del suelo respecto al bot
	var height_to_floor: float = bot.global_position.y - down_hit.position.y
	if height_to_floor < 0.25 or height_to_floor > STEP_DOWN_MAX_HEIGHT:
		# Demasiado cerca (no es escalón) o muy lejos (caída peligrosa)
		return false
	
	# Verificar que el suelo detectado es caminable (no muy inclinado)
	if down_hit.normal.y < 0.7:  # ~45° máximo
		return false
	
	return true


## Verifica si el bot está actualmente sobre una superficie inclinada (rampa).
## Retorna true si el ángulo del suelo supera los 5°.
func _is_on_ramp() -> bool:
	if bot == null or not bot.is_on_floor():
		return false
	
	var floor_normal: Vector3 = bot.get_floor_normal()
	if floor_normal == Vector3.ZERO:
		return false
	
	# Ángulo entre el normal del suelo y Vector3.UP
	var angle_rad: float = acos(clamp(floor_normal.dot(Vector3.UP), -1.0, 1.0))
	return angle_rad > deg_to_rad(5.0)


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
