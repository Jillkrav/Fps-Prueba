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
var _hunt_initialized: bool = false


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
	_hunt_initialized = false
	
	var perception = brain.perception
	if perception:
		_hunt_target = perception.get_last_known_enemy_position()


func execute(brain: BotBrain, delta: float) -> void:
	# Si durante la caza reaparece un enemigo visible, el brain
	# cambiará automáticamente a COMBAT por la prioridad mayor
	
	if _hunt_target == Vector3.ZERO:
		# No hay nada que cazar
		brain.reevaluate_enemies()
		return
	
	# Inicializar ruta de caza
	if not _hunt_initialized:
		brain.set_route_target(_hunt_target)
		_hunt_initialized = true
	
	# Navegar hacia la última posición conocida
	brain.navigate_with_route(delta, brain.role_speed(6.0), _hunt_target)
	
	# Verificar si hemos llegado
	if brain.bot.global_position.distance_to(_hunt_target) <= brain.bot.navigation_agent.target_desired_distance:
		# Llegamos pero no encontramos al enemigo
		_hunt_initialized = false
		brain.reevaluate_enemies()
	
	# Apuntar en la dirección de caza mientras nos movemos
	brain.aim_at(_hunt_target)


func exit(_brain: BotBrain) -> void:
	_hunt_initialized = false
	_hunt_target = Vector3.ZERO
