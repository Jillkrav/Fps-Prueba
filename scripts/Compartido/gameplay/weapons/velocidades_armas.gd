# scripts/velocidades_armas.gd
# Autoload singleton. Registrar como "VelocidadesArmas" en Project Settings > Autoload.
extends Node

const CONFIG_PATH := "res://config/Compartido/velocidades_armas.json"
const DEFAULT_SPEED := 6.0

var _data: Dictionary = {}

# ─── Inicialización ──────────────────────────────────────────────────

func _ready() -> void:
	_load_config()


func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("VelocidadesArmas: No se encontró velocidades_armas.json en " + CONFIG_PATH)
		return

	var file      := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var json  := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("VelocidadesArmas: Error al parsear JSON - línea %d: %s" % [json.get_error_line(), json.get_error_message()])
		return

	_data = json.get_data().get("velocidades", {})
	print("VelocidadesArmas: velocidades_armas.json cargado OK. %d armas registradas." % _data.size())


# ─── Métodos públicos ────────────────────────────────────────────────

## Retorna la Velocidad con Arma equipada (VA) para el arma indicada.
## Si el arma no está registrada, devuelve DEFAULT_SPEED (6.0).
func get_va(nombre_arma: String) -> float:
	var entry: Dictionary = _data.get(nombre_arma, {})
	return float(entry.get("VA", DEFAULT_SPEED))


## Retorna la Velocidad mientras Dispara (VD) para el arma indicada.
## Si el arma no está registrada, devuelve DEFAULT_SPEED (6.0).
func get_vd(nombre_arma: String) -> float:
	var entry: Dictionary = _data.get(nombre_arma, {})
	return float(entry.get("VD", DEFAULT_SPEED))


## Retorna TRUE si el arma tiene entrada en el config.
func tiene_arma(nombre_arma: String) -> bool:
	return _data.has(nombre_arma)


## Retorna la cantidad de armas registradas.
func cantidad_armas() -> int:
	return _data.size()
