extends CharacterBody3D
class_name EnemyBase

# ─────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────

enum Sexo        { MASCULINO, FEMENINO }
enum Relacion    { ENEMIGO, NEUTRAL, AMIGABLE }
enum Experiencia { BAJA, MEDIA, ALTA }
enum Estado {
	IDLE,
	GUARDIA,
	ALERTA,
	BUSCANDO,
	ESCONDIENDO,
	SIGUIENDO,
	ATACANDO
}

# ─────────────────────────────────────────
# IDENTIDAD
# ─────────────────────────────────────────

@export var enemy_name: String = "Enemigo"
@export var especie: String = ""
@export var sexo: Sexo = Sexo.MASCULINO
@export var relacion: Relacion = Relacion.ENEMIGO
@export var experiencia: Experiencia = Experiencia.MEDIA
@export var skin_path: String = ""
@export var voz_path: String = ""
@export var estado: Estado = Estado.IDLE

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

@export var max_health: float = 30.0
@export var speed: float = 3.0
@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_rate: float = 1.0

# ─────────────────────────────────────────
# VARIABLES INTERNAS
# ─────────────────────────────────────────

var current_health: float = 30.0
var target_player: Player = null
var last_attack_time: int = 0
var is_dead: bool = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	current_health = max_health
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target_player = players[0] as Player

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Si el jugador es invisible, el NPC no hace nada
	if target_player and target_player.is_in_group("invisible_to_npc"):
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	if target_player and not target_player.is_dead:
		var target_pos: Vector3 = target_player.global_transform.origin
		var direction: Vector3 = Vector3.ZERO

		if navigation_agent and !navigation_agent.is_navigation_finished():
			navigation_agent.target_position = target_pos
			var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
			direction = (next_path_pos - global_transform.origin).normalized()
		else:
			direction = (target_pos - global_transform.origin).normalized()

		direction.y = 0
		direction = direction.normalized()
		look_at_target_flat(target_pos)

		var dist_to_player: float = global_transform.origin.distance_to(target_pos)

		if dist_to_player <= attack_range:
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
# MOVIMIENTO
# ─────────────────────────────────────────

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat_pos: Vector3 = Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat_pos.distance_to(global_transform.origin) > 0.1:
		look_at(flat_pos, Vector3.UP)

# ─────────────────────────────────────────
# COMBATE
# ─────────────────────────────────────────

func attempt_attack() -> void:
	var current_time: int = Time.get_ticks_msec()
	var time_since_last_attack: float = (current_time - last_attack_time) / 1000.0
	if time_since_last_attack >= attack_rate:
		last_attack_time = current_time
		perform_attack()

func perform_attack() -> void:
	if target_player and target_player.has_method("take_damage"):
		target_player.take_damage(damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	flash_red()
	if current_health <= 0:
		die()

func flash_red() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh:
		var mat: Material = mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			var orig_color: Color = mat.albedo_color
			mat.albedo_color = Color.RED
			var timer: SceneTreeTimer = get_tree().create_timer(0.1)
			timer.timeout.connect(func() -> void: mat.albedo_color = orig_color)

func die() -> void:
	is_dead = true
	queue_free()

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
