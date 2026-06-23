extends NpcBase
class_name NpcMelee

func _ready() -> void:
	npc_name      = "NPC Melee"
	especie       = ""              # Definir al instanciar
	sexo          = Sexo.MASCULINO  # Definir al instanciar
	relacion      = Relacion.ENEMIGO
	experiencia   = Experiencia.MEDIA
	skin_path     = ""              # Definir al instanciar
	voz_path      = ""              # Definir al instanciar
	estado        = Estado.IDLE

	max_health    = 25.0
	speed         = 4.0
	damage        = 15.0
	attack_range  = 1.8
	attack_rate   = 1.0
	super._ready()
