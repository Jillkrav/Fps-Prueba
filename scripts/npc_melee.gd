# scripts/npc_melee.gd
extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name     = "NPC Melee"
	experiencia  = Experiencia.MEDIA
	estado       = Estado.IDLE
	# Stats desde skill.json usando arma melee (sin cargador -> _configurar_arma lo detecta)
	if nombre_arma == "":
		nombre_arma = "Crowbar"

	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	target.take_damage(damage)
