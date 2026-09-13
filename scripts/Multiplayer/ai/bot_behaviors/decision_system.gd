# scripts/ai/decision_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE DECISIÓN — FSM JERÁRQUICA (FASE 3)
#
# Reemplaza a BotBrain + Behaviors como motor de decisión.
# Es el ÚNICO escritor de:
#   - target_entity
#   - movement_command (MovementCommand)
#   - combat_command (CombatCommand)
#   - focus_point
#
# ── FLUJO ──
#   1. process(delta): evaluar transiciones, ejecutar estado actual
#   2. El estado actual escribe en movement_command, combat_command
#   3. DecisionSystem envía comandos a MovementSystem
#   4. MovementSystem los ejecuta y ESCRIBE velocity
#
# ── NUNCA ESCRIBE ──
#   velocity, weapon_state, sensor_data, memory_store
# ──────────────────────────────────────────────────────────────────
extends Node
class_name DecisionSystem


# ══════════════════════════════════════════════════════════════════
# ANTI-FLAP (PROBLEMA 1)
# ══════════════════════════════════════════════════════════════════

## Debounce global: un estado debe estar activo al menos este tiempo antes de
## permitir otra transición de estado, para evitar ping-pong rápido como
## COMBAT ↔ RETREATING ↔ FLEEING cuando varias condiciones coinciden a la vez.
## Cuando un bot recibe muchas señales simultáneas, se asienta en un estado en
## lugar de oscilar de un lado a otro cada frame.
const MIN_STATE_RESIDENCY: float = 0.6


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando la FSM cambia de estado.
signal state_changed(old_state: BotState, new_state: BotState)

## Se emite cuando se selecciona un nuevo objetivo.
signal target_selected(entity_id: int)

## Se emite cuando se emite un comando.
signal command_issued(cmd_type: String)


# ══════════════════════════════════════════════════════════════════
# PROPIETARIO DE (solo él escribe)
# ══════════════════════════════════════════════════════════════════

## Objetivo actual del bot (enemigo o core).
## ÚNICO escritor: DecisionSystem (o sus estados).
var target_entity: Node3D = null:
	set(value):
		if target_entity != value:
			target_entity = value
			if value != null:
				target_selected.emit(value.get_instance_id())

## Comando de movimiento (leído por MovementSystem).
## ÚNICO escritor: DecisionSystem (o sus estados).
var movement_command: MovementCommand = MovementCommand.new()

## Comando de combate (leído por CombatSystem).
## ÚNICO escritor: DecisionSystem (o sus estados).
var combat_command: CombatCommand = CombatCommand.new()

## Punto focal hacia dónde mirar.
## ÚNICO escritor: DecisionSystem (o sus estados).
var focus_point: Vector3 = Vector3.ZERO

## Solicitud de atención reactiva emitida por PerceptionSystem/BotBase.
## DecisionSystem la traduce a CombatCommand para conservar una única ruta de mando.
var _attention_position: Vector3 = Vector3.ZERO
var _attention_turn_speed: float = 0.0
var _attention_expires_at: float = 0.0


# ══════════════════════════════════════════════════════════════════
# FSM STATE
# ══════════════════════════════════════════════════════════════════

## Estado actual de la FSM.
var current_state: BotState = null

## Estado anterior (útil para transiciones).
var previous_state: BotState = null

## Tiempo en el estado actual.
var time_in_state: float = 0.0

## Mapa de todos los estados registrados: StateType → BotState
var _states: Dictionary = {}


# ══════════════════════════════════════════════════════════════════
# REFERENCIAS A SISTEMAS (lectura)
# ══════════════════════════════════════════════════════════════════

var bot: BotBase = null
var perception_sys: PerceptionSystem = null
var memory_sys: MemorySystem = null
var movement_sys: MovementSystem = null
var navigation_sys: NavigationSystem = null
var combat_sys: CombatSystem = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	bot = get_parent() as BotBase
	perception_sys = get_node_or_null("../PerceptionSystem") as PerceptionSystem
	memory_sys = get_node_or_null("../MemorySystem") as MemorySystem
	movement_sys = get_node_or_null("../MovementSystem") as MovementSystem
	navigation_sys = get_node_or_null("../NavigationSystem") as NavigationSystem
	combat_sys = get_node_or_null("../CombatSystem") as CombatSystem

	# Registrar estados hijos (creados por BotBase)
	_register_child_states()

	# Estado inicial: Roaming
	if _states.size() > 0:
		_change_state(BotState.StateType.ROAMING)


## Registra todos los nodos BotState hijos como estados de la FSM.
func _register_child_states() -> void:
	for child in get_children():
		if child is BotState:
			var state: BotState = child as BotState
			state.decision_system = self
			_states[state.state_type] = state


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado desde BotBase._physics_process()
# ══════════════════════════════════════════════════════════════════

## Procesa la decisión del bot este frame.
## FASE 3 del flujo: después de percepción/memoria, antes de movimiento.
func process(delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── 1. Resetear comandos transitorios ──
	movement_command.reset()
	combat_command.reset()
	# Limpiar comandos pendientes (FASE 3 — no heredar saltos/dodges viejos)
	movement_command._clear_pending()

	# ── 2. Las necesidades críticas interrumpen cualquier estado ──
	if bot != null and bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		if not is_in_state(BotState.StateType.FLEEING):
			change_state(BotState.StateType.FLEEING)
	elif bot != null and bot.tactical_sys != null and bot.tactical_sys.requires_cover_for_reload():
		if not is_in_state(BotState.StateType.FLEEING) and not is_in_state(BotState.StateType.COVER_RELOAD):
			change_state(BotState.StateType.COVER_RELOAD)
	
	# ── 3. Ejecutar estado actual ──
	if current_state:
		time_in_state += delta
		current_state.execute(delta)

	# ── 3b. Watchdog: evitar estados pegados ──
	# Si un estado lleva más de max_duration sin salir por sus propios medios
	# (por ejemplo, una ruta inalcanzable o un recurso inexistente), forzamos
	# la transición a timeout_fallback para que el bot nunca se quede bugeado
	# repitiendo lo mismo. ROAMING (max_duration=INF) nunca se ve afectado.
	if current_state and current_state.max_duration != INF \
			and time_in_state > current_state.max_duration:
		current_state.on_timeout_forced()
		_debug_decision("Watchdog: %s superó %.1fs → %s" % [
			current_state.state_name,
			current_state.max_duration,
			BotState.StateType.keys()[current_state.timeout_fallback]])
		change_state(current_state.timeout_fallback)

	# ── 3. Atención reactiva: mirar primero, evaluar combate después ──
	_apply_attention_command()

	# ── 4. Validar comandos ──
	_validate_commands()

	# ── 5. Procesar solicitud de dodge (CombatSystem → DecisionSystem) ──
	_evaluate_dodge_request()

	# ── 6. Enviar comandos a sistemas ──
	_push_commands()


## Solicita mirar hacia una amenaza que todavía no está dentro del POV del arma.
## Si ya hay combate activo, no lo pisa: el objetivo confirmado conserva prioridad.
func request_attention(target_pos: Vector3, turn_speed: float, duration: float) -> void:
	if bot == null or bot.is_dead or target_pos == Vector3.ZERO:
		return
	if _has_live_character_target():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var expires_at: float = now + maxf(duration, 0.0)
	if expires_at >= _attention_expires_at or turn_speed > _attention_turn_speed:
		_attention_position = target_pos
		_attention_turn_speed = maxf(turn_speed, 0.0)
		_attention_expires_at = expires_at


## Inserta la orden temporal de atención en el comando de combate del tick actual.
func _apply_attention_command() -> void:
	if _attention_position == Vector3.ZERO:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now >= _attention_expires_at:
		_clear_attention()
		return
	if _has_live_character_target():
		_clear_attention()
		return
	if combat_command.engage:
		return
	combat_command.set_attention(
		_attention_position,
		_attention_turn_speed,
		_attention_expires_at - now)


func _clear_attention() -> void:
	_attention_position = Vector3.ZERO
	_attention_turn_speed = 0.0
	_attention_expires_at = 0.0


func _has_live_character_target() -> bool:
	return has_target() and target_entity is CharacterBody3D and not is_target_dead()


## Evalúa solicitudes de dodge del CombatSystem.
## CombatSystem marca wants_dodge cuando cree que debería esquivar.
## DecisionSystem decide si concede (peligro de caer/etc) o deniega.
func _evaluate_dodge_request() -> void:
	if combat_sys == null:
		return
	if not combat_sys.wants_dodge:
		return
	if combat_sys.dodge_state != CombatSystem.DodgeState.DODGING:
		combat_sys.deny_dodge()
		return

	# ── Evaluar si es seguro esquivar ──
	# Solo conceder si:
	# 1. No estamos en modo NONE/HOLD (no tiene sentido esquivar si no nos movemos)
	# 2. No hay peligro de caer (podríamos añadir raycast más adelante)

	var should_grant: bool = true

	# No dodge si ya tenemos un comando de movimiento prioritario
	if movement_command.mode == MovementCommand.Mode.NAVIGATE:
		# Esquivar durante navegación puede ser útil
		should_grant = true

	if should_grant:
		# Conceder dodge: cola comandos pendientes (FASE 3 — persisten entre ticks)
		movement_command.queue_dodge(combat_sys.dodge_direction, 10.0)
		# Incluir salto si el CombatSystem lo indica (daño recibido en rango cercano)
		if combat_sys.dodge_with_jump:
			movement_command.queue_jump(7.0)
		combat_sys.confirm_dodge()
		_debug_decision("Dodge CONCEDIDO: %s" % str(combat_sys.dodge_direction.round()))
	else:
		combat_sys.deny_dodge()
		_debug_decision("Dodge DENEGADO")


## Valida coherencia de los comandos antes de enviarlos.
func _validate_commands() -> void:
	# No disparar sin objetivo válido
	if combat_command.engage and not has_target():
		combat_command.cease_fire = true
		combat_command.engage = false

	# NAVIGATE requiere un destino explícito; Vector3.ZERO es una coordenada
	# authored válida y no debe usarse como centinela de "sin destino".
	if movement_command.mode == MovementCommand.Mode.NAVIGATE:
		if not movement_command.has_target_position:
			movement_command.mode = MovementCommand.Mode.NONE


## Envía los comandos a los sistemas correspondientes.
func _push_commands() -> void:
	# ── Movement ──
	if movement_sys and movement_command.mode != MovementCommand.Mode.NONE:
		movement_sys.set_command(movement_command)
		command_issued.emit("movement")

	# ── Focus point (debug / info, el aiming real lo hace CombatSystem) ──
	if has_target() and is_instance_valid(target_entity):
		focus_point = target_entity.global_position + Vector3.UP * 1.2
	elif combat_command.aim_at_position != Vector3.ZERO:
		focus_point = combat_command.aim_at_position

	# Emitir comando de combate si hay acción
	if combat_command.engage or combat_command.cease_fire:
		command_issued.emit("combat")

	# ── Aim + Shoot: DELEGADO a CombatSystem ──
	# CombatSystem lee combat_command y target_entity directamente.
	# Ya no llamamos bot._aim_at_target() ni bot._shoot() aquí.
	# Esto elimina VIOLACIONES de arquitectura donde DecisionSystem
	# escribía aim y disparo directamente.

	# ── Pasar combat_command a CombatSystem ──
	# El combat_command se comunica vía property (combat_sys lo lee
	# directamente de self.combat_command en su process())


# ══════════════════════════════════════════════════════════════════
# GESTIÓN DE ESTADOS (FSM)
# ══════════════════════════════════════════════════════════════════

## Cambia al estado especificado.
## Llamar desde un estado con: decision_system.change_state(type)
func change_state(new_type: int) -> void:
	if new_type == current_state.state_type if current_state else false:
		return
	# Debounce global anti-flap (problema 1): si acabamos de entrar en el estado
	# actual hace muy poco, bloqueamos la transición para que el bot se asiente
	# y no oscile entre estados. El estado puede salir por su propia lógica o el
	# watchdog; solo se retrasa el "chicle" de cambiar cada frame.
	if current_state and time_in_state < MIN_STATE_RESIDENCY:
		return
	_change_state(new_type)


## Cambio interno de estado.
func _change_state(new_type: int) -> void:
	var new_state: BotState = _states.get(new_type)
	if not new_state:
		#_debug_decision("ERROR: Estado %d no registrado" % new_type)
		return
	if new_state == current_state:
		return

	var old_state: BotState = current_state

	# Salir del estado actual
	if old_state:
		old_state.exit(new_state)
		# Resetear comandos al salir
		movement_command.reset()
		combat_command.reset()

	# Transicionar
	previous_state = old_state
	current_state = new_state
	time_in_state = 0.0

	# Entrar al nuevo estado
	current_state.enter(old_state)

	emit_signal("state_changed", old_state, new_state)
	_debug_decision("Estado: %s → %s" % [
		old_state.state_name if old_state else "null",
		new_state.state_name])


## Obtiene un estado por tipo.
func get_state(type: int) -> BotState:
	return _states.get(type)


## Verifica si el estado actual es de un tipo específico.
func is_in_state(type: int) -> bool:
	return current_state != null and current_state.state_type == type


# ══════════════════════════════════════════════════════════════════
# CONSULTAS DE ESTADO (para estados y sistemas externos)
# ══════════════════════════════════════════════════════════════════

## ¿Hay un objetivo enemigo vivo?
func has_target() -> bool:
	return target_entity != null \
		and is_instance_valid(target_entity) \
		and target_entity.is_inside_tree()

## ¿El objetivo actual está muerto, destruido, o fuera del árbol?
func is_target_dead() -> bool:
	if not has_target():
		return true
	if not target_entity.is_inside_tree():
		return true
	if target_entity.has_method("is_queued_for_deletion") and target_entity.is_queued_for_deletion():
		return true
	if target_entity.get("is_dead") == true:
		return true
	if target_entity.get("is_destroyed") == true:
		return true
	return false

## Distancia al objetivo (o INF si no hay).
func dist_to_target() -> float:
	if has_target() and bot and bot.is_inside_tree():
		return bot.global_position.distance_to(target_entity.global_position)
	return INF

## Salud del bot como porcentaje (0.0 - 1.0).
func health_pct() -> float:
	if bot and bot.max_health > 0:
		return bot.current_health / bot.max_health
	return 0.0

## Nombre del estado actual para debug.
func debug_string() -> String:
	return "Decision[%s time=%.1fs target=%s]" % [
		current_state.state_name if current_state else "null",
		time_in_state,
		str(target_entity.get("_npc_id") if target_entity else "none"),
	]


# ══════════════════════════════════════════════════════════════════
# MANEJADORES DE EVENTOS (delegados al estado actual)
# ══════════════════════════════════════════════════════════════════

## Un jugador/NPC entró en nuestro campo de visión.
func notify_see_player(player: Node3D) -> void:
	if current_state:
		current_state.on_see_player(player)

## Escuchamos un ruido.
func notify_hear_noise(loudness: float, source: Vector3) -> void:
	if current_state:
		current_state.on_hear_noise(loudness, source)

## Recibimos daño.
func notify_take_damage(amount: float, attacker: Node3D) -> void:
	if current_state:
		current_state.on_take_damage(amount, attacker)

## El bot chocó contra una pared.
func notify_hit_wall(normal: Vector3) -> void:
	if current_state:
		current_state.on_hit_wall(normal)

## El movement_system detectó atasco.
func notify_stuck_detected(phase: int, cause: String) -> void:
	if current_state:
		current_state.on_stuck_detected(phase, cause)

## El movement_system reportó llegada a destino.
func notify_destination_reached() -> void:
	if current_state:
		current_state.on_destination_reached()


# ══════════════════════════════════════════════════════════════════
# DEBUG
# ══════════════════════════════════════════════════════════════════

func _debug_decision(msg: String) -> void:
	if bot:
		bot._debug("[Decision] " + msg)
