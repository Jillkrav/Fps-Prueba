# scripts/ai/states/state_combat.gd
# ──────────────────────────────────────────────────────────────────
# STATE_COMBAT — Raíz de combate
#
# Estado principal de combate. Gestiona sub-estados internos
# (CHASE, STRAFE, CORE_ATTACK, RETREAT) inspirados en UT99.
#
# Comportamiento migrado de BehaviorCombat.
#
# ── TRANSICIONES DE SALIDA ──
# → HUNTING:   Si perdemos el objetivo pero hay memoria
# → ROAMING:   Si no hay objetivo ni memoria
# → RETREATING: Si la salud es muy baja
# ──────────────────────────────────────────────────────────────────
extends BotState
class_name StateCombat


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Distancia mínima para recalcular ruta de persecución
const CHASE_RECALC_DIST: float = 5.0

## Tiempo máximo (segundos) que el bot sigue combatiendo sin ver al objetivo.
## Si el enemigo se esconde detrás de un obstáculo más de este tiempo,
## el bot transiciona a HUNTING para perseguir la última posición conocida.
## Esto evita que el bot se quede "wallhackeando" (disparando a través de paredes).
const MAX_TIME_WITHOUT_LOS: float = 2.0


# ══════════════════════════════════════════════════════════════════
# ENUM — Sub-fases de combate
# ══════════════════════════════════════════════════════════════════

enum CombatPhase { NONE, CHASE, STRAFE, RETREAT, CORE_ATTACK }


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## Sub-fase actual de combate
var phase: int = CombatPhase.CHASE

# Strafe
var _strafe_direction: int = 1
var _last_strafe_change: float = 0.0

# LOS tracking
## Tiempo acumulado (segundos) sin línea de visión hacia el objetivo.
## Se reinicia a 0 cada vez que el objetivo vuelve a ser visible.
var _time_without_los: float = 0.0

# Core attack
var _core_target_last: Vector3 = Vector3.ZERO

# Chase
var _chase_target_last: Vector3 = Vector3.ZERO

# Retreat
var _retreat_target: Vector3 = Vector3.ZERO



func _init() -> void:
	state_type = StateType.COMBAT
	state_name = "combat"


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA DEL ESTADO
# ══════════════════════════════════════════════════════════════════

func enter(_previous_state: BotState) -> void:
	phase = CombatPhase.CHASE
	_strafe_direction = 1 if randi() % 2 == 0 else -1
	_last_strafe_change = Time.get_ticks_msec() / 1000.0
	_chase_target_last = Vector3.ZERO
	_core_target_last = Vector3.ZERO
	_retreat_target = Vector3.ZERO
	_time_without_los = 0.0

	# Si estamos atacando core, ir directamente a esa fase
	if bot and bot._is_attacking_core:
		phase = CombatPhase.CORE_ATTACK

	# Equipar arma al entrar en combate (Fase 4)
	if bot and bot.weapon_equip_state:
		bot.weapon_equip_state.equip()

	# ── Hook: notificar al rol que entramos en combate (FASE 7) ──
	if bot and bot._tactical_role:
		bot._tactical_role.on_combat_start(bot)
		# También notificar detección de enemigo si tenemos objetivo
		if decision_system and decision_system.target_entity:
			bot._tactical_role.on_enemy_detected(bot, decision_system.target_entity)


func execute(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return

	# ── 1. Verificar transiciones de salida ──
	if _check_exit_transitions():
		return
	
	# Necesidades críticas y recarga bajo fuego tienen prioridad sobre atacar.
	if bot.tactical_sys != null and bot.tactical_sys.should_force_flee():
		change_state(BotState.StateType.FLEEING)
		return
	if bot.tactical_sys != null and bot.tactical_sys.requires_cover_for_reload():
		change_state(BotState.StateType.COVER_RELOAD)
		return

	# ── 2. Validar objetivo ──
	if not _validate_target():
		# Sin objetivo válido — salir de combate
		if _has_enemy_memory():
			# Hay memoria del enemigo: ir a HUNTING en lugar de ROAMING
			change_state(BotState.StateType.HUNTING)
		else:
			change_state(BotState.StateType.ROAMING)
		return

	# ── 2b. Verificar línea de visión sostenida ──
	# Si el objetivo está vivo pero no visible (se escondió), cronometrar
	# el tiempo sin LOS. Si supera MAX_TIME_WITHOUT_LOS, transicionar a
	# HUNTING para perseguir la última posición conocida en lugar de
	# quedarse mirando/ disparando a la pared.
	if _is_target_visible():
		_time_without_los = 0.0
	else:
		_time_without_los += _delta
		if _time_without_los > MAX_TIME_WITHOUT_LOS:
			_debug("Objetivo perdido de vista durante %.1fs → HUNTING" % _time_without_los)
			if _has_enemy_memory():
				change_state(BotState.StateType.HUNTING)
			else:
				# No hay memoria, volver a roaming
				change_state(BotState.StateType.ROAMING)
			return

	# ── 3. Verificar retirada táctica ──
	if _check_retreat():
		return

	# ── 4. Actualizar sub-fase según distancia ──
	_update_phase()

	# ── 5. Ejecutar sub-fase ──
	match phase:
		CombatPhase.CHASE:
			_execute_chase()
		CombatPhase.STRAFE:
			_execute_strafe()
		CombatPhase.CORE_ATTACK:
			_execute_core_attack()


# ══════════════════════════════════════════════════════════════════
# TRANSICIONES DE SALIDA
# ══════════════════════════════════════════════════════════════════

func _check_exit_transitions() -> bool:
	# ── ¿Salud crítica? → RETREATING ──
	if health_pct() < 0.20:
		change_state(BotState.StateType.RETREATING)
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# VALIDACIÓN DEL OBJETIVO
# ══════════════════════════════════════════════════════════════════

func _validate_target() -> bool:
	# Si estamos atacando core, verificar que el core existe
	if phase == CombatPhase.CORE_ATTACK:
		if bot and bot._enemy_core and is_instance_valid(bot._enemy_core) and bot._enemy_core.is_inside_tree():
			if bot._enemy_core.get("is_destroyed") != true:
				return true
		# Core destruido o inválido
		_re_evaluate()
		return false

	# Si tenemos objetivo en DecisionSystem, verificar que está vivo
	if has_target() and not is_target_dead():
		return true

	# Sin objetivo — verificar si hay enemigos visibles
	if perception and perception.has_visible_enemies():
		return true  # El próximo frame PerceptionSystem actualizará target

	# Sin objetivo y sin enemigos visibles
	_re_evaluate()
	return false


func _re_evaluate() -> void:
	if bot:
		bot._re_evaluar_enemigos()


# ══════════════════════════════════════════════════════════════════
# RETIRADA TÁCTICA (sub-fase dentro de combate)
# ══════════════════════════════════════════════════════════════════

func _check_retreat() -> bool:
	var role: TacticalRole = _get_role()
	if role == null:
		return false

	var should_retreat: bool = role.should_retreat(
		health_pct(),
		_dist_to_own_core(),
		role.base_defense_radius > 0.0
	)

	if not should_retreat:
		return false

	var own_core: Node = _get_own_core()
	if own_core and is_instance_valid(own_core):
		var fallback: Vector3 = role.get_fallback_position(
			own_core.global_position, bot.global_position)
		var dist_to_fb: float = bot.global_position.distance_to(fallback)

		_retreat_target = fallback
		movement_cmd.set_navigate(_retreat_target, _role_speed(5.0))

		if dist_to_fb < 3.0:
			phase = CombatPhase.CHASE
			_re_evaluate()
		return true

	return false


# ══════════════════════════════════════════════════════════════════
# ACTUALIZACIÓN DE SUB-FASE
# ══════════════════════════════════════════════════════════════════

func _update_phase() -> void:
	var role: TacticalRole = _get_role()
	var dist: float = _get_target_distance()
	var engage_max: float = role.preferred_engagement_max if role else 15.0

	# Un francotirador ya apostado tras un one_way_low_wall no abandona su
	# posición para perseguir: convierte el contacto visible en fuego estático.
	if _is_sniper_in_one_way_cover():
		phase = CombatPhase.STRAFE
		return
	if bot and bot._is_attacking_core:
		phase = CombatPhase.CORE_ATTACK
	elif dist > engage_max:
		phase = CombatPhase.CHASE
	else:
		phase = CombatPhase.STRAFE


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CHASE (persecución)
# ══════════════════════════════════════════════════════════════════

func _execute_chase() -> void:
	var target: Node3D = decision_system.target_entity if decision_system else null
	if target == null or not target.is_inside_tree():
		return

	# Apuntar y disparar mientras perseguimos
	var aim_pos: Vector3 = target.global_position
	if target is CharacterBody3D:
		aim_pos += Vector3.UP * 1.2
	else:
		aim_pos += Vector3.UP * 0.7
	combat_cmd.set_engage(aim_pos, 0)
	combat_cmd.force_fire = true  # Forzar disparo aunque el ángulo no sea perfecto

	# Navegar hacia el enemigo
	var speed: float = _role_speed(5.5)
	var current_target: Vector3 = target.global_position

	if _chase_target_last == Vector3.ZERO or \
	   current_target.distance_to(_chase_target_last) > CHASE_RECALC_DIST:
		_chase_target_last = current_target

	movement_cmd.set_navigate(_chase_target_last, speed)
	# Sprint en persecución (Fase B)
	movement_cmd.sprint = true


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: STRAFE (combate evasivo lateral)
# ══════════════════════════════════════════════════════════════════

func _execute_strafe() -> void:
	var target: Node3D = decision_system.target_entity if decision_system else null
	if target == null or not target.is_inside_tree():
		return

	var role: TacticalRole = _get_role()

	# Apuntar y disparar
	combat_cmd.set_engage(target.global_position + Vector3.UP * 1.2, 0)
	combat_cmd.force_fire = true  # Forzar disparo aunque el ángulo no sea perfecto

	# El francotirador debe conservar su puesto tras el muro bajo orientado.
	if _is_sniper_in_one_way_cover():
		movement_cmd.set_hold()
		return

	# Cambiar dirección de strafe periódicamente
	var strafe_interval: float = role.strafe_change_interval if role else 2.0
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_strafe_change > randf_range(strafe_interval * 0.5, strafe_interval * 1.5):
		_strafe_direction *= -1
		_last_strafe_change = now
		# Salto táctico durante strafe (solo en rango cerrado < 5m)
		var jump_chance: float = role.jump_frequency if role else 0.0
		if jump_chance > 0.0 and _get_target_distance() < 5.0 and randf() < jump_chance and bot.is_on_floor():
			movement_cmd.queue_jump()

	# Movimiento lateral + ajuste de distancia
	var dir_to_enemy: Vector3 = (target.global_position - bot.global_position).normalized()
	var side_dir: Vector3 = dir_to_enemy.cross(Vector3.UP) * _strafe_direction

	# Desde un muro bajo o tronera, mantener la cobertura y disparar con
	# micro-strafe. La semántica llega por los props reutilizables y no fuerza
	# ninguna escena/mapa a tenerlos.
	if _is_using_peek_cover():
		side_dir *= 0.45

	var dist: float = _get_target_distance()
	var engage_min: float = role.preferred_engagement_min if role else 5.0
	var engage_max: float = role.preferred_engagement_max if role else 15.0

	var move_vec: Vector3 = side_dir
	if dist < engage_min:
		move_vec -= dir_to_enemy * 0.5  # Alejarse
	elif dist > engage_max:
		move_vec += dir_to_enemy * 0.5  # Acercarse

	var speed: float = _role_speed(5.0)
	movement_cmd.set_direct(move_vec, speed)
	movement_cmd.is_strafing = true  # Metadata para sistema de animación
	
	# ── Crouch táctico: agacharse al strafear a quemarropa (< 5m) ──
	if dist < 5.0:
		movement_cmd.crouch = true
	else:
		movement_cmd.crouch = false


# ══════════════════════════════════════════════════════════════════
# SUB-FASE: CORE_ATTACK (atacar core enemigo)
# ══════════════════════════════════════════════════════════════════

func _execute_core_attack() -> void:
	if bot == null or bot._enemy_core == null:
		_re_evaluate()
		return

	var core: Node = bot._enemy_core
	if not is_instance_valid(core) or not core.is_inside_tree():
		_re_evaluate()
		return

	var target_pos: Vector3 = core.global_position + Vector3.UP * 0.7
	combat_cmd.set_engage(target_pos, 0)
	combat_cmd.force_fire = true

	var dist: float = bot.global_position.distance_to(core.global_position)
	var role: TacticalRole = _get_role()
	var engage_max: float = role.preferred_engagement_max if role else 15.0

	if dist > engage_max:
		# Lejos del core: navegar hacia él (sprint)
		_core_target_last = core.global_position
		movement_cmd.set_navigate(_core_target_last, _role_speed(5.0))
		movement_cmd.sprint = true
	else:
		# Cerca del core: disparar quieto
		movement_cmd.set_hold()


# ══════════════════════════════════════════════════════════════════
# EVENTOS
# ══════════════════════════════════════════════════════════════════

func on_see_player(player: Node3D) -> void:
	# Actualizar target al jugador detectado
	if player is CharacterBody3D:
		if decision_system:
			decision_system.target_entity = player
		# Mantener fase actual (no resettear)


func on_take_damage(_amount: float, attacker: Node3D) -> void:
	if bot != null and bot.tactical_sys != null:
		bot.tactical_sys.notify_damage(attacker)
	# Si no tenemos objetivo y alguien nos ataca, responder
	if not has_target() and attacker and is_instance_valid(attacker):
		if decision_system:
			decision_system.target_entity = attacker
		phase = CombatPhase.CHASE


func exit(_next_state: BotState) -> void:
	_chase_target_last = Vector3.ZERO
	_core_target_last = Vector3.ZERO
	_retreat_target = Vector3.ZERO
	_time_without_los = 0.0
	combat_cmd.reset()

	# Guardar arma al salir de combate, salvo al pasar a cobertura para
	# recargar: esa transición debe conservarla equipada para iniciar la recarga.
	if bot and bot.weapon_equip_state and (_next_state == null or _next_state.state_type != BotState.StateType.COVER_RELOAD):
		bot.weapon_equip_state.unequip()


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

func _dist_to_own_core() -> float:
	if bot:
		return bot._get_dist_to_own_core()
	return 0.0

func _get_target_distance() -> float:
	return dist_to_target()

func _role_speed(base_speed: float) -> float:
	if bot:
		return bot._role_speed(bot._tactical_role, base_speed)
	return base_speed

## Verifica si el objetivo actual está visible (tiene línea de visión).
## Consulta el sistema de percepción que ya procesa LOS con dual raycast.
func _is_using_peek_cover() -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var peek_points: Array[Node] = bot.get_tree().get_nodes_in_group(&"peek_cover_points")
	for point: Node in peek_points:
		if point != null and is_instance_valid(point) and point.is_inside_tree():
			if bot.global_position.distance_to(point.global_position) <= 2.6:
				return true
	return false


## Comprueba si el bot está apostado cerca del lado seguro de un muro bajo
## de un sentido. Se basa en la API del prop para no acoplar combate a escenas.
func _is_sniper_in_one_way_cover() -> bool:
	var role: TacticalRole = _get_role()
	if bot == null or role == null or role.type != Roles.Type.FRANCOTIRADOR or not bot.is_inside_tree():
		return false
	var covers: Array[Node] = bot.get_tree().get_nodes_in_group(&"cover_points")
	for cover: Node in covers:
		if cover == null or not is_instance_valid(cover) or not cover.is_inside_tree():
			continue
		var parent: Node = cover.get_parent()
		if parent == null or not parent.has_method("supports_one_way_cover"):
			continue
		if not bool(parent.call("supports_one_way_cover")):
			continue
		if bot.global_position.distance_to(cover.global_position) <= 2.6:
			return true
	return false


func _is_target_visible() -> bool:
	if perception == null or decision_system == null:
		return false
	if not decision_system.has_target():
		return false
	var target: Node3D = decision_system.target_entity
	if not is_instance_valid(target):
		return false
	# Revisar si el objetivo está en la lista de enemigos visibles
	for entry in perception.visible_enemies:
		if entry.get("body", null) == target:
			return true
	return false

## Verifica si hay recuerdos de enemigos en el sistema de memoria.
## Útil para decidir si transicionar a HUNTING o ROAMING.
func _has_enemy_memory() -> bool:
	if memory == null:
		return false
	return memory.has_enemy_memory()
