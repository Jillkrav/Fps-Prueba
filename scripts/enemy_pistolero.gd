# scripts/enemy_pistolero.gd
# Enemigo con pistola. Hereda de EnemyBase.
# Daño leído desde ConfigManager (arma USP).
extends EnemyBase
class_name EnemyPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	enemy_name   = "Enemigo Pistolero"
	sexo         = Sexo.MASCULINO
	relacion     = Relacion.ENEMIGO
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE

	# Stats propios — max_health se delega a enemy_base._ready() via ConfigManager
	speed        = 2.5
	attack_range = 12.0
	attack_rate  = 1.5

	# Daño: usa DañoAlJugador de la USP como referencia para enemigos pistoleros
	var cfg := ConfigManager.get_arma("USP")
	damage = float(cfg.get("DañoAlJugador", 25.0))

	super._ready()

func perform_attack() -> void:
	if not target_player or target_player.is_dead:
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
