# scripts/ai/states/state_hit.gd
# ──────────────────────────────────────────────────────────────────
# STATE_HIT — Stun breve al recibir daño
#
# El bot se queda quieto (HOLD) durante ~0.4s al recibir daño.
# No interrumpe el objetivo actual — al terminar el stun vuelve
# al estado que tenía antes del golpe.
#
# ── TRANSICIONES DE SALIDA ──
# → PREVIOUS:  Cuando el stun termina (vuelve a COMBAT/ROAMING/...)
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateHit


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Duración del stun en segundos.
const STUN_DURATION: float = 0.4

## Duración de la invulnerabilidad post-stun (evita cadenas).
const INVULNERABILITY_DURATION: float = 0.2

## Malla de seguridad para el stun. El stun ya tiene su propio timer (0.4s),
## pero este tope garantiza que el bot nunca quede bloqueado si algo falla.
const HIT_STATE_TIMEOUT: float = 2.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tipo del estado al que volver después del stun.
var _previous_state_type: int = BotState.StateType.ROAMING

## Tiempo restante de stun.
var _stun_timer: float = 0.0



func _init() -> void:
	state_type = StateType.TAKING_HIT
	state_name = "hit_reaction"
	max_duration = HIT_STATE_TIMEOUT
	timeout_fallback = StateType.ROAMING


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(previous_state: BotState) -> void:
	if previous_state:
		_previous_state_type = previous_state.state_type
	else:
		_previous_state_type = BotState.StateType.ROAMING
	
	_stun_timer = STUN_DURATION
	
	# Detener movimiento durante el stun
	movement_cmd.set_hold()
	# No disparar durante el stun
	combat_cmd.cease_fire = true
	
	_debug("Hit! Stun %.1fs, volveré a %s" % [
		STUN_DURATION,
		BotState.StateType.keys()[_previous_state_type]
	])


func execute(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	_stun_timer -= delta
	
	# Durante el stun: mantener HOLD y cease_fire
	movement_cmd.set_hold()
	combat_cmd.cease_fire = true
	
	# ── Transición de salida: stun terminó ──
	if _stun_timer <= 0.0:
		# Volver al estado que tenía antes del golpe
		_return_to_previous_state()


func exit(_next_state: BotState) -> void:
	_stun_timer = 0.0
	# La ventana se guarda en BotBase: así sobrevive a la transición inmediata
	# desde TAKING_HIT a COMBAT/HUNTING/ROAMING y bloquea el daño de verdad.
	if bot != null:
		bot.activate_damage_reaction_immunity(INVULNERABILITY_DURATION)


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

## Decide a qué estado volver después del stun.
func _return_to_previous_state() -> void:
	if bot != null and bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return
	# Si tenemos un objetivo enemigo válido → combat
	if has_target() and not is_target_dead():
		change_state(BotState.StateType.COMBAT)
		return
	
	# Si hay enemigos visibles → combat (actualizará target)
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return
	
	# Si tenemos memoria de un enemigo → hunting
	if memory and memory.has_enemy_memory():
		change_state(BotState.StateType.HUNTING)
		return
	
	# Por defecto → roaming
	change_state(BotState.StateType.ROAMING)


# ══════════════════════════════════════════════════════════════════
# EVENTOS
# ══════════════════════════════════════════════════════════════════

func on_take_damage(_amount: float, _attacker: Node3D) -> void:
	# Mientras este estado está activo, BotBase no reinicia el stun. La ventana
	# posterior se aplica al salir mediante activate_damage_reaction_immunity().
	pass


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _debug(msg: String) -> void:
	if bot:
		bot._debug("[%s] %s" % [state_name, msg])
