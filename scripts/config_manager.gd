# scripts/config_manager.gd
# Autoload singleton. Registrar como "ConfigManager" en Project Settings > Autoload.
extends Node

const CONFIG_PATH := "res://config/Skillcfg.json"

var _data: Dictionary = {}

# ─── Accesos directos ───────────────────────────────────────────────

var salud_jugador: float:
	get: return float(_cfg_get("SistemaSalud/SaludEstandarJugador", 100.0))

var mult_cabeza: float:
	get: return float(_cfg_get("SistemaSalud/MultiplicadoresDaño/Cabeza", 5.0))

var mult_torso: float:
	get: return float(_cfg_get("SistemaSalud/MultiplicadoresDaño/Torso", 1.0))

# ─── Inicialización ─────────────────────────────────────────────────

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("ConfigManager: No se encontró skill cfg en %s" % CONFIG_PATH)
		return

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		push_error("ConfigManager: Error JSON línea %d — %s" % [json.get_error_line(), json.get_error_message()])
		return

	_data = json.get_data().get("ConfiguracionJuego", {})
	print("ConfigManager: Skillcfg.json cargado OK.")

# ─── Métodos públicos ────────────────────────────────────────────────

## Devuelve todos los datos de un arma por nombre exacto del JSON.
## Ejemplo: ConfigManager.get_arma("USP")
func get_arma(nombre: String) -> Dictionary:
	var armas: Dictionary = _data.get("Armas", {})
	for categoria: Dictionary in armas.values():
		if categoria.has(nombre):
			return categoria[nombre]
	push_warning("ConfigManager: Arma '%s' no encontrada." % nombre)
	return {}

## Devuelve la vida de un NPC por tipo ("Enemigo" o "Aliado").
func get_vida_npc(tipo: String) -> float:
	return float(_data.get("NPCs", {}).get(tipo, {}).get("Vida", 100.0))

## Devuelve la curación de un botiquín por nombre.
func get_curacion_botiquin(nombre: String) -> float:
	return float(_data.get("Objetos", {}).get(nombre, {}).get("CantidadCuracion", 25.0))

## Devuelve la precisión de la IA según nivel de experiencia.
func get_precision_ia(experiencia: String) -> float:
	return float(
		_data.get("SistemaIA", {})
		     .get("Experiencia", {})
		     .get(experiencia, {})
		     .get("PrecisionDecimal", 0.45)
	)

## Helpers de tipo para weapon.gd o lógica de disparo.
func es_escopeta(cfg: Dictionary) -> bool:
	return cfg.has("CantidadPerdigones")

func es_melee(cfg: Dictionary) -> bool:
	return cfg.get("TipoAtaque", "") == "Melee"

# ─── Acceso genérico por ruta (INTERNO) ─────────────────────────────
# Nombrado _cfg_get para evitar conflicto con Object._get(StringName)

## Acceso genérico a _data por ruta separada con "/".
## Ejemplo: _cfg_get("SistemaSalud/SaludEstandarJugador", 100.0)
func _cfg_get(path: String, default_value: Variant) -> Variant:
	var keys := path.split("/")
	var current: Variant = _data
	for key in keys:
		if current is Dictionary and current.has(key):
			current = current[key]
		else:
			return default_value
	return current
