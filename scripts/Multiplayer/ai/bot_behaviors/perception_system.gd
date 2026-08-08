# scripts/ai/perception_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE PERCEPCIÓN MODULAR — FASE 1 REFACTORIZACIÓN
#
# Centraliza toda la detección sensorial del NPC:
# - Visión (Area3D + RayCast3D)
# - Evaluación de prioridad de enemigos
# - Selección de objetivo actual
#
# ── CAMBIO IMPORTANTE (Refactorización FASE 1) ──
# PerceptionSystem ya NO escribe directamente en BotBase.
# En su lugar, PRODUCE sensor_data y EMITE señales.
# - sensor_data: visible_enemies, heard_noises (solo lectura externa)
# - Señales: entity_detected, entity_lost, threat_assessed
# - DecisionSystem (BotBrain) se suscribe a estas señales
#
# ── FLUJO ──
# 1. Escanea AreaVision por cuerpos enemigos
# 2. Verifica línea de visión con RayCast3D
# 3. Calcula prioridad de cada enemigo visible
# 4. Registra en MemorySystem: "enemigo visto en posición X"
# 5. Selecciona el mejor objetivo
# 6. EMITE señales (ya no escribe en BotBase)
# ──────────────────────────────────────────────────────────────────
extends Node
class_name PerceptionSystem


# ══════════════════════════════════════════════════════════════════
# SEÑALES (FASE 1: comunicación desacoplada)
# ══════════════════════════════════════════════════════════════════

## Se emite cuando se detecta un nuevo enemigo o cambia el objetivo principal.
signal entity_detected(entity: Node3D, position: Vector3)

## Se emite cuando se pierde de vista al objetivo actual.
signal entity_lost(entity: Node3D)

## Se emite cada frame con el array de enemigos visibles evaluados.
signal threat_assessed(visible_enemies: Array)


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Distancia máxima para considerar que un enemigo está "cerca
## del core enemigo"
const ENEMY_NEAR_CORE_DIST: float = 15.0

## Máximo de enemigos que se procesan con raycasts por cada update().
## Los enemigos se ordenan por distancia antes de procesar, así que
## solo los N más cercanos reciben verificación de línea de visión.
## Esto evita el cuello de botella O(n²) con muchos bots.
const MAX_ENEMIES_PER_SCAN: int = 6

## Apertura total del cono de visión. La mitad se aplica a cada lado del
## eje del arma; así la detección representa adónde está apuntando el bot.
const DEFAULT_WEAPON_FOV_DEGREES: float = 110.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## El bot dueño de este sistema
var bot: BotBase:
	get:
		if _bot == null:
			_bot = get_parent() as BotBase
		return _bot
var _bot: BotBase = null

## Referencia al MemorySystem (hermano en el árbol)
var memory: MemorySystem = null

# ── DATOS SENSORIALES (sensor_data) ──
# NADIE más escribe esto. Solo PerceptionSystem produce estos datos.
# Otros sistemas (DecisionSystem, BotBrain) los LEEN.

## Enemigos visibles detectados este frame (ordenados por prioridad).
## Este es el principal `sensor_data`. Contiene diccionarios con
## { "body": Node3D, "score": float, "dist": float }
var visible_enemies: Array[Dictionary] = []

# ── TRACKING INTERNO (privado) ──
# target_entity es PROPIEDAD de DecisionSystem.
# PerceptionSystem solo SUGIERE a través de señales, no asigna.

## Objetivo enemigo detectado (solo tracking interno para señales).
var _target_enemy: Node3D = null

## Última posición conocida del enemigo (para señales).
var _last_seen_position: Vector3 = Vector3.ZERO

## Tiempo acumulado con el mismo objetivo
var _time_on_target: float = 0.0

## ¿Estamos atacando actualmente el core enemigo?
var _detected_core: bool = false


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as BotBase
	# Buscar MemorySystem como hermano
	if bot:
		memory = bot.get_node_or_null("MemorySystem") as MemorySystem


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado cada frame desde BotBase._physics_process()
# ══════════════════════════════════════════════════════════════════

## Actualiza la percepción: escanea enemigos, verifica LOS, calcula
## prioridades y registra en MemorySystem. Debe llamarse cada frame.
func update(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	var role: TacticalRole = bot._tactical_role
	var bodies: Array = bot.area_vision.get_overlapping_bodies()
	var weapon_aim_origin: Vector3 = _get_weapon_aim_origin()
	var weapon_forward: Vector3 = _get_weapon_forward()
	var weapon_fov_degrees: float = _get_weapon_fov_degrees()
	
	# ── Ordenar por distancia (los más cercanos primero) ─────────
	# Así los enemigos prioritarios reciben verificación LOS primero,
	# y el límite MAX_ENEMIES_PER_SCAN capta a los más peligrosos.
	var bot_pos: Vector3 = bot.global_position
	bodies.sort_custom(func(a, b): return bot_pos.distance_squared_to(a.global_position) < bot_pos.distance_squared_to(b.global_position))
	
	# ── Fase 1: Recolectar enemigos visibles con puntuación ──────
	visible_enemies.clear()
	
	var enemies_processed: int = 0
	
	for body in bodies:
		if body == bot or not body is CharacterBody3D:
			continue
		if body.get("is_dead") == true:
			continue
		if body.get("is_invisible") == true:
			continue
		
		var body_equipo: int = body.get("equipo_id") if "equipo_id" in body else -1
		if not GameState.son_enemigos(bot.equipo_id, body_equipo):
			continue
		
		var target_pos: Vector3 = body.global_position + Vector3.UP * 0.9
		var dist: float = bot_pos.distance_to(body.global_position)
		
		# Un enemigo debe estar dentro del cono que describe el arma del bot.
		# AreaVision mantiene la lista de candidatos por distancia; este filtro
		# añade dirección real sin depender de una cámara ni de la orientación del
		# cuerpo en el frame anterior.
		if not _is_inside_weapon_fov(weapon_aim_origin, weapon_forward, target_pos, weapon_fov_degrees):
			continue
		
		# Filtro por rango de reacción del rol
		if role and dist > role.reaction_range:
			continue
		
		# ── LÍMITE DE PERCEPCIÓN: solo procesar N enemigos por update ──
		# Los filtros baratos (equipo, distancia, vida) corren para todos,
		# pero los raycasts caros solo para los primeros N que pasan.
		if enemies_processed >= MAX_ENEMIES_PER_SCAN:
			break
		enemies_processed += 1
		
		# La visibilidad se calcula desde el origen de tiro, no desde el centro
		# del collider. Un único raycast hasta torso/cabeza evita falsos negativos
		# de muros bajos sin permitir ver o disparar a través de paredes.
		if not _has_weapon_line_of_sight(body, weapon_aim_origin, target_pos):
			continue
		
		# Calcular % de vida del enemigo
		var enemy_hp_pct: float = 1.0
		if "current_health" in body and "max_health" in body:
			var max_hp: float = body.max_health
			if max_hp > 0:
				enemy_hp_pct = float(body.current_health) / max_hp
		
		# Puntuar según el rol
		var score: float = 100.0 - dist
		if role:
			score = role.score_enemy_priority(
				body, dist,
				bot._get_dist_to_own_core(),
				false,
				enemy_hp_pct
			)
		
		visible_enemies.append({ "body": body, "score": score, "dist": dist })
		
		# ── Registrar en MemorySystem ──
		if memory != null:
			memory.record_enemy_position(body, body.global_position)
	
	# ── Fase 2: Decidir objetivo actual ──────────────────────────
	_select_target(role)
	
	# ── Fase 3: Emitir señales de amenaza ────────────────────────
	emit_signal("threat_assessed", visible_enemies)
	
	# ── Fase 4: Actualizar timer de objetivo ─────────────────────
	if _target_enemy != null and is_instance_valid(_target_enemy):
		_time_on_target += delta
	else:
		_time_on_target = 0.0


## Selecciona el mejor objetivo enemigo.
## Ya NO escribe en BotBase. Solo actualiza tracking interno y emite señales.
func _select_target(role: TacticalRole) -> void:
	if visible_enemies.is_empty():
		# Sin enemigos visibles
		if _target_enemy != null and is_instance_valid(_target_enemy):
			# Si teníamos un objetivo y lo perdimos de vista,
			# actualizar last_seen_position para HUNT
			if _target_enemy is CharacterBody3D and not _target_enemy.get("is_dead"):
				_last_seen_position = _target_enemy.global_position
				# Registrar en memoria para HUNT
				if memory != null:
					memory.record_enemy_position(_target_enemy, _last_seen_position)
			
			# Emitir señal de pérdida
			var lost_entity: Node3D = _target_enemy
			_target_enemy = null
			_detected_core = false
			emit_signal("entity_lost", lost_entity)
		return
	
	# Ordenar por puntuación (mayor primero)
	visible_enemies.sort_custom(func(a, b): return a.score > b.score)
	var best_target: Dictionary = visible_enemies[0]
	var best_body: Node3D = best_target.body as Node3D
	
	# Si es el mismo objetivo que ya tenemos, mantenerlo
	if best_body == _target_enemy and is_instance_valid(_target_enemy):
		_last_seen_position = _target_enemy.global_position
		return
	
	# Decisión del rol: ¿debemos realmente atacar?
	if role:
		var dist_to_base: float = bot._get_dist_to_own_core()
		var enemy_near_core: bool = false
		if bot._enemy_core and is_instance_valid(bot._enemy_core):
			enemy_near_core = best_target.dist < ENEMY_NEAR_CORE_DIST
		
		if not role.should_engage_enemy(
			bot.global_position, best_body.global_position,
			enemy_near_core, dist_to_base
		):
			return  # El rol dice que no debe atacar
	
	# Cambiar al nuevo objetivo y emitir señal
	var previous_target: Node3D = _target_enemy
	_target_enemy = best_body
	_last_seen_position = best_body.global_position
	_detected_core = false
	
	if previous_target != _target_enemy:
		if previous_target != null:
			emit_signal("entity_lost", previous_target)
		emit_signal("entity_detected", _target_enemy, _last_seen_position)


## Origen físico de la visión: muzzle si existe; cabeza como respaldo.
func _get_weapon_aim_origin() -> Vector3:
	if bot == null:
		return Vector3.ZERO
	var weapon: Weapon = bot.get_current_weapon()
	if weapon != null and is_instance_valid(weapon) and weapon.is_inside_tree():
		return weapon._get_muzzle_position()
	if bot.head != null and is_instance_valid(bot.head):
		return bot.head.global_position
	return bot.global_position + Vector3.UP * 0.9


## Eje de visión real: el forward del arma, o el de cabeza/cuerpo si aún no se creó.
func _get_weapon_forward() -> Vector3:
	if bot == null:
		return Vector3.FORWARD
	var weapon: Weapon = bot.get_current_weapon()
	if weapon != null and is_instance_valid(weapon) and weapon.is_inside_tree():
		return -weapon.global_transform.basis.z.normalized()
	if bot.head != null and is_instance_valid(bot.head):
		return -bot.head.global_transform.basis.z.normalized()
	return -bot.global_transform.basis.z.normalized()


## Permite que cada arma declare su FOV opcionalmente; mantiene un valor seguro por defecto.
func _get_weapon_fov_degrees() -> float:
	if bot != null:
		var weapon: Weapon = bot.get_current_weapon()
		if weapon != null and is_instance_valid(weapon):
			var configured_fov: Variant = weapon.get("ai_vision_fov_degrees")
			if configured_fov is float or configured_fov is int:
				return clampf(float(configured_fov), 20.0, 170.0)
	return DEFAULT_WEAPON_FOV_DEGREES


func _is_inside_weapon_fov(origin: Vector3, forward: Vector3, target_pos: Vector3, fov_degrees: float) -> bool:
	var direction_to_target: Vector3 = target_pos - origin
	if direction_to_target.length_squared() <= 0.0001:
		return true
	var normalized_forward: Vector3 = forward.normalized()
	var normalized_direction: Vector3 = direction_to_target.normalized()
	var half_fov_radians: float = deg_to_rad(fov_degrees * 0.5)
	return normalized_forward.dot(normalized_direction) >= cos(half_fov_radians)


func _has_weapon_line_of_sight(target: Node3D, origin: Vector3, target_pos: Vector3) -> bool:
	if bot == null or not bot.is_inside_tree():
		return false
	var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_pos)
	query.collision_mask = bot.raycast_vision.collision_mask if bot.raycast_vision != null else 15
	query.exclude = [bot]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider: Node = result.get("collider", null) as Node
	return _is_target(target, collider)


# ── HELPER: Verifica si un collider es el cuerpo objetivo ─────
static func _is_target(body: Node3D, collider: Node) -> bool:
	if collider == null:
		return false
	if collider == body:
		return true
	var parent_check: Node = collider
	while parent_check:
		if parent_check == body:
			return true
		parent_check = parent_check.get_parent()
	return false


# ══════════════════════════════════════════════════════════════════
# API PÚBLICA — Consultas (sensor_data de solo lectura)
# ══════════════════════════════════════════════════════════════════

## ¿Hay enemigos visibles?
func has_visible_enemies() -> bool:
	return not visible_enemies.is_empty()


## Retorna el mejor enemigo visible (el de mayor score).
func get_best_visible_enemy() -> Node3D:
	if visible_enemies.is_empty():
		return null
	return visible_enemies[0].get("body", null) as Node3D


## Retorna el objetivo principal detectado (sugerencia para DecisionSystem).
func get_suggested_target() -> Node3D:
	return _target_enemy


## Retorna la última posición conocida del objetivo.
func get_last_known_position() -> Vector3:
	return _last_seen_position


# ══════════════════════════════════════════════════════════════════
# API DE MEMORIA (BACKWARD COMPATIBILITY)
# ══════════════════════════════════════════════════════════════════
# Estos métodos existían en PerceptionSystem y behaviors los usan.
# Ahora delegan en MemorySystem. Cuando los behaviors se refactoricen
# a FASE 5, estos métodos se eliminarán.
# ══════════════════════════════════════════════════════════════════

## ¿Hay memoria de enemigos? (delega en MemorySystem)
func has_memory() -> bool:
	return memory != null and memory.has_enemy_memory()


## Retorna la última posición conocida de un enemigo (delega en MemorySystem).
func get_last_known_enemy_position() -> Vector3:
	if memory != null:
		return memory.get_last_enemy_position()
	return Vector3.ZERO


## Retorna el enemigo recordado más reciente (delega en MemorySystem).
func get_last_known_enemy() -> Node3D:
	if memory == null:
		return null
	var entry: MemorySystem.MemoryEntry = memory.get_most_recent(MemorySystem.MemoryType.ENEMY_POSITION)
	if entry != null:
		var enemy: Node3D = entry.data.get("enemy", null) as Node3D
		if enemy != null and is_instance_valid(enemy) and enemy.is_inside_tree():
			return enemy
	return null


## Retorna la cantidad de enemigos recordados (delega en MemorySystem).
func memory_count() -> int:
	if memory != null:
		return memory.count_type(MemorySystem.MemoryType.ENEMY_POSITION)
	return 0


# ══════════════════════════════════════════════════════════════════
# RESET
# ══════════════════════════════════════════════════════════════════

## Resetea todo el estado de percepción (útil en respawn).
func reset() -> void:
	# Emitir pérdida si había un objetivo activo
	if _target_enemy != null:
		var lost: Node3D = _target_enemy
		_target_enemy = null
		emit_signal("entity_lost", lost)
	
	_last_seen_position = Vector3.ZERO
	_detected_core = false
	_time_on_target = 0.0
	visible_enemies.clear()
	# La memoria NO se resetea aquí. MemorySystem tiene su propio reset
	# que se llama desde BotBase.respawn().
