extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────

enum Sexo        { MASCULINO, FEMENINO }
enum Relacion    { AMIGABLE, NEUTRAL, ENEMIGO }
enum Experiencia { BAJA, MEDIA, ALTA }
enum EstadoTactico {
	IDLE,
	GUARDIA,
	ALERTA,
	BUSCANDO,
	ESCONDIENDO,
	SIGUIENDO,
	ATACANDO,
	ARRANSE
}

# ─────────────────────────────────────────
# IDENTIDAD
# ─────────────────────────────────────────

@export var npc_name: String = "NPC"
@export var especie: String = ""
@export var sexo: Sexo = Sexo.MASCULINO
@export var relacion: Relacion = Relacion.ENEMIGO
@export var experiencia: Experiencia = Experiencia.MEDIA
@export var skin_path: String = ""
@export var voz_path: String = ""

# ─────────────────────────────────────────
# ARMA
# El NPC se identifica por el arma que porta, no por su clase.
# nombre_arma se setea en el editor o en spawn. La logica de disparo
# usa los datos del arma directo desde ConfigManager.
# ─────────────────────────────────────────

@export var nombre_arma: String = "USP"

# Propiedades calculadas desde el arma (se llenan en _ready)
var arma_danio: float = 10.0
var arma_rango: float = 50.0
var arma_spread: float = 0.0
var arma_segundos_por_bala: float = 1.0
var arma_pellets: int = 1
var _arma_cfg: Dictionary = {}

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

@export var max_health: float = 30.0
@export var speed: float = 3.0
@export var attack_range: float = 2.0
@export var attack_rate: float = 1.0
# 'damage' se calcula desde el arma; sigue disponible como override manual.
@export var damage: float = 10.0

# ─────────────────────────────────────────
# ARRANCARSE - Configuracion
# ─────────────────────────────────────────

@export var umbral_arrancarse: float = 0.2
@export var radio_busqueda_vida: float = 20.0

# ─────────────────────────────────────────
# VARIABLES INTERNAS
# ─────────────────────────────────────────

var estado_actual: EstadoTactico = EstadoTactico.IDLE
var current_health: float = 30.0
var target: Node3D = null
var last_attack_time: int = 0
var is_dead: bool = false
var _base_color: Color = Color.WHITE

var _estimulo_audio_activo: bool = false
var _estimulo_vision_activo: bool = false

var _enemigos_en_rango_vision: Array[Node3D] = []
var _timer_reaccion: float = 0.0
var _reaccionando: bool = false
var _objetivo_reaccion: Node3D = null

var _posicion_ruido: Vector3 = Vector3.ZERO
var _hay_ruido: bool = false

var _objetivo_vida: Node3D = null
var _objetivo_aliado: Node3D = null

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
@onready var area_vision: Area3D = get_node_or_null("AreaVision")
@onready var area_audio: Area3D = get_node_or_null("AreaAudio")
@onready var raycast_vision: RayCast3D = get_node_or_null("RaycastVision")

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	current_health = max_health
	estado_actual = EstadoTactico.IDLE
	target = null

	_cargar_arma()
	_apply_relation_color()

	if area_vision:
		if not area_vision.body_entered.is_connected(_on_vision_body_entered):
			area_vision.body_entered.connect(_on_vision_body_entered)
		if not area_vision.body_exited.is_connected(_on_vision_body_exited):
			area_vision.body_exited.connect(_on_vision_body_exited)
	else:
		push_warning("[NpcBase] " + npc_name + ": No se encontro AreaVision.")

	if area_audio:
		if not area_audio.body_entered.is_connected(_on_audio_body_entered):
			area_audio.body_entered.connect(_on_audio_body_entered)
		if not area_audio.body_exited.is_connected(_on_audio_body_exited):
			area_audio.body_exited.connect(_on_audio_body_exited)
	else:
		push_warning("[NpcBase] " + npc_name + ": No se encontro AreaAudio.")

	if not raycast_vision:
		push_warning("[NpcBase] " + npc_name + ": No se encontro RaycastVision.")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if relacion == Relacion.ENEMIGO:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player and player.is_in_group("invisible_to_npc"):
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
			move_and_slide()
			return

	_evaluar_vision(delta)

	match estado_actual:
		EstadoTactico.IDLE:
			_proceso_idle(delta)
		EstadoTactico.ALERTA:
			_proceso_alerta(delta)
		EstadoTactico.BUSCANDO:
			_proceso_buscando(delta)
		EstadoTactico.ATACANDO:
			_proceso_atacando(delta)
		EstadoTactico.ARRANSE:
			_proceso_arrancarse(delta)
		EstadoTactico.GUARDIA, EstadoTactico.ESCONDIENDO, EstadoTactico.SIGUIENDO:
			pass

	move_and_slide()

# ─────────────────────────────────────────
# ARMA - CARGA Y DISPARO
# ─────────────────────────────────────────

func _cargar_arma() -> void:
	# Intentar cargar desde ConfigManager. Si no existe, usar los @export como fallback.
	if nombre_arma == "":
		return
	if not Engine.has_singleton("ConfigManager") and not ClassDB.class_exists("ConfigManager"):
		# ConfigManager no disponible todavia, usar valores @export
		arma_danio = damage
		return
	_arma_cfg = ConfigManager.get_arma(nombre_arma)
	if _arma_cfg.is_empty():
		push_warning("[NpcBase] " + npc_name + ": Arma '" + nombre_arma + "' no encontrada en config. Usando @export.")
		arma_danio = damage
		return
	arma_danio             = float(_arma_cfg.get("DanioAlNPC",             damage))
	arma_rango             = float(_arma_cfg.get("RangoDisparo",           arma_rango))
	arma_spread            = float(_arma_cfg.get("Dispersion",             arma_spread))
	arma_segundos_por_bala = float(_arma_cfg.get("DanioPorSegundo",        arma_segundos_por_bala))
	arma_pellets           = int(_arma_cfg.get("Pellets",                  arma_pellets))
	# Sincronizar damage con el del arma para compatibilidad con codigo externo
	damage = arma_danio
	# Si el arma define rango de ataque, usarlo como attack_range
	if arma_rango > 0.0:
		attack_range = arma_rango

func _calcular_dano_por_distancia(dist: float) -> float:
	# Escopetas y armas de area usan caida de danio. Otras armas danio plano.
	var pellets_cfg: int = int(_arma_cfg.get("Pellets", 1))
	if pellets_cfg > 1:
		# Caida de danio segun distancia (0.2 minimo)
		var mult: float = clamp((attack_range - dist) / attack_range, 0.2, 1.0)
		return arma_danio * mult
	return arma_danio

# ─────────────────────────────────────────
# ESTADOS TACTICOS
# ─────────────────────────────────────────

func _proceso_idle(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)

func _proceso_alerta(_delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)

func _proceso_buscando(_delta: float) -> void:
	if _posicion_ruido != Vector3.ZERO:
		_mover_hacia(_posicion_ruido)
		var dist: float = global_transform.origin.distance_to(_posicion_ruido)
		if dist < 1.5:
			_posicion_ruido = Vector3.ZERO
			_hay_ruido = false
			_cambiar_estado(EstadoTactico.ALERTA)
	else:
		_cambiar_estado(EstadoTactico.ALERTA)

func _proceso_atacando(_delta: float) -> void:
	if target == null or not is_instance_valid(target) \
		or (target.has_method("is_dead") and target.get("is_dead") == true):
		target = null
		_reaccionando = false
		_objetivo_reaccion = null
		_cambiar_estado(EstadoTactico.BUSCANDO)
		return

	if not _tiene_linea_de_vision(target):
		_reaccionando = false
		_objetivo_reaccion = null
		_posicion_ruido = target.global_transform.origin
		_cambiar_estado(EstadoTactico.BUSCANDO)
		return

	var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
	look_at_target_flat(target.global_transform.origin)

	if dist <= attack_range:
		velocity.x = 0
		velocity.z = 0
		attempt_attack()
	else:
		_mover_hacia(target.global_transform.origin)

func _proceso_arrancarse(_delta: float) -> void:
	_objetivo_vida = _buscar_pickup_vida()
	if _objetivo_vida and is_instance_valid(_objetivo_vida):
		_mover_hacia(_objetivo_vida.global_transform.origin)
		return

	if _objetivo_aliado == null or not is_instance_valid(_objetivo_aliado):
		_objetivo_aliado = _buscar_aliado_mas_cercano()

	if _objetivo_aliado and is_instance_valid(_objetivo_aliado):
		var dist_aliado: float = global_transform.origin.distance_to(_objetivo_aliado.global_transform.origin)
		var radio_audio: float = _obtener_radio_audio()
		if dist_aliado <= radio_audio:
			if _estimulo_audio_activo or _estimulo_vision_activo:
				_cambiar_estado(EstadoTactico.ALERTA)
			else:
				_cambiar_estado(EstadoTactico.IDLE)
			return
		_mover_hacia(_objetivo_aliado.global_transform.origin)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

# ─────────────────────────────────────────
# DETECCION POR VISION (Area3D verde)
# ─────────────────────────────────────────

func _on_vision_body_entered(body: Node3D) -> void:
	if _es_enemigo(body):
		if not _enemigos_en_rango_vision.has(body):
			_enemigos_en_rango_vision.append(body)

func _on_vision_body_exited(body: Node3D) -> void:
	_enemigos_en_rango_vision.erase(body)
	if body == _objetivo_reaccion:
		_reaccionando = false
		_objetivo_reaccion = null
		if estado_actual == EstadoTactico.ATACANDO:
			_cambiar_estado(EstadoTactico.BUSCANDO)

func _evaluar_vision(delta: float) -> void:
	if estado_actual == EstadoTactico.ARRANSE:
		return

	for enemigo in _enemigos_en_rango_vision:
		if not is_instance_valid(enemigo):
			continue
		if _tiene_linea_de_vision(enemigo):
			_estimulo_vision_activo = true
			if _reaccionando and _objetivo_reaccion == enemigo:
				_timer_reaccion -= delta
				if _timer_reaccion <= 0.0:
					_reaccionando = false
					_objetivo_reaccion = null
					target = enemigo
					_cambiar_estado(EstadoTactico.ATACANDO)
			elif not _reaccionando and estado_actual != EstadoTactico.ATACANDO:
				_reaccionando = true
				_objetivo_reaccion = enemigo
				match experiencia:
					Experiencia.BAJA:
						_timer_reaccion = 1.2
					Experiencia.MEDIA:
						_timer_reaccion = 0.5
					Experiencia.ALTA:
						_timer_reaccion = 0.1
			return

	_estimulo_vision_activo = false

func _tiene_linea_de_vision(objetivo: Node3D) -> bool:
	if raycast_vision == null:
		return false
	var origen: Vector3 = global_transform.origin + Vector3(0, 0.8, 0)
	raycast_vision.global_transform.origin = origen
	var dir: Vector3 = (objetivo.global_transform.origin - origen).normalized()
	raycast_vision.target_position = raycast_vision.to_local(origen + dir * 50.0)
	raycast_vision.force_raycast_update()
	if raycast_vision.is_colliding():
		var collider: Object = raycast_vision.get_collider()
		if collider == objetivo or (collider is Node and collider.get_parent() == objetivo):
			return true
		return false
	return false

# ─────────────────────────────────────────
# DETECCION POR AUDIO (Area3D amarilla)
# ─────────────────────────────────────────

func _on_audio_body_entered(body: Node3D) -> void:
	if _es_enemigo(body):
		_estimulo_audio_activo = true
		_hay_ruido = true
		_posicion_ruido = body.global_transform.origin
		if estado_actual == EstadoTactico.IDLE or estado_actual == EstadoTactico.GUARDIA:
			_cambiar_estado(EstadoTactico.ALERTA)
		if estado_actual == EstadoTactico.ALERTA:
			_cambiar_estado(EstadoTactico.BUSCANDO)

func _on_audio_body_exited(body: Node3D) -> void:
	if area_audio:
		var cuerpos: Array = area_audio.get_overlapping_bodies()
		for c in cuerpos:
			if _es_enemigo(c):
				return
	_estimulo_audio_activo = false

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

func attempt_attack() -> void:
	var current_time: int = Time.get_ticks_msec()
	var elapsed: float = (current_time - last_attack_time) / 1000.0
	if elapsed >= attack_rate:
		last_attack_time = current_time
		perform_attack()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
	var dano_final: float = _calcular_dano_por_distancia(dist)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origen_disparo: Vector3 = global_transform.origin + Vector3(0, 1.0, 0)
	var destino_disparo: Vector3 = target.global_transform.origin + Vector3(0, 1.0, 0)

	var pellets_a_disparar: int = max(arma_pellets, 1)
	for i in range(pellets_a_disparar):
		var dir_base: Vector3 = (destino_disparo - origen_disparo).normalized()
		var dir_final: Vector3 = dir_base
		if arma_spread > 0.0:
			dir_final += Vector3(
				randf_range(-arma_spread, arma_spread),
				randf_range(-arma_spread, arma_spread),
				randf_range(-arma_spread, arma_spread)
			)
			dir_final = dir_final.normalized()
		var query := PhysicsRayQueryParameters3D.create(
			origen_disparo,
			origen_disparo + dir_final * attack_range
		)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		if result and result.get("collider") == target:
			target.take_damage(dano_final)
			draw_debug_laser(origen_disparo, result.get("position", destino_disparo), Color.YELLOW)
			break  # Un impacto es suficiente para aplicar danio

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	flash_hit()
	if current_health > 0 and (current_health / max_health) <= umbral_arrancarse:
		if estado_actual != EstadoTactico.ARRANSE:
			_objetivo_vida = null
			_objetivo_aliado = null
			_cambiar_estado(EstadoTactico.ARRANSE)
	if current_health <= 0:
		die()

func flash_hit() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color.WHITE
			var t: SceneTreeTimer = get_tree().create_timer(0.1)
			t.timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.albedo_color = _base_color
			)

func die() -> void:
	is_dead = true
	queue_free()

# ─────────────────────────────────────────
# UTILIDADES
# ─────────────────────────────────────────

func _es_enemigo(body: Node3D) -> bool:
	if body == self:
		return false
	if relacion == Relacion.ENEMIGO:
		if body.is_in_group("player"):
			return true
		if body is NpcBase and body.relacion == Relacion.AMIGABLE:
			return true
	if relacion == Relacion.AMIGABLE:
		if body is NpcBase and body.relacion == Relacion.ENEMIGO:
			return true
	return false

func _cambiar_estado(nuevo_estado: EstadoTactico) -> void:
	if estado_actual == nuevo_estado:
		return
	estado_actual = nuevo_estado

func _mover_hacia(destino: Vector3) -> void:
	if navigation_agent:
		navigation_agent.target_position = destino
		if not navigation_agent.is_navigation_finished():
			var next: Vector3 = navigation_agent.get_next_path_position()
			var dir: Vector3 = (next - global_transform.origin).normalized()
			dir.y = 0
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			look_at_target_flat(destino)
			return
	var dir: Vector3 = (destino - global_transform.origin).normalized()
	dir.y = 0
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	look_at_target_flat(destino)

func _buscar_pickup_vida() -> Node3D:
	var pickups: Array = get_tree().get_nodes_in_group("pickup_vida")
	var mas_cercano: Node3D = null
	var dist_min: float = radio_busqueda_vida
	for p in pickups:
		if not is_instance_valid(p):
			continue
		var d: float = global_transform.origin.distance_to((p as Node3D).global_transform.origin)
		if d < dist_min:
			dist_min = d
			mas_cercano = p as Node3D
	return mas_cercano

func _buscar_aliado_mas_cercano() -> Node3D:
	var aliados: Array = get_tree().get_nodes_in_group("npc")
	var mas_cercano: Node3D = null
	var dist_min: float = INF
	for a in aliados:
		if a == self:
			continue
		if a is NpcBase and a.relacion == relacion and not a.is_dead:
			var d: float = global_transform.origin.distance_to((a as Node3D).global_transform.origin)
			if d < dist_min:
				dist_min = d
				mas_cercano = a as Node3D
	return mas_cercano

func _obtener_radio_audio() -> float:
	if area_audio:
		for child in area_audio.get_children():
			if child is CollisionShape3D and child.shape is SphereShape3D:
				return (child.shape as SphereShape3D).radius
	return 5.0

# ─────────────────────────────────────────
# RELACION: COLOR
# ─────────────────────────────────────────

func _apply_relation_color() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	match relacion:
		Relacion.ENEMIGO:
			mat.albedo_color = Color(0.85, 0.15, 0.15)
		Relacion.AMIGABLE:
			var opciones: Array[Color] = [
				Color(0.1, 0.4, 0.9),
				Color(0.1, 0.75, 0.95),
				Color(0.15, 0.8, 0.3),
			]
			mat.albedo_color = opciones[randi() % opciones.size()]
		Relacion.NEUTRAL:
			mat.albedo_color = Color(0.7, 0.7, 0.1)
	_base_color = mat.albedo_color
	mesh.set_surface_override_material(0, mat)

# ─────────────────────────────────────────
# MOVIMIENTO
# ─────────────────────────────────────────

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat_pos: Vector3 = Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat_pos.distance_to(global_transform.origin) > 0.1:
		look_at(flat_pos, Vector3.UP)

# ─────────────────────────────────────────
# DEBUG
# ─────────────────────────────────────────

func draw_debug_laser(start: Vector3, end: Vector3, color: Color = Color.WHITE) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	mesh_instance.mesh = immediate_mesh
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	get_parent().add_child(mesh_instance)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	var timer: SceneTreeTimer = get_tree().create_timer(0.08)
	timer.timeout.connect(func() -> void: mesh_instance.queue_free())
