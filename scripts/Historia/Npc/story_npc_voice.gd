class_name StoryNpcVoice
extends Resource

## Voz de los NPCs de Historia por estado de la máquina jerárquica.
##
## Por ahora es VOZ DE DEBUG: cuando el NPC cambia de estado puede "hablar"
## una línea de su tabla, que se muestra en el display de debug flotante.
## Cuando haya audio, basta con añadir el clip a la tabla (o conectar a
## `line_spoken`) sin tocar la IA: la clave es el voice_key() de la máquina
## ("corriendo_huida", "en_combate_disparando", ...).
##
## Asignable por NPC en el Inspector (recurso .tres compartido o en línea).

signal line_spoken(key: String, text: String)

@export_category("Voz")
## Activa la voz del NPC.
@export var enabled: bool = true
## Probabilidad de decir una línea al cambiar de estado.
@export_range(0.0, 1.0, 0.05) var line_chance: float = 0.8
## Segundos mínimos ENTRE líneas de un mismo NPC (anti-spam).
@export_range(0.5, 60.0, 0.5) var global_cooldown: float = 8.0
## Segundos que la línea se mantiene visible en el display de debug.
@export_range(0.5, 10.0, 0.5) var line_display_time: float = 2.5
## Tabla de líneas por estado/sub-estado: clave = voice_key() de la máquina
## (p. ej. "corriendo_huida"), valor = Array[String] de líneas posibles.
## Si la clave exacta no existe, prueba la clave solo del estado ("corriendo").
@export var lines: Dictionary = {
	"muerto": ["¡Agh!", "..."],
	"deteccion_confirmado": ["¡Enemigo a la vista!", "¡Ahí está!", "¡Contacto!"],
	"deteccion_pidiendo_ayuda": ["¡Ayuda aquí!", "¡Necesito refuerzos!", "¡Que alguien venga!"],
	"corriendo_huida": ["¡Me largo!", "¡Retirada!", "¡Cúbranme!"],
	"corriendo_apurarse": ["¡Ahi voy!", "¡Voy corriendo!", "¡Ya voy!"],
	"corriendo_persiguiendo": ["¡No se me escapa!", "¡Te tengo!", "¡Ven aquí!"],
	"en_combate_disparando": ["¡Fuego!", "¡Recibe!", "¡Toma esto!"],
	"en_combate_en_cobertura": ["¡Cubriéndome!", "¡Aquí no me alcanzas!"],
	"en_combate_recargando": ["¡Recargando!", "¡Cubran un momento!"],
	"gano_combate_vigilando": ["¡Zona despejada!", "¡Listo!", "¡Se acabó!"],
}

## Instante de la última línea dicha (Time.get_ticks_msec). Arranca en un
## valor muy negativo para que el cooldown NUNCA bloquee la primera línea.
var _last_spoken_msec: int = -1000000


## Llama el NPC al cambiar de estado. Devuelve la línea dicha (vacío si
## calma, cooldown, azar o tabla sin líneas). También emite `line_spoken`
## para enganchar audio en el futuro.
func try_speak(machine: StoryNpcStateMachine) -> String:
	if not enabled or machine == null:
		return ""
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_spoken_msec < int(global_cooldown * 1000.0):
		return ""
	var key: String = machine.voice_key()
	var candidates: Array = _lines_for(key, machine)
	if candidates.is_empty():
		return ""
	if randf() > line_chance:
		return ""
	_last_spoken_msec = now_msec
	var text: String = str(candidates[randi() % candidates.size()])
	line_spoken.emit(key, text)
	return text


## Candidatas para una clave exacta; si no hay, fallback a la clave de solo
## el estado ("en_combate_disparando" → "en_combate").
func _lines_for(key: String, machine: StoryNpcStateMachine) -> Array:
	var entry: Variant = lines.get(key)
	if entry is Array and not (entry as Array).is_empty():
		return entry as Array
	var state_key: String = StoryNpcStateMachine.state_name(machine.state).to_lower()
	var state_entry: Variant = lines.get(state_key)
	if state_entry is Array:
		return state_entry as Array
	return []
