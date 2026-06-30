# scripts/ai/perception_system.gd
# ──────────────────────────────────────────────────────────────────
# SISTEMA DE PERCEPCIÓN MODULAR
#
# Centraliza toda la detección sensorial del NPC:
# - Visión (Area3D + RayCast3D)
# - Memoria de posiciones enemigas (última posición conocida)
# - Evaluación de prioridad de enemigos
# - (Futuro) Detección de sonidos (disparos, explosiones)
# - (Futuro) Conocimiento de posición de aliados
#
# Este nodo se añade como hijo de NpcBase, junto al BotBrain.
# ──────────────────────────────────────────────────────────────────
extends Node
class_name PerceptionSystem


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Tiempo máximo (segundos) que recordamos una posición enemiga
const MEMORY_DURATION: float = 10.0

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

## Objetivo enemigo actual (puede ser un CharacterBody3D o Core)
var target_enemy: Node3D = null

## Última posición conocida del enemigo (para HUNT)
var last_seen_position: Vector3 = Vector3.ZERO

## Lista de todas las posiciones recordadas de enemigos
## { "position": Vector3, "time": float, "enemy": Node3D }
var memory: Array[Dictionary] = []

## Tiempo acumulado con el mismo objetivo
var time_on_target: float = 0.0

## ¿Estamos atacando actualmente el core enemigo?
var is_attacking_core: bool = false

## Enemigos visibles detectados este frame (ordenados por prioridad)
var visible_enemies: Array[Dictionary] = []


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_bot = get_parent() as NpcBase


# ══════════════════════════════════════════════════════════════════
# CICLO PRINCIPAL — Llamado cada frame desde BotBrain o NpcBase
# ══════════════════════════════════════════════════════════════════

## Actualiza la percepción: escanea enemigos, verifica LOS, calcula
## prioridades y actualiza la memoria. Debe llamarse cada frame.
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
		
		# Chequeo de LOS (Line of Sight)
		var local_target: Vector3 = bot.to_local(target_pos)
		bot.raycast_vision.target_position = local_target
		bot.raycast_vision.force_raycast_update()
		
		var collider = bot.raycast_vision.get_collider()
		var has_los: bool = false
		if collider == body:
			has_los = true
		elif collider:
			var parent_check: Node = collider
			while parent_check:
				if parent_check == body:
					has_los = true
					break
				parent_check = parent_check.get_parent()
		
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
		
		# Actualizar memoria: siempre recordamos la última posición
		_add_to_memory(body, body.global_position)
	
	# ── Fase 2: Actualizar memoria (decaimiento) ─────────────────
	_decay_memory(delta)
	
	# ── Fase 3: Decidir objetivo actual ──────────────────────────
	_select_target(role)
	
	# ── Fase 4: Sincronizar con variables del bot ────────────────
	_sync_to_bot()
	
	# ── Fase 5: Actualizar timer de objetivo ─────────────────────
	if target_enemy != null and is_instance_valid(target_enemy):
		time_on_target += delta
	else:
		time_on_target = 0.0


## Selecciona el mejor objetivo enemigo.
func _select_target(role: TacticalRole) -> void:
	if visible_enemies.is_empty():
		# Sin enemigos visibles
		if target_enemy != null and is_instance_valid(target_enemy):
			# Si teníamos un objetivo y lo perdimos de vista,
			# actualizar last_seen_position para HUNT
			if target_enemy is CharacterBody3D and not target_enemy.get("is_dead"):
				last_seen_position = target_enemy.global_position
			elif target_enemy.get("is_destroyed") == true or target_enemy.get("is_dead") == true:
				target_enemy = null
				is_attacking_core = false
		return
	
	# Ordenar por puntuación (mayor primero)
	visible_enemies.sort_custom(func(a, b): return a.score > b.score)
	var best_target: Dictionary = visible_enemies[0]
	var best_body: Node3D = best_target.body as Node3D
	
	# Si es el mismo objetivo que ya tenemos, mantenerlo
	if best_body == target_enemy and is_instance_valid(target_enemy):
		last_seen_position = target_enemy.global_position
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
	
	# Cambiar al nuevo objetivo
	target_enemy = best_body
	last_seen_position = best_body.global_position
	is_attacking_core = false


## Sincroniza el estado de percepción con las variables del bot.
func _sync_to_bot() -> void:
	if bot:
		bot.target_enemy = target_enemy
		bot.last_seen_position = last_seen_position
		bot._is_attacking_core = is_attacking_core


# ══════════════════════════════════════════════════════════════════
# MEMORIA
# ══════════════════════════════════════════════════════════════════

## Añade la posición de un enemigo a la memoria (o la actualiza).
func _add_to_memory(enemy: Node3D, position: Vector3) -> void:
	for entry in memory:
		if entry.get("enemy") == enemy:
			entry["position"] = position
			entry["time"] = Time.get_ticks_msec() / 1000.0
			return
	
	memory.append({
		"enemy": enemy,
		"position": position,
		"time": Time.get_ticks_msec() / 1000.0
	})


## Decae la memoria: elimina entradas antiguas.
func _decay_memory(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	memory = memory.filter(func(e): return (now - e.get("time", 0)) < MEMORY_DURATION)


## Retorna la posición recordada más reciente de un enemigo,
## o Vector3.ZERO si no hay memoria válida.
func get_last_known_enemy_position() -> Vector3:
	if memory.is_empty():
		return Vector3.ZERO
	# La más reciente
	memory.sort_custom(func(a, b): return a.get("time", 0) > b.get("time", 0))
	return memory[0].get("position", Vector3.ZERO)


## Retorna el enemigo recordado más reciente (para HUNT).
func get_last_known_enemy() -> Node3D:
	if memory.is_empty():
		return null
	memory.sort_custom(func(a, b): return a.get("time", 0) > b.get("time", 0))
	var enemy: Node3D = memory[0].get("enemy", null)
	if enemy != null and is_instance_valid(enemy) and enemy.is_inside_tree():
		return enemy
	return null


## Retorna true si hay algún recuerdo de enemigos.
func has_memory() -> bool:
	return not memory.is_empty()


## Retorna la cantidad de enemigos recordados.
func memory_count() -> int:
	return memory.size()


# ══════════════════════════════════════════════════════════════════
# UTILIDADES
# ══════════════════════════════════════════════════════════════════

## ¿Hay enemigos visibles?
func has_visible_enemies() -> bool:
	return not visible_enemies.is_empty()


## Retorna el mejor enemigo visible (el de mayor score).
func get_best_visible_enemy() -> Node3D:
	if visible_enemies.is_empty():
		return null
	return visible_enemies[0].get("body", null) as Node3D


## Resetea todo el estado de percepción (útil en respawn).
func reset() -> void:
	target_enemy = null
	last_seen_position = Vector3.ZERO
	is_attacking_core = false
	time_on_target = 0.0
	visible_enemies.clear()
	memory.clear()
