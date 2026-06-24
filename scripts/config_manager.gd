# scripts/config_manager.gd
# Autoload singleton. Registrar como "ConfigManager" en Project Settings > Autoload.
extends Node

const CONFIG_PATH := "res://config/skill.cfg.json"

var _data: Dictionary = {}

# ─── Accesos directos ───────────────────────────────────────────────

var salud_jugador: float:
	get: return _cfg_get("SistemaSalud/SaludEstandarJugador", 100.0)

var mult_cabeza: float:
	get: return _cfg_get("SistemaSalud/MultiplicadoresDano/Cabeza", 5.0)

var mult_torso: float:
	get: return _cfg_get("SistemaSalud/MultiplicadoresDano/Torso", 1.0)

# ─── Inicializacion ──────────────────────────────────────────────────

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("ConfigManager: No se encontro skill.cfg.json en " + CONFIG_PATH)
		return

	var file      := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var json  := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("ConfigManager: Error al parsear JSON - linea %d: %s" % [json.get_error_line(), json.get_error_message()])
		return

	_data = json.get_data().get("ConfiguracionJuego", {})
	print("ConfigManager: skill.cfg.json cargado OK. Claves: ", _data.keys())

# ─── Metodos publicos ────────────────────────────────────────────────

## Devuelve todos los datos de un arma por nombre exacto del JSON.
## Busca en todas las categorias (Pistolas, Subfusiles, Rifles, etc).
## Devuelve diccionario con claves del JSON, o {} si no existe.
func get_arma(nombre: String) -> Dictionary:
	var armas: Dictionary = _data.get("Armas", {})
	for categoria in armas.values():
		if categoria.has(nombre):
			return categoria[nombre]
	push_warning("ConfigManager: Arma '%s' no encontrada en skill.cfg.json" % nombre)
	return {}

## Devuelve la vida de un NPC por tipo ("Enemigo" o "Aliado").
func get_vida_npc(tipo: String) -> float:
	return float(_data.get("NPCs", {}).get(tipo, {}).get("Vida", 100.0))

## Devuelve la curacion de un botiquin por nombre ("BotiquinPequeno", etc).
func get_curacion_botiquin(nombre: String) -> float:
	return float(_data.get("Objetos", {}).get(nombre, {}).get("CantidadCuracion", 25.0))

## Devuelve lista de nombres de armas de una categoria ("Pistolas", "Rifles", etc).
## Si categoria es "", devuelve todas las armas de todas las categorias.
func get_nombres_armas(categoria: String = "") -> Array[String]:
	var result: Array[String] = []
	var armas: Dictionary = _data.get("Armas", {})
	if categoria != "" and armas.has(categoria):
		result.assign(armas[categoria].keys())
	else:
		for cat in armas.values():
			for nombre in cat.keys():
				result.append(nombre)
	return result

# ─── Acceso generico por ruta ────────────────────────────────────────

## Acceso generico interno. Separa claves con "/".
## Ejemplo: _cfg_get("SistemaSalud/SaludEstandarJugador", 100.0)
## NOTA: no usar "_get" porque es un metodo reservado de Object en Godot.
func _cfg_get(path: String, default_value: Variant) -> Variant:
	var keys    := path.split("/")
	var current: Variant = _data
	for key in keys:
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return default_value
	return current
