extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name        = "NPC Melee"
	equipo          = NpcBase.Equipo.DOS
	experiencia     = NpcBase.Experiencia.MEDIA
	estado          = NpcBase.Estado.IDLE
	speed           = 4.0
	attack_range    = 1.5
	weapon_name_cfg = ""  # Melee no usa arma del JSON
	super._ready()        # Carga vida desde ConfigManager

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	# Daño melee fijo (sin arma en JSON)
	if target.has_method("take_damage"):
		target.take_damage(20.0)
