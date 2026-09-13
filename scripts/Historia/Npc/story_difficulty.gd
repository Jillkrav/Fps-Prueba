class_name StoryDifficulty
extends Node

## Dificultad GLOBAL de los NPCs de Historia (autoload "StoryDifficulty").
##
## Un solo sitio para escalar a todos los NPCs (tiradores y melee): daño que
## hacen, cadencia de disparo, precisión, cobertura y reacción. Los NPCs leen
## los multiplicadores EN VIVO cada frame, así que cambiar el nivel afecta a
## los NPCs ya spawneados sin reiniciar nada.
##
## La composición final en cada NPC es: valor base × personalidad ×
## dificultad (orden fijo y documentado en TiradorConfig).
##
## Los ajustes viven en el recurso editable config/Historia/story_difficulty.tres
## (StoryDifficultySettings), tuneable desde el Inspector. Si falta el .tres
## se usan los valores por defecto de la clase.

const SETTINGS_PATH: String = "res://config/Historia/story_difficulty.tres"

var settings: StoryDifficultySettings = null


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	if settings != null:
		return  # ya cargado: no recargar (los cambios en vivo no se pisan)
	if ResourceLoader.exists(SETTINGS_PATH):
		settings = load(SETTINGS_PATH) as StoryDifficultySettings
	if settings == null:
		settings = StoryDifficultySettings.new()


## Cambia el nivel activo (en vivo; afecta a los NPCs ya spawneados).
func set_level(level: StoryDifficultySettings.Level) -> void:
	_load_settings()
	settings.level = level


## Nivel activo.
func get_level() -> StoryDifficultySettings.Level:
	_load_settings()
	return settings.level


## Guarda los ajustes actuales al .tres (para persistir el nivel).
func save_settings() -> void:
	if settings != null:
		ResourceSaver.save(settings, SETTINGS_PATH)


## Manager activo o null (tests sin autoload / sin árbol). NUNCA asumas que
## existe: los NPCs hacen `manager != null` antes de usarlo.
static func get_manager() -> StoryDifficulty:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(^"DifficultyManager") as StoryDifficulty
	return null


# ── Multiplicadores activos ────────────────────────────────────────────────

func damage_dealt_multiplier() -> float:
	return _value("damage_dealt", 1.0)


func fire_interval_multiplier() -> float:
	return _value("fire_interval", 1.0)


func accuracy_delta() -> float:
	return _value("accuracy_delta", 0.0)


func cover_threshold_multiplier() -> float:
	return _value("cover_threshold", 1.0)


func reaction_multiplier() -> float:
	return _value("reaction", 1.0)


## Segundos extra mínimos entre disparos del NPC por la dificultad
## (0 en NORMAL: no se restringe nada; >0 frena la cadencia).
func fire_extra_interval() -> float:
	_load_settings()
	var extra: float = maxf(0.0, fire_interval_multiplier() - 1.0) \
			* settings.fire_extra_interval_base
	return extra


## Valor de un array de multiplicadores en el nivel activo.
func _value(array_name: String, fallback: float) -> float:
	_load_settings()
	var values: Array = settings.get(array_name) as Array
	if values.is_empty():
		return fallback
	var index: int = clampi(int(settings.level), 0, values.size() - 1)
	return float(values[index])
