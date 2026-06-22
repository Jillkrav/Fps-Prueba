extends EnemyBase
class_name EnemyEscopetero

func _ready() -> void:
	enemy_name = "Enemigo Escopeta"
	max_health = 50.0 # Más resistente
	speed = 3.0
	damage = 25.0 # Alto daño a corta distancia
	attack_range = 6.0 # Rango medio-corto
	attack_rate = 2.0 # Lento en disparar
	super._ready()

func perform_attack() -> void:
	# Dispara un perdigón/ráfaga que causa daño escalado por la distancia
	if target_player and not target_player.is_dead:
		var dist: float = global_transform.origin.distance_to(target_player.global_transform.origin)
		# A menor distancia, más daño hace la escopeta
		var damage_multiplier: float = clamp((attack_range - dist) / attack_range, 0.2, 1.0)
		var final_damage: float = damage * damage_multiplier
		
		# Verificar línea de visión
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_transform.origin + Vector3(0, 1.0, 0),
			target_player.global_transform.origin + Vector3(0, 1.0, 0)
		)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)
		
		if result and result.get("collider") == target_player:
			target_player.take_damage(final_damage)
			# Efecto visual de varios lásers dispersos
			for i in range(4):
				var offset_end: Vector3 = target_player.global_transform.origin + Vector3(
					randf_range(-0.4, 0.4),
					randf_range(-0.4, 0.4),
					randf_range(-0.4, 0.4)
				)
				draw_debug_laser(global_transform.origin + Vector3(0, 1.0, 0), offset_end)

func draw_debug_laser(start: Vector3, end: Vector3) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	
	mesh_instance.mesh = immediate_mesh
	material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.ORANGE
	mesh_instance.material_override = material
	
	get_parent().add_child(mesh_instance)
	
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	
	var timer: SceneTreeTimer = get_tree().create_timer(0.08)
	timer.timeout.connect(func() -> void: mesh_instance.queue_free())
