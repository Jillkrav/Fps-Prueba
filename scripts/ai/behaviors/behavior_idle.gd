# scripts/ai/behaviors/behavior_idle.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO INACTIVO (IDLE)
#
# Comportamiento de último recurso: el bot se queda quieto.
# Normalmente nunca se ejecuta porque PATROL tiene prioridad más
# alta, pero sirve como estado seguro cuando el bot se inicializa
# o después de un respawn.
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
	# Siempre disponible como fallback, pero con la prioridad
	# más baja para que cualquier otro behavior lo reemplace
	return PRIORITY_IDLE


func execute(brain: BotBrain, _delta: float) -> void:
	# Frenar suavemente
	brain.bot.velocity.x = move_toward(brain.bot.velocity.x, 0, 10.0)
	brain.bot.velocity.z = move_toward(brain.bot.velocity.z, 0, 10.0)
