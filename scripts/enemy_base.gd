extends CharacterBody3D
class_name EnemyBase

@export var enemy_name: String = "Enemigo"
@export var max_health: float = 30.0
@export var speed: float = 3.0
@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_rate: float = 1.0 # Tiempo entre ataques

var current_health: float = 30.0
var target_player: Player = null
var last_attack_time: int = 0
var is_dead: bool = false

# Gravedad
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

func _ready() -> void:
	current_health = max_health
	
	# Buscar al jugador en el árbol de escena
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target_player = players[0] as Player

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	# Gravedad simple
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if target_player and not target_player.is_dead:
		var target_pos: Vector3 = target_player.global_transform.origin
		
		# Comportamiento de navegación simple. 
		# Si hay NavigationAgent3D y está configurada la navegación, se usa.
		# De lo contrario, nos movemos directamente hacia él de forma simple (fallback robusto si no hay NavMesh).
		var direction: Vector3 = Vector3.ZERO
		
		if navigation_agent and !navigation_agent.is_navigation_finished():
			navigation_agent.target_position = target_pos
			var next_path_pos: Vector3 = navigation_agent.get_next_path_position()
			direction = (next_path_pos - global_transform.origin).normalized()
		else:
			# Movimiento directo hacia el jugador
			direction = (target_pos - global_transform.origin).normalized()
			
		# Evitar movimientos verticales en la velocidad de movimiento horizontal
		direction.y = 0
		direction = direction.normalized()
		
		# Mirar al jugador (eje Y únicamente para no rotar raro)
		look_at_target_flat(target_pos)
		
		# Determinar distancia
		var dist_to_player: float = global_transform.origin.distance_to(target_pos)
		
		# Lógica de ataque o aproximación
		if dist_to_player <= attack_range:
			velocity.x = 0
			velocity.z = 0
			attempt_attack()
		else:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
	else:
		# Si no hay jugador o está muerto, se queda quieto
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func look_at_target_flat(target_pos: Vector3) -> void:
	var flat_pos: Vector3 = Vector3(target_pos.x, global_transform.origin.y, target_pos.z)
	if flat_pos.distance_to(global_transform.origin) > 0.1:
		look_at(flat_pos, Vector3.UP)

func attempt_attack() -> void:
	var current_time: int = Time.get_ticks_msec()
	var time_since_last_attack: float = (current_time - last_attack_time) / 1000.0
	
	if time_since_last_attack >= attack_rate:
		last_attack_time = current_time
		perform_attack()

# Método para sobrescribir en heredados
func perform_attack() -> void:
	if target_player and target_player.has_method("take_damage"):
		target_player.take_damage(damage)

func take_damage(amount: float) -> void:
	if is_dead:
		return
		
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	
	# Efecto visual rápido de parpadeo de daño
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
