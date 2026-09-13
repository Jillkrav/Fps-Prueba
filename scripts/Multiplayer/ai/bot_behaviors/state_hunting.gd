# scripts/ai/states/state_hunting.gd
# ──────────────────────────────────────────────────────────────────
# STATE_HUNTING — Cacería (perseguir última posición conocida)
#
# Cuando el bot pierde de vista a su objetivo, en lugar de olvidarlo
# instantáneamente, se dirige a donde lo vio por última vez.
# Inspirado en el HUNTING state de UT99.
#
# Comportamiento migrado de BehaviorHunt.
#
# ── TRANSICIONES DE SALIDA ──
# → COMBAT:   Si reaparece un enemigo visible durante la cacería
# → ROAMING:  Si llegamos al destino y no encontramos nada
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateHunting


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Tiempo máximo persiguiendo la última posición conocida. Si no llega ni
## encuentra nada en ese tiempo (p.ej. ruta inalcanzable), el watchdog fuerza
## a ROAMING en lugar de quedarse navegando a un punto sin salida.
const HUNT_TIMEOUT: float = 8.0

var _hunt_target: Vector3 = Vector3.ZERO


func _init() -> void:
	state_type = StateType.HUNTING
	state_name = "hunting"
	max_duration = HUNT_TIMEOUT
	timeout_fallback = StateType.ROAMING


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	# Obtener la última posición recordada del enemigo
	if memory:
		_hunt_target = memory.get_last_enemy_position()
	_debug("Cazando posición: %s" % str(_hunt_target.round()))


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	if bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return

	# ── Si durante la caza aparece un enemigo visible → COMBAT ──
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)
		return

	# ── Si no hay destino de cacería → ROAMING ──
	if _hunt_target == Vector3.ZERO:
		change_state(BotState.StateType.ROAMING)
		return

	# ── Navegar hacia la última posición conocida ──
	movement_cmd.set_navigate(_hunt_target, _role_speed(6.0))
	movement_cmd.sprint = true  # Persecución en sprint
	combat_cmd.set_aim(_hunt_target)

	# ── Verificar si hemos llegado ──
	var desired_dist: float = bot.navigation_agent.target_desired_distance if bot.navigation_agent else 2.0
	if bot.global_position.distance_to(_hunt_target) <= desired_dist:
		# Llegamos y no vimos al enemigo — volver a roaming
		_debug("Destino de cacería alcanzado, sin contacto")
		change_state(BotState.StateType.ROAMING)


func exit(_next_state: BotState) -> void:
	_hunt_target = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# MANEJADORES DE EVENTOS
# ══════════════════════════════════════════════════════════════════

func on_see_player(_player: Node3D) -> void:
	# Si vemos a alguien durante la cacería, ir a combate directamente
	if perception and perception.has_visible_enemies():
		change_state(BotState.StateType.COMBAT)


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed
