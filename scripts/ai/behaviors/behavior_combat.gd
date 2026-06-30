# scripts/ai/behaviors/behavior_combat.gd
# ──────────────────────────────────────────────────────────────────
# COMPORTAMIENTO DE COMBATE
#
# Maneja el combate cuerpo a cuerpo y a distancia con enemigos.
# Reemplaza los estados ATTACKING y TACTICAL_MOVE de la FSM original.
# Se activa cuando hay un enemigo visible y el rol decide atacar.
#
# ── SUB-FASES INTERNAS ──
# - CHASE:     Persigue al enemigo si está fuera del rango de combate
# - STRAFE:    Combate evasivo lateral dentro del rango preferido
# - RETREAT:   Retirada táctica (poca vida, muy lejos de base)
# - CORE:      Ataca el core enemigo
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


# ══════════════════════════════════════════════════════════════════
# ENUM — Sub-fases de combate
# ══════════════════════════════════════════════════════════════════

enum CombatPhase { CHASE, STRAFE, RETREAT, CORE_ATTACK }


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES DE INSTANCIA
# ══════════════════════════════════════════════════════════════════

var phase: int = CombatPhase.CHASE

# Variables de strafe
var _strafe_direction: int = 1
var _last_strafe_change: float = 0.0
var _jump_timer: float = 0.0
var _route_initialized: bool = false


func _init() -> void:
	behavior_name = "combat"


# ══════════════════════════════════════════════════════════════════
# INTERFAZ BotBehavior
# ══════════════════════════════════════════════════════════════════

func get_priority(brain: BotBrain) -> float:
	var perception = brain.perception
	if perception == null:
		return -1.0
	
	# Prioridad máxima si tenemos un enemigo vivo visible
	if perception.has_visible_enemies():
		return PRIORITY_COMBAT
	
	# También combatir si estamos atacando el core
	if brain.is_attacking_core():
		return PRIORITY_COMBAT
	
	# Si tenemos un objetivo vivo pero no visible (estamos en
	# medio de una persecución), el HUNT lo maneja
	return -1.0


func enter(brain: BotBrain) -> void:
	phase = CombatPhase.CHASE
	_strafe_direction = 1 if randi() % 2 == 0 else -1
	_last_strafe_change = Time.get_ticks_msec() / 1000.0
	_route_initialized = false
	_jump_timer = 0.0
	
	# Si el objetivo es el core, ir directamente a CORE_ATTACK
	if brain.is_attacking_core():
		phase = CombatPhase.CORE_ATTACK


func execute(brain: BotBrain, delta: float) -> void:
	if not _validate_target(brain):
		return
	
	var role: TacticalRole = brain.get_tactical_role()
	
	# ── Verificar retirada táctica ─────────────────────────────────
	if _check_retreat(brain, role, delta):
		return
	
	# ── Actualizar sub-fase según la distancia ─────────────────────
	var dist: float = brain.dist_to_target()
	var engage_min: float = role.preferred_engagement_min if role else 5.0
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	
	if brain.is_attacking_core():
		phase = CombatPhase.CORE_ATTACK
	elif dist > engage_max:
		phase = CombatPhase.CHASE
	else:
		phase = CombatPhase.STRAFE
	
	# ── Ejecutar sub-fase ──────────────────────────────────────────
	match phase:
		CombatPhase.CHASE:
			_execute_chase(brain, delta, role)
		CombatPhase.STRAFE:
			_execute_strafe(brain, delta, role, dist, engage_min, engage_max)
		CombatPhase.CORE_ATTACK:
			_execute_core_attack(brain, delta, role)
		# RETREAT se maneja en _check_retreat


func exit(_brain: BotBrain) -> void:
	_route_initialized = false


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN DEL OBJETIVO
# ══════════════════════════════════════════════════════════════════

## Verifica que el objetivo siga siendo válido. Retorna false si
## debemos salir del comportamiento.
func _validate_target(brain: BotBrain) -> bool:
	if brain.is_attacking_core():
		# Verificar que el core sigue existiendo
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

## Evalúa si el bot debe retirarse. Si lo hace, ejecuta la retirada
## y retorna true.
func _check_retreat(brain: BotBrain, role: TacticalRole, delta: float) -> bool:
	if role == null:
		return false
	
	# Salud muy baja + no muy agresivo = retirada
	var hp: float = brain.health_pct()
	var should_retreat: bool = role.should_retreat(
		hp,
		brain.dist_to_own_core(),
		role.base_defense_radius > 0.0
	)
	
	if not should_retreat:
		return false
	
	# Ejecutar retirada
	var own_core: Node = brain.get_own_core()
	if own_core and is_instance_valid(own_core):
		var fallback: Vector3 = role.get_fallback_position(
			own_core.global_position, brain.bot.global_position)
		var dist_to_fb: float = brain.bot.global_position.distance_to(fallback)
		
		if brain.bot._nav_target == Vector3.ZERO:
			brain.set_route_target(fallback)
		brain.navigate_with_route(delta, brain.role_speed(5.0), fallback)
		
		if dist_to_fb < 3.0:
			phase = CombatPhase.CHASE  # Reset para cuando vuelva
			brain.reevaluate_enemies()
		return true
	
	return false


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CHASE (persecución)
# ══════════════════════════════════════════════════════════════════

func _execute_chase(brain: BotBrain, delta: float, role: TacticalRole) -> void:
	var target: Node3D = brain.bot.target_enemy
	if target == null:
		return
	
	# Apuntar al centro del objetivo
	var aim_pos: Vector3 = target.global_position
	if target is CharacterBody3D:
		aim_pos += Vector3.UP * 1.2
	else:
		aim_pos += Vector3.UP * 0.7
	brain.aim_at(aim_pos)
	
	# Disparar mientras perseguimos (si está en rango)
	var dist: float = brain.dist_to_target()
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	if dist <= engage_max * 1.5 and brain.bot._weapon and brain.bot._weapon.can_fire():
		brain.shoot()
	
	# Navegar hacia el enemigo
	if brain.bot._route_target_pos == Vector3.ZERO or \
	   target.global_position.distance_to(brain.bot._route_target_pos) > 5.0:
		brain.set_route_target(target.global_position)
		_route_initialized = false
	
	brain.navigate_with_route(delta, brain.role_speed(5.5), target.global_position)


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: STRAFE (combate evasivo)
# ══════════════════════════════════════════════════════════════════

func _execute_strafe(brain: BotBrain, _delta: float, role: TacticalRole,
	dist: float, engage_min: float, engage_max: float) -> void:
	
	var target: Node3D = brain.bot.target_enemy
	if target == null:
		return
	
	# Apuntar
	brain.aim_at(target.global_position + Vector3.UP * 1.2)
	
	# Cambio de strafe influenciado por el rol
	var strafe_interval: float = role.strafe_change_interval if role else 2.0
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_strafe_change > randf_range(strafe_interval * 0.5, strafe_interval * 1.5):
		_strafe_direction *= -1
		_last_strafe_change = now
		var jump_chance: float = role.jump_frequency if role else 0.0
		if randf() < jump_chance and brain.bot.is_on_floor():
			brain.bot.velocity.y = 5.0
	
	# Calcular movimiento lateral + ajuste de distancia
	var dir_to_enemy: Vector3 = (target.global_position - brain.bot.global_position).normalized()
	var side_dir: Vector3 = dir_to_enemy.cross(Vector3.UP) * _strafe_direction
	
	var move_vec: Vector3 = side_dir
	if dist < engage_min:
		move_vec -= dir_to_enemy * 0.5   # Alejarse
	elif dist > engage_max:
		move_vec += dir_to_enemy * 0.5   # Acercarse
	
	var speed: float = brain.role_speed(5.0)
	brain.bot.velocity.x = move_vec.x * speed
	brain.bot.velocity.z = move_vec.z * speed
	
	# Disparar mientras strafeamos
	brain.try_shoot()


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CORE_ATTACK (atacar objetivo principal)
# ══════════════════════════════════════════════════════════════════

func _execute_core_attack(brain: BotBrain, delta: float, role: TacticalRole) -> void:
	var core: Node = brain.get_enemy_core()
	if core == null or not is_instance_valid(core):
		brain.reevaluate_enemies()
		return
	
	var target_pos: Vector3 = core.global_position + Vector3.UP * 0.7
	brain.aim_at(target_pos)
	
	var dist: float = brain.bot.global_position.distance_to(core.global_position)
	var engage_max: float = role.preferred_engagement_max if role else 15.0
	
	if dist > engage_max:
		# Navegar hacia el core con ruta diversificada
		if not _route_initialized:
			brain.set_route_target(core.global_position)
			brain.bot._nav_target = core.global_position
			_route_initialized = true
		brain.navigate_with_route(delta, brain.role_speed(5.0), core.global_position)
	else:
		# Cerca del core: disparar quieto
		brain.try_shoot()
		brain.bot.velocity.x = move_toward(brain.bot.velocity.x, 0, 10.0)
		brain.bot.velocity.z = move_toward(brain.bot.velocity.z, 0, 10.0)
