extends NpcBase
class_name NpcEscopetero

func _ready() -> void:
	npc_name        = "NPC Escopeta"
	equipo          = NpcBase.Equipo.DOS
	experiencia     = NpcBase.Experiencia.MEDIA
	estado          = NpcBase.Estado.IDLE
	speed           = 3.0
	attack_range    = 6.0
	weapon_name_cfg = "M3"  # Nombre exacto en skill.cfg.json
	super._ready()          # Carga vida y arma desde ConfigManager

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
		# FIX: CantidadPerdigones no existe en el JSON actual.
		# Se usa 4 como valor por defecto fijo hasta que se agregue al JSON.
		var num_pellets: int = 4
		for _i in range(num_pellets):
			draw_debug_laser(
				global_transform.origin + Vector3(0, 1.0, 0),
				target.global_transform.origin + Vector3(
					randf_range(-0.4, 0.4),
					randf_range(-0.4, 0.4),
					randf_range(-0.4, 0.4)
				),
				Color.ORANGE
			)
