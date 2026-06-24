# scripts/npc_base.gd
extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────

enum Sexo        { MASCULINO, FEMENINO }
enum Relacion    { AMIGABLE, NEUTRAL, ENEMIGO }
enum Experiencia { BAJA, MEDIA, ALTA }
enum Estado {
	IDLE, GUARDIA, ALERTA, BUSCANDO, ESCONDIENDOSE, SIGUIENDO, ATACANDO
}

# ─────────────────────────────────────────
# IDENTIDAD
# ─────────────────────────────────────────

@export var npc_name:    String      = "NPC"
@export var especie:     String      = ""
@export var sexo:        Sexo        = Sexo.MASCULINO
@export var relacion:    Relacion    = Relacion.ENEMIGO
@export var experiencia: Experiencia = Experiencia.MEDIA
@export var skin_path:   String      = ""
@export var voz_path:    String      = ""
@export var estado:      Estado      = Estado.IDLE

## Equipo al que pertenece: "rojo" o "azul".
## Los NPC con relacion ENEMIGO son siempre equipo "rojo".
## Los NPC con relacion AMIGABLE heredan el equipo del jugador.
@export var equipo: String = "rojo"

## Nombre del arma a usar (debe coincidir exactamente con la clave en skill.cfg.json).
@export var nombre_arma: String = ""

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

@export var max_health:   float = 100.0
@export var speed:        float = 3.0
@export var damage:       float = 10.0
@export var attack_range: float = 2.0
@export var attack_rate:  float = 1.0

# ─────────────────────────────────────────
# VARIABLES INTERNAS
# ─────────────────────────────────────────

var current_health:   float  = 100.0
var target:           Node3D = null
var last_attack_time: int    = 0
var is_dead:          bool   = false
var _base_color:      Color  = Color.WHITE

# Cast explicito a float para evitar warning "Variant value"
var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

# Nodos de la barra de vida flotante (se crean en _ready)
var _healthbar_root:  Node3D         = null
var _healthbar_bg:    MeshInstance3D = null
var _healthbar_fill:  MeshInstance3D = null
var _weapon_label_3d: Label3D        = null

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	if max_health == 100.0:
		if relacion == Relacion.AMIGABLE:
			max_health = ConfigManager.get_vida_npc("Aliado")
		else:
			max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health

	# Asignar equipo segun relacion si no fue forzado externamente
	if relacion == Relacion.ENEMIGO:
		equipo = "rojo"
	# AMIGABLE: el equipo lo asigna el spawner segun el equipo del jugador

	_apply_relation_color()
	_pick_target()
	_setup_healthbar()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Mantener la barra de vida mirando siempre a la camara
	if _healthbar_root and is_instance_valid(_healthbar_root):
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			_healthbar_root.look_at(cam.global_transform.origin, Vector3.UP)

	if target == null or not is_instance_valid(target) \
			or (target.has_method("is_dead") and target.get("is_dead") == true):
		_pick_target()

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

	if target and is_instance_valid(target):
		var target_pos: Vector3 = target.global_transform.origin
		var direction:  Vector3 = Vector3.ZERO

		if navigation_agent and not navigation_agent.is_navigation_finished():
			navigation_agent.target_position = target_pos
			direction = (navigation_agent.get_next_path_position() - global_transform.origin).normalized()
		else:
			direction = (target_pos - global_transform.origin).normalized()

		direction.y = 0
		direction   = direction.normalized()
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

# ─────────────────────────────────────────
# BARRA DE VIDA FLOTANTE
# ─────────────────────────────────────────

func _setup_healthbar() -> void:
	_healthbar_root          = Node3D.new()
	_healthbar_root.position = Vector3(0, 2.4, 0)
	add_child(_healthbar_root)

	# ── Fondo gris ──
	_healthbar_bg      = MeshInstance3D.new()
	var bg_mesh        := QuadMesh.new()
	bg_mesh.size       = Vector2(1.1, 0.18)
	_healthbar_bg.mesh = bg_mesh
	var bg_mat         := StandardMaterial3D.new()
	bg_mat.albedo_color   = Color(0.15, 0.15, 0.15, 0.85)
	bg_mat.shading_mode   = StandardMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_healthbar_bg.set_surface_override_material(0, bg_mat)
	_healthbar_root.add_child(_healthbar_bg)

	# ── Relleno (vida actual) ──
	_healthbar_fill      = MeshInstance3D.new()
	var fill_mesh        := QuadMesh.new()
	fill_mesh.size       = Vector2(1.0, 0.13)
	_healthbar_fill.mesh = fill_mesh
	var fill_mat         := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.1, 0.85, 0.1)
	fill_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_healthbar_fill.set_surface_override_material(0, fill_mat)
	_healthbar_root.add_child(_healthbar_fill)

	# ── Label nombre del arma ──
	_weapon_label_3d                  = Label3D.new()
	_weapon_label_3d.position         = Vector3(0, 0.18, 0.01)
	_weapon_label_3d.font_size        = 24
	_weapon_label_3d.modulate         = Color.WHITE
	_weapon_label_3d.outline_size     = 6
	_weapon_label_3d.outline_modulate = Color(0, 0, 0, 0.8)
	_weapon_label_3d.billboard        = BaseMaterial3D.BILLBOARD_DISABLED
	_weapon_label_3d.double_sided     = true
	_weapon_label_3d.text             = nombre_arma if nombre_arma != "" else "---"
	_healthbar_root.add_child(_weapon_label_3d)

	_update_healthbar()

func _update_healthbar() -> void:
	if not is_instance_valid(_healthbar_fill):
		return
	var ratio: float = clamp(current_health / max_health, 0.0, 1.0)
	_healthbar_fill.scale.x    = ratio
	_healthbar_fill.position.x = (ratio - 1.0) * 0.5

	# Cast explicito a StandardMaterial3D para evitar warning de Variant
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
		_weapon_label_3d.text = nombre if nombre != "" else "---"

# ─────────────────────────────────────────
# RELACION
# ─────────────────────────────────────────

func _apply_relation_color() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh:
		return
	var mat := StandardMaterial3D.new()
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
# SELECCION DE OBJETIVO (IA DE EQUIPOS)
# ─────────────────────────────────────────
# Logica:
#   - Un NPC ENEMIGO (equipo rojo) ataca al jugador Y a NPC AMIGABLE.
#   - Un NPC AMIGABLE (equipo azul u otro) ataca a NPC ENEMIGO Y al jugador
#     si el jugador es del equipo contrario.
#   - El equipo del jugador se lee desde GameState.selected_team.
# ─────────────────────────────────────────

func _es_enemigo_de(otro: Node) -> bool:
	if not is_instance_valid(otro):
		return false

	# Otro es el jugador
	if otro.is_in_group("player"):
		var gs: Node = get_node_or_null("/root/GameState")
		var equipo_jugador: String = "azul"
		if gs and "selected_team" in gs:
			equipo_jugador = gs.selected_team
		# Si somos del mismo equipo que el jugador, NO es enemigo
		return equipo != equipo_jugador

	# Otro es un NPC
	if otro is NpcBase:
		return equipo != otro.equipo

	return false

func _pick_target() -> void:
	target = null
	var closest_dist: float = INF

	# Evaluar al jugador como posible objetivo
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and _es_enemigo_de(player):
		var d: float = global_transform.origin.distance_to((player as Node3D).global_transform.origin)
		if d < closest_dist:
			closest_dist = d
			target = player as Node3D

	# Evaluar NPC como posibles objetivos
	for node in get_tree().get_nodes_in_group("npc"):
		if node == self:
			continue
		if node is NpcBase and not node.is_dead and _es_enemigo_de(node):
			var d: float = global_transform.origin.distance_to(node.global_transform.origin)
			if d < closest_dist:
				closest_dist = d
				target = node as Node3D

# ─────────────────────────────────────────
# MOVIMIENTO
# ─────────────────────────────────────────

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat_pos := Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat_pos.distance_to(global_transform.origin) > 0.1:
		look_at(flat_pos, Vector3.UP)

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

func attempt_attack() -> void:
	var elapsed: float = (Time.get_ticks_msec() - last_attack_time) / 1000.0
	if elapsed >= attack_rate:
		last_attack_time = Time.get_ticks_msec()
		perform_attack()

func perform_attack() -> void:
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health  = clamp(current_health, 0, max_health)
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
			get_tree().create_timer(0.1).timeout.connect(
				func() -> void:
					if is_instance_valid(mat):
						mat.albedo_color = _base_color
			)

func die() -> void:
	is_dead = true
	queue_free()

# ─────────────────────────────────────────
# DEBUG
# ─────────────────────────────────────────

func draw_debug_laser(start: Vector3, end: Vector3, color: Color = Color.WHITE) -> void:
	var mesh_instance  := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material       := StandardMaterial3D.new()
	mesh_instance.mesh          = immediate_mesh
	material.shading_mode       = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color       = color
	mesh_instance.material_override = material
	get_parent().add_child(mesh_instance)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	get_tree().create_timer(0.08).timeout.connect(
		func() -> void: mesh_instance.queue_free()
	)
