extends CharacterBody3D
class_name NpcBase

# ─────────────────────────────────────────
# ENUMS
# ─────────────────────────────────────────

enum Sexo        { MASCULINO, FEMENINO }
enum Experiencia { BAJA, MEDIA, ALTA }
enum Equipo      { UNO = 1, DOS = 2 }
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

@export var npc_name: String = "NPC"
@export var especie: String = ""
@export var sexo: Sexo = Sexo.MASCULINO
@export var equipo: Equipo = Equipo.DOS
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
var target: Node3D = null
var last_attack_time: int = 0
var is_dead: bool = false
var _base_color: Color = Color.WHITE

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────

## Devuelve true si el jugador está invisible para los NPCs.
func _player_is_invisible() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	return player != null and player.is_in_group("invisible_to_npc")

## Devuelve el equipo del jugador según GameState ("rojo" → DOS, "azul" → UNO, "" → ninguno/enemigo de todos).
func _get_player_team() -> Equipo:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		match gs.selected_team:
			"rojo":
				return Equipo.DOS
			"azul":
				return Equipo.UNO
	# Por defecto si no eligió equipo, se considera equipo UNO
	return Equipo.UNO

## Devuelve true si este NPC es enemigo del nodo indicado.
func es_enemigo_de(nodo: Node) -> bool:
	if nodo.is_in_group("player"):
		# El NPC ataca al jugador solo si son de equipos distintos
		return equipo != _get_player_team()
	if nodo is NpcBase:
		return equipo != nodo.equipo
	return false

# ─────────────────────────────────────────
# CICLO DE VIDA
# ─────────────────────────────────────────

func _ready() -> void:
	current_health = max_health
	_apply_team_color()
	_pick_target()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Refrescar objetivo si murió, es inválido, o el jugador cambió de visibilidad
	if target == null or not is_instance_valid(target) \
		or (target.has_method("is_dead") and target.get("is_dead") == true) \
		or (target.is_in_group("player") and _player_is_invisible()):
		_pick_target()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if target and is_instance_valid(target):
		var target_pos: Vector3 = target.global_transform.origin
		var direction: Vector3 = Vector3.ZERO

		if navigation_agent and not navigation_agent.is_navigation_finished():
			navigation_agent.target_position = target_pos
			var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
			direction = (next_path_pos - global_transform.origin).normalized()
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

# ─────────────────────────────────────────
# EQUIPO: COLOR Y OBJETIVO
# ─────────────────────────────────────────

func _apply_team_color() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	match equipo:
		Equipo.DOS:
			mat.albedo_color = Color(0.85, 0.15, 0.15)
		Equipo.UNO:
			var opciones: Array[Color] = [
				Color(0.1, 0.4, 0.9),
				Color(0.1, 0.75, 0.95),
				Color(0.15, 0.8, 0.3),
			]
			mat.albedo_color = opciones[randi() % opciones.size()]
	_base_color = mat.albedo_color
	mesh.set_surface_override_material(0, mat)

func _pick_target() -> void:
	target = null
	var todos_npcs: Array = get_tree().get_nodes_in_group("npcs")
	var jugador_invisible: bool = _player_is_invisible()
	var player_team: Equipo = _get_player_team()

	var closest_dist: float = INF

	# ¿Este NPC es enemigo del jugador?
	var atacar_jugador: bool = (equipo != player_team) and not jugador_invisible

	if atacar_jugador:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player and not player.get("is_dead"):
			var d: float = global_transform.origin.distance_to(player.global_transform.origin)
			if d < closest_dist:
				closest_dist = d
				target = player

	# Siempre busca NPCs del equipo contrario
	for node in todos_npcs:
		if node == self:
			continue
		if node is NpcBase and node.equipo != equipo and not node.is_dead:
			var d: float = global_transform.origin.distance_to(node.global_transform.origin)
			if d < closest_dist:
				closest_dist = d
				target = node as Node3D

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
	var elapsed: float = (current_time - last_attack_time) / 1000.0
	if elapsed >= attack_rate:
		last_attack_time = current_time
		perform_attack()

func perform_attack() -> void:
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	flash_hit()
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
