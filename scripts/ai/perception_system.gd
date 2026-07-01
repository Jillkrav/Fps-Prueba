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
# PerceptionSystem ya NO escribe directamente en NpcBase.
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
# 6. EMITE señales (ya no escribe en NpcBase)
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


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## El bot dueño de este sistema
var bot: NpcBase:
	get:
		if _bot == null:
			_bot = get_parent() as NpcBase
		return _bot
var _bot: NpcBase = null

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
	_bot = get_parent() as NpcBase
	# Buscar MemorySystem como hermano
	if bot:
		memory = bot.get_node_or_null("MemorySystem") as MemorySystem


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado cada frame desde NpcBase._physics_process()
# ══════════════════════════════════════════════════════════════════

## Actualiza la percepción: escanea enemigos, verifica LOS, calcula
## prioridades y registra en MemorySystem. Debe llamarse cada frame.
func update(delta: float) -> void:
	if bot == null or bot.is_dead:
		return
	
	var role: TacticalRole = bot._tactical_role
	var bodies: Array = bot.area_vision.get_overlapping_bodies()
	
	# ── Fase 1: Recolectar enemigos visibles con puntuación ──────
	visible_enemies.clear()
	
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
		
		var target_pos: Vector3 = body.global_position + Vector3.UP * 1.5
		var dist: float = bot.global_position.distance_to(body.global_position)
		
		# Filtro por rango de reacción del rol
		if role and dist > role.reaction_range:
			continue
		
		# Chequeo de LOS (Line of Sight) — doble verificación
		var local_target: Vector3 = bot.to_local(target_pos)
		bot.raycast_vision.target_position = local_target
		bot.raycast_vision.force_raycast_update()
		
		# Raycast 1: desde el cuerpo (actual)
		var collider_1: Node = bot.raycast_vision.get_collider()
		
		# Raycast 2: desde la cabeza (offset vertical)
		var head_pos: Vector3 = bot.head.global_position if bot.head else bot.global_position + Vector3.UP * 0.9
		var space_state: PhysicsDirectSpaceState3D = bot.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(head_pos, target_pos)
		query.collision_mask = bot.raycast_vision.collision_mask
		query.exclude = [bot]
		var result: Dictionary = space_state.intersect_ray(query)
		var collider_2 = result.get("collider", null) if not result.is_empty() else null
		
		# LOS requiere que AMBOS rayos impacten al enemigo
		var has_los: bool = _is_target(body, collider_1) and _is_target(body, collider_2)
		
		if not has_los:
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
## Ya NO escribe en NpcBase. Solo actualiza tracking interno y emite señales.
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
	# que se llama desde NpcBase.respawn().
