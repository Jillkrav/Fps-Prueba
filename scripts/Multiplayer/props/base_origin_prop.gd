# base_origin_prop.gd
# ──────────────────────────────────────────────────────────────────
# PROP DE ORIGEN DE BASE — Punto de orientación para los bots.
#
# Es un marcador SIN colisión que se coloca manualmente en cada base
# (oculto o bajo el mapa) y sirve ÚNICAMENTE para que los bots calculen
# la distancia a su base y a la base enemiga.
#
# Ejemplo de uso: decidir si un rol agresivo, al completar una ruta, arranca
# el cooldown de ruta completada (solo cuando está MÁS CERCA de la base
# enemiga que de la propia).
#
# Permite más de una base por equipo: se colocan varios props con el mismo
# `team_id`. La lógica de arriba usa la base MÁS CERCANA de cada equipo.
# ──────────────────────────────────────────────────────────────────
extends Node3D
class_name BaseOriginProp


## Grupo en el que se publican todos los props de origen de base.
## Los bots los localizan con get_tree().get_nodes_in_group().
const GROUP_BASE_ORIGINS: StringName = &"base_origins"

## Equipo al que pertenece esta base de origen (Enums.Equipo.AZUL/ROJO/...).
## Rellenar al colocar el prop en el mapa.
@export var team_id: int = int(Enums.Equipo.AZUL)


func _ready() -> void:
	# Publicar en el grupo para que los bots encuentren el punto de orientación.
	add_to_group(GROUP_BASE_ORIGINS)
