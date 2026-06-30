# scripts/ai/behaviors/behavior_hunt.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO DE CAZA (HUNT)
#
# Persigue la última posición conocida de un enemigo cuando se
# pierde el contacto visual. Inspirado en el HUNTING state de UT.
#
# Cuando el bot pierde de vista a su objetivo, en lugar de olvidarlo
# instantáneamente, se dirige a donde lo vio por última vez.
#
# Si al llegar encuentra al enemigo, transiciona a COMBAT.
# Si no encuentra nada, transiciona a PATROL.
#
# ── MIGRADO A DECISIONCONTEXT (FASE 5) ──
# Escribe en DecisionContext para navegación y apuntado.
# BotBrain._execute_context() traduce set_navigate + aim_target
# a NavigationSystem.move_to() + npc_base._aim_at_target().
#
# ── PRIORIDAD ──
# 50 si hay una posición recordada a la que ir
# ──────────────────────────────────────────────────────────────────
extends BotBehavior
class_name BehaviorHunt


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

const PRIORITY_HUNT: float = 50.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

var _hunt_target: Vector3 = Vector3.ZERO


func _init() -> void:
	behavior_name = "hunt"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ BotBehavior
# ══════════════════════════════════════════════════════════════════

func get_priority(brain: BotBrain) -> float:
	# Solo cazar si NO hay enemigos visibles (el combate tiene
	# prioridad) y tenemos una posición recordada
	var perception = brain.perception
	if perception == null:
		return -1.0
	
	if not perception.has_memory():
		return -1.0
	
	# Si hay enemigos visibles, el COMBAT los maneja
	if perception.has_visible_enemies():
		return -1.0
	
	return PRIORITY_HUNT


func enter(brain: BotBrain) -> void:
	var perception = brain.perception
	if perception:
		_hunt_target = perception.get_last_known_enemy_position()
	
	brain.context.flags.behavior_name = behavior_name


func execute(brain: BotBrain, _delta: float) -> void:
	# Si durante la caza reaparece un enemigo visible, el brain
	# cambiará automáticamente a COMBAT por la prioridad mayor
	
	if _hunt_target == Vector3.ZERO:
		# No hay nada que cazar
		brain.reevaluate_enemies()
		return
	
	# ── Escribir intenciones en el DecisionContext ──
	# BotBrain._execute_context() traducirá esto a:
	#   navigation.move_to(_hunt_target, brain.role_speed(6.0))
	#   bot._aim_at_target(_hunt_target)
	brain.context.movement.set_navigate(_hunt_target, brain.role_speed(6.0))
	brain.context.combat.aim_target = _hunt_target
	brain.context.flags.behavior_name = behavior_name
	
	# Verificar si hemos llegado (NavigationSystem maneja el resto)
	if brain.bot.global_position.distance_to(_hunt_target) <= brain.bot.navigation_agent.target_desired_distance:
		brain.reevaluate_enemies()


func exit(_brain: BotBrain) -> void:
	_hunt_target = Vector3.ZERO
