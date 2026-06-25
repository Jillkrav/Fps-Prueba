# scripts/npc_base.gd
# NPC UNIVERSAL: el comportamiento de combate depende del arma asignada.
extends CharacterBody3D
class_name NpcBase

enum Sexo { MASCULINO, FEMENINO }
enum Experiencia { BAJA, MEDIA, ALTA }
enum Estado { IDLE, GUARDIA, ALERTA, BUSCANDO, ESCONDIENDOSE, SIGUIENDO, ATACANDO }

# NOTA: Relacion se mantiene solo para compatibilidad con el DevMenu.
enum Relacion { AMIGABLE, NEUTRAL, ENEMIGO }

@export var npc_name: String = "NPC"
@export var especie: String = ""
@export var sexo: Sexo = Sexo.MASCULINO
@export var relacion: Relacion = Relacion.ENEMIGO
@export var experiencia: Experiencia = Experiencia.MEDIA
@export var skin_path: String = ""
@export var voz_path: String = ""
@export var estado: Estado = Estado.IDLE
@export var nombre_arma: String = ""

@export var equipo_id: int = 2

var _relacion_forzada: bool = false

@export var max_health: float = 100.0
@export var speed: float = 3.0
@export var damage: float = 15.0
@export var attack_range: float = 2.0
@export var attack_rate: float = 1.0

var current_health: float = 100.0
var target: Node3D = null
var last_attack_time: int = 0
var is_dead: bool = false
var _base_color: Color = Color.WHITE
var _es_ranged: bool = false
var _es_escopeta: bool = false
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

var _healthbar_root: Node3D = null
var _healthbar_bg: MeshInstance3D = null
var _healthbar_fill: MeshInstance3D = null
var _weapon_label_3d: Label3D = null

var _retarget_timer: float = 0.0
const RETARGET_INTERVAL: float = 2.0

func _ready() -> void:
	add_to_group("npcs")
	if max_health == 100.0:
		max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health

	if not _relacion_forzada:
		match relacion:
			Relacion.ENEMIGO:
				equipo_id = GameStateClass.Equipo.ROJO
			Relacion.AMIGABLE:
				equipo_id = _equipo_jugador()
			Relacion.NEUTRAL:
				equipo_id = GameStateClass.Equipo.ESPECTADOR

	_configurar_arma()
	_apply_team_color()
	_pick_target()
	_setup_healthbar()

func _configurar_arma() -> void:
	if nombre_arma == "":
		_es_ranged   = false
		_es_escopeta = false
		attack_range = 1.8
		attack_rate  = 1.0
		speed        = 4.0
		damage       = 15.0
		return
	var cfg: Dictionary = ConfigManager.get_arma(nombre_arma)
	if cfg.is_empty():
		_es_ranged   = false
		attack_range = 1.8
		return
	var rango_cfg: float = float(cfg.get("RangoAtaque", 10.0))
	attack_range = rango_cfg
	_es_ranged   = rango_cfg > 1.8
	var categoria: String = str(cfg.get("Categoria", "")).to_lower()
	_es_escopeta = categoria.contains("escopeta") or nombre_arma.to_lower().contains("shotgun")

	# FIX: buscar la clave de danno con todos los posibles nombres del JSON
	# Clave oficial nueva: "DanioAlNPC" — fallbacks para configs viejas
	var danno_val: float = 0.0
	for clave in ["DanioAlNPC", "DannoAlNPC", "DaNNOAlNPC", "DaNNioAlNPC", "Danno", "Dano"]:
		if cfg.has(clave):
			danno_val = float(cfg[clave])
			break
	if danno_val <= 0.0:
		danno_val = 20.0
	damage = danno_val

	if _es_ranged:
		speed       = 2.5
		attack_rate = float(cfg.get("CadenciaSegundos", 1.5))
	else:
		speed       = 4.0
		attack_rate = 1.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _healthbar_root and is_instance_valid(_healthbar_root):
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			_healthbar_root.look_at(cam.global_transform.origin, Vector3.UP)

	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL:
		_retarget_timer = 0.0
		if target == null or not is_instance_valid(target) or (target.has_method("is_dead") and target.get("is_dead")):
			_pick_target()

	if target == null or not is_instance_valid(target) or (target.has_method("is_dead") and target.get("is_dead")):
		_pick_target()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var player: Node = get_tree().get_first_node_in_group("player")
	if player and player.is_in_group("invisible_to_npc") and _es_enemigo_de_nodo(player):
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	if target and is_instance_valid(target):
		var target_pos: Vector3 = target.global_transform.origin
		var direction: Vector3 = Vector3.ZERO
		if navigation_agent and not navigation_agent.is_navigation_finished():
			navigation_agent.target_position = target_pos
			direction = (navigation_agent.get_next_path_position() - global_transform.origin).normalized()
		else:
			direction = (target_pos - global_transform.origin).normalized()
		direction.y = 0
		direction = direction.normalized()
		look_at_target_flat(target_pos)
		var dist: float = global_transform.origin.distance_to(target_pos)
		if dist <= attack_range:
			velocity.x = 0
			velocity.z = 0
			attempt_attack()
		else:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	move_and_slide()

func _setup_healthbar() -> void:
	_healthbar_root = Node3D.new()
	_healthbar_root.position = Vector3(0, 2.4, 0)
	add_child(_healthbar_root)
	_healthbar_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.1, 0.18)
	_healthbar_bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.85)
	bg_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_healthbar_bg.set_surface_override_material(0, bg_mat)
	_healthbar_root.add_child(_healthbar_bg)
	_healthbar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(1.0, 0.13)
	_healthbar_fill.mesh = fill_mesh
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.1, 0.85, 0.1)
	fill_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_healthbar_fill.set_surface_override_material(0, fill_mat)
	_healthbar_root.add_child(_healthbar_fill)
	_weapon_label_3d = Label3D.new()
	_weapon_label_3d.position = Vector3(0, 0.18, 0.01)
	_weapon_label_3d.font_size = 24
	_weapon_label_3d.modulate = Color.WHITE
	_weapon_label_3d.outline_size = 6
	_weapon_label_3d.outline_modulate = Color(0, 0, 0, 0.8)
	_weapon_label_3d.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_weapon_label_3d.double_sided = true
	_weapon_label_3d.text = nombre_arma if nombre_arma != "" else "Melee"
	_healthbar_root.add_child(_weapon_label_3d)
	_update_healthbar()

func _update_healthbar() -> void:
	if not is_instance_valid(_healthbar_fill):
		return
	var ratio: float = clamp(current_health / max_health, 0.0, 1.0)
	_healthbar_fill.scale.x = ratio
	_healthbar_fill.position.x = (ratio - 1.0) * 0.5
	var fill_mat: StandardMaterial3D = _healthbar_fill.get_surface_override_material(0) as StandardMaterial3D
	if fill_mat:
		if ratio > 0.5:
			fill_mat.albedo_color = Color(0.1, 0.85, 0.1)
		elif ratio > 0.25:
			fill_mat.albedo_color = Color(0.9, 0.75, 0.0)
		else:
			fill_mat.albedo_color = Color(0.9, 0.1, 0.1)

func update_weapon_label(nombre: String) -> void:
	nombre_arma = nombre
	if is_instance_valid(_weapon_label_3d):
		_weapon_label_3d.text = nombre if nombre != "" else "Melee"

func _apply_team_color() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GameState.color_equipo(equipo_id)
	_base_color = mat.albedo_color
	mesh.set_surface_override_material(0, mat)

func _equipo_jugador() -> int:
	return GameState.player_team

func _es_enemigo_de_nodo(otro: Node) -> bool:
	if not is_instance_valid(otro):
		return false
	var otro_equipo: int
	if otro.is_in_group("player"):
		otro_equipo = _equipo_jugador()
	elif otro is NpcBase:
		otro_equipo = otro.equipo_id
	else:
		return false
	return GameState.son_enemigos(equipo_id, otro_equipo)

func _pick_target() -> void:
	target = null
	var closest_dist: float = INF
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and _es_enemigo_de_nodo(player):
		if not player.is_in_group("invisible_to_npc"):
			var d: float = global_transform.origin.distance_to((player as Node3D).global_transform.origin)
			if d < closest_dist:
				closest_dist = d
				target = player as Node3D
	for node in get_tree().get_nodes_in_group("npcs"):
		if node == self:
			continue
		if node is NpcBase and not node.is_dead and _es_enemigo_de_nodo(node):
			var d: float = global_transform.origin.distance_to(node.global_transform.origin)
			if d < closest_dist:
				closest_dist = d
				target = node as Node3D

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat_pos := Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat_pos.distance_to(global_transform.origin) > 0.1:
		look_at(flat_pos, Vector3.UP)

func attempt_attack() -> void:
	var elapsed: float = (Time.get_ticks_msec() - last_attack_time) / 1000.0
	if elapsed >= attack_rate:
		last_attack_time = Time.get_ticks_msec()
		perform_attack()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	if _es_ranged:
		_atacar_a_distancia()
	else:
		_atacar_melee()

func _atacar_melee() -> void:
	target.take_damage(damage)

func _atacar_a_distancia() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin_pos: Vector3 = global_transform.origin + Vector3(0, 1.0, 0)
	var target_pos: Vector3 = target.global_transform.origin + Vector3(0, 1.0, 0)
	if _es_escopeta:
		var impactos: int = 0
		var dist: float = global_transform.origin.distance_to(target.global_transform.origin)
		var damage_mult: float = clamp((attack_range - dist) / attack_range, 0.2, 1.0)
		for _i in range(5):
			var spread_end: Vector3 = target_pos + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
			var q := PhysicsRayQueryParameters3D.create(origin_pos, spread_end)
			q.exclude = [self]
			var res: Dictionary = space_state.intersect_ray(q)
			if res and res.get("collider") == target:
				impactos += 1
			draw_debug_laser(origin_pos, spread_end, Color.ORANGE)
		if impactos > 0:
			target.take_damage(damage * damage_mult * impactos)
	else:
		var q := PhysicsRayQueryParameters3D.create(origin_pos, target_pos)
		q.exclude = [self]
		var res: Dictionary = space_state.intersect_ray(q)
		if res and res.get("collider") == target:
			target.take_damage(damage)
			draw_debug_laser(origin_pos, target_pos, Color.YELLOW)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	_update_healthbar()
	flash_hit()
	if current_health <= 0:
		die()

func flash_hit() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color.WHITE
			get_tree().create_timer(0.1).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.albedo_color = _base_color
			)

func die() -> void:
	is_dead = true
	queue_free()

func draw_debug_laser(start: Vector3, end: Vector3, color: Color = Color.WHITE) -> void:
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	mesh_instance.mesh = immediate_mesh
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	get_parent().add_child(mesh_instance)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	get_tree().create_timer(0.08).timeout.connect(func() -> void: mesh_instance.queue_free())
