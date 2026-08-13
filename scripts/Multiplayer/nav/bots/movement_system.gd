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

# Las señales stuck_detected, stuck_resolved y path_blocked
# viven en StuckHandler (stuck_handler.gd) que es quien las emite.


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

# Gravedad (inicializada en _ready para evitar parse error con const)
var _gravity: float = 9.8

# ── Gait thresholds (fracción de la velocidad máxima) ──
## Por debajo de esta fracción de max_speed se considera WALK.
const GAIT_WALK_THRESHOLD: float = 0.35
## Por debajo de esta fracción se considera RUN; por encima SPRINT.
const GAIT_SPRINT_THRESHOLD: float = 0.85

# ── Stuck detection: delegado a StuckHandler.gd (FASE 2) ─────────
# Toda la lógica de stuck recovery se maneja en stuck_handler.gd.
# Las constantes STUCK_PROGRESS_THRESHOLD, RECOVERY_PHASE*_DURATION
# y STUCK_BLOCKED_TRIGGER_TIME viven allá. Estas están obsoletas.
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


# ══════════════════════════════════════════════════════════════════
# ENUM — Gait (intensidad de movimiento para animación)
# ══════════════════════════════════════════════════════════════════

## Clasificación del tipo de paso para el sistema de animación.
enum MovementGait {
	IDLE = 0,    # Velocidad casi nula (velocity.length() < epsilon)
	WALK = 1,    # Velocidad baja (andar)
	RUN = 2,     # Velocidad media (correr)
	SPRINT = 3,  # Velocidad alta (esprintar)
	CROUCH = 4,  # Agachado (idle o en movimiento reducido)
}


# RVO avoidance (nativo de NavigationServer3D)
var _rvo_safe_velocity: Vector3 = Vector3.ZERO

# ── Superficies tácticas ────────────────────────────────────────────
# Se consulta de forma limitada, no por frame, para que mapas con muchos bots
# no paguen búsquedas de grupos innecesarias. Los AvoidFloorProp publican el
# grupo `avoid_surfaces` y exponen duck-typing para no acoplar movimiento a props.
const TACTICAL_SURFACE_RECHECK_INTERVAL: float = 0.35
var _requested_navigation_target: Vector3 = Vector3.ZERO
var _tactical_navigation_target: Vector3 = Vector3.ZERO
var _next_tactical_surface_check_time: float = 0.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Referencia al bot dueño
var bot: BotBase = null

## Comando de movimiento actual (escrito por DecisionSystem/BotBrain)
var command: MovementCommand = MovementCommand.new()

## Gait actual del bot (IDLE/WALK/RUN/SPRINT). Solo lectura para animación.
var current_gait: int = MovementGait.IDLE

## Dirección de movimiento relativa al facing del bot.
## x = lateral (-1 izquierda, 1 derecha), y = forward/back (-1 atrás, 1 adelante).
var _move_direction_rel: Vector2 = Vector2.ZERO

## Flag de landing: true el frame justo después de aterrizar.
var just_landed: bool = false
var _was_on_floor: bool = true

## Referencia al NavigationAgent3D
var agent: NavigationAgent3D = null

## Referencia al NavigationSystem (para pathfinding helper)
var nav_system: NavigationSystem = null

# ── Vault controller (step-up 2) ──
var _vault_controller: VaultController = null

# ── Auto-jump (solicitado por NavigationSystem) ──
var auto_jump_pending: bool = false
var auto_jump_velocity: float = 7.0

# ── Saltos authored ─────────────────────────────────────────────────
## Movimiento balístico breve activado por SaltoInicio. Vive aquí para que
## MovementSystem siga siendo el único escritor de velocity del bot.
const AUTHORED_JUMP_HORIZONTAL_SPEED: float = 9.0
const AUTHORED_JUMP_MIN_DURATION: float = 0.35
const AUTHORED_JUMP_MAX_DURATION: float = 1.35
const AUTHORED_JUMP_MAX_VERTICAL_SPEED: float = 12.0
const AUTHORED_JUMP_LANDING_DISTANCE: float = 2.4
var _authored_jump_active: bool = false
var _authored_jump_target: Vector3 = Vector3.ZERO
var _authored_jump_elapsed: float = 0.0
var _authored_jump_duration: float = 0.0
var _authored_jump_finish_seen: bool = false

# ── Stuck handler (unificado FASE 2) ──
## Fusiona ObstacleEvader + StuckRecovery en un solo sistema.
var stuck_handler: StuckHandler = null



# ── Navigation tracking ──
var nav_target: Vector3 = Vector3.ZERO
var route_waypoint: Vector3 = Vector3.ZERO
var route_phase: int = 0
var route_target_pos: Vector3 = Vector3.ZERO
var last_agent_target: Vector3 = Vector3.ZERO
## El comando conserva Vector3.ZERO para datos authored, pero _execute_navigate
## nunca lo entrega a NavigationAgent3D porque el nodo nativo lo rechaza.
var _has_last_agent_target: bool = false

## Dirección horizontal deseada de movimiento (hacia dónde el bot QUIERE ir,
## siguiendo el camino/navmesh). NO es la velocidad real (que RVO puede
## desviar): es lo que debe mirar el cuerpo para no avanzar de espaldas.
var _facing_dir: Vector3 = Vector3.FORWARD

# ── Barrido de vigilancia (look-around 360°) ─────────────────────────
## Referencia al nodo de la cabeza (para el barrido vertical natural).
var _head: Node3D = null
## Próximo instante (seg) para iniciar un barrido de vigilancia.
var _next_look_around_time: float = 0.0
## ¿Barrido de vigilancia en curso?
var _look_around_active: bool = false
## Ángulo (rad) que falta por girar en el barrido actual.
var _look_around_remaining: float = 0.0
## Velocidad angular del barrido actual (rad/s).
var _look_around_speed: float = 0.0
## Dirección del giro: +1 derecha (CW), -1 izquierda (CCW).
var _look_around_dir: float = 1.0
## Tiempo transcurrido del barrido actual (para el vaivén vertical).
var _look_around_elapsed: float = 0.0
## Pitch de la cabeza al iniciar el barrido (se restaura al terminar).
var _look_around_start_pitch: float = 0.0


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	bot = get_parent() as BotBase
	agent = bot.navigation_agent if bot and bot.has_node("NavigationAgent3D") else null
	nav_system = get_node_or_null("../NavigationSystem") as NavigationSystem
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	# ── Vault controller (step-up 2) ──
	_vault_controller = VaultController.new()
	_vault_controller.setup(bot)
	# Conectar RVO avoidance signal
	if agent:
		agent.velocity_computed.connect(_on_agent_velocity_computed)
		
	# ── Stuck handler (unificado FASE 2) ──
	stuck_handler = StuckHandler.new()
	stuck_handler.name = "StuckHandler"
	add_child(stuck_handler)

	# ── Barrido de vigilancia: cachear la cabeza e inicializar temporizador ──
	_head = bot.get_node_or_null("Head") as Node3D
	_next_look_around_time = Time.get_ticks_msec() / 1000.0 \
		+ randf_range(LOOK_AROUND_MIN_INTERVAL, LOOK_AROUND_MAX_INTERVAL)


## Procesa el movimiento y ESCRIBE velocity (único lugar).
## Llamar ANTES de move_and_slide().
func process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	# ── 0. Saltos authored / Vault: procesar antes del movimiento normal ──
	if _authored_jump_active:
		_process_authored_jump(delta)
		_update_gait()
		_update_move_direction()
		return
	if _vault_controller and _vault_controller.is_vaulting():
		_vault_controller.process_vault(delta, Time.get_ticks_msec() / 1000.0)
		return  # Saltar gravedad, saltos, etc.
	
	# ── 1. Leer comando de movimiento ──
	var move_mode: int = command.mode
	var move_speed: float = command.speed
	# ── Sobreescribir la velocidad según el arma del bot ──
	if bot and move_speed > 0.0 and move_mode in [MovementCommand.Mode.NAVIGATE, MovementCommand.Mode.DIRECT]:
		if bot._is_bot_firing():
			move_speed = bot._get_weapon_vd()
		else:
			move_speed = bot._get_weapon_va()
		# ── Apuntando: velocidad reducida a la mitad ──
		if bot._is_bot_aiming():
			move_speed *= 0.5
		# ── Sprint desactivado por petición del usuario (botas a velocidad normal) ──
		# if command.sprint and not command.crouch:
		# 	move_speed *= 1.4
		# ── Crouch: ×0.5 (Fase B) ──
		if command.crouch:
			move_speed *= 0.5
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
	
	
	# ── 5. Consumir comandos pendientes (persisten entre ticks de IA, FASE 3) ──
	# _pending_dodge: sobreescribe velocity.xz para evasión inmediata.
	# Persiste hasta que el bot esté en suelo y pueda ejecutarlo.
	if command._pending_dodge:
		var dodge_dir: Vector3 = command._pending_dodge_direction.normalized()
		dodge_dir.y = 0.0
		if dodge_dir.length_squared() > 0.001:
			bot.velocity.x = dodge_dir.x * command._pending_dodge_impulse
			bot.velocity.z = dodge_dir.z * command._pending_dodge_impulse
		command._pending_dodge = false
	
	# _pending_jump: se re-intenta cada frame hasta que el bot esté en el suelo.
	# Resuelve el bug donde un salto solicitado en un tick de IA se perdía
	# porque el bot no estaba en el suelo en ese frame exacto.
	if command._pending_jump and bot.is_on_floor() and not (_vault_controller and _vault_controller.is_vaulting()):
		bot.velocity.y = command._pending_jump_velocity
		command._pending_jump = false
	
	
	# ── 6. Aplicar stuck recovery si está activo ──
	if stuck_handler and stuck_handler.process_recovery(delta):
		var recovery_vel: Vector3 = stuck_handler.get_recovery_velocity()
		bot.velocity.x = recovery_vel.x
		bot.velocity.z = recovery_vel.z
	
	# ── 7. Limpiar comando (solo si no es frame persistente) ──
	# NOTA: command.reset() NO toca los campos _pending_*,
	# por lo que sobreviven entre ticks de IA.
	if move_mode != MovementCommand.Mode.NONE:
		command.reset()
	
	# ── 7. Actualizar gait y dirección de movimiento (cada frame) ──
	_update_gait()
	_update_move_direction()
	# ── 7b. Encara el cuerpo hacia la dirección de movimiento ──────────
	# Cuando el bot NAVEGA (roaming, hunting sin objetivo vivo, etc.) el
	# CombatSystem no rota el cuerpo (no apunta a nada), así que el bot
	# avanzaba de espaldas. Aquí rotamos el cuerpo hacia donde se mueve,
	# PERO solo si no estamos en combate activo, para no pelear con el
	# CombatSystem que encara al objetivo.
	_face_movement_direction(delta)
	# ── 7c. Barrido de vigilancia (giro 360° periódico) ─────────────────
	# Cada 5–7 s el bot da una vuelta completa para inspeccionar si hay
	# enemigos detrás o a los lados. Se salta en combate/disparando.
	_update_look_around(delta)


## Inicia un salto authored hacia el Area3D de aterrizaje configurada.
## Retorna false sin tocar movimiento si el destino no es viable.
func start_authored_jump(finish: SaltoFin) -> bool:
	if bot == null or finish == null or not is_instance_valid(finish) or not finish.is_inside_tree():
		return false
	if _authored_jump_active or not bot.is_on_floor():
		return false
	var destination: Vector3 = finish.global_position
	var horizontal_offset: Vector3 = destination - bot.global_position
	horizontal_offset.y = 0.0
	var horizontal_distance: float = horizontal_offset.length()
	if horizontal_distance < 0.5 or horizontal_distance > 12.0:
		return false
	var vertical_offset: float = destination.y - bot.global_position.y
	# Para saltos descendentes se reserva tiempo suficiente de caída; de otro
	# modo un trigger situado en una plataforma alta nunca alcanzaría su suelo.
	var fall_duration: float = sqrt(maxf(-2.0 * vertical_offset / _gravity, 0.0))
	var duration: float = clampf(
		maxf(horizontal_distance / AUTHORED_JUMP_HORIZONTAL_SPEED, fall_duration),
		AUTHORED_JUMP_MIN_DURATION,
		AUTHORED_JUMP_MAX_DURATION)
	var initial_vertical_speed: float = (vertical_offset + 0.5 * _gravity * duration * duration) / duration
	if initial_vertical_speed < 0.0 or initial_vertical_speed > AUTHORED_JUMP_MAX_VERTICAL_SPEED:
		return false
	_authored_jump_active = true
	_authored_jump_target = destination
	_authored_jump_elapsed = 0.0
	_authored_jump_duration = duration
	_authored_jump_finish_seen = false
	bot.velocity = horizontal_offset.normalized() * (horizontal_distance / duration)
	bot.velocity.y = initial_vertical_speed
	return true


## La zona final comunica que el bot completó el tramo authored.
func finish_authored_jump(finish: SaltoFin) -> void:
	if not _authored_jump_active or finish == null or not is_instance_valid(finish):
		return
	if finish.global_position.distance_to(_authored_jump_target) <= AUTHORED_JUMP_LANDING_DISTANCE:
		_authored_jump_finish_seen = true


func _process_authored_jump(delta: float) -> void:
	if bot == null:
		_cancel_authored_jump()
		return
	_authored_jump_elapsed += delta
	bot.velocity.y -= _gravity * delta
	var horizontal_offset: Vector3 = _authored_jump_target - bot.global_position
	horizontal_offset.y = 0.0
	if horizontal_offset.length_squared() > 0.01:
		var horizontal_speed: float = horizontal_offset.length() / maxf(_authored_jump_duration - _authored_jump_elapsed, 0.05)
		horizontal_speed = minf(horizontal_speed, AUTHORED_JUMP_HORIZONTAL_SPEED * 1.25)
		var direction: Vector3 = horizontal_offset.normalized()
		bot.velocity.x = direction.x * horizontal_speed
		bot.velocity.z = direction.z * horizontal_speed
	if (_authored_jump_finish_seen or bot.global_position.distance_to(_authored_jump_target) <= AUTHORED_JUMP_LANDING_DISTANCE) \
	and bot.is_on_floor() and bot.velocity.y <= 0.0:
		_cancel_authored_jump()
	elif _authored_jump_elapsed >= AUTHORED_JUMP_MAX_DURATION:
		_cancel_authored_jump()


func _cancel_authored_jump() -> void:
	_authored_jump_active = false
	_authored_jump_target = Vector3.ZERO
	_authored_jump_elapsed = 0.0
	_authored_jump_duration = 0.0
	_authored_jump_finish_seen = false


## Post-procesa después de move_and_slide().
## Verifica stuck, llegada a destino, etc.
func post_process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	# ── Landing detection ──
	just_landed = bot.is_on_floor() and not _was_on_floor
	_was_on_floor = bot.is_on_floor()
	
	# ── Detectar stuck (StuckHandler unificado) ──
	if stuck_handler:
		stuck_handler.post_process(delta)


# ══════════════════════════════════════════════════════════════════
# EJECUCIÓN POR MODO
# ══════════════════════════════════════════════════════════════════

## Navega usando NavigationAgent3D hacia un destino.
func _execute_navigate(delta: float, target: Vector3, speed: float) -> void:
	if agent == null:
		return
	# NavigationAgent3D no acepta Vector3.ZERO. Aunque el dato authored pueda
	# representarlo, no se permite llegar al agente: el estado debe avanzar al
	# siguiente waypoint o esperar una ruta utilizable, sin emitir errores nativos.
	if target == Vector3.ZERO:
		bot.velocity.x = move_toward(bot.velocity.x, 0.0, speed * delta * 3.0)
		bot.velocity.z = move_toward(bot.velocity.z, 0.0, speed * delta * 3.0)
		return

	var requested_target: Vector3 = target
	var effective_target: Vector3 = _resolve_tactical_navigation_target(requested_target)
	
	# Actualizar target del agente si cambió. La validez se representa mediante
	# MovementCommand.has_target_position, por lo que (0,0,0) funciona como un
	# waypoint authored legítimo.
	if command.has_target_position and (not _has_last_agent_target or effective_target != last_agent_target):
		# Última barrera: nunca asignar el vector cero al agente nativo. El comando
		# puede representarlo para rutas authored, pero si no se logró proyectar a
		# NavMesh se frena este frame y se deja que la FSM elija el siguiente nodo.
		if effective_target == Vector3.ZERO:
			bot.velocity.x = move_toward(bot.velocity.x, 0.0, speed * delta * 3.0)
			bot.velocity.z = move_toward(bot.velocity.z, 0.0, speed * delta * 3.0)
			return
		agent.target_position = effective_target
		last_agent_target = effective_target
		_has_last_agent_target = true
		nav_target = effective_target
		route_target_pos = effective_target
	
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

	# Dirección horizontal deseada (hacia dónde va el camino). Se usa para
	# orientar el cuerpo hacia el frente del camino, NO hacia la velocidad
	# (que RVO puede desviar, incluso hacia atrás).
	_facing_dir = Vector3(dir.x, 0.0, dir.z).normalized()

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
	# Suprimir si hay cobertura delante (debe cubrirse, no saltarla)
	# y si el rol no permite franquear (jump_frequency == 0).
	if on_floor and height_diff > AUTO_JUMP_HEIGHT and height_diff < AUTO_JUMP_MAX_HEIGHT \
	and _detect_step_front(dir) and not _detect_ramp_ahead(dir) \
	and _role_allows_big_climb() and not _is_cover_ahead(dir):
		auto_jump_pending = true
		# Velocidad de salto: sqrt(2*g*h) * 1.15 para compensar el frame de gravedad
		auto_jump_velocity = clamp(sqrt(2.0 * _gravity * height_diff) * 1.15, 5.0, 12.0)
	
	# ── Step-up assist: raycasts para escalones que el step-up nativo no alcanza ──
	# Similar al sistema del player, pero adaptado para bots.
	# Detecta caras verticales de escalones/rampas y aplica impulso vertical.
	# En rampas, _detect_step_front NO se activa porque el filtro normal.y < 0.3
	# excluye superficies inclinadas. _detect_ramp_ahead es el que detecta rampas.
	# Suprimido si hay cobertura delante (el bot debe refugiarse, no saltarla).
	if on_floor and _detect_step_front(dir) and not _is_cover_ahead(dir):
		bot.velocity.y = max(bot.velocity.y, STEP_ASSIST_VELOCITY)
	
	# ── Vault / Step-up 2: automático para bots ──────────────────────────
	# Para obstáculos más grandes que el step-up assist pero dentro del
	# rango vault (~0.78u a 1.56u). El VaultController detecta y ejecuta.
	# Suprimido si hay cobertura delante o el rol no permite franquear.
	if on_floor and _vault_controller and not _vault_controller.is_vaulting() \
	and _role_allows_big_climb() and not _is_cover_ahead(dir):
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


## Resuelve superficies que la IA no debe elegir como destino normal.
## Si un bot nace o queda dentro de una AvoidFloorProp, la próxima navegación
## sale primero del área; si el objetivo queda dentro, lo desvía a un borde.
## La penalización de rutas largas se deja al horneado por regiones con travel_cost,
## porque NavigationObstacle3D no modifica el pathfinding estático.
func _resolve_tactical_navigation_target(requested_target: Vector3) -> Vector3:
	if bot == null or not bot.is_inside_tree() or requested_target == Vector3.ZERO:
		return requested_target

	var now: float = Time.get_ticks_msec() / 1000.0
	var target_changed: bool = requested_target != _requested_navigation_target
	if not target_changed and now < _next_tactical_surface_check_time:
		return _tactical_navigation_target

	_requested_navigation_target = requested_target
	_next_tactical_surface_check_time = now + TACTICAL_SURFACE_RECHECK_INTERVAL
	_tactical_navigation_target = requested_target
	var surfaces: Array[Node] = bot.get_tree().get_nodes_in_group(&"avoid_surfaces")
	for surface: Node in surfaces:
		if surface == null or not is_instance_valid(surface):
			continue
		if not surface.has_method(&"is_position_inside"):
			continue

		var bot_is_inside: bool = bool(surface.call(&"is_position_inside", bot.global_position))
		if bot_is_inside and surface.has_method(&"get_exit_position"):
			_tactical_navigation_target = surface.call(
				&"get_exit_position", bot.global_position, requested_target) as Vector3
			return _tactical_navigation_target

		var target_is_inside: bool = bool(surface.call(&"is_position_inside", requested_target))
		if target_is_inside and surface.has_method(&"get_detour_position"):
			_tactical_navigation_target = surface.call(
				&"get_detour_position", requested_target, bot.global_position) as Vector3
			return _tactical_navigation_target

	return _tactical_navigation_target


## Movimiento por vector directo (strafe, retreat).
func _execute_direct(delta: float, dir: Vector3, speed: float) -> void:
	if dir.length_squared() < 0.001:
		_execute_hold(delta)
		return
	
	var normalized_dir: Vector3 = dir.normalized()
	# Ya no aplanamos Y a 0 — el bot necesita la componente vertical
	# para moverse correctamente en rampas y pendientes.
	# normalized_dir.y = 0.0

	# Dirección horizontal deseada para el facing (los DIRECT suelen ser
	# strafes/retrocesos tácticos: orientar el cuerpo hacia la dirección
	# de desplazamiento para no arrastrarse de lado o de espaldas).
	_facing_dir = Vector3(normalized_dir.x, 0.0, normalized_dir.z).normalized()

	var desired: Vector3 = normalized_dir * speed
	
	# Step-up assist para movimento directo (strafe en rampas)
	if bot.is_on_floor() and _detect_step_front(normalized_dir) and not _is_cover_ahead(normalized_dir):
		bot.velocity.y = max(bot.velocity.y, 3.0)
	
	# ── Vault / Step-up 2: automático para bots (strafe) ──
	if bot.is_on_floor() and _vault_controller and not _vault_controller.is_vaulting() \
	and _role_allows_big_climb() and not _is_cover_ahead(normalized_dir):
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


# ── Stuck detection delegada a StuckHandler ──
# (toda la lógica se movió a stuck_handler.gd en FASE 2)


# ══════════════════════════════════════════════════════════════════
# SUPRESIÓN DE FRANQUEO — Cobertura & rol
# ══════════════════════════════════════════════════════════════════
# Los bots tenían el problema de saltar/vaultear SOBRE las coberturas en
# lugar de usarlas. El _detect_step_front() y try_vault() veían la cara
# vertical de un muro (cobertura) como un obstáculo a franquear. Estas
# dos comprobaciones lo corrigen:
#   1. _is_cover_ahead(): PSA cuando hay un punto de cobertura delante en
#      la dirección de movimiento → NO saltar, ir hacia la cobertura.
#   2. _role_allows_big_climb(): gate por rol vía jump_frequency → los
#      bots solo franquean obstáculos grandes si el rol lo permite.
# El step-up assist (escalones PEQUEÑOS ≤ 0.42u) se conserva para la
# movilidad; solo se suprime el franqueo GRANDE (vault + auto-jump).

## Distancia horizontal de detección de cobertura delante del bot.
const COVER_AHEAD_REACH: float = 2.2

## Retorna true si hay un punto de cobertura delante en la dirección de
## movimiento (dentro de COVER_AHEAD_REACH). Si lo hay, el bot NO debe
## saltar/vaultear esa cobertura; debe refugiarse en su lugar.
func _is_cover_ahead(move_dir: Vector3) -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	if covers.is_empty():
		return false

	var fwd: Vector3 = move_dir
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return false
	fwd = fwd.normalized()

	var bot_pos: Vector3 = bot.global_position
	for cover: Node in covers:
		if cover == null or not is_instance_valid(cover) or not cover.is_inside_tree():
			continue
		# Posición concreta desde la que se toma cobertura (duck-typing).
		var cover_pos: Vector3 = cover.global_position
		if "get_cover_position" in cover:
			cover_pos = cover.get_cover_position()
		var to_cover: Vector3 = cover_pos - bot_pos
		to_cover.y = 0.0
		var horiz_dist: float = to_cover.length()
		if horiz_dist > COVER_AHEAD_REACH:
			continue
		to_cover = to_cover.normalized()
		# La cobertura debe estar delante (no detrás) para afectar el salto.
		if to_cover.dot(fwd) > 0.5:
			return true
	return false


## Retorna true si el rol del bot permite franquear obstáculos grandes
## (vault + auto-jump). Controlado por jump_frequency en roles.
## 0 → el bot NO salta ni vaulta (solo uso de escalones pequeños).
func _role_allows_big_climb() -> bool:
	if bot == null or bot._tactical_role == null:
		return false
	return bot._tactical_role.jump_frequency > 0.0


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


# (_is_on_ramp se movió a StuckHandler en FASE 2)


# ══════════════════════════════════════════════════════════════════
# GAIT & MOVE DIRECTION — Metadata para sistema de animación
# ══════════════════════════════════════════════════════════════════

## Actualiza el gait (IDLE/WALK/RUN/SPRINT) según la velocidad actual del bot.
## No modifica físicas — solo metadata para el sistema de animación.
func _update_gait() -> void:
	if bot == null:
		current_gait = MovementGait.IDLE
		return
	
	var speed_val: float = Vector3(bot.velocity.x, 0.0, bot.velocity.z).length()
	
	if speed_val < 0.1:
		current_gait = MovementGait.IDLE
		return
	
	# Determinar max_speed posible según modo y armas
	var max_speed: float = command.speed if command.speed > 0.0 else 6.0
	# Si el arma overridea la velocidad (VA), usarla como referencia
	if bot._is_bot_firing():
		max_speed = max(max_speed, bot._get_weapon_vd())
	else:
		max_speed = max(max_speed, bot._get_weapon_va())
	if max_speed <= 0.0:
		max_speed = 6.0
	
	var speed_frac: float = speed_val / max_speed
	
	# Crouch override: agachado siempre es CROUCH, independiente de velocidad
	if command.crouch:
		current_gait = MovementGait.CROUCH
		return
	
	# Sprint solo si el comando lo solicita explícitamente
	if command.sprint and speed_frac > GAIT_SPRINT_THRESHOLD:
		current_gait = MovementGait.SPRINT
	elif speed_frac > GAIT_WALK_THRESHOLD:
		current_gait = MovementGait.RUN
	else:
		current_gait = MovementGait.WALK


## Actualiza _move_direction_rel: dirección de movimiento relativa al facing.
## Eje X: -1 (izquierda) a 1 (derecha)
## Eje Y: -1 (atrás) a 1 (adelante)
func _update_move_direction() -> void:
	if bot == null:
		_move_direction_rel = Vector2.ZERO
		return
	
	var move_dir: Vector3 = Vector3(bot.velocity.x, 0.0, bot.velocity.z)
	if move_dir.length_squared() < 0.001:
		_move_direction_rel = Vector2.ZERO
		return
	
	move_dir = move_dir.normalized()
	var facing_dir: Vector3 = -bot.global_transform.basis.z  # Forward del bot
	
	# Producto punto: qué tanto va hacia adelante (1) o atrás (-1)
	var forward_amount: float = move_dir.dot(facing_dir)
	forward_amount = clampf(forward_amount, -1.0, 1.0)
	
	# Producto cruz: componente lateral (positivo = derecha)
	var right_dir: Vector3 = facing_dir.cross(Vector3.UP).normalized()
	var lateral_amount: float = move_dir.dot(right_dir)
	lateral_amount = clampf(lateral_amount, -1.0, 1.0)
	
	_move_direction_rel = Vector2(lateral_amount, forward_amount)


## Retorna la dirección de movimiento relativa al facing del bot.
## x = lateral (-1 izq, 1 der), y = forward/back (-1 atrás, 1 adelante).
func get_move_direction() -> Vector2:
	return _move_direction_rel


# ══════════════════════════════════════════════════════════════════
# ORIENTACIÓN DEL CUERPO (FACING)
# ══════════════════════════════════════════════════════════════════

## Velocidad de giro del cuerpo hacia la dirección de movimiento (rad/s).
const TURN_SPEED: float = 10.0

## Intervalo aleatorio entre barridos de vigilancia (5–7 s).
const LOOK_AROUND_MIN_INTERVAL: float = 5.0
const LOOK_AROUND_MAX_INTERVAL: float = 7.0
## Velocidad angular base del barrido: ~360° en ~2.3 s.
const LOOK_AROUND_BASE_SPEED: float = 2.7
## Variación de velocidad angular por barrido (rad/s).
const LOOK_AROUND_SPEED_VARIATION: float = 0.9
## Fracción del giro usada para acelerar al inicio y frenar al final.
const LOOK_AROUND_EASE_FRACTION: float = 0.18
## Amplitud del barrido vertical de la cabeza (rad).
const LOOK_AROUND_HEAD_PITCH_AMP: float = deg_to_rad(16.0)
## Frecuencia del vaivén vertical de la cabeza (rad/s).
const LOOK_AROUND_HEAD_PITCH_FREQ: float = 2.4

## Retorna true si el bot está en combate activo (con un objetivo vivo o un
## comando de mira explícito). En esos casos el CombatSystem es quien controla
## la rotación del cuerpo encarando al objetivo, así que MovementSystem NO debe
## pelear por el facing.
func _bot_is_in_combat() -> bool:
	if bot == null or bot.decision_sys == null:
		return false
	# Objetivo vivo presente → el CombatSystem encara al objetivo.
	if bot.decision_sys.has_target():
		return true
	# Comando de mira hacia un punto concreto (p.ej. hunting) → el
	# CombatSystem rota hacia ese punto.
	var cc: CombatCommand = bot.decision_sys.combat_command
	if cc and cc.aim_at_position != Vector3.ZERO:
		return true
	return false


## Rota suavemente el cuerpo del bot para encarar la dirección horizontal de
## su movimiento. Se aplica solo cuando se mueve y NO está en combate activo,
## evitando que el bot avance de espaldas durante la navegación.
func _face_movement_direction(delta: float) -> void:
	if bot == null:
		return
	# Durante el barrido de vigilancia el giro lo controla _update_look_around.
	if _look_around_active:
		return
	# En combate activo el CombatSystem controla el facing → no intervenir.
	if _bot_is_in_combat():
		return
	# Solo rotar si el bot realmente se mueve horizontalmente.
	var move_h: Vector3 = Vector3(bot.velocity.x, 0.0, bot.velocity.z)
	if move_h.length_squared() < 0.01:
		return

	# Orientar hacia la dirección DESEADA (del camino/navmesh), no hacia la
	# velocidad real. La velocidad puede desviarse (RVO, jump assist) e incluso
	# apuntar hacia atrás; si miráramos hacia ella el bot se vería de espalda.
	var forward: Vector3 = _facing_dir
	if forward.length_squared() < 0.001:
		forward = move_h.normalized()
	# Yaw que orienta el forward (-Z) del bot hacia la dirección de movimiento.
	# forward = (-sin(yaw), 0, -cos(yaw)) → sin(yaw)=-forward.x, cos(yaw)=-forward.z
	var target_yaw: float = atan2(-forward.x, -forward.z)
	# Se usa rotación local porque el bot es un CharacterBody3D raíz (sin
	# parent rotated), así que local == global; además es testeable sin árbol.
	var current_yaw: float = bot.rotation.y
	var delta_yaw: float = angle_difference(current_yaw, target_yaw)
	var max_step: float = TURN_SPEED * delta
	var new_yaw: float = current_yaw + clampf(delta_yaw, -max_step, max_step)
	bot.rotation = Vector3(bot.rotation.x, new_yaw, bot.rotation.z)


# ══════════════════════════════════════════════════════════════════
# BARRIDO DE VIGILANCIA (LOOK-AROUND 360°)
# ══════════════════════════════════════════════════════════════════

## Inicia un giro completo de 360° del cuerpo mientras el bot escanea su
## entorno buscando enemigos detrás o a los lados. Se dispara cada 5–7 s
## aleatoriamente cuando el bot no está en combate ni disparando.
func _start_look_around() -> void:
	_look_around_active = true
	# Dirección aleatoria para naturalidad (60% derecha, 40% izquierda).
	_look_around_dir = 1.0 if randf() < 0.6 else -1.0
	_look_around_speed = LOOK_AROUND_BASE_SPEED + randf_range(
		-LOOK_AROUND_SPEED_VARIATION * 0.5, LOOK_AROUND_SPEED_VARIATION)
	_look_around_remaining = TAU
	_look_around_elapsed = 0.0
	if _head:
		_look_around_start_pitch = _head.rotation.x


## Actualiza el barrido de vigilancia. Se llama cada frame (no solo en el
## tick de IA) para que el giro se vea suave y continuo.
func _update_look_around(delta: float) -> void:
	if bot == null or bot.is_dead or bot.is_frozen:
		return
	# Abortar si entra en combate o vuelve a disparar: el CombatSystem toma
	# el control del facing y no debe pelearse con el giro.
	if _bot_is_in_combat() or bot._is_bot_firing():
		if _look_around_active:
			_finish_look_around(true)
		return
	if not _look_around_active:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now >= _next_look_around_time:
			_start_look_around()
		return

	# Barrido activo: frenar el avance y girar el cuerpo en el sitio.
	bot.velocity.x = move_toward(bot.velocity.x, 0.0, 12.0 * delta)
	bot.velocity.z = move_toward(bot.velocity.z, 0.0, 12.0 * delta)
	_look_around_elapsed += delta

	# Velocidad angular con suavizado al inicio/fin (acelera y frena para
	# que el giro no se vea mecánico).
	var step: float = _look_around_speed * _look_around_ease() * delta
	if step >= _look_around_remaining:
		step = _look_around_remaining
	bot.rotation = Vector3(
		bot.rotation.x,
		bot.rotation.y + _look_around_dir * step,
		bot.rotation.z)
	_look_around_remaining -= step

	# Vaivén vertical de la cabeza mientras escanea (más natural).
	if _head:
		var pitch: float = _look_around_start_pitch \
			+ sin(_look_around_elapsed * LOOK_AROUND_HEAD_PITCH_FREQ) \
			* LOOK_AROUND_HEAD_PITCH_AMP
		_head.rotation = Vector3(pitch, 0.0, 0.0)

	if _look_around_remaining <= 0.0:
		_finish_look_around(false)


## Factor de suavizado [0,1]: acelera al inicio y frena al final del giro.
func _look_around_ease() -> float:
	var total: float = TAU
	var progress: float = 1.0 - clampf(_look_around_remaining / total, 0.0, 1.0)
	var frac: float = LOOK_AROUND_EASE_FRACTION
	if progress < frac:
		return progress / frac
	if progress > 1.0 - frac:
		return (1.0 - progress) / frac
	return 1.0


## Finaliza el barrido: restaura la cabeza y reprograma el próximo.
func _finish_look_around(_abort: bool = false) -> void:
	_look_around_active = false
	if _head:
		_head.rotation = Vector3(_look_around_start_pitch, 0.0, 0.0)
	# Reprogramar el próximo barrido (5–7 s).
	_next_look_around_time = Time.get_ticks_msec() / 1000.0 \
		+ randf_range(LOOK_AROUND_MIN_INTERVAL, LOOK_AROUND_MAX_INTERVAL)


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA
# ══════════════════════════════════════════════════════════════════

## Establece el comando de movimiento desde BotBrain/DecisionSystem.
## Se copia el contenido porque DecisionSystem reutiliza y resetea su comando
## cada tick de IA. Mantener una referencia compartida hacía que los frames
## intermedios vieran Mode.NONE, pararan a algunos bots y desincronizaran RVO.
func set_command(cmd: MovementCommand) -> void:
	command.copy_from(cmd)


## ¿Está atascado? Delega al StuckHandler.
func is_stuck() -> bool:
	return stuck_handler and stuck_handler.is_in_recovery()


## Invalida el objetivo cacheado tras una recuperación. Sin esta operación,
## StuckHandler podía poner el agent sobre el bot y el siguiente comando con el
## mismo waypoint no se reenviaba por parecer igual al target anterior.
## Era una causa de bots individuales detenidos tras un reroute, especialmente
## visible al aumentar la congestión a 100 jugadores.
func invalidate_navigation_target() -> void:
	_has_last_agent_target = false
	last_agent_target = Vector3.ZERO
	if agent != null and bot != null and bot.global_position != Vector3.ZERO:
		agent.target_position = bot.global_position


## Resetea todo el estado de movimiento (útil en respawn).
func reset() -> void:
	command.reset()
	if stuck_handler:
		stuck_handler.reset()
	nav_target = Vector3.ZERO
	route_waypoint = Vector3.ZERO
	route_phase = 0
	route_target_pos = Vector3.ZERO
	last_agent_target = Vector3.ZERO
	_has_last_agent_target = false
	_requested_navigation_target = Vector3.ZERO
	_tactical_navigation_target = Vector3.ZERO
	_next_tactical_surface_check_time = 0.0
	if agent and bot != null and bot.global_position != Vector3.ZERO:
		agent.target_position = bot.global_position
