# scripts/props/prop_base.gd
# Base class for all Props — objetos de escena reutilizables
# que los bots pueden recorrer (rampas, escaleras, etc).
class_name PropBase
extends StaticBody3D

## Nombre descriptivo del prop (para debug y editor)
@export var prop_name: String = "Prop"

func _ready() -> void:
	add_to_group("props")
