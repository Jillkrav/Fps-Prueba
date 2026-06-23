extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name      = "NPC Melee"
	especie       = ""
	sexo          = Sexo.MASCULINO
	experiencia   = Experiencia.MEDIA
	skin_path     = ""
	voz_path      = ""
	estado        = Estado.IDLE

	max_health    = 40.0
	speed         = 4.0
	damage        = 15.0
	attack_range  = 1.5
	attack_rate   = 1.0
	# equipo se asigna ANTES de _ready() desde el spawner o inspector
	# NO sobreescribir aqui
	super._ready()

func perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_dead") and target.get("is_dead"):
		return
	target.take_damage(damage)
