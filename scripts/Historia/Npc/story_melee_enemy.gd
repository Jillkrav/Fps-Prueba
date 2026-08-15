class_name StoryMeleeEnemy
extends CharacterBody3D

## Zombie lento de Historia. Usa NavigationAgent3D nativo porque las misiones
## necesitan persecución local y precisa, no las rutas tácticas del multijugador.
signal died(enemy: StoryMeleeEnemy, killer_id: int)

@export_category("Stats")
@export var max_health: float = 55.0
@export_range(0.1, 10.0, 0.05) var movement_speed: float = 1.65
@export_range(0.5, 5.0, 0.05) var attack_range: float = 1.5
@export var melee_damage: float = 10.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 1.1

@export_category("Navigation")
@export var target_group: StringName = &"player"
@export var stop_distance: float = 1.15

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var current_health: float = 0.0
var is_dead: bool = false
var equipo_id: int = int(Enums.Equipo.ROJO)
var is_invisible: bool = false
var _attack_timer: float = 0.0
var _gravity: float = 9.8

# MeshInstance3D no tiene 'modulate' (es una propiedad 2D de CanvasItem).
# Para teñir la malla 3D usamos un StandardMaterial3D propio (duplicado para
# no alterar el material compartido de la escena) y su albedo_color.
var _tint_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE


func _ready() -> void:
	add_to_group(&"npc")
	add_to_group(&"story_enemy")
	current_health = max_health
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = stop_distance
	_setup_tint_material()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var player: Player = get_tree().get_first_node_in_group(target_group) as Player
	if player == null or player.is_dead or player.is_invisible:
		velocity.x = move_toward(velocity.x, 0.0, movement_speed)
		velocity.z = move_toward(velocity.z, 0.0, movement_speed)
		move_and_slide()
		return
	var horizontal_to_player: Vector3 = player.global_position - global_position
	horizontal_to_player.y = 0.0
	var player_distance: float = horizontal_to_player.length()
	if player_distance <= attack_range:
		velocity.x = 0.0
		velocity.z = 0.0
		_face_direction(horizontal_to_player, delta)
		_try_attack(player)
		move_and_slide()
		return
	var desired_direction: Vector3 = _get_navigation_direction(player.global_position)
	velocity.x = desired_direction.x * movement_speed
	velocity.z = desired_direction.z * movement_speed
	_face_direction(desired_direction, delta)
	move_and_slide()


func take_damage(amount: float, zone: String = "Torso", killer_id: int = -1) -> void:
	if is_dead:
		return
	var multiplier: float = 2.0 if zone == "Cabeza" else 1.0
	current_health = maxf(0.0, current_health - amount * multiplier)
	_tint(Color(1.0, 0.35, 0.35))
	if current_health <= 0.0:
		die(killer_id)


func die(killer_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	_tint(Color(0.2, 0.2, 0.2))
	died.emit(self, killer_id)
	await get_tree().create_timer(0.25).timeout
	queue_free()


## Duplica el material de la malla para poder teñirla por instancia sin afectar
## a los zombies hermanos que comparten el mismo recurso StandardMaterial3D.
func _setup_tint_material() -> void:
	if mesh.material_override is StandardMaterial3D:
		_tint_material = (mesh.material_override as StandardMaterial3D).duplicate()
		_base_albedo = _tint_material.albedo_color
		mesh.material_override = _tint_material
	else:
		# No hay material override Standard (o es shader): no podemos teñir albedo.
		_tint_material = null


func _tint(color: Color) -> void:
	if _tint_material == null:
		return
	_tint_material.albedo_color = color


func _get_navigation_direction(target_position: Vector3) -> Vector3:
	var navigation_map: RID = navigation_agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		var direct_direction: Vector3 = target_position - global_position
		direct_direction.y = 0.0
		return direct_direction.normalized()
	navigation_agent.target_position = target_position
	if navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0
	return direction.normalized()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var target_yaw: float = atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 7.0, 1.0))


func _try_attack(player: Player) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	player.take_damage(melee_damage, "Torso", get_instance_id())
