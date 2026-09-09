## story_faction_system.gd
## ─────────────────────────────────────────────────────────────────────────────
## Sistema de facciones para los niveles de Historia.
##
## Lee `res://config/Historia/story_factions.json` (definido por id entero):
##   - facción 1 = Jugador y aliados (el humano y sus NPCs aliados)
##   - facción 2 = Zombies y aliens (enemigos PvE)
##   - facción 3 = Soldados enemigos (futuro combate NPC vs NPC)
##   - ... ampliable añadiendo entradas al JSON.
##
## Diseñado para que los NPCs aliados y enemigos del futuro se definan SOLO por
## su `faction_id`; el resto (quién es enemigo, color de equipo, nombre) lo
## resuelve este sistema a partir del JSON. Así no hace falta tocar código para
## añadir una facción nueva.
##
## Los ids de facción están alineados con Enums.Equipo (1=AZUL, 2=ROJO, 3=AMARILLO),
## por lo que el daño entre facciones respeta el sistema de fuego amigo existente
## (GameState.son_enemigos / es_dano_bloqueado_por_fff) sin cambios.
##
## Uso (API estática, no hace falta instanciar):
##   StoryFactionSystem.are_hostile(2, 1)          # -> true
##   StoryFactionSystem.are_allied(2, 2)           # -> true
##   StoryFactionSystem.get_faction_name(2)        # -> "Zombies y Aliens"
##   StoryFactionSystem.get_color(1)               # -> Color
## ─────────────────────────────────────────────────────────────────────────────
class_name StoryFactionSystem
extends RefCounted

const CONFIG_PATH: String = "res://config/Historia/story_factions.json"

## Facción por defecto del jugador humano (y sus aliados).
const PLAYER_FACTION: int = 1

## Facción por defecto de los enemigos PvE (zombies / aliens).
const ENEMY_FACTION: int = 2

static var _loaded: bool = false
static var _factions: Dictionary = {}   # id(int) -> Dictionary del JSON
static var _order: Array[int] = []      # ids en orden de definición


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_factions.clear()
	_order.clear()
	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[StoryFactionSystem] No se pudo abrir %s" % CONFIG_PATH)
		_loaded = true
		return
	var parser: JSON = JSON.new()
	var err: Error = parser.parse(file.get_as_text())
	file.close()
	if err != OK or not (parser.data is Dictionary):
		push_warning("[StoryFactionSystem] JSON inválido en %s" % CONFIG_PATH)
		_loaded = true
		return
	for entry: Variant in (parser.data as Dictionary).get("factions", []):
		if not (entry is Dictionary):
			continue
		var fid: int = int((entry as Dictionary).get("id", -1))
		if fid <= 0:
			continue
		_factions[fid] = entry
		_order.append(fid)
	_loaded = true


## Devuelve el dict de la facción (vacío si no existe).
static func get_faction(faction_id: int) -> Dictionary:
	_ensure_loaded()
	return _factions.get(faction_id, {}) as Dictionary


## Nombre legible de la facción.
static func get_faction_name(faction_id: int) -> String:
	return String(get_faction(faction_id).get("name", "Facción %d" % faction_id))


## Color representativo de la facción (desde el JSON, formato #rrggbb).
static func get_color(faction_id: int) -> Color:
	var hex: String = String(get_faction(faction_id).get("color", "#ffffff"))
	return Color(hex)


## Ids de las facciones que esta facción considera enemigas (según el JSON).
static func get_hostile_ids(faction_id: int) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in get_faction(faction_id).get("hostile_to", []):
		out.append(int(v))
	return out


## true si ambas facciones son enemigas (evalúa de forma simétrica, así el JSON
## solo necesita declarar la relación en una dirección). La misma facción nunca
## es enemiga de sí misma.
static func are_hostile(faction_a: int, faction_b: int) -> bool:
	if faction_a == faction_b:
		return false
	if get_hostile_ids(faction_a).has(faction_b):
		return true
	if get_hostile_ids(faction_b).has(faction_a):
		return true
	return false


## true si NO son enemigas (misma facción o aliadas según hostile_to).
static func are_allied(faction_a: int, faction_b: int) -> bool:
	return not are_hostile(faction_a, faction_b)


## Todos los ids de facción definidos en el JSON.
static func all_faction_ids() -> Array[int]:
	_ensure_loaded()
	return _order.duplicate()
