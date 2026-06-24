# scripts/npc_base.gd
# Clase base para todos los NPCs (aliados, neutrales, enemigos).
# La vida se carga desde ConfigManager según la relacion del NPC.
extends CharacterBody3D
class_name NpcBase

# ── Enums ────────────────────────────────────────────────────────────────

enum Sexo        { MASCULINO, FEMENINO }
enum Relacion    { AMIGABLE, NEUTRAL, ENEMIGO }
enum Experiencia { BAJA, MEDIA, ALTA }
enum Estado      { IDLE, GUARDIA, ALERTA, BUSCANDO, ESCONDIENDOSE, SIGUIENDO, ATACANDO }

# ── Identidad ────────────────────────────────────────────────────────────

@export var npc_name:    String      = "NPC"
@export var especie:     String      = ""
@export var sexo:        Sexo        = Sexo.MASCULINO
@export var relacion:    Relacion    = Relacion.ENEMIGO
@export var experiencia: Experiencia = Experiencia.MEDIA
@export var skin_path:   String      = ""
@export var voz_path:    String      = ""
@export var estado:      Estado      = Estado.IDLE

# ── Combate — valores por defecto, se sobreescriben en subclases ─────────

@export var max_health:   float = 0.0  # 0 = delegar a ConfigManager en _ready()
@export var speed:        float = 3.0
@export var damage:       float = 10.0
@export var attack_range: float = 2.0
@export var attack_rate:  float = 1.0

# ── Variables internas ───────────────────────────────────────────────────

var current_health:   float   = 0.0
var target:           Node3D  = null
var last_attack_time: int     = 0
var is_dead:          bool    = false
var _base_color:      Color   = Color.WHITE

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

# ── Ciclo de vida ────────────────────────────────────────────────────────

func _ready() -> void:
	# Si la subclase no asignó max_health, lo tomamos del JSON según relación
	if max_health <= 0.0:
		match relacion:
			Relacion.AMIGABLE:
				max_health = ConfigManager.get_vida_npc("Aliado")
			_:
				max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health

	_apply_relation_color()
	_pick_target()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Refrescar objetivo si el actual ya no es válido
	if not is_instance_valid(target) or \
		(target.has_method("is_dead") and target.get("is_dead") == true):
		_pick_target()

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Invisibilidad del jugador solo afecta a NPCs enemigos
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
			var next: Vector3 = navigation_agent.get_next_path_position()
			direction = (next - global_transform.origin).normalized()
		else:
			direction = (target_pos - global_transform.origin).normalized()

		direction.y = 0.0
		direction   = direction.normalized()
		look_at_target_flat(target_pos)

		var dist: float = global_transform.origin.distance_to(target_pos)
		if dist <= attack_range:
			velocity.x = 0.0
			velocity.z = 0.0
			attempt_attack()
		else:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

# ── Relación: color y objetivo ───────────────────────────────────────────

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

func _pick_target() -> void:
	target = null
	match relacion:
		Relacion.ENEMIGO:
			var player: Node = get_tree().get_first_node_in_group("player")
			if player:
				target = player as Node3D
		Relacion.AMIGABLE:
			var closest_dist := INF
			for node in get_tree().get_nodes_in_group("npc"):
				if node == self:
					continue
				if node is NpcBase and node.relacion == Relacion.ENEMIGO and not node.is_dead:
					var d: float = global_transform.origin.distance_to(node.global_transform.origin)
					if d < closest_dist:
						closest_dist = d
						target = node as Node3D
		Relacion.NEUTRAL:
			target = null

# ── Movimiento ───────────────────────────────────────────────────────────

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat := Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat.distance_to(global_transform.origin) > 0.1:
		look_at(flat, Vector3.UP)

# ── Combate ──────────────────────────────────────────────────────────────

func attempt_attack() -> void:
	var elapsed: float = (Time.get_ticks_msec() - last_attack_time) / 1000.0
	if elapsed >= attack_rate:
		last_attack_time = Time.get_ticks_msec()
		perform_attack()

## Sobreescribir en subclases para definir el ataque específico.
func perform_attack() -> void:
	if target and target.has_method("take_damage"):
		target.take_damage(damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health  = clamp(current_health, 0.0, max_health)
	flash_hit()
	if current_health <= 0.0:
		die()

func flash_hit() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh:
		return
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

# ── Debug ────────────────────────────────────────────────────────────────

func draw_debug_laser(start: Vector3, end: Vector3, color: Color = Color.WHITE) -> void:
	var mi:  MeshInstance3D     = MeshInstance3D.new()
	var im:  ImmediateMesh      = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mi.mesh = im
	mat.shading_mode     = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color     = color
	mi.material_override = mat
	get_parent().add_child(mi)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(start)
	im.surface_add_vertex(end)
	im.surface_end()
	get_tree().create_timer(0.08).timeout.connect(func() -> void: mi.queue_free())
