# scripts/npc_pistolero.gd
extends NpcBase
class_name NpcPistolero

func _ready() -> void:
	npc_name     = "NPC Pistolero"
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE
	speed        = 2.5
	attack_range = 12.0
	attack_rate  = 1.5

	# La relacion y el equipo son asignados por el spawner ANTES de _ready.
	# Solo usamos ENEMIGO como valor por defecto si el spawner no asigno nada.
	if relacion == Relacion.ENEMIGO and equipo == "rojo":
		pass  # valores por defecto correctos, no tocar
	# Si el spawner asigno AMIGABLE, respetar esa asignacion sin sobreescribir.

	# Arma: usa nombre_arma si fue asignado externamente, si no usa USP por defecto
	if nombre_arma == "":
		nombre_arma = "USP"
	var cfg: Dictionary = ConfigManager.get_arma(nombre_arma)
	damage = float(cfg.get("DaNNÃ±oAlNPC", cfg.get("DañoAlNPC", 30.0)))

	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
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
