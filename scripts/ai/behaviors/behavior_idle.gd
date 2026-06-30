# scripts/ai/behaviors/behavior_idle.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO INACTIVO (IDLE)
#
# Comportamiento de último recurso: el bot se queda quieto.
# Normalmente nunca se ejecuta porque PATROL tiene prioridad más
# alta, pero sirve como estado seguro cuando el bot se inicializa
# o después de un respawn.
#
# ── MIGRADO A DECISIONCONTEXT (FASE 5) ──
# Escribe en DecisionContext. BotBrain._execute_context() traduce
# a NavigationSystem. No usa la API antigua (brain.navigate_to,
# brain.aim_at, etc.).
#
# ── PRIORIDAD ──
# 0 (mínima, solo se activa si ningún otro behavior lo hace)
# ──────────────────────────────────────────────────────────────────
extends BotBehavior
class_name BehaviorIdle


const PRIORITY_IDLE: float = 0.0


func _init() -> void:
	behavior_name = "idle"


func get_priority(_brain: BotBrain) -> float:
	return PRIORITY_IDLE


func enter(brain: BotBrain) -> void:
	brain.context.movement.set_hold()
	brain.context.flags.behavior_name = behavior_name


func execute(brain: BotBrain, _delta: float) -> void:
	brain.context.movement.set_hold()
	brain.context.flags.behavior_name = behavior_name
	brain.context.combat.wants_to_shoot = false
	brain.context.combat.aim_target = Vector3.ZERO
