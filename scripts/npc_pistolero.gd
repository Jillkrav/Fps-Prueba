extends NpcBase
class_name NpcPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	npc_name = "NPC Pistolero"
	relacion = Relacion.ENEMIGO
	experiencia = Experiencia.MEDIA
	estado = Estado.IDLE
	speed = 2.5
	attack_range = 12.0
	attack_rate = 1.5
	nombre_arma = "Glock"
	max_health = ConfigManager.get_vida_npc("Enemigo")
	current_health = max_health
	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_transform.origin + Vector3(0, 1.0, 0),
		target.global_transform.origin + Vector3(0, 1.0, 0)
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	if result and result.get("collider") == target:
		_npc_fire_weapon(target)
		draw_debug_laser(
			global_transform.origin + Vector3(0, 1.0, 0),
			target.global_transform.origin + Vector3(0, 1.0, 0),
			Color.YELLOW
		)
