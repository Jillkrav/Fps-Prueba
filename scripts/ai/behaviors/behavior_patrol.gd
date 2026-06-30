# scripts/ai/behaviors/behavior_patrol.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO DE PATRULLA
#
# Comportamiento por defecto cuando no hay enemigos ni objetivos
# urgentes. El bot navega hacia el core enemigo (objetivo principal)
# o deambula si no hay core disponible.
#
# También maneja:
# - Radio defensivo: si el bot tiene base_defense_radius, vuelve
#   a la base cuando se aleja demasiado
# - Pickups: busca armas y munición
# - Rutas diversificadas: cada bot se aproxima desde ángulos distintos
#
# ── MIGRADO A DECISIONCONTEXT (FASE 5) ──
# Escribe en DecisionContext para navegación.
# BotBrain._execute_context() traduce a NavigationSystem.
#
# ── PRIORIDAD ──
# 10 (siempre activo como comportamiento por defecto)
# ──────────────────────────────────────────────────────────────────
extends BotBehavior
class_name BehaviorPatrol


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

const PRIORITY_PATROL: float = 10.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

var _objective_reached: bool = false
var _nav_target: Vector3 = Vector3.ZERO


func _init() -> void:
	behavior_name = "patrol"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ BotBehavior
# ══════════════════════════════════════════════════════════════════

func get_priority(_brain: BotBrain) -> float:
	return PRIORITY_PATROL


func enter(brain: BotBrain) -> void:
	_objective_reached = false
	_nav_target = Vector3.ZERO
	brain.context.movement.reset()
	brain.context.flags.behavior_name = behavior_name


func execute(brain: BotBrain, _delta: float) -> void:
	var role: TacticalRole = brain.get_tactical_role()
	
	# ── 1. Verificar radio defensivo ───────────────────────────────
	if _check_defense_radius(brain, role):
		return
	
	# ── 2. Verificar pickups cercanos ─────────────────────────────
	# NOTA: check_pickups todavía usa API antigua internamente.
	# Cuando se refactorice, reemplazar con context writes.
	if brain.check_pickups(_delta):
		return
	
	# ── 3. Decidir: ir al core enemigo o deambular ────────────────
	var has_core: bool = _has_valid_core(brain)
	var should_patrol: bool = _should_patrol_instead(role)
	
	if has_core and not should_patrol:
		_advance_to_core(brain, role)
	else:
		_wander(brain, role)
	
	# Escribir en el context para BotBrain._execute_context()
	brain.context.flags.behavior_name = behavior_name


# ══════════════════════════════════════════════════════════════════
# RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

func _check_defense_radius(brain: BotBrain, _role: TacticalRole) -> bool:
	var role: TacticalRole = brain.get_tactical_role()
	if role and role.base_defense_radius > 0.0:
		var own_core: Node = brain.get_own_core()
		if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
			var dist_to_base: float = brain.bot.global_position.distance_to(own_core.global_position)
			if dist_to_base > role.base_defense_radius:
				_nav_target = own_core.global_position
				brain.context.movement.set_navigate(_nav_target, brain.role_speed(4.5))
				return true
	return false


# ══════════════════════════════════════════════════════════════════
# DECISIÓN: PATRULLAR vs AVANZAR
# ══════════════════════════════════════════════════════════════════

func _has_valid_core(brain: BotBrain) -> bool:
	var core: Node = brain.get_enemy_core()
	return core != null and is_instance_valid(core) and core.is_inside_tree() \
		and not core.get("is_destroyed")


func _should_patrol_instead(role: TacticalRole) -> bool:
	if role == null:
		return randf() < 0.3
	
	match role.movement_profile:
		TacticalRole.MovementProfile.PATROL:
			return randf() < 0.4
		TacticalRole.MovementProfile.DEFENSIVE:
			return randf() < 0.3
		_:
			return randf() < 0.2


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: AVANZAR AL CORE ENEMIGO
# ══════════════════════════════════════════════════════════════════

func _advance_to_core(brain: BotBrain, role: TacticalRole) -> void:
	var core: Node = brain.get_enemy_core()
	if core == null:
		_wander(brain, role)
		return
	
	var dist_to_core: float = brain.bot.global_position.distance_to(core.global_position)
	
	if dist_to_core < 4.0:
		_objective_reached = true
	
	if _nav_target == Vector3.ZERO or _objective_reached:
		_nav_target = core.global_position
		_objective_reached = false
	
	var speed: float = brain.role_speed(4.5)
	brain.context.movement.set_navigate(_nav_target, speed)


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: DEAMBULAR / PATRULLAR
# ══════════════════════════════════════════════════════════════════

func _wander(brain: BotBrain, role: TacticalRole) -> void:
	var wander_radius: float = _get_wander_radius(role)
	var nav: NavigationSystem = brain.navigation
	
	if _nav_target == Vector3.ZERO or (nav != null and nav.is_navigation_finished()):
		var nav_map_rid: RID
		if nav != null and nav.agent != null:
			nav_map_rid = nav.agent.get_navigation_map()
		elif brain.bot.navigation_agent != null:
			nav_map_rid = brain.bot.navigation_agent.get_navigation_map()
		else:
			nav_map_rid = RID()
		
		var raw_target: Vector3 = brain.bot.global_position + Vector3(
			randf_range(-wander_radius, wander_radius), 0,
			randf_range(-wander_radius, wander_radius))
		
		if nav_map_rid.is_valid() and NavigationServer3D.map_is_active(nav_map_rid):
			_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		else:
			_nav_target = raw_target
	
	brain.context.movement.set_navigate(_nav_target, brain.role_speed(3.5))


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

func _get_wander_radius(role: TacticalRole) -> float:
	if not role:
		return 20.0
	match role.movement_profile:
		TacticalRole.MovementProfile.DEFENSIVE:
			return 10.0
		TacticalRole.MovementProfile.AGGRESSIVE:
			return 25.0
		TacticalRole.MovementProfile.FLANKING:
			return 22.0
		TacticalRole.MovementProfile.PATROL:
			return 18.0
		_:
			return 20.0
