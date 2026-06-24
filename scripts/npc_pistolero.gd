extends NpcBase
class_name NpcPistolero

func _ready() -> void:
	npc_name       = "NPC Pistolero"
	equipo         = NpcBase.Equipo.DOS
	experiencia    = NpcBase.Experiencia.MEDIA
	estado         = NpcBase.Estado.IDLE
	speed          = 2.5
	attack_range   = 12.0
	weapon_name_cfg = "Glock"  # Nombre exacto en skill.cfg.json
	super._ready()             # Carga vida y arma desde ConfigManager

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
		_npc_fire_weapon()
		draw_debug_laser(
			global_transform.origin + Vector3(0, 1.0, 0),
			target.global_transform.origin + Vector3(0, 1.0, 0),
			Color.YELLOW
		)
