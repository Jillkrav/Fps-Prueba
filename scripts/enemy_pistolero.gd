extends EnemyBase
class_name EnemyPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	enemy_name = "Enemigo Pistolero"
	max_health = 35.0
	speed = 2.5
	damage = 8.0
	attack_range = 12.0
	attack_rate = 1.5
	super._ready()

func perform_attack() -> void:
	if target_player and not target_player.is_dead:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_transform.origin + Vector3(0, 1.0, 0),
			target_player.global_transform.origin + Vector3(0, 1.0, 0)
		)
		query.exclude = [self]
		var result: Dictionary = space_state.intersect_ray(query)

		if result and result.get("collider") == target_player:
			target_player.take_damage(damage)
			draw_debug_laser(
				global_transform.origin + Vector3(0, 1.0, 0),
				target_player.global_transform.origin + Vector3(0, 1.0, 0),
				Color.YELLOW
			)
