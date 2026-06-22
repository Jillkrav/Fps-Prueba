extends EnemyBase
class_name EnemyPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	enemy_name = "Enemigo Pistolero"
	max_health = 35.0
	speed = 2.5 # Más lento
	damage = 8.0 # Daño moderado
	attack_range = 12.0 # Ataca desde lejos
	attack_rate = 1.5
	super._ready()

func perform_attack() -> void:
	# Simula disparo de pistola (distancia media)
	if target_player and not target_player.is_dead:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_transform.origin + Vector3(0, 1.0, 0),
			target_player.global_transform.origin + Vector3(0, 1.0, 0)
		)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		
		# Si hay línea de visión clara hacia el jugador (colisiona con jugador primero o nada)
		if result and result.get("collider") == target_player:
			target_player.take_damage(damage)
			# Pequeño efecto visual de rayo/línea de disparo si quisiéramos
			draw_debug_laser(global_transform.origin + Vector3(0, 1.0, 0), target_player.global_transform.origin + Vector3(0, 1.0, 0))

func draw_debug_laser(start: Vector3, end: Vector3) -> void:
	# Creamos una línea temporal en 3D
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	
	mesh_instance.mesh = immediate_mesh
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.YELLOW
	mesh_instance.material_override = material
	
	get_parent().add_child(mesh_instance)
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	
	# Auto-eliminar después de un frame
	var timer: SceneTreeTimer = get_tree().create_timer(0.08)
	timer.timeout.connect(func() -> void: mesh_instance.queue_free())
