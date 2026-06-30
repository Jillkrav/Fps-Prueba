# scripts/ai/behaviors/behavior_combat.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO DE COMBATE
#
# Maneja el combate cuerpo a cuerpo y a distancia con enemigos.
# Reemplaza los estados ATTACKING y TACTICAL_MOVE de la FSM original.
# Se activa cuando hay un enemigo visible y el rol decide atacar.
#
# ── SUB-FASES INTERNAS ──
# - CHASE:     Persigue al enemigo (NAVEGACIÓN)
# - STRAFE:    Combate evasivo lateral (MOVIMIENTO DIRECTO)
# - RETREAT:   Retirada táctica (NAVEGACIÓN)
# - CORE:      Ataca el core enemigo
#
# ── MIGRADO A DECISIONCONTEXT (FASE 5) ──
# Cada sub-fase escribe en el DecisionContext:
# - CHASE / RETREAT / CORE (lejos) → movimiento NAVEGAR
# - STRAFE / CORE (cerca)          → movimiento DIRECTO o HOLD
# La lógica de combate (strafe jumps, aim, shoot) sigue aquí,
# solo cambia CÓMO se escribe la intención de movimiento.
#
# ── PRIORIDAD ──
# 100 si hay enemigo visible y debemos atacar
# ──────────────────────────────────────────────────────────────────
extends BotBehavior
class_name BehaviorCombat


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Prioridad de combate (la más alta del sistema)
const PRIORITY_COMBAT: float = 100.0

## Distancia mínima para recalcular ruta de persecución
const CHASE_RECALC_DIST: float = 5.0


# ══════════════════════════════════════════════════════════════════
# ENUM — Sub-fases de combate
# ══════════════════════════════════════════════════════════════════

enum CombatPhase { CHASE, STRAFE, RETREAT, CORE_ATTACK }


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

var phase: int = CombatPhase.CHASE

# Strafe
var _strafe_direction: int = 1
var _last_strafe_change: float = 0.0

# Core attack
var _core_target_last: Vector3 = Vector3.ZERO

# Chase
var _chase_target_last: Vector3 = Vector3.ZERO

# Retreat
var _retreat_target: Vector3 = Vector3.ZERO


func _init() -> void:
	behavior_name = "combat"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ BotBehavior
# ══════════════════════════════════════════════════════════════════

func get_priority(brain: BotBrain) -> float:
	var perception = brain.perception
	if perception == null:
		return -1.0
	
	if perception.has_visible_enemies():
		return PRIORITY_COMBAT
	
	if brain.is_attacking_core():
		return PRIORITY_COMBAT
	
	return -1.0


func enter(brain: BotBrain) -> void:
	phase = CombatPhase.CHASE
	_strafe_direction = 1 if randi() % 2 == 0 else -1
	_last_strafe_change = Time.get_ticks_msec() / 1000.0
	_chase_target_last = Vector3.ZERO
	_core_target_last = Vector3.ZERO
	_retreat_target = Vector3.ZERO
	
	if brain.is_attacking_core():
		phase = CombatPhase.CORE_ATTACK
	
	brain.context.flags.behavior_name = behavior_name


func execute(brain: BotBrain, delta: float) -> void:
	# Resetear context para evitar arrastrar intenciones de frames
	# anteriores si salimos temprano por validación fallida
	brain.context.movement.reset()
	brain.context.combat.reset()
	
	if not _validate_target(brain):
		return
	
	var role: TacticalRole = brain.get_tactical_role()
	
	# ── Retirada táctica ──────────────────────────────────────────
	if _check_retreat(brain, role, delta):
		return
	
	# ── Actualizar sub-fase ───────────────────────────────────────
	var dist: float = brain.dist_to_target()
	var engage_min: float = role.preferred_engagement_min if role else 5.0
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	
	if brain.is_attacking_core():
		phase = CombatPhase.CORE_ATTACK
	elif dist > engage_max:
		phase = CombatPhase.CHASE
	else:
		phase = CombatPhase.STRAFE
	
	# ── Ejecutar sub-fase ─────────────────────────────────────────
	match phase:
		CombatPhase.CHASE:
			_execute_chase(brain, role)
		CombatPhase.STRAFE:
			_execute_strafe(brain, role, dist, engage_min, engage_max)
		CombatPhase.CORE_ATTACK:
			_execute_core_attack(brain, role)
	
	brain.context.flags.behavior_name = behavior_name


func exit(_brain: BotBrain) -> void:
	_chase_target_last = Vector3.ZERO
	_core_target_last = Vector3.ZERO
	_retreat_target = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN DEL OBJETIVO
# ══════════════════════════════════════════════════════════════════

func _validate_target(brain: BotBrain) -> bool:
	if brain.is_attacking_core():
		var core: Node = brain.get_enemy_core()
		if core == null or not is_instance_valid(core) or not core.is_inside_tree():
			brain.reevaluate_enemies()
			return false
		if core.get("is_destroyed") == true:
			brain.reevaluate_enemies()
			return false
		return true
	
	if not brain.has_target():
		return false
	
	if brain.is_target_dead():
		brain.reevaluate_enemies()
		return false
	
	return true


# ══════════════════════════════════════════════════════════════════
# RETIRADA TÁCTICA
# ══════════════════════════════════════════════════════════════════

func _check_retreat(brain: BotBrain, _role: TacticalRole, _delta: float) -> bool:
	var role: TacticalRole = brain.get_tactical_role()
	if role == null:
		return false
	
	var hp: float = brain.health_pct()
	var should_retreat: bool = role.should_retreat(
		hp,
		brain.dist_to_own_core(),
		role.base_defense_radius > 0.0
	)
	
	if not should_retreat:
		return false
	
	var own_core: Node = brain.get_own_core()
	if own_core and is_instance_valid(own_core):
		var fallback: Vector3 = role.get_fallback_position(
			own_core.global_position, brain.bot.global_position)
		var dist_to_fb: float = brain.bot.global_position.distance_to(fallback)
		
		# Escribir en context: navegar hacia el punto de retirada
		_retreat_target = fallback
		brain.context.movement.set_navigate(_retreat_target, brain.role_speed(5.0))
		brain.context.flags.behavior_name = behavior_name
		
		if dist_to_fb < 3.0:
			phase = CombatPhase.CHASE
			brain.reevaluate_enemies()
		return true
	
	return false


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CHASE (persecución)
# ══════════════════════════════════════════════════════════════════

func _execute_chase(brain: BotBrain, role: TacticalRole) -> void:
	var target: Node3D = brain.bot.target_enemy
	if target == null:
		return
	
	# Apuntar al centro del objetivo
	var aim_pos: Vector3 = target.global_position
	if target is CharacterBody3D:
		aim_pos += Vector3.UP * 1.2
	else:
		aim_pos += Vector3.UP * 0.7
	brain.context.combat.aim_target = aim_pos
	
	# Disparar mientras perseguimos
	var dist: float = brain.dist_to_target()
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	if dist <= engage_max * 1.5 and brain.bot._weapon and brain.bot._weapon.can_fire():
		brain.context.combat.wants_to_shoot = true
	
	# Navegar hacia el enemigo (recalcular ruta si se movió mucho)
	var speed: float = brain.role_speed(5.5)
	var current_target: Vector3 = target.global_position
	
	if _chase_target_last == Vector3.ZERO or \
	   current_target.distance_to(_chase_target_last) > CHASE_RECALC_DIST:
		_chase_target_last = current_target
	
	brain.context.movement.set_navigate(_chase_target_last, speed)


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: STRAFE (combate evasivo)
# ══════════════════════════════════════════════════════════════════

func _execute_strafe(brain: BotBrain, role: TacticalRole,
	dist: float, engage_min: float, engage_max: float) -> void:
	
	var target: Node3D = brain.bot.target_enemy
	if target == null:
		return
	
	# Apuntar
	brain.context.combat.aim_target = target.global_position + Vector3.UP * 1.2
	
	# Cambio de strafe
	var strafe_interval: float = role.strafe_change_interval if role else 2.0
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_strafe_change > randf_range(strafe_interval * 0.5, strafe_interval * 1.5):
		_strafe_direction *= -1
		_last_strafe_change = now
		var jump_chance: float = role.jump_frequency if role else 0.0
		if randf() < jump_chance and brain.bot.is_on_floor():
			brain.bot.velocity.y = 5.0
	
	# Movimiento lateral + ajuste de distancia
	var dir_to_enemy: Vector3 = (target.global_position - brain.bot.global_position).normalized()
	var side_dir: Vector3 = dir_to_enemy.cross(Vector3.UP) * _strafe_direction
	
	var move_vec: Vector3 = side_dir
	if dist < engage_min:
		move_vec -= dir_to_enemy * 0.5
	elif dist > engage_max:
		move_vec += dir_to_enemy * 0.5
	
	var speed: float = brain.role_speed(5.0)
	
	# STRAFE usa movimiento DIRECTO (no pathfinding) porque es
	# movimiento táctico de combate. NavigationSystem solo pasa
	# el vector a velocity sin intervenir.
	brain.context.movement.set_direct(move_vec, speed)
	
	# Disparar
	brain.context.combat.wants_to_shoot = true


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CORE_ATTACK (atacar objetivo principal)
# ══════════════════════════════════════════════════════════════════

func _execute_core_attack(brain: BotBrain, role: TacticalRole) -> void:
	var core: Node = brain.get_enemy_core()
	if core == null or not is_instance_valid(core):
		brain.reevaluate_enemies()
		return
	
	var target_pos: Vector3 = core.global_position + Vector3.UP * 0.7
	brain.context.combat.aim_target = target_pos
	
	var dist: float = brain.bot.global_position.distance_to(core.global_position)
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	
	if dist > engage_max:
		# Lejos del core: navegar hacia él
		_core_target_last = core.global_position
		brain.context.movement.set_navigate(_core_target_last, brain.role_speed(5.0))
	else:
		# Cerca del core: disparar quieto
		brain.context.combat.wants_to_shoot = true
		brain.context.movement.set_hold()
