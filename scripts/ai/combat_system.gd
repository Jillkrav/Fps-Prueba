# scripts/ai/combat_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE COMBATE MODULAR — FASE 4 REFACTORIZACIÓN
#
# ÚNICO escritor de aim_rotation en todo el NPC.
# Lee combat_command (de DecisionSystem) y lo traduce a
# aim_rotation, modo de fuego, y solicitudes de evasión.
#
# ── PROPIETARIO DE (solo él escribe) ──
#   aim_rotation (Quaternion)
#   dodge_state
#   current_target_position
#   engagement_analysis
#   wants_dodge (solicitud a DecisionSystem)
#   dodge_direction (dirección sugerida)
#
# ── LECTURA DE ──
#   combat_command (DecisionSystem)
#   target_entity (DecisionSystem)
#   weapon_status (WeaponSystem / NpcBase._weapon)
#
# ── NUNCA ESCRIBE ──
#   velocity, movement_command, target_entity
# ──────────────────────────────────────────────────────────────────
extends Node
class_name CombatSystem


# ══════════════════════════════════════════════════════════════════
# ENUMS
# ══════════════════════════════════════════════════════════════════

## Estado de evasión del bot.
enum DodgeState {
	NONE = 0,       # Sin evasión activa
	DODGING = 1,    # Evasión en curso (esperando confirmación)
	COOLDOWN = 2,   # Enfriamiento después de evadir
}


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando el arma dispara y hay resultados.
signal weapon_fired(hit_result: Array)

## Se emite cuando un objetivo entra en rango de combate.
signal target_in_range(entity_id: int, distance: float)

## Se emite cuando se pierde el rastro del objetivo actual.
signal target_lost(entity_id: int)

## El CombatSystem solicita una evasión. DecisionSystem decide si concede.
signal dodge_requested(direction: Vector3)


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Error base mínimo de puntería (grados). Los bots muy hábiles se acercan.
const AIM_ERROR_MIN_DEG: float = 0.5

## Error base máximo de puntería (grados). Bots poco hábiles.
const AIM_ERROR_MAX_DEG: float = 8.0

## Umbral de precisión para considerar que estamos apuntando al objetivo.
const AIM_ACCEPTANCE_ANGLE_DEG: float = 15.0

## Tiempo mínimo entre solicitudes de dodge.
const DODGE_COOLDOWN_TIME: float = 1.5

## Distancia a la que un enemigo se considera "en rango de combate cercano".
const CLOSE_COMBAT_RANGE: float = 5.0

## Distancia máxima para considerar un enemigo "detectable" visualmente.
const MAX_ENGAGEMENT_RANGE: float = 50.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES — PROPIETARIO
# ══════════════════════════════════════════════════════════════════

## Rotación de puntería (Quaternion). ÚNICO escritor: CombatSystem.
## Representa hacia dónde apunta el bot en el espacio 3D.
var aim_rotation: Quaternion = Quaternion.IDENTITY

## Estado de evasión actual.
var dodge_state: int = DodgeState.NONE

## Posición mundial del objetivo actual (para cálculos de puntería).
var current_target_position: Vector3 = Vector3.ZERO

## Análisis de compromiso — datos del enfrentamiento actual.
var engagement_analysis: Dictionary = {}

## Rastrea si el frame anterior teníamos un objetivo en rango (para señales).
var _had_target_in_range: bool = false

## El CombatSystem quiere que el bot esquive. DecisionSystem lee esto.
var wants_dodge: bool = false

## Intervalo mínimo entre mensajes de debug para evitar spam.
const DEBUG_COOLDOWN_SEC: float = 1.0
var _last_debug_time: float = 0.0

## Dirección sugerida para la evasión.
var dodge_direction: Vector3 = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES — INTERNAS
# ══════════════════════════════════════════════════════════════════

## Referencia al NPC dueño.
var bot: NpcBase = null

## Referencia al sistema de decisión (lee target_entity, combat_command).
var decision_sys: DecisionSystem = null

## Referencia al sistema de armas (FASE 5) — para perfiles AI.
var weapon_sys: WeaponSystem = null

## Caché de head node para rotación vertical.
var _head_node: Node3D = null

## Temporizador de enfriamiento de dodge.
var _dodge_cooldown_timer: float = 0.0


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	bot = get_parent() as NpcBase
	decision_sys = get_node_or_null("../DecisionSystem") as DecisionSystem
	weapon_sys = get_node_or_null("../WeaponSystem") as WeaponSystem
	if bot:
		_head_node = bot.get_node_or_null("Head") as Node3D
	_debug("CombatSystem listo (aim_rotation=%s, head=%s, weapon_sys=%s)" % [
		"OK" if aim_rotation != Quaternion.IDENTITY else "IDLE",
		"OK" if _head_node else "null",
		"OK" if weapon_sys else "null",
	])


## Procesa el combate y ESCRIBE aim_rotation (único lugar).
## Llamar DESPUÉS de decision_sys.process() (FASE 5 del flujo).
func process(_delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	if decision_sys == null:
		return

	# ── 1. Leer comando de combate ──
	var cmd: CombatCommand = decision_sys.combat_command
	if cmd == null:
		return

	# ── 1b. Alimentar distancia al WeaponSystem (FASE 5) ──
	if weapon_sys and decision_sys.has_target():
		weapon_sys.update_enemy_distance(decision_sys.dist_to_target())

	# ── 2. Actualizar dodge cooldown ──
	_update_dodge_cooldown(_delta)

	# ── 3. Procesar según modo ──
	if cmd.cease_fire:
		# Cesación de fuego: solo apuntar pero no disparar
		if cmd.aim_at_position != Vector3.ZERO:
			_update_aim(cmd.aim_at_position)
		else:
			# Apuntar al objetivo si existe
			_aim_at_target_entity()
		return

	if cmd.engage:
		# Modo combate ofensivo: apuntar + disparar
		var target_pos: Vector3 = _get_effective_target(cmd)
		_update_aim(target_pos)
		_check_fire_weapon(cmd)
		_check_dodge_request()
	else:
		# Solo apuntar (sin disparar)
		if cmd.aim_at_position != Vector3.ZERO:
			_update_aim(cmd.aim_at_position)
		elif decision_sys.has_target():
			_aim_at_target_entity()

	# ── 4. Actualizar engagement_analysis ──
	_update_engagement_analysis()


# ══════════════════════════════════════════════════════════════════
# CÁLCULO DE PUNTERÍA
# ══════════════════════════════════════════════════════════════════

## Obtiene la posición efectiva a la que apuntar.
## Aplica ajustes según tipo de arma (splash, hit-scan, proyectil).
func _get_effective_target(cmd: CombatCommand) -> Vector3:
	var target_pos: Vector3 = cmd.aim_at_position

	# Si tenemos target_entity vivo, apuntar a su centro
	if decision_sys and decision_sys.has_target():
		var target: Node3D = decision_sys.target_entity
		target_pos = target.global_position

		# Ajuste según tipo de entidad (humanoides vs objetos)
		if target is CharacterBody3D:
			target_pos += Vector3.UP * 0.9  # Centro del torso (cápsula 1.8m)
		else:
			target_pos += Vector3.UP * 0.7  # Centro genérico

		var weapon: Weapon = _get_weapon()

		# ── Lead prediction para proyectiles ──
		# Si el arma dispara proyectiles con velocidad, predecir
		# la posición futura del objetivo
		if weapon and weapon.velocidad_proyectil > 0.0:
			target_pos = _calculate_lead_target(target, target_pos, weapon.velocidad_proyectil)

		# ── Ajuste por splash damage ──
		# Armas con splash (cohetes, granadas) apuntan al suelo
		# cerca del objetivo, no directamente a él
		if weapon and _has_splash_damage(weapon):
			var dist: float = bot.global_position.distance_to(target_pos)
			if dist < 15.0:
				# Apuntar al suelo delante del objetivo
				target_pos.y = target.global_position.y - 0.3
			# Si está lejos, apuntar normal

	return target_pos


## Calcula la posición exacta del torso del objetivo para armas hit-scan.
## A diferencia de _get_effective_target(), esta NO aplica lead prediction
## (porque las balas viajan instantáneamente) ni ajustes de splash.
## Útil para pasar directamente al RayCast3D del arma.
func _get_hitscan_target_position(cmd: CombatCommand) -> Vector3:
	if not decision_sys or not decision_sys.has_target():
		return Vector3.ZERO

	var target: Node3D = decision_sys.target_entity
	var torso_pos: Vector3 = target.global_position

	# Ajuste al torso: centro del CharacterBody3D
	if target is CharacterBody3D:
		torso_pos += Vector3.UP * 0.9  # Centro del torso (mitad de cápsula 1.8m)
	else:
		torso_pos += Vector3.UP * 0.7

	# Si hay aim_at_position explícito del comando, usarlo como base
	if cmd.aim_at_position != Vector3.ZERO:
		torso_pos = cmd.aim_at_position
		if target is CharacterBody3D:
			torso_pos.y = target.global_position.y + 0.9

	return torso_pos


## Calcula la posición futura predicha (lead) de un objetivo en movimiento
## para armas con proyectil (VelocidadProyectil > 0).
## Fórmula: predecir dónde estará el objetivo cuando el proyectil llegue.
func _calculate_lead_target(target: Node3D, target_pos: Vector3, projectile_speed: float) -> Vector3:
	if projectile_speed <= 0.0:
		return target_pos
	# Distancia actual al objetivo
	var dist: float = bot.global_position.distance_to(target_pos)
	if dist < 0.5:
		return target_pos  # Muy cerca, no necesita lead
	# Tiempo estimado de viaje del proyectil
	var travel_time: float = dist / projectile_speed
	# Velocidad del objetivo (si es CharacterBody3D)
	var target_velocity: Vector3 = Vector3.ZERO
	if target is CharacterBody3D:
		target_velocity = target.velocity
	elif target is RigidBody3D:
		target_velocity = target.linear_velocity
	# Si el objetivo apenas se mueve, no necesita lead
	if target_velocity.length_squared() < 1.0:
		return target_pos
	# Posición futura predicha
	var predicted: Vector3 = target_pos + target_velocity * travel_time
	# Limitar la predicción a un máximo razonable para evitar overshoot
	var max_lead: float = max(dist * 0.5, 5.0)
	var lead_offset: Vector3 = predicted - target_pos
	if lead_offset.length() > max_lead:
		lead_offset = lead_offset.normalized() * max_lead
		predicted = target_pos + lead_offset
	return predicted


## Actualiza aim_rotation hacia target_pos y aplica a nodos del bot.
func _update_aim(target_pos: Vector3) -> void:
	if bot == null:
		return

	# Calcular dirección hacia el objetivo
	var direction: Vector3 = (target_pos - bot.global_position).normalized()
	if direction.length_squared() < 0.001:
		return

	# Guardar aim_rotation como Quaternion
	aim_rotation = Quaternion(Vector3.FORWARD, direction)

	# ── Aplicar a nodos del bot ──

	# Rotación horizontal del cuerpo (solo eje Y)
	var look_pos: Vector3 = target_pos
	look_pos.y = bot.global_position.y
	if bot.global_position.distance_to(look_pos) > 0.1:
		bot.look_at(look_pos, Vector3.UP)

	# Rotación vertical de la cabeza (solo pitch).
	# FIX: Evitamos head.look_at() + rotation.y = 0 porque la conversión
	# quaternion→euler puede producir ángulos incorrectos y la cabeza
	# no apunta exactamente al objetivo, causando que _is_aiming_at_target()
	# falle con ángulos > 15° aunque el bot visualmente esté apuntando.
	if _head_node:
		var head_pos: Vector3 = _head_node.global_position
		var dir_to_target: Vector3 = (target_pos - head_pos).normalized()
		if dir_to_target.length_squared() > 0.001:
			# Transformar la dirección al espacio local del cuerpo (el cuerpo
			# ya rotó para encarar al objetivo horizontalmente)
			var body_basis: Basis = bot.global_transform.basis
			var local_dir: Vector3 = body_basis.inverse() * dir_to_target
			# Calcular pitch: ángulo vertical en el plano Y-Z local
			# atan2(y, -z) porque -Z es forward en Godot
			var pitch: float = atan2(local_dir.y, -local_dir.z) if abs(local_dir.z) > 0.001 else 0.0
			# Negativo porque en Godot rotación X positiva = mirar hacia abajo
			_head_node.rotation = Vector3(-pitch, 0.0, 0.0)
			# Limitar rotación vertical para evitar que se vea antinatural
			_head_node.rotation.x = clamp(
				_head_node.rotation.x,
				deg_to_rad(-60),
				deg_to_rad(60)
			)


## Apunta al target_entity del DecisionSystem si existe.
func _aim_at_target_entity() -> void:
	if decision_sys == null or not decision_sys.has_target():
		return
	var target: Node3D = decision_sys.target_entity
	var aim_pos: Vector3 = target.global_position
	if target is CharacterBody3D:
		aim_pos += Vector3.UP * 0.9  # Centro del torso
	else:
		aim_pos += Vector3.UP * 0.7
	_update_aim(aim_pos)


# ══════════════════════════════════════════════════════════════════
# DISPARO
# ══════════════════════════════════════════════════════════════════

## Verifica si debemos disparar este frame y dispara si aplica.
func _check_fire_weapon(cmd: CombatCommand) -> void:
	var weapon: Weapon = _get_weapon()
	if weapon == null:
		_debug("_check_fire_weapon: weapon is NULL")
		return
	if not weapon.can_fire():
		_debug_rl("_check_fire_weapon: cannot fire (ammo=%d, reloading=%s)" % [
			weapon.ammo_in_mag, weapon.is_reloading])
		return
	_debug("_check_fire_weapon: weapon OK (%s ammo=%d) force_fire=%s" % [
		weapon.weapon_name, weapon.ammo_in_mag, cmd.force_fire])

	# Verificar que estamos apuntando en la dirección correcta
	if not _is_aiming_at_target():
		if not cmd.force_fire:
			_debug("_check_fire_weapon: aiming check FAILED (force_fire=false)")
			return

	# ── Configurar override de posición/dirección para proyectiles ──
	# Los proyectiles deben spawnear desde la cabeza del bot,
	# no desde el arma (para que la trayectoria coincida con aim_rotation)
	var categoria: String = weapon.categoria_municion
	var is_projectile_or_melee: bool = categoria in ["arrojadiza", "explosiva", "plasma", "cuerpo_a_cuerpo"]
	if is_projectile_or_melee:
		var launch_pos: Vector3 = _get_launch_position()
		var launch_dir: Vector3 = _get_launch_direction()
		weapon.set_shoot_override(launch_pos, launch_dir)
		_debug("Projectile fire: pos=%s dir=%s" % [str(launch_pos), str(launch_dir)])
	else:
		# ── Hit-scan: apuntar directamente al torso del objetivo ──
		# En lugar de depender de la rotación cuerpo+cabeza (que puede tener
		# desviaciones), calculamos la dirección exacta desde el arma hasta
		# el torso del objetivo y se la pasamos al RayCast3D.
		var hit_target_pos: Vector3 = _get_hitscan_target_position(cmd)
		if hit_target_pos != Vector3.ZERO:
			weapon.override_hitscan_target(hit_target_pos)
			_debug("Hitscan direct aim: target=%s" % str(hit_target_pos.round()))

	# Disparar
	var killer_id: int = -1
	if is_instance_valid(MatchManager):
		killer_id = MatchManager.get_player_id_by_pawn(bot)

	var hits: Array = weapon.fire()

	# ── Procesar hits solo para armas hit-scan ──
	# Para proyectiles/melee, el daño lo maneja ProjectileBase/Weapon
	if not is_projectile_or_melee:
		for hit in hits:
			var col: Node = hit.get("collider")
			if not col:
				continue
			var target: Node = col
			if target is Area3D:
				target = target.get_parent()
			while target and not target.has_method("take_damage"):
				target = target.get_parent()

			if target and target.has_method("take_damage"):
				if target is Player:
					target.take_damage(hit["damage_vs_player"], "Torso", killer_id)
				else:
					target.take_damage(hit["damage_vs_npc"], "Torso", killer_id)

		if hits.size() > 0:
			emit_signal("weapon_fired", hits)
	else:
		# Para proyectiles/melee, emitir señal con información de debug
		if hits.size() > 0:
			emit_signal("weapon_fired", hits)
		_debug("Proyectil/Melee disparado: %s, categoria=%s, speed=%.1f" % [
			weapon.weapon_name, categoria, weapon.velocidad_proyectil])


## Verifica si el bot está apuntando aproximadamente hacia el objetivo.
## Usa el forward de la cabeza (que tiene pitch vertical) en lugar del cuerpo
## para detectar correctamente objetivos a diferentes alturas.
## La dirección de referencia es desde la cabeza (donde está el arma) y apunta
## al torso del objetivo (mismo target_pos que _get_effective_target).
func _is_aiming_at_target() -> bool:
	if decision_sys == null or not decision_sys.has_target():
		return false
	var target: Node3D = decision_sys.target_entity
	
	# Usar el mismo target_pos que _get_effective_target para consistencia
	var aim_target_pos: Vector3 = target.global_position
	if target is CharacterBody3D:
		aim_target_pos += Vector3.UP * 0.9  # Centro del torso
	else:
		aim_target_pos += Vector3.UP * 0.7  # Centro genérico
	
	# Referencia: posición de la cabeza (donde está montada el arma)
	var reference_pos: Vector3 = _head_node.global_position if _head_node else bot.global_position
	var dir_to_target: Vector3 = (aim_target_pos - reference_pos).normalized()
	
	# Dirección forward de la cabeza (incluye pitch vertical + yaw del cuerpo)
	var aim_forward: Vector3 = -_head_node.global_transform.basis.z if _head_node else -bot.global_transform.basis.z
	
	# Para armas con proyectil (viajero), usar un ángulo más generoso porque
	# el proyectil corregirá la trayectoria con lead prediction
	var acceptance_angle: float = AIM_ACCEPTANCE_ANGLE_DEG
	var weapon: Weapon = _get_weapon()
	if weapon and weapon.categoria_municion in ["arrojadiza", "explosiva", "plasma"]:
		acceptance_angle = 25.0  # Más tolerante para proyectiles
	var angle_deg: float = rad_to_deg(aim_forward.angle_to(dir_to_target))
	# Debug periódico: solo log si está cerca del límite
	if angle_deg > acceptance_angle * 0.8 and angle_deg <= acceptance_angle * 1.5:
		_debug("_is_aiming_at_target: angle=%.1f° (limit=%.0f°) — %s" % [
			angle_deg, acceptance_angle,
			"PASA" if angle_deg <= acceptance_angle else "FALLA"])
	return angle_deg <= acceptance_angle


## Verifica si el arma tiene daño por área (splash).
## Usa el WeaponAIProfile si está disponible (FASE 5).
func _has_splash_damage(weapon: Weapon) -> bool:
	# Método 1: Usar perfil AI del WeaponSystem (FASE 5)
	if weapon_sys:
		var profile: WeaponAIProfile = weapon_sys.get_profile_for(weapon.weapon_name)
		if profile:
			return profile.splash_damage

	# Método 2: Usar perfil AI del arma (FASE 5)
	if weapon.ai_profile:
		return weapon.ai_profile.splash_damage

	# Método 3: Fallback por nombre de arma
	var splash_names: Array[String] = ["rocket", "grenade", "rl", "flak alt", "bio"]
	var wname: String = weapon.weapon_name.to_lower()
	for sname in splash_names:
		if sname in wname:
			return true
	return false


# ══════════════════════════════════════════════════════════════════
# EVASIÓN (DODGE)
# ══════════════════════════════════════════════════════════════════

## Actualiza el temporizador de enfriamiento de dodge.
func _update_dodge_cooldown(delta: float) -> void:
	if dodge_state == DodgeState.COOLDOWN:
		_dodge_cooldown_timer -= delta
		if _dodge_cooldown_timer <= 0.0:
			dodge_state = DodgeState.NONE
			_dodge_cooldown_timer = 0.0


## Evalúa si deberíamos solicitar una evasión.
## NO escribe velocity — solo marca wants_dodge para DecisionSystem.
func _check_dodge_request() -> void:
	if dodge_state != DodgeState.NONE:
		return  # Ya en evasión o enfriamiento

	# Solo dodge si hay un target y estamos en rango cercano
	if not decision_sys or not decision_sys.has_target():
		return

	var dist: float = decision_sys.dist_to_target()
	if dist > CLOSE_COMBAT_RANGE * 2.0:
		return

	# Probabilidad de dodge (mayor en combate cercano)
	var dodge_chance: float = 0.0
	if dist < CLOSE_COMBAT_RANGE:
		dodge_chance = 0.15  # 15% por frame en rango cercano
	elif dist < CLOSE_COMBAT_RANGE * 2.0:
		dodge_chance = 0.05  # 5% en rango medio

	if randf() > dodge_chance:
		return

	# Determinar dirección de evasión (perpendicular al enemigo)
	var target: Node3D = decision_sys.target_entity
	var to_target: Vector3 = (target.global_position - bot.global_position).normalized()
	var side: Vector3 = to_target.cross(Vector3.UP)
	# Alternar izquierda/derecha aleatoriamente
	if randi() % 2 == 0:
		side = -side

	wants_dodge = true
	dodge_direction = side.normalized()
	dodge_state = DodgeState.DODGING

	emit_signal("dodge_requested", dodge_direction)
	_debug("Dodge solicitado: %s" % str(dodge_direction.round()))


## El DecisionSystem confirmó que ejecutará el dodge.
## Llamar desde DecisionSystem cuando concede un dodge.
func confirm_dodge() -> void:
	wants_dodge = false
	dodge_direction = Vector3.ZERO
	dodge_state = DodgeState.COOLDOWN
	_dodge_cooldown_timer = DODGE_COOLDOWN_TIME


## El DecisionSystem denegó el dodge.
## Llamar desde DecisionSystem cuando rechaza un dodge.
func deny_dodge() -> void:
	wants_dodge = false
	dodge_direction = Vector3.ZERO
	dodge_state = DodgeState.COOLDOWN
	_dodge_cooldown_timer = DODGE_COOLDOWN_TIME * 0.5  # Enfriamiento más corto


# ══════════════════════════════════════════════════════════════════
# ANÁLISIS DE COMPROMISO
# ══════════════════════════════════════════════════════════════════

## Actualiza el análisis del enfrentamiento actual.
func _update_engagement_analysis() -> void:
	if decision_sys == null:
		engagement_analysis = {}
		return

	var analysis: Dictionary = {}

	if decision_sys.has_target():
		var target: Node3D = decision_sys.target_entity
		var dist: float = decision_sys.dist_to_target()
		analysis["has_target"] = true
		analysis["distance"] = dist
		analysis["target_position"] = target.global_position
		analysis["in_combat_range"] = dist <= MAX_ENGAGEMENT_RANGE
		analysis["in_close_range"] = dist <= CLOSE_COMBAT_RANGE
		analysis["in_preferred_range"] = _is_in_preferred_range(dist)

		# Evaluar threat level básico
		if dist < CLOSE_COMBAT_RANGE:
			analysis["threat_level"] = "HIGH"
		elif dist < CLOSE_COMBAT_RANGE * 3.0:
			analysis["threat_level"] = "MEDIUM"
		else:
			analysis["threat_level"] = "LOW"

		# Actualizar current_target_position
		current_target_position = target.global_position

		# Emitir señal si el objetivo entró en rango de combate
		var in_range: bool = dist <= MAX_ENGAGEMENT_RANGE
		if in_range and not _had_target_in_range:
			target_in_range.emit(target.get_instance_id(), dist)
		_had_target_in_range = in_range
	else:
		# Emitir señal si se perdió el objetivo que estaba en rango
		if _had_target_in_range and engagement_analysis.get("has_target", false):
			target_lost.emit(-1)
		_had_target_in_range = false
		analysis["has_target"] = false
		analysis["threat_level"] = "NONE"

	engagement_analysis = analysis


## Verifica si la distancia está dentro del rango preferido del arma actual.
## Usa el WeaponAIProfile para rangos precisos (FASE 5).
func _is_in_preferred_range(dist: float) -> bool:
	var weapon: Weapon = _get_weapon()
	if weapon == null:
		return true

	# Método 1: Usar perfil AI para rango preciso
	var profile: WeaponAIProfile = null
	if weapon_sys:
		profile = weapon_sys.get_profile_for(weapon.weapon_name)
	if profile == null and weapon.ai_profile:
		profile = weapon.ai_profile

	if profile:
		return dist >= profile.preferred_range_min and dist <= profile.preferred_range_max

	# Fallback por weapon_range
	return dist <= weapon.weapon_range * 0.8


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

## Devuelve la posición desde donde debe lanzarse un proyectil.
## Usa la posición de la cabeza del bot + un pequeño offset hacia adelante.
func _get_launch_position() -> Vector3:
	if _head_node and is_instance_valid(_head_node):
		return _head_node.global_position + _head_node.global_transform.basis.z * -0.3
	if bot and is_instance_valid(bot):
		return bot.global_position + Vector3.UP * 0.8
	return Vector3.ZERO


## Devuelve la dirección hacia la que debe lanzarse un proyectil.
## Usa la dirección forward de aim_rotation (o de la cabeza si está disponible).
func _get_launch_direction() -> Vector3:
	if _head_node and is_instance_valid(_head_node):
		return -_head_node.global_transform.basis.z
	# Fallback: usar aim_rotation
	var forward: Vector3 = aim_rotation * Vector3.FORWARD
	if forward.length_squared() > 0.001:
		return forward.normalized()
	return Vector3.FORWARD


## Obtiene el arma actual del bot accediendo directamente al escenario,
## igual que hace el jugador (player.gd -> Head/Weapon).
## Esto evita problemas con la cadena weapon_sys / _weapon / get_current_weapon.
func _get_weapon() -> Weapon:
	if bot == null or not is_instance_valid(bot):
		return null
	# Acceso directo al nodo arma (hijo de Head), mismo patrón que el player
	var head_node: Node3D = bot.get_node_or_null("Head")
	if head_node:
		var weapon_node: Node = head_node.get_node_or_null("Weapon")
		if weapon_node:
			return weapon_node as Weapon
	# Fallback: intentar con _weapon del bot (para compatibilidad)
	return bot.get("_weapon") if bot.get("_weapon") != null else null


## Método de compatibilidad — apunta directamente a una posición.
## Usado por BotBrain legacy hasta su migración completa.
## Equivalente a _aim_at_target() en NpcBase.
func aim_directly(target_pos: Vector3) -> void:
	_update_aim(target_pos)


## Debug output
func _debug(msg: String) -> void:
	if bot:
		bot._debug("[Combat] " + msg)


## Debug output con rate-limit para evitar spam.
func _debug_rl(msg: String) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_debug_time < DEBUG_COOLDOWN_SEC:
		return
	_last_debug_time = now
	if bot:
		bot._debug("[Combat] " + msg)
