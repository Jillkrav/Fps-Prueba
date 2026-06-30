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


func _init() -> void:
	behavior_name = "patrol"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ BotBehavior
# ══════════════════════════════════════════════════════════════════

func get_priority(_brain: BotBrain) -> float:
	# Comportamiento por defecto: siempre disponible
	return PRIORITY_PATROL


func enter(brain: BotBrain) -> void:
	_objective_reached = false
	# Resetear nav target para que recalcule ruta al entrar
	brain.bot._nav_target = Vector3.ZERO
	brain.reset_stuck()


func execute(brain: BotBrain, delta: float) -> void:
	var role: TacticalRole = brain.get_tactical_role()
	
	# ── 1. Verificar radio defensivo ───────────────────────────────
	if _check_defense_radius(brain, role, delta):
		return
	
	# ── 2. Verificar pickups cercanos ─────────────────────────────
	if brain.check_pickups(delta):
		return
	
	# ── 3. Decidir: ir al core enemigo o deambular ────────────────
	var has_core: bool = _has_valid_core(brain)
	var should_patrol: bool = _should_patrol_instead(role)
	
	if has_core and not should_patrol:
		_execute_advance_to_core(brain, delta, role)
	else:
		_execute_wander(brain, delta, role)


# ══════════════════════════════════════════════════════════════════
# RADIO DEFENSIVO
# ══════════════════════════════════════════════════════════════════

## Si el bot tiene radio defensivo y está muy lejos de la base,
## redirige hacia ella.
func _check_defense_radius(brain: BotBrain, role: TacticalRole, delta: float) -> bool:
	if role and role.base_defense_radius > 0.0:
		var own_core: Node = brain.get_own_core()
		if own_core and is_instance_valid(own_core) and own_core.is_inside_tree():
			var dist_to_base: float = brain.bot.global_position.distance_to(own_core.global_position)
			if dist_to_base > role.base_defense_radius:
				if brain.bot._nav_target == Vector3.ZERO or brain.bot.navigation_agent.is_navigation_finished():
					brain.set_route_target(own_core.global_position)
				brain.navigate_with_route(delta, brain.role_speed(4.5), own_core.global_position)
				return true
	return false


# ══════════════════════════════════════════════════════════════════
# DECISIÓN: PATRULLAR vs AVANZAR
# ══════════════════════════════════════════════════════════════════

## ¿El core enemigo es un objetivo válido?
func _has_valid_core(brain: BotBrain) -> bool:
	var core: Node = brain.get_enemy_core()
	return core != null and is_instance_valid(core) and core.is_inside_tree() \
		and not core.get("is_destroyed")


## ¿Debemos patrullar en lugar de ir directamente al core?
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

func _execute_advance_to_core(brain: BotBrain, delta: float, role: TacticalRole) -> void:
	var core: Node = brain.get_enemy_core()
	if core == null:
		_execute_wander(brain, delta, role)
		return
	
	var dist_to_core: float = brain.bot.global_position.distance_to(core.global_position)
	
	if dist_to_core < 4.0:
		_objective_reached = true
	
	# Establecer nuevo destino cuando: es la primera vez o llegamos
	if brain.bot._nav_target == Vector3.ZERO or _objective_reached:
		brain.set_route_target(core.global_position)
		_objective_reached = false
	
	var speed: float = brain.role_speed(4.5)
	brain.navigate_with_route(delta, speed, core.global_position)


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: DEAMBULAR / PATRULLAR
# ══════════════════════════════════════════════════════════════════

func _execute_wander(brain: BotBrain, delta: float, role: TacticalRole) -> void:
	var wander_radius: float = _get_wander_radius(role)
	
	if brain.bot._nav_target == Vector3.ZERO or brain.bot.navigation_agent.is_navigation_finished():
		var nav_map_rid: RID = brain.bot.navigation_agent.get_navigation_map()
		var raw_target: Vector3 = brain.bot.global_position + Vector3(
			randf_range(-wander_radius, wander_radius), 0,
			randf_range(-wander_radius, wander_radius))
		if NavigationServer3D.map_is_active(nav_map_rid):
			brain.bot._nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
		else:
			brain.bot._nav_target = raw_target
		brain.bot.navigation_agent.target_position = brain.bot._nav_target
	
	brain.navigate_to(brain.bot._nav_target, brain.role_speed(3.5), delta)


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

## Devuelve el radio de deambulación según el rol.
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
