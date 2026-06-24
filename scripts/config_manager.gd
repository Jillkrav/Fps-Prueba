# scripts/config_manager.gd
# Autoload singleton. Registrado como "ConfigManager" en project.godot.
extends Node

const CONFIG_PATH := "res://config/skill.json"

var _data: Dictionary = {}

# ── Accesos directos ──────────────────────────────────────────────────────────
var salud_jugador: float:
	get: return float(_get_path("SistemaSalud/SaludEstandarJugador", 100.0))

var mult_cabeza: float:
	get: return float(_get_path("SistemaSalud/MultiplicadoresDanio/Cabeza", 5.0))

var mult_torso: float:
	get: return float(_get_path("SistemaSalud/MultiplicadoresDanio/Torso", 1.0))

# ── Ciclo de vida ─────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("ConfigManager: No se encontro " + CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var text  := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ConfigManager: Error JSON linea %d — %s" % [json.get_error_line(), json.get_error_message()])
		return
	_data = json.get_data().get("ConfiguracionJuego", {})
	print("ConfigManager: skill.json cargado OK")

# ── API publica ───────────────────────────────────────────────────────────────

## Devuelve el dict completo de un arma buscando en todas las categorias.
## Ejemplo: ConfigManager.get_arma("USP")
func get_arma(nombre: String) -> Dictionary:
	for categoria in _data.get("Armas", {}).values():
		if categoria.has(nombre):
			return categoria[nombre]
	push_warning("ConfigManager: Arma '%s' no encontrada en skill.json" % nombre)
	return {}

## Devuelve la vida de un NPC por tipo ("Enemigo" o "Aliado").
func get_vida_npc(tipo: String) -> float:
	return float(_data.get("NPCs", {}).get(tipo, {}).get("Vida", 100.0))

## Devuelve la curacion de un botiquin ("BotiquinPequeno", "BotiquinMediano", "BotiquinGrande").
func get_curacion_botiquin(nombre: String) -> float:
	return float(_data.get("Objetos", {}).get(nombre, {}).get("CantidadCuracion", 25.0))

# ── Acceso interno por ruta "Seccion/Clave/SubClave" ──────────────────────────
func _get_path(path: String, default_val: Variant) -> Variant:
	var keys   := path.split("/")
	var current: Variant = _data
	for key in keys:
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return default_val
	return current
