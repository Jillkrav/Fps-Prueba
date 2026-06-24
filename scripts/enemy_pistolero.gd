# scripts/enemy_pistolero.gd
# Enemigo que usa pistola. El arma y el daño se cargan desde skill.cfg.json.
extends EnemyBase

func _ready() -> void:
	weapon_name_cfg = "USP"   # Nombre exacto del JSON
	speed = 3.5
	attack_range = 15.0
	super._ready()            # Carga vida y arma desde ConfigManager
