# animation_set.gd
# ─────────────────────────────────────────────────────────────────────────────
# ÚNICO archivo responsable de definir todas las animaciones del juego.
#
# Cada animación tiene:
#   - file:   nombre del archivo FBX (dentro de fbx_directory)
#   - loop:   modo de loop (none=0, linear=1, pingpong=2)
#   - fallback: nombre lógico de animación alternativa (vacío = sin fallback)
#   - speed:  escala de velocidad (1.0 = normal)
#
# Para agregar, quitar o modificar animaciones solo se edita este .tres.
# No es necesario tocar player.gd, bot_base.gd ni ningún script.
#
# Uso:
#   anim_set.get_anim_path("idle")        → "res://.../Rifle standing Idle.fbx"
#   anim_set.get_loop_mode("idle")        → 1 (Animation.LOOP_LINEAR)
#   anim_set.get_fallback("death")        → ""
#   anim_set.get_speed("run")             → 1.0
# ─────────────────────────────────────────────────────────────────────────────
extends Resource
class_name AnimationSet

## Carpeta base donde están los archivos FBX.
@export var fbx_directory: String = "res://Assets/Animaciones/Player/Con arma/"

## Animaciones disponibles:  nombre_lógico → nombre_del_archivo.fbx
@export var animations: Dictionary = {}

## Configuración por animación:  nombre_lógico → { loop, fallback, speed }
##   loop:     0 = LOOP_NONE, 1 = LOOP_LINEAR, 2 = LOOP_PINGPONG
##   fallback: nombre de otra animación si esta no existe
##   speed:    multiplicador de velocidad (1.0 = normal)
## Para animaciones sin entrada explícita se usan valores por defecto.
@export var animation_config: Dictionary = {}


## ── Helpers ─────────────────────────────────────────────────────────────────

## Devuelve la ruta completa (res://...) de un archivo FBX por nombre lógico.
func get_anim_path(anim_name: String) -> String:
	var filename: String = animations.get(anim_name, "")
	if filename.is_empty():
		return ""
	return fbx_directory.path_join(filename)

## Devuelve el nombre del archivo FBX para una animación (sin directorio).
func get_filename(anim_name: String) -> String:
	return str(animations.get(anim_name, ""))

## Devuelve el modo de loop. Por defecto LOOP_LINEAR (1).
func get_loop_mode(anim_name: String) -> int:
	var cfg: Dictionary = _get_config(anim_name)
	return int(cfg.get("loop", 1))

## Devuelve el nombre de la animación de fallback, o cadena vacía.
func get_fallback(anim_name: String) -> String:
	var cfg: Dictionary = _get_config(anim_name)
	return str(cfg.get("fallback", ""))

## Devuelve la escala de velocidad. Por defecto 1.0.
func get_speed(anim_name: String) -> float:
	var cfg: Dictionary = _get_config(anim_name)
	return float(cfg.get("speed", 1.0))

## Lista todos los nombres de animación que tienen archivo asignado.
func get_animation_list() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in animations.keys():
		result.append(str(key))
	return result

func _get_config(anim_name: String) -> Dictionary:
	var raw = animation_config.get(anim_name)
	if raw is Dictionary:
		return raw
	return {}
