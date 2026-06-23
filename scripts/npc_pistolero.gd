extends NpcBase
class_name NpcPistolero

@export var shoot_range: float = 15.0

func _ready() -> void:
	npc_name      = "NPC Pistolero"
	especie       = ""
	sexo          = Sexo.MASCULINO
	experiencia   = Experiencia.MEDIA
	skin_path     = ""
	voz_path      = ""
	estado        = Estado.IDLE

	max_health    = 35.0
	speed         = 2.5
	damage        = 8.0
	attack_range  = 12.0
	attack_rate   = 1.5
	# equipo se asigna ANTES de _ready() desde el spawner o inspector
	# NO sobreescribir aqui
	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_transform.origin + Vector3(0, 1.0, 0),
		target.global_transform.origin + Vector3(0, 1.0, 0)
	)
	query.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.get("collider") == target:
		target.take_damage(damage)
		draw_debug_laser(
			global_transform.origin + Vector3(0, 1.0, 0),
			target.global_transform.origin + Vector3(0, 1.0, 0),
			Color.YELLOW
		)
