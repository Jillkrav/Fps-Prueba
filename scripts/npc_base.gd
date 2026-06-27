# scripts/npc_base.gd
# Base class for all NPCs. Recreación avanzada de la lógica de UT1.
extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# EXPORTS & CONFIG
# ─────────────────────────────────────────

@export var equipo_id: int = int(Enums.Equipo.ROJO)
@export var nombre_arma: String = "USP"
@export var experiencia: int = int(Enums.Experiencia.MEDIA)
@export var rol: int = int(Enums.Rol.SOLDADO)

# Propiedades de UT1
var skill: float = 3.0
var accuracy: float = 0.5
var combat_style: float = 0.5
var jumpiness: float = 0.3

# ─────────────────────────────────────────
# STATE & FSM
# ─────────────────────────────────────────

enum State { IDLE, ROAMING, ATTACKING, TACTICAL_MOVE, HUNTING }
var current_state: State = State.IDLE

var target_enemy: Node3D = null
var last_seen_position: Vector3 = Vector3.ZERO
var is_dead: bool = false
var max_health: float = 100.0
var current_health: float = 100.0
var is_invisible: bool = false # Para el modo espectador del bot

# Movement
var _strafe_direction: int = 1
var _last_strafe_change: float = 0.0
var _jump_timer: float = 0.0

# Navigation target tracking (evitar reset del target cada frame)
var _nav_target: Vector3 = Vector3.ZERO

# Stuck detection
var _stuck_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _stuck_threshold: float = 6.0  # segundos sin moverse = atascado (aumentado para evitar falsos positivos durante navegacion)

# Core / objective system (UT99 Orders pattern)
var _enemy_core: Node3D = null
var _is_attacking_core: bool = false
var _team_objective: Vector3 = Vector3.ZERO
var _objective_reached: bool = false

# Components
var _weapon: Weapon = null
const WEAPON_PLACEHOLDER: PackedScene = preload("res://scenes/weapons/weapon_placeholder.tscn")
const DROPPED_WEAPON: PackedScene = preload("res://scenes/pickups/dropped_weapon.tscn")

var _npc_id: int = 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var area_vision: Area3D = $AreaVision
@onready var raycast_vision: RayCast3D = $RaycastVision
@onready var head: Node3D = $Head

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	_npc_id = randi() % 9000 + 1000
	add_to_group("npc")
	
	max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health
	
	_equipar_arma()
	_aplicar_color_equipo()
	
	# Ajustar skill (0 a 7 en UT1)
	skill = float(experiencia) * 2.5 + 1.0
	
	# Encontrar core enemigo como objetivo principal
	call_deferred("_find_enemy_core")
	
	# Iniciar roaming despues de 0.5s para dar tiempo a que el
	# NavigationServer sincronice el NavMesh y las rutas sean validas.
	_change_state(State.IDLE)
	get_tree().create_timer(0.5).timeout.connect(_start_roaming)
	_debug("INICIALIZADO | Equipo=%s | Arma=%s" % [GameState.nombre_equipo(equipo_id), nombre_arma])

func _start_roaming() -> void:
	if is_dead:
		return
	# Forzar ROAMING independientemente del estado actual.
	# Los bots se detectan entre si por AreaVision (radio 30) durante
	# la inicializacion y cambian a HUNTING/ATTACKING antes de que el
	# NavigationServer haya sincronizado el NavMesh. Al forzar ROAMING
	# aqui nos aseguramos de que empiecen a navegar con el NavMesh listo.
	_change_state(State.ROAMING)

func _physics_process(delta: float) -> void:
	if is_dead or not is_inside_tree():
		return
	
	_update_perception()
	_check_core_proximity()
	_update_timers(delta)
	
	# Si se detecto atascado, saltamos el movimiento del estado para que
	# el empuje + salto de _check_stuck surtan efecto en move_and_slide().
	var stuck_handled: bool = _check_stuck(delta)
	
	if not stuck_handled:
		match current_state:
			State.IDLE: _state_idle(delta)
			State.ROAMING: _state_roaming(delta)
			State.ATTACKING: _state_attacking(delta)
			State.TACTICAL_MOVE: _state_tactical(delta)
			State.HUNTING: _state_hunting(delta)
	
	if not is_on_floor():
		velocity.y -= _gravity * delta
	
	move_and_slide()

# ─────────────────────────────────────────
# CEREBRO (FSM)
# ─────────────────────────────────────────

func _change_state(new_state: State) -> void:
	if current_state == new_state: return
	current_state = new_state
	# _debug("Cambio a %s" % State.keys()[new_state])

func _update_timers(delta: float) -> void:
	if _jump_timer > 0: _jump_timer -= delta

func _update_perception() -> void:
	var bodies: Array = area_vision.get_overlapping_bodies()
	var closest_enemy: Node3D = null
	var min_dist: float = 9999.0
	
	for body in bodies:
		if body == self or not body is CharacterBody3D: continue
		if body.get("is_dead") == true: continue
		if body.get("is_invisible") == true: continue
		
		var body_equipo: int = body.get("equipo_id") if "equipo_id" in body else -1
		if GameState.son_enemigos(equipo_id, body_equipo):
			var target_pos: Vector3 = body.global_position + Vector3.UP * 1.5
			var dist: float = global_position.distance_to(body.global_position)
			
			# Chequeo de LOS (Line of Sight)
			var local_target: Vector3 = to_local(target_pos)
			raycast_vision.target_position = local_target
			raycast_vision.force_raycast_update()
			
			var collider = raycast_vision.get_collider()
			if collider == body or (collider and (collider.get_parent() == body or collider.get_parent().get_parent() == body)):
				if dist < min_dist:
					min_dist = dist
					closest_enemy = body
	
	if closest_enemy:
		# Prioridad: enemigos vivos > core
		_is_attacking_core = false
		target_enemy = closest_enemy
		last_seen_position = target_enemy.global_position
		if current_state == State.ROAMING or current_state == State.IDLE or current_state == State.HUNTING:
			_change_state(State.ATTACKING)
		elif current_state == State.TACTICAL_MOVE:
			pass
	elif target_enemy:
		if target_enemy.get("is_dead") == true:
			target_enemy = null
			_is_attacking_core = false
			_change_state(State.ROAMING)
		elif target_enemy is Core and _is_attacking_core:
			if target_enemy.is_destroyed:
				target_enemy = null
				_is_attacking_core = false
				_change_state(State.ROAMING)
		elif current_state != State.HUNTING:
			_change_state(State.HUNTING)
			navigation_agent.target_position = last_seen_position
	elif current_state == State.ATTACKING and _is_attacking_core and _enemy_core and not _enemy_core.is_destroyed:
		pass
	else:
		if current_state == State.ATTACKING or current_state == State.TACTICAL_MOVE:
			_change_state(State.ROAMING)

# ─────────────────────────────────────────
# ESTADOS
# ─────────────────────────────────────────

func _state_idle(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 10.0)
	velocity.z = move_toward(velocity.z, 0, 10.0)

func _state_roaming(delta: float) -> void:
	# Si tenemos un core enemigo, navegar hacia el
	if _enemy_core and is_instance_valid(_enemy_core) and _enemy_core.is_inside_tree() and not _enemy_core.is_destroyed:
		var dist_to_core: float = global_position.distance_to(_enemy_core.global_position)
		if dist_to_core < 4.0:
			_objective_reached = true
		
		# Solo actualizar target si: llegamos al destino o es la primera vez
		# NO usar is_navigation_finished() aqui porque retorna true mientras
		# el NavigationAgent calcula la ruta, causando un bucle de reset.
		if _nav_target == Vector3.ZERO or _objective_reached:
			var offset: Vector3 = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
			var raw_target: Vector3 = _enemy_core.global_position + offset
			# Asegurar que el target este sobre el navmesh
			var nav_map_rid: RID = navigation_agent.get_navigation_map()
			if NavigationServer3D.map_is_active(nav_map_rid):
				_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
			else:
				_nav_target = raw_target
			navigation_agent.target_position = _nav_target
			_objective_reached = false
		
		_move_to_target(delta, 4.0, _enemy_core.global_position)
	else:
		# Sin core: navegacion aleatoria
		if _nav_target == Vector3.ZERO or navigation_agent.is_navigation_finished():
			var nav_map_rid: RID = navigation_agent.get_navigation_map()
			var raw_target: Vector3 = global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			if NavigationServer3D.map_is_active(nav_map_rid):
				_nav_target = NavigationServer3D.map_get_closest_point(nav_map_rid, raw_target)
			else:
				_nav_target = raw_target
			navigation_agent.target_position = _nav_target
		_move_to_target(delta, 3.5, _nav_target)

func _state_attacking(delta: float) -> void:
	if not target_enemy or (is_instance_valid(target_enemy) and target_enemy.get("is_destroyed") == true):
		target_enemy = null
		_is_attacking_core = false
		_change_state(State.ROAMING)
		return
	
	# Apuntar al centro del objetivo
	var aim_pos: Vector3 = target_enemy.global_position
	if target_enemy is CharacterBody3D:
		aim_pos += Vector3.UP * 1.2
	else:
		aim_pos += Vector3.UP * 0.7
	
	_aim_at_target(aim_pos)
	
	if _weapon and _weapon.can_fire():
		_shoot()
	
	var dist: float = global_position.distance_to(target_enemy.global_position)
	
	if _is_attacking_core:
		if dist > 8.0:
			_move_to_target(delta, 5.0, target_enemy.global_position)
		else:
			velocity.x = move_toward(velocity.x, 0, 10.0)
			velocity.z = move_toward(velocity.z, 0, 10.0)
	else:
		if dist > 15.0:
			_move_to_target(delta, 5.5, target_enemy.global_position)
		else:
			_change_state(State.TACTICAL_MOVE)

func _state_tactical(_delta: float) -> void:
	if not target_enemy: return
	_aim_at_target(target_enemy.global_position + Vector3.UP * 1.2)
	
	if Time.get_ticks_msec() / 1000.0 - _last_strafe_change > randf_range(1.0, 3.0):
		_strafe_direction *= -1
		_last_strafe_change = Time.get_ticks_msec() / 1000.0
		if randf() < jumpiness and is_on_floor():
			velocity.y = 5.0
	
	var dir_to_enemy: Vector3 = (target_enemy.global_position - global_position).normalized()
	var side_dir: Vector3 = dir_to_enemy.cross(Vector3.UP) * _strafe_direction
	
	var dist: float = global_position.distance_to(target_enemy.global_position)
	var move_vec: Vector3 = side_dir
	if dist < 8.0: move_vec -= dir_to_enemy * 0.5
	elif dist > 12.0: move_vec += dir_to_enemy * 0.5
	
	velocity.x = move_vec.x * 5.0
	velocity.z = move_vec.z * 5.0
	
	if _weapon and _weapon.can_fire():
		_shoot()
	
	if dist > 20.0:
		_change_state(State.ATTACKING)

func _state_hunting(delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		target_enemy = null
		_change_state(State.ROAMING)
		return
	_move_to_target(delta, 6.0)

# ─────────────────────────────────────────
# ACCIONES
# ─────────────────────────────────────────

func _aim_at_target(target_pos: Vector3) -> void:
	# Rotación horizontal (Cuerpo)
	var look_pos: Vector3 = target_pos
	look_pos.y = global_position.y
	if global_position.distance_to(look_pos) > 0.1:
		look_at(look_pos, Vector3.UP)
	
	# Rotación vertical (Cabeza)
	if head:
		head.look_at(target_pos, Vector3.UP)
		head.rotation.y = 0 # Mantener solo rotación vertical
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-60), deg_to_rad(60))

func _move_to_target(delta: float, speed: float, target: Vector3 = Vector3.ZERO) -> void:
	# Solo actualizar target_position si cambio. Si se envia el mismo valor
	# cada frame, el NavigationAgent reinicia el calculo de ruta continuamente.
	if target != Vector3.ZERO and target != navigation_agent.target_position:
		navigation_agent.target_position = target
	elif target == Vector3.ZERO:
		# Usar el target actual del agente como referencia
		target = navigation_agent.target_position
	
	# Verificar que el mapa de navegación esté sincronizado antes de consultar
	var nav_map_rid: RID = navigation_agent.get_navigation_map()
	var map_iter: int = NavigationServer3D.map_get_iteration_id(nav_map_rid)
	if map_iter == 0:
		# Mapa no listo aún — mantener velocidad actual, no frenar
		return
	
	var nav_finished: bool = navigation_agent.is_navigation_finished()
	
	if nav_finished:
		# La navegación terminó. Si hemos llegado al destino, frenar.
		# Si no hemos llegado, el NavigationAgent aun esta calculando la ruta.
		# NO usar fallback en linea recta porque choca contra paredes.
		# Solo esperar a que el agente tenga la ruta lista.
		if target != Vector3.ZERO:
			var dist_to_target: float = global_position.distance_to(target)
			if dist_to_target <= navigation_agent.target_desired_distance:
				# Llegamos al destino — frenar suavemente
				velocity.x = move_toward(velocity.x, 0.0, speed * delta * 3.0)
				velocity.z = move_toward(velocity.z, 0.0, speed * delta * 3.0)
				return
		# No hemos llegado, esperar a que el agente calcule la ruta
		return
	
	var next_pos: Vector3 = navigation_agent.get_next_path_position()
	var dir: Vector3 = (next_pos - global_position).normalized()
	
	# Si la dirección es ~cero (next_pos == global_position), no frenar abruptamente
	if dir.length_squared() < 0.001:
		return
	
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _shoot() -> void:
	if not _weapon: return
	
	var killer_id: int = -1
	if is_instance_valid(MatchManager):
		killer_id = MatchManager.get_player_id_by_pawn(self)
	
	var hits: Array = _weapon.fire()
	for hit in hits:
		var col: Node = hit["collider"]
		if not col: continue
		var target: Node = col
		if target is Area3D: target = target.get_parent()
		while target and not target.has_method("take_damage"):
			target = target.get_parent()
		
		if target and target.has_method("take_damage"):
			if target is Player: target.take_damage(hit["damage_vs_player"], "Torso", killer_id)
			else: target.take_damage(hit["damage_vs_npc"], "Torso", killer_id)

# ─────────────────────────────────────────
# SISTEMA DE DAÑO & EQUIPOS
# ─────────────────────────────────────────

func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1) -> void:
	if is_dead: return
	var mult: float = 1.0
	if zone == "Cabeza": mult = 2.0
	current_health -= amount * mult
	
	# UT1: Retaliación inmediata si no tenemos objetivo (y no estamos atacando core)
	if target_enemy == null and not _is_attacking_core:
		_change_state(State.ATTACKING)
		
	if current_health <= 0:
		die(killer_id)

func die(killer_id: int = -1) -> void:
	if is_dead: return
	is_dead = true
	_drop_weapon()
	
	# Reportar muerte al MatchManager
	if is_instance_valid(MatchManager):
		MatchManager.reportar_muerte(self, killer_id)  # Estadisticas
		MatchManager.reportar_muerte_bot(self)          # Respawn timer + contadores
	
	# ── Nuevo comportamiento: NO destruir el bot ──
	# Deshabilitar fisicas, proceso, colisiones y visibilidad
	# El MatchManager se encarga del respawn reutilizando esta misma instancia
	set_physics_process(false)
	set_process(false)
	hide()
	
	# Deshabilitar colision
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = true
	
	# Detener navegacion
	if navigation_agent:
		navigation_agent.target_position = global_position
	
	_debug("MUERTO - esperando respawn...")

func _drop_weapon() -> void:
	if not DROPPED_WEAPON or not _weapon:
		return
	if not is_inside_tree():
		return
	var drop: Node = DROPPED_WEAPON.instantiate()
	if not drop: return
	get_parent().add_child(drop)
	drop.global_transform.origin = global_transform.origin + Vector3.UP * 0.5
	if drop.has_method("set_weapon_data"):
		drop.set_weapon_data({
			"tipo_arma": _weapon.weapon_name,
			"balas_cargador": _weapon.ammo_in_mag,
			"balas_reserva": _weapon.reserve_ammo,
			"capacidad_cargador": _weapon.clip_size
		})

func _re_evaluar_enemigos() -> void:
	target_enemy = null
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_nav_target = Vector3.ZERO
	_change_state(State.ROAMING)

# ─────────────────────────────────────────
# CORE DETECTION & STUCK HANDLING
# ─────────────────────────────────────────

func _find_enemy_core() -> void:
	_enemy_core = null
	_is_attacking_core = false
	_team_objective = Vector3.ZERO
	
	var cores: Array[Node] = get_tree().get_nodes_in_group("core")
	for core in cores:
		if not is_instance_valid(core):
			continue
		if core.get("is_destroyed") == true:
			continue
		var core_team: int = core.get("team") if "team" in core else -1
		if GameState.son_enemigos(equipo_id, core_team):
			_enemy_core = core
			_team_objective = core.global_position
			_debug("OBJETIVO: Core %s en %s" % [GameState.nombre_equipo(core_team), str(_team_objective)])
			return
	
	# Si no encontro core, reintentar
	get_tree().create_timer(1.0).timeout.connect(_find_enemy_core)

func _check_core_proximity() -> void:
	if not _enemy_core or not is_instance_valid(_enemy_core) or not _enemy_core.is_inside_tree():
		_find_enemy_core()
		return
	if _enemy_core.get("is_destroyed") == true:
		_enemy_core = null
		_is_attacking_core = false
		if current_state == State.ATTACKING and target_enemy == null:
			_change_state(State.ROAMING)
		return
	
	# Si ya estamos en combate con un personaje, no cambiar al core
	if target_enemy and target_enemy is CharacterBody3D and not target_enemy.get("is_dead"):
		return
	
	var dist: float = global_position.distance_to(_enemy_core.global_position)
	if dist > 25.0:
		return
	
	# Verificar linea de vision con el core
	var target_pos: Vector3 = _enemy_core.global_position + Vector3.UP * 0.7
	var local_target: Vector3 = to_local(target_pos)
	raycast_vision.target_position = local_target
	raycast_vision.force_raycast_update()
	
	var collider = raycast_vision.get_collider()
	var core_hit: bool = (collider == _enemy_core)
	if not core_hit and collider:
		var parent_check: Node = collider.get_parent()
		while parent_check:
			if parent_check == _enemy_core:
				core_hit = true
				break
			parent_check = parent_check.get_parent()
	
	if core_hit:
		if not _is_attacking_core or target_enemy != _enemy_core:
			_is_attacking_core = true
			target_enemy = _enemy_core
			if current_state != State.ATTACKING and current_state != State.TACTICAL_MOVE:
				_change_state(State.ATTACKING)
			_debug("ATACANDO CORE enemigo! Distancia: %.1f" % dist)
	else:
		if _is_attacking_core:
			_is_attacking_core = false
			target_enemy = null
			_change_state(State.ROAMING)

func _check_stuck(delta: float) -> bool:
	if current_state == State.IDLE or is_dead:
		_stuck_timer = 0.0
		_last_position = global_position
		return false
	
	var moved: float = global_position.distance_to(_last_position)
	# Usar distance_to en lugar de distance_squared_to porque a 60fps
	# un bot moviendose a 4u/s recorre ~0.067u/frame, y 0.067^2=0.0044,
	# que ESTA por debajo del viejo umbral de 0.01 (falso positivo).
	# Con distance_to, el umbral 0.05 equivale a ~3u/s minimo detectables.
	if moved < 0.05:
		_stuck_timer += delta
		if _stuck_timer >= _stuck_threshold:
			_debug("ATASCADO! Saltando y buscando ruta alternativa...")
			_stuck_timer = 0.0
			# Saltar para superar obstaculos bajos y activar movimiento vertical
			if is_on_floor():
				velocity.y = jumpiness * 15.0 + 2.0
			# Empuje fuerte en direccion aleatoria
			var push_dir: Vector3 = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized()
			velocity.x = push_dir.x * 5.0
			velocity.z = push_dir.z * 5.0
			
			# Recalcular ruta a un punto aleatorio del navmesh
			var random_offset: Vector3 = Vector3(randf_range(-15.0, 15.0), 0, randf_range(-15.0, 15.0))
			var nav_map: RID = navigation_agent.get_navigation_map()
			if NavigationServer3D.map_is_active(nav_map):
				var raw_target: Vector3 = global_position + random_offset
				var valid_target: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, raw_target)
				navigation_agent.target_position = valid_target
			else:
				navigation_agent.target_position = global_position + random_offset
			
			# Devuelve true para que _physics_process SKIP el movimiento
			# del estado este frame, permitiendo que el empuje+salto
			# surta efecto en move_and_slide()
			return true
	else:
		_stuck_timer = max(0.0, _stuck_timer - delta * 2.0)
	
	_last_position = global_position
	return false

func _equipar_arma() -> void:
	if nombre_arma == "": return
	var weapon_instance: Node3D = WEAPON_PLACEHOLDER.instantiate()
	# Añadir al nodo Head para que apunte con la mirada vertical
	if head:
		head.add_child(weapon_instance)
		_weapon = weapon_instance as Weapon
		if _weapon:
			_weapon.initialize_from_name(nombre_arma)

func _aplicar_color_equipo() -> void:
	var color: Color = GameState.color_equipo(equipo_id)
	if has_node("MeshInstance3D"): _aplicar_color_a_mesh($MeshInstance3D, color)
	if has_node("Head/HeadMesh"): _aplicar_color_a_mesh($Head/HeadMesh, color)

func _aplicar_color_a_mesh(mesh: MeshInstance3D, color: Color) -> void:
	var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
	if not mat: mat = mesh.mesh.surface_get_material(0) as StandardMaterial3D
	if not mat: return
	mat = mat.duplicate()
	mat.albedo_color = color
	mesh.set_surface_override_material(0, mat)

## Llamado por MatchManager para reutilizar esta instancia tras un respawn.
## Restaura el bot a su estado operativo completo.
func respawn() -> void:
	is_dead = false
	current_health = max_health
	
	# Re-habilitar proceso y visibilidad
	set_physics_process(true)
	set_process(true)
	show()
	
	# Re-habilitar colision
	var cs: CollisionShape3D = find_child("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.disabled = false
	
	# Restaurar estado de la FSM — resetear TODO lo que dependa del equipo
	_change_state(State.IDLE)
	target_enemy = null
	_is_attacking_core = false
	_enemy_core = null
	_team_objective = Vector3.ZERO
	_nav_target = Vector3.ZERO
	_stuck_timer = 0.0
	
	# Re-equipar arma
	_equipar_arma()
	_aplicar_color_equipo()
	
	# Buscar core enemigo y re-evaluar
	call_deferred("_find_enemy_core")
	get_tree().create_timer(0.5).timeout.connect(_start_roaming)
	
	_debug("RESPAWNEADO")

func _debug(msg: String) -> void:
	print("[NPC #%d | %s] %s" % [_npc_id, GameState.nombre_equipo(equipo_id), msg])
