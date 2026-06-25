# scripts/iaskill.gd
# Sistema de IA táctica inspirado en F.E.A.R.
# Componente Node que se agrega como hijo del NpcBase.
# Maneja: FSM de estados, detección por ruido/visión, cobertura, flanqueo,
#          recarga, y experiencia diferenciada.
class_name IASkill
extends Node

# ─── Señales ──────────────────────────────────────────────────────────
signal estado_cambiado(estado_anterior: int, estado_nuevo: int)
signal objetivo_detectado(objetivo: Node3D)
signal objetivo_perdido(ultima_posicion: Vector3)
signal ruido_detectado(posicion: Vector3)

# ─── Enums ────────────────────────────────────────────────────────────
enum EstadoTactico {
	IDLE,          # Sin objetivo, patrulla o espera
	ALERTA,        # Detectó ruido/movimiento, investiga posición
	ATACANDO,      # Línea de visión al enemigo, dispara
	BUSCANDO,      # Perdió visión, va a última posición conocida
	ESCONDIENDOSE, # Busca cobertura, recarga o espera que baje amenaza
	MUERTO         # NPC muerto
}

enum ExperienciaIA {
	BAJA,   # Lenta, imprecisa, no busca cover
	MEDIA,  # Estándar, cover ocasional
	ALTA    # Rápida, busca cover, flanquea, coordina
}

# ─── Exports (configurables desde editor) ─────────────────────────────
@export var experiencia: ExperienciaIA = ExperienciaIA.MEDIA

# Radio de detección de ruido (esfera alrededor del NPC)
@export var noise_detection_radius: float = 12.0

# Dimensiones del cono de visión (caja alargada frente al NPC)
@export var vision_width: float  = 3.0
@export var vision_height: float = 2.5
@export var vision_depth: float  = 18.0

# Offset vertical del origen del raycast de visión
@export var vision_ray_height: float = 1.2

# Tiempo que el NPC recuerda la última posición antes de rendirse
@export var buscar_timeout: float = 5.0

# Tiempo mínimo en escondite antes de reevaluar
@export var esconder_timeout: float = 3.0

# Tiempo de recarga en segundos
@export var reload_time: float = 2.0

# ─── Variables de estado ──────────────────────────────────────────────
var npc: NpcBase = null
var estado_actual: EstadoTactico = EstadoTactico.IDLE
var estado_anterior: EstadoTactico = EstadoTactico.IDLE

# Referencias al objetivo
var objetivo: Node3D = null
var ultima_pos_objetivo: Vector3 = Vector3.ZERO
var pos_investigar: Vector3 = Vector3.ZERO

# Temporizadores
var state_timer: float = 0.0
var buscar_timer: float = 0.0
var esconder_timer: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false
var decision_timer: float = 0.0
const DECISION_INTERVAL: float = 0.5  # Reevaluar cada 0.5s

# Munición
var balas_cargador: int = 0
var capacidad_cargador: int = 0
var balas_reserva: int = 0
var es_arma_fuego: bool = false

# Cobertura
var cover_position: Vector3 = Vector3.ZERO
var in_cover: bool = false

# Nodos de detección (creados en _ready)
var noise_area: Area3D = null
var noise_shape: CollisionShape3D = null
var vision_area: Area3D = null
var vision_shape: CollisionShape3D = null
var vision_raycast: RayCast3D = null

# ─── Inicialización ───────────────────────────────────────────────────

func _ready() -> void:
	# Nos desactivamos hasta que el NPC nos asigne
	set_process(false)
	set_physics_process(false)

## Inicializa el módulo de IA. Llamar desde NpcBase._ready().
func initialize(npc_ref: NpcBase) -> void:
	npc = npc_ref
	_configure_from_weapon()
	_create_noise_area()
	_create_vision_area()
	_create_vision_raycast()

	estado_actual = EstadoTactico.IDLE if not npc.is_dead else EstadoTactico.MUERTO
	state_timer = 0.0

	set_process(true)
	set_physics_process(true)
	print("IASkill: Inicializado para '%s' — exp=%s arma=%s" % [
		npc.npc_name, _exp_name(), npc.nombre_arma
	])

## Lee skill.json y configura las variables de munición.
func _configure_from_weapon() -> void:
	if npc.nombre_arma == "":
		es_arma_fuego = false
		capacidad_cargador = 0
		balas_cargador = 0
		balas_reserva = 0
		return

	var cfg: Dictionary = ConfigManager.get_arma(npc.nombre_arma)
	if cfg.is_empty():
		es_arma_fuego = false
		return

	var tiene_cargador: bool = cfg.has("TamanoCargador")
	es_arma_fuego = tiene_cargador

	if es_arma_fuego:
		capacidad_cargador = int(cfg.get("TamanoCargador", 30))
		balas_cargador = capacidad_cargador
		balas_reserva = int(cfg.get("ReservaMunicionMaxima", 120))
		reload_time = float(cfg.get("TiempoRecargaSegundos", 2.0))
	else:
		capacidad_cargador = 0
		balas_cargador = 0
		balas_reserva = 0

# ─── Creación de áreas de detección ───────────────────────────────────

func _create_noise_area() -> void:
	if not npc or not is_instance_valid(npc):
		return

	noise_area = Area3D.new()
	noise_area.name = "NoiseDetectionArea"
	noise_area.collision_layer = 0
	# Detectar jugador (capa 1) y otros NPCs (capa 4)
	noise_area.collision_mask = 1 | 4

	noise_shape = CollisionShape3D.new()
	noise_shape.name = "NoiseCollision"
	var sphere := SphereShape3D.new()
	sphere.radius = noise_detection_radius
	noise_shape.shape = sphere
	noise_area.add_child(noise_shape)

	# Debug: esfera amarilla transparente
	var debug_mesh := MeshInstance3D.new()
	debug_mesh.name = "NoiseDebug"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = noise_detection_radius
	sphere_mesh.height = noise_detection_radius * 2.0
	debug_mesh.mesh = sphere_mesh
	var debug_mat := StandardMaterial3D.new()
	debug_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.08)  # Amarillo transparente
	debug_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	debug_mat.cull_mode = BaseMaterial3D.CULL_BACK
	debug_mesh.set_surface_override_material(0, debug_mat)
	debug_mesh.top_level = false
	noise_area.add_child(debug_mesh)

	noise_area.body_entered.connect(_on_noise_body_entered)

	npc.add_child(noise_area)

func _create_vision_area() -> void:
	if not npc or not is_instance_valid(npc):
		return

	vision_area = Area3D.new()
	vision_area.name = "VisionArea"
	vision_area.collision_layer = 0
	# Detectar jugador (capa 1) y otros NPCs (capa 4)
	vision_area.collision_mask = 1 | 4

	vision_shape = CollisionShape3D.new()
	vision_shape.name = "VisionCollision"
	var box := BoxShape3D.new()
	box.size = Vector3(vision_width, vision_height, vision_depth)
	vision_shape.shape = box
	vision_area.add_child(vision_shape)

	# Posicionar la caja delante del NPC (local +Z es adelante, por eso half-depth)
	vision_shape.position = Vector3(0, vision_height * 0.4, vision_depth * 0.5)

	# Debug: caja verde transparente
	var debug_mesh_box := MeshInstance3D.new()
	debug_mesh_box.name = "VisionDebug"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(vision_width, vision_height, vision_depth)
	debug_mesh_box.mesh = box_mesh
	var debug_mat_box := StandardMaterial3D.new()
	debug_mat_box.albedo_color = Color(0.0, 1.0, 0.0, 0.06)  # Verde transparente
	debug_mat_box.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	debug_mat_box.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat_box.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	debug_mat_box.cull_mode = BaseMaterial3D.CULL_BACK
	debug_mesh_box.set_surface_override_material(0, debug_mat_box)
	debug_mesh_box.position = Vector3(0, vision_height * 0.4, vision_depth * 0.5)
	vision_area.add_child(debug_mesh_box)

	vision_area.body_entered.connect(_on_vision_body_entered)

	npc.add_child(vision_area)

func _create_vision_raycast() -> void:
	if not npc or not is_instance_valid(npc):
		return

	vision_raycast = RayCast3D.new()
	vision_raycast.name = "VisionRayCast"
	vision_raycast.enabled = true
	vision_raycast.hit_from_inside = true
	vision_raycast.collision_mask = npc.collision_mask
	vision_raycast.exclude_parent = true
	vision_raycast.target_position = Vector3(0, 0, -vision_depth)
	vision_raycast.position = Vector3(0, vision_ray_height, 0)
	npc.add_child(vision_raycast)

# ─── Procesamiento principal ──────────────────────────────────────────

func _process(_delta: float) -> void:
	if not npc or not is_instance_valid(npc) or npc.is_dead:
		return

	if npc._healthbar_root and is_instance_valid(npc._healthbar_root):
		var cam: Camera3D = npc.get_viewport().get_camera_3d()
		if cam:
			npc._healthbar_root.look_at(cam.global_transform.origin, Vector3.UP)

	# Forzar muerte si el NPC murió externamente
	if npc.current_health <= 0 and estado_actual != EstadoTactico.MUERTO:
		_force_death()
		return

func _physics_process(delta: float) -> void:
	if not npc or not is_instance_valid(npc) or npc.is_dead:
		return

	if estado_actual == EstadoTactico.MUERTO:
		return

	npc._retarget_timer += delta
	if npc._retarget_timer >= npc.RETARGET_INTERVAL and not _tiene_objetivo_valido():
		npc._retarget_timer = 0.0
		npc._pick_target()
		if npc.target and is_instance_valid(npc.target):
			_on_target_found(npc.target as Node3D)

	# Gravedad
	if not npc.is_on_floor():
		npc.velocity.y -= npc.gravity * delta
	else:
		npc.velocity.y = 0.0

	# Timers de estado
	state_timer += delta
	decision_timer += delta

	# Ejecutar estado actual
	match estado_actual:
		EstadoTactico.IDLE:
			_exec_idle(delta)
		EstadoTactico.ALERTA:
			_exec_alerta(delta)
		EstadoTactico.ATACANDO:
			_exec_atacando(delta)
		EstadoTactico.BUSCANDO:
			_exec_buscando(delta)
		EstadoTactico.ESCONDIENDOSE:
			_exec_escondiendose(delta)

	npc.move_and_slide()

# ─── Fábrica de estados ───────────────────────────────────────────────

func _cambiar_estado(nuevo: EstadoTactico) -> void:
	if estado_actual == nuevo:
		return
	estado_anterior = estado_actual
	var _anterior_str: String = EstadoTactico.keys()[estado_anterior]
	var _nuevo_str: String = EstadoTactico.keys()[nuevo]
	estado_actual = nuevo
	state_timer = 0.0
	estado_cambiado.emit(estado_anterior, nuevo)

	# Resetear timers específicos al cambiar
	match nuevo:
		EstadoTactico.ALERTA:
			pass
		EstadoTactico.BUSCANDO:
			buscar_timer = 0.0
		EstadoTactico.ESCONDIENDOSE:
			esconder_timer = 0.0

# ─── Implementación de estados ────────────────────────────────────────

## IDLE: Sin objetivo. Idealmente patrulla, pero por ahora espera o deambula.
func _exec_idle(_delta: float) -> void:
	# Frenar
	npc.velocity.x = move_toward(npc.velocity.x, 0, npc.speed * 0.5)
	npc.velocity.z = move_toward(npc.velocity.z, 0, npc.speed * 0.5)

	# Si tenemos objetivo, cambiar a ATACANDO inmediatamente
	if _tiene_objetivo_valido():
		_cambiar_estado(EstadoTactico.ATACANDO)
		return

	# Buscar objetivo periódicamente
	if decision_timer >= DECISION_INTERVAL:
		decision_timer = 0.0
		_buscar_objetivo_activo()

## ALERTA: Investigar posición de ruido/movimiento sospechoso.
func _exec_alerta(_delta: float) -> void:
	if _tiene_objetivo_valido():
		_cambiar_estado(EstadoTactico.ATACANDO)
		return

	# Verificar si hay línea de visión hacia la posición de investigación
	if _check_line_of_sight_to_point(pos_investigar):
		objetivo = _find_target_at_position(pos_investigar)
		if objetivo and is_instance_valid(objetivo):
			ultima_pos_objetivo = objetivo.global_transform.origin
			_cambiar_estado(EstadoTactico.ATACANDO)
			return

	# Moverse hacia la posición de investigación
	var dir: Vector3 = _direction_to(pos_investigar)
	if dir.length_squared() > 0.1:
		npc.velocity.x = dir.x * npc.speed * 0.8
		npc.velocity.z = dir.z * npc.speed * 0.8
		npc.look_at_target_flat(pos_investigar)
	else:
		npc.velocity.x = move_toward(npc.velocity.x, 0, npc.speed * 0.5)
		npc.velocity.z = move_toward(npc.velocity.z, 0, npc.speed * 0.5)

	# Si llegamos o pasó demasiado tiempo, volver a IDLE
	var dist_inv: float = npc.global_transform.origin.distance_to(pos_investigar)
	if dist_inv < 1.5 or state_timer > 6.0:
		_cambiar_estado(EstadoTactico.IDLE)

## ATACANDO: Línea de visión al enemigo. Disparar según cadencia.
func _exec_atacando(_delta: float) -> void:
	if not _tiene_objetivo_valido():
		_cambiar_estado(EstadoTactico.IDLE)
		return

	var target_pos: Vector3 = objetivo.global_transform.origin
	var dist: float = npc.global_transform.origin.distance_to(target_pos)

	# Mirar al objetivo
	npc.look_at_target_flat(target_pos)

	# Verificar línea de visión
	if _has_line_of_sight():
		ultima_pos_objetivo = target_pos

		# Disparar
		if es_arma_fuego:
			if balas_cargador <= 0:
				_cambiar_estado(EstadoTactico.ESCONDIENDOSE)
				return

			if npc.attempt_attack_with_ammo():
				balas_cargador -= 1
		else:
			# Arma melee: acercarse y atacar
			if dist <= npc.attack_range:
				npc.velocity.x = 0
				npc.velocity.z = 0
				npc.attempt_attack()
			else:
				var dir: Vector3 = _direction_to(target_pos)
				npc.velocity.x = dir.x * npc.speed
				npc.velocity.z = dir.z * npc.speed

		# Experiencia: NPCs con ALTA pueden flanquear
		if experiencia == ExperienciaIA.ALTA and dist < vision_depth * 0.6:
			if _should_flank():
				_exec_flanking_move(target_pos)
	else:
		# Perdió línea de visión
		_cambiar_estado(EstadoTactico.BUSCANDO)

func _exec_flanking_move(target_pos: Vector3) -> void:
	# Movimiento lateral al objetivo para flanquear
	var dir_to_target: Vector3 = (target_pos - npc.global_transform.origin).normalized()
	var perpendicular: Vector3 = Vector3(-dir_to_target.z, 0, dir_to_target.x).normalized()
	var flank_dir: Vector3 = perpendicular * sign(sin(Time.get_ticks_msec() * 0.001))
	npc.velocity.x = flank_dir.x * npc.speed * 0.6 + _direction_to(target_pos).x * npc.speed * 0.4
	npc.velocity.z = flank_dir.z * npc.speed * 0.6 + _direction_to(target_pos).z * npc.speed * 0.4

## BUSCANDO: Perdió visión, va a última posición conocida.
func _exec_buscando(_delta: float) -> void:
	buscar_timer += _delta

	# Si reaparece línea de visión, volver a ATACANDO
	if _tiene_objetivo_valido() and _has_line_of_sight():
		_cambiar_estado(EstadoTactico.ATACANDO)
		return

	# Moverse hacia la última posición conocida
	var dir: Vector3 = _direction_to(ultima_pos_objetivo)
	if dir.length_squared() > 0.1:
		npc.velocity.x = dir.x * npc.speed
		npc.velocity.z = dir.z * npc.speed
		npc.look_at_target_flat(ultima_pos_objetivo)
	else:
		npc.velocity.x = move_toward(npc.velocity.x, 0, npc.speed * 0.3)
		npc.velocity.z = move_toward(npc.velocity.z, 0, npc.speed * 0.3)

	# Si llegó a la última posición y no ve nada -> rendirse
	var dist: float = npc.global_transform.origin.distance_to(ultima_pos_objetivo)
	if dist < 1.5 or buscar_timer > buscar_timeout:
		_cambiar_estado(EstadoTactico.IDLE)

## ESCONDIENDOSE: Busca cobertura, recarga o espera.
func _exec_escondiendose(delta: float) -> void:
	esconder_timer += delta

	# Si tenemos objetivo visible, salir a ATACAR
	if _tiene_objetivo_valido() and _has_line_of_sight():
		_cambiar_estado(EstadoTactico.ATACANDO)
		return

	# Prioridad 1: Recargar si está vacío
	if es_arma_fuego and (balas_cargador <= 0 or is_reloading) and balas_reserva > 0:
		_exec_reload(delta)
		return

	# Prioridad 2: Buscar cobertura
	if not in_cover or esconder_timer > esconder_timeout:
		if _find_cover_position():
			in_cover = true
			var dir: Vector3 = _direction_to(cover_position)
			if dir.length_squared() > 0.1:
				npc.velocity.x = dir.x * npc.speed * 1.2
				npc.velocity.z = dir.z * npc.speed * 1.2
				npc.look_at_target_flat(cover_position)
				return

	# Si estamos en cover, quedarnos quietos
	npc.velocity.x = move_toward(npc.velocity.x, 0, npc.speed * 1.5)
	npc.velocity.z = move_toward(npc.velocity.z, 0, npc.speed * 1.5)

	# Salir del estado si recargamos y pasó suficiente tiempo
	if esconder_timer > esconder_timeout and not is_reloading:
		in_cover = false
		if _tiene_objetivo_valido():
			_cambiar_estado(EstadoTactico.BUSCANDO)
		else:
			_cambiar_estado(EstadoTactico.IDLE)

## Recarga: timer controlado.
func _exec_reload(delta: float) -> void:
	if not is_reloading:
		is_reloading = true
		reload_timer = 0.0
		print("IASkill: %s recargando..." % npc.npc_name)

	reload_timer += delta
	if reload_timer >= reload_time:
		_recargar_completado()

	# Mirar alrededor mientras recarga
	if _tiene_objetivo_valido():
		npc.look_at_target_flat(ultima_pos_objetivo)

func _recargar_completado() -> void:
	if not es_arma_fuego:
		is_reloading = false
		return

	var needed: int = capacidad_cargador - balas_cargador
	var transfer: int = min(needed, balas_reserva)
	balas_cargador += transfer
	balas_reserva -= transfer
	is_reloading = false
	print("IASkill: %s recargó — cargador=%d/%d reserva=%d" % [
		npc.npc_name, balas_cargador, capacidad_cargador, balas_reserva
	])

# ─── Detección de ruido ───────────────────────────────────────────────

func _on_noise_body_entered(body: Node) -> void:
	if estado_actual == EstadoTactico.MUERTO:
		return
	if not body or not is_instance_valid(body):
		return
	if body == npc:
		return

	# Solo reaccionar a jugador y otros NPCs
	var es_interesante: bool = body.is_in_group("player") or body.is_in_group("npcs")
	if not es_interesante:
		return

	# No reaccionar a aliados
	if body is NpcBase and npc._es_enemigo_de_nodo(body):
		pass  # Es enemigo, seguir
	elif body.is_in_group("player") and npc._es_enemigo_de_nodo(body):
		pass  # Es jugador enemigo, seguir
	else:
		return  # Aliado, ignorar

	var source_pos: Vector3 = (body as Node3D).global_transform.origin

	# El ruido NO da la posición exacta -> generamos un punto de investigación
	# con un offset aleatorio
	var offset := Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-0.5, 0.5),
		randf_range(-3.0, 3.0)
	)
	var investigar_pos: Vector3 = source_pos + offset

	_trigger_noise_alert(investigar_pos)

func _trigger_noise_alert(pos: Vector3) -> void:
	if estado_actual == EstadoTactico.ATACANDO or estado_actual == EstadoTactico.MUERTO:
		return

	if estado_actual == EstadoTactico.ESCONDIENDOSE and not is_reloading:
		return

	# Experiencia: ALTA reacciona más rápido (no ignora ruido)
	if experiencia == ExperienciaIA.BAJA and estado_actual == EstadoTactico.IDLE and randf() < 0.4:
		return  # 40% de ignorar el ruido si es BAJA

	pos_investigar = pos
	ruido_detectado.emit(pos)
	_cambiar_estado(EstadoTactico.ALERTA)

# ─── Detección visual ─────────────────────────────────────────────────

func _on_vision_body_entered(body: Node) -> void:
	if estado_actual == EstadoTactico.MUERTO:
		return
	if not body or not is_instance_valid(body):
		return
	if body == npc:
		return
	if not _es_enemigo_valido(body):
		return

	# Verificar línea de visión con raycast
	if _has_line_of_sight_to_body(body as Node3D):
		_on_target_found(body as Node3D)

## Verifica línea de visión directa usando el RayCast3D.
func _has_line_of_sight() -> bool:
	if not objetivo or not is_instance_valid(objetivo):
		return false
	return _has_line_of_sight_to_body(objetivo)

func _has_line_of_sight_to_body(body: Node3D) -> bool:
	if not vision_raycast or not body:
		return false

	var origin: Vector3 = npc.global_transform.origin + Vector3(0, vision_ray_height, 0)
	var target_pos: Vector3 = body.global_transform.origin + Vector3(0, vision_ray_height * 0.7, 0)

	# Actualizar target del raycast
	var local_target: Vector3 = npc.to_local(target_pos)
	vision_raycast.target_position = local_target
	vision_raycast.force_raycast_update()

	if vision_raycast.is_colliding():
		var collider: Node = vision_raycast.get_collider()
		# Si el collider es el objetivo o un hijo del objetivo -> línea limpia
		if collider == body or (collider and _is_child_of_node(collider, body)):
			return true
		# También aceptar si el collider es el mismo NPC (hit_from_inside)
		if collider == npc:
			return true
		return false

	# No chocó con nada -> línea limpia
	return true

func _check_line_of_sight_to_point(point: Vector3) -> bool:
	if not vision_raycast:
		return false

	var local_target: Vector3 = npc.to_local(point)
	vision_raycast.target_position = local_target
	vision_raycast.force_raycast_update()

	if vision_raycast.is_colliding():
		var collider: Node = vision_raycast.get_collider()
		return collider == npc  # Solo el mismo NPC (no hay pared)

	return true  # No hay obstrucción

func _on_target_found(ene: Node3D) -> void:
	objetivo = ene
	ultima_pos_objetivo = ene.global_transform.origin
	objetivo_detectado.emit(ene)

	# Experiencia: ALTA reacciona inmediatamente
	if experiencia == ExperienciaIA.ALTA:
		_cambiar_estado(EstadoTactico.ATACANDO)
	elif experiencia == ExperienciaIA.BAJA:
		# Retardo artificial en reacción
		if state_timer < 0.5:
			_cambiar_estado(EstadoTactico.ALERTA)
		else:
			_cambiar_estado(EstadoTactico.ATACANDO)
	else:
		_cambiar_estado(EstadoTactico.ATACANDO)

# ─── Cobertura ────────────────────────────────────────────────────────

func _find_cover_position() -> bool:
	if not _tiene_objetivo_valido():
		return false

	# Solo buscar cobertura si experiencia lo permite
	if experiencia == ExperienciaIA.BAJA:
		return false

	var chance_cover: float = 0.3 if experiencia == ExperienciaIA.MEDIA else 0.7
	if randf() > chance_cover:
		return false

	var target_pos: Vector3 = objetivo.global_transform.origin
	var npc_pos: Vector3 = npc.global_transform.origin

	# Dirección opuesta al objetivo + offset lateral aleatorio
	var away_dir: Vector3 = (npc_pos - target_pos).normalized()
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.1:
		away_dir = Vector3(1, 0, 0)

	# Buscar posición de cobertura a 3-8 unidades del NPC, lejos del enemigo
	var cover_dist: float = randf_range(3.0, 8.0)
	var lateral_offset: float = randf_range(-4.0, 4.0)
	var lateral_dir: Vector3 = Vector3(-away_dir.z, 0, away_dir.x).normalized()

	cover_position = npc_pos + away_dir * cover_dist + lateral_dir * lateral_offset
	cover_position.y = npc_pos.y

	# Verificar que la posición de cobertura no esté expuesta al enemigo
	var space_state: PhysicsDirectSpaceState3D = npc.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		cover_position + Vector3(0, 1.0, 0),
		target_pos + Vector3(0, 1.0, 0)
	)
	q.exclude = [npc]
	var res: Dictionary = space_state.intersect_ray(q)

	# Si hay algo entre cover y target (una pared), es buen cover
	if res and res.get("collider") != objetivo:
		return true

	# Si no hay obstáculo, el cover no sirve
	return false

# ─── Flanqueo ─────────────────────────────────────────────────────────

func _should_flank() -> bool:
	if experiencia != ExperienciaIA.ALTA:
		return false
	if not _tiene_objetivo_valido():
		return false
	if randf() > 0.3:  # 30% de chance por tick
		return false
	# No flanquear si estamos muy cerca
	var dist: float = npc.global_transform.origin.distance_to(objetivo.global_transform.origin)
	return dist > 3.0

# ─── Búsqueda de objetivo ─────────────────────────────────────────────

func _buscar_objetivo_activo() -> void:
	if _tiene_objetivo_valido():
		return

	# Buscar jugador
	var player: Node = npc.get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and npc._es_enemigo_de_nodo(player):
		if not player.is_in_group("invisible_to_npc"):
			if _has_line_of_sight_to_body(player as Node3D):
				_on_target_found(player as Node3D)
				return

	# Buscar otros NPCs
	for node in npc.get_tree().get_nodes_in_group("npcs"):
		if node == npc:
			continue
		if node is NpcBase and not node.is_dead and npc._es_enemigo_de_nodo(node):
			if _has_line_of_sight_to_body(node as Node3D):
				_on_target_found(node as Node3D)
				return

func _find_target_at_position(pos: Vector3) -> Node3D:
	# Busca qué entidad está en la posición investigada
	var player: Node = npc.get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		var dist: float = (player as Node3D).global_transform.origin.distance_to(pos)
		if dist < 2.0 and npc._es_enemigo_de_nodo(player):
			return player as Node3D

	for node in npc.get_tree().get_nodes_in_group("npcs"):
		if node == npc:
			continue
		if node is NpcBase and not node.is_dead:
			var dist: float = (node as Node3D).global_transform.origin.distance_to(pos)
			if dist < 2.0 and npc._es_enemigo_de_nodo(node):
				return node as Node3D

	return null

# ─── Utilidades ───────────────────────────────────────────────────────

func _tiene_objetivo_valido() -> bool:
	return objetivo != null and is_instance_valid(objetivo) and not _is_dead(objetivo)

func _is_dead(node: Node) -> bool:
	if node.has_method("is_dead"):
		return node.get("is_dead") == true
	return false

func _es_enemigo_valido(body: Node) -> bool:
	if not is_instance_valid(body):
		return false
	if body == npc:
		return false
	return npc._es_enemigo_de_nodo(body)

func _is_child_of_node(child: Node, parent: Node) -> bool:
	var current: Node = child
	while current:
		if current == parent:
			return true
		current = current.get_parent()
	return false

func _direction_to(target: Vector3) -> Vector3:
	var dir: Vector3 = (target - npc.global_transform.origin).normalized()
	dir.y = 0.0
	return dir

func _force_death() -> void:
	_cambiar_estado(EstadoTactico.MUERTO)
	set_process(false)
	set_physics_process(false)

func _exp_name() -> String:
	match experiencia:
		ExperienciaIA.BAJA: return "BAJA"
		ExperienciaIA.MEDIA: return "MEDIA"
		ExperienciaIA.ALTA:  return "ALTA"
	return "?"

# ─── Consulta de munición ─────────────────────────────────────────────

func tiene_municion_suficiente() -> bool:
	return balas_cargador > 0 or balas_reserva > 0

func porcentaje_municion() -> float:
	if capacidad_cargador <= 0:
		return 1.0
	return float(balas_cargador) / float(capacidad_cargador)

## Devuelve datos de munición para el arma dropeada.
func get_ammo_data() -> Dictionary:
	return {
		"tipo_arma": npc.nombre_arma,
		"balas_cargador": balas_cargador,
		"balas_reserva": balas_reserva,
		"capacidad_cargador": capacidad_cargador
	}

# ─── Limpieza ─────────────────────────────────────────────────────────

func _exit_tree() -> void:
	set_process(false)
	set_physics_process(false)
