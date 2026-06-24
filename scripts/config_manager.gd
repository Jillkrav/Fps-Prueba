# scripts/config_manager.gd
# Autoload singleton — registrar en Project > Autoloads con nombre "ConfigManager".
extends Node

const CONFIG_PATH := "res://config/skill.cfg.json"

var _data: Dictionary = {}

# ── Accesos directos frecuentes ──────────────────────────────────────────

var salud_jugador: float:
	get: return float(_get("SistemaSalud/SaludEstandarJugador", 100.0))

var mult_cabeza: float:
	get: return float(_get("SistemaSalud/MultiplicadoresDaño/Cabeza", 5.0))

var mult_torso: float:
	get: return float(_get("SistemaSalud/MultiplicadoresDaño/Torso", 1.0))

# ── Ciclo de vida ────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("ConfigManager: No se encontró skill.cfg.json en " + CONFIG_PATH)
		return

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("ConfigManager: Error al parsear JSON — línea %d: %s" % [
			json.get_error_line(), json.get_error_message()
		])
		return

	_data = json.get_data().get("ConfiguracionJuego", {})
	print("ConfigManager: skill.cfg.json cargado correctamente.")

# ── API pública ──────────────────────────────────────────────────────────

## Devuelve el diccionario completo de un arma buscando por nombre exacto.
## Ejemplo: ConfigManager.get_arma("USP")
## Retorna {} si el arma no existe — los scripts deben manejar ese caso.
func get_arma(nombre: String) -> Dictionary:
	var armas: Dictionary = _data.get("Armas", {})
	for categoria: Dictionary in armas.values():
		if categoria.has(nombre):
			return categoria[nombre]
	push_warning("ConfigManager: Arma '%s' no encontrada en skill.cfg.json" % nombre)
	return {}

## Devuelve la vida de un tipo de NPC.
## tipo: "Enemigo" | "Aliado"
func get_vida_npc(tipo: String) -> float:
	return float(_data.get("NPCs", {}).get(tipo, {}).get("Vida", 100.0))

## Devuelve la curación de un botiquín.
## nombre: "BotiquinPequeño" | "BotiquinMediano" | "BotiquinGrande"
func get_curacion_botiquin(nombre: String) -> float:
	return float(_data.get("Objetos", {}).get(nombre, {}).get("CantidadCuracion", 25.0))

## Lista todos los nombres de armas disponibles en el JSON.
func get_nombres_armas() -> Array:
	var resultado: Array = []
	var armas: Dictionary = _data.get("Armas", {})
	for categoria: Dictionary in armas.values():
		resultado.append_array(categoria.keys())
	return resultado

# ── Acceso genérico interno ──────────────────────────────────────────────

func _get(path: String, default_value: Variant) -> Variant:
	var keys := path.split("/")
	var current: Variant = _data
	for key: String in keys:
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return default_value
	return current
