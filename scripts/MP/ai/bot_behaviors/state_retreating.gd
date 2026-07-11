# scripts/ai/states/state_retreating.gd
# ──────────────────────────────────────────────────────────────────
# STATE_RETREATING — Retirada táctica
#
# El bot huye hacia su base cuando la salud es crítica.
# Navega hacia el core aliado (o un punto seguro) y deja de
# disparar para priorizar la supervivencia.
#
# ── TRANSICIONES DE SALIDA ──
# → ROAMING:   Cuando la salud se recupera o llegamos a la base
# → COMBAT:    Si nos atacan durante la retirada (autodefensa)
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateRetreating


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Destino de retirada
var _retreat_target: Vector3 = Vector3.ZERO

## ¿Estamos cerca de la base?
var _near_base: bool = false


func _init() -> void:
	state_type = StateType.RETREATING
	state_name = "retreating"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	_near_base = false
	_retreat_target = Vector3.ZERO

	# Encontrar punto de retirada
	var role: TacticalRole = _get_role()
	var own_core: Node = _get_own_core()

	if own_core and is_instance_valid(own_core):
		if role:
			_retreat_target = role.get_fallback_position(
				own_core.global_position, bot.global_position)
		else:
			_retreat_target = own_core.global_position

	# No disparar durante la retirada
	if decision_system:
		decision_system.combat_command.cease_fire = true

	_debug("Retirada hacia: %s" % str(_retreat_target.round()))


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── 1. Verificar transiciones ──
	if _check_transitions():
		return

	# ── 2. Navegar hacia el punto de retirada ──
	if _retreat_target != Vector3.ZERO:
		movement_cmd.set_navigate(_retreat_target, _role_speed(5.5))

		# Verificar si hemos llegado
		var dist: float = bot.global_position.distance_to(_retreat_target)
		if dist < 3.0:
			_near_base = true
			_debug("Base alcanzada durante retirada")
			change_state(BotState.StateType.ROAMING)

	# ── 3. Apuntar hacia atrás (cubrir retirada) si hay enemigo ──
	if has_target() and is_instance_valid(decision_system.target_entity):
		var enemy_pos: Vector3 = decision_system.target_entity.global_position
		combat_cmd.set_aim(enemy_pos)


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

func _check_transitions() -> bool:
	# ── Salud recuperada → ROAMING ──
	if health_pct() > 0.50:
		_debug("Salud recuperada, volviendo a roaming")
		change_state(BotState.StateType.ROAMING)
		return true

	# ── Enemigo visible durante retirada → COMBAT (autodefensa) ──
	if perception and perception.has_visible_enemies():
		_debug("Enemigo detectado durante retirada, defendiéndose")
		change_state(BotState.StateType.COMBAT)
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# EVENTOS
# ══════════════════════════════════════════════════════════════════

func on_take_damage(_amount: float, attacker: Node3D) -> void:
	# Si nos atacan durante la retirada, responder
	if attacker and is_instance_valid(attacker) and attacker is CharacterBody3D:
		if decision_system:
			decision_system.target_entity = attacker
		change_state(BotState.StateType.COMBAT)


func exit(_next_state: BotState) -> void:
	_retreat_target = Vector3.ZERO
	_near_base = false


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

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed
