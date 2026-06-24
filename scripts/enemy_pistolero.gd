# scripts/enemy_pistolero.gd
extends EnemyBase
class_name EnemyPistolero

func _ready() -> void:
	enemy_name   = "Enemigo Pistolero"
	relacion     = Relacion.ENEMIGO
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE
	speed        = 2.5
	attack_range = 12.0
	attack_rate  = 1.5
	# damage desde USP (DanioAlJugador, porque ataca al jugador)
	var cfg := ConfigManager.get_arma("USP")
	damage = float(cfg.get("DanioAlJugador", 25.0))
	super._ready()

func perform_attack() -> void:
	if target_player == null or target_player.is_dead:
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
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
