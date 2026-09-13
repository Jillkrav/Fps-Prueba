class_name StoryNpcStateMachine
extends RefCounted

## Máquina de estados JERÁRQUICA compartida por los NPCs de Historia
## (Tirador y CuerpoACuerpo).
##
## NO sustituye al StoryNPCTacticalBrain: el brain decide QUÉ HACE el NPC y esta
## máquina DERIVA lo que ESTÁ PASANDO (estado visible) a partir de flags de
## intención que los comportamientos publican cada frame. El estado resultante
## es el punto de enganche para animaciones, diálogos de voz y depuración.
##
## Estados (con prioridad de derivación en este orden):
##   MUERTO > CORRIENDO > DETECCION > EN_COMBATE > GANO_COMBATE > PATRULLANDO > QUIETO
##
## Sub-estados (StringName, significado por arquetipo):
##   DETECCION : "sospechando" | "confirmado" | "pidiendo_ayuda"
##   CORRIENDO : "huida" | "apurarse" | "persiguiendo"
##   EN_COMBATE (tirador) : "disparando" | "en_cobertura" | "recargando" | "kiting"
##   EN_COMBATE (melee)   : "atacando" | "acercandose"
##   GANO_COMBATE: "vigilando"
##   MUERTO: "muerto"

signal state_changed(
	previous_state: State,
	new_state: State,
	previous_sub: StringName,
	new_sub: StringName
)

enum State {
	QUIETO,
	PATRULLANDO,
	DETECCION,
	CORRIENDO,
	EN_COMBATE,
	GANO_COMBATE,
	MUERTO,
}

## Sub-estado vacío (el estado no tiene subdivisión en este frame).
const SUB_NONE: StringName = &""

var state: State = State.QUIETO
var substate: StringName = SUB_NONE
## Instante (Time.get_ticks_msec) en el que se entró en el estado actual.
var state_started_msec: int = 0


## Asigna el estado derivado de este frame. Ignora la llamada si no cambió
## nada (evita re-disparar señales y animaciones cada frame).
func set_state(new_state: State, new_sub: StringName = SUB_NONE) -> void:
	if state == new_state and substate == new_sub:
		return
	var previous_state: State = state
	var previous_sub: StringName = substate
	state = new_state
	substate = new_sub
	state_started_msec = Time.get_ticks_msec()
	state_changed.emit(previous_state, state, previous_sub, substate)


## Segundos transcurridos en el estado actual.
func time_in_state() -> float:
	return float(Time.get_ticks_msec() - state_started_msec) / 1000.0


## Texto legible del estado ("CORRIENDO·HUIDA") para el display de debug.
func describe() -> String:
	var text: String = state_name(state)
	if substate != SUB_NONE:
		text += "·" + String(substate).to_upper()
	return text


## Clave para tablas de voz/animación ("corriendo_huida"). Sin sub-estado,
## solo el estado ("muerto").
func voice_key() -> String:
	var key: String = state_name(state).to_lower()
	if substate != SUB_NONE:
		key += "_" + String(substate)
	return key


static func state_name(value: State) -> String:
	match value:
		State.QUIETO:
			return "QUIETO"
		State.PATRULLANDO:
			return "PATRULLANDO"
		State.DETECCION:
			return "DETECCION"
		State.CORRIENDO:
			return "CORRIENDO"
		State.EN_COMBATE:
			return "EN_COMBATE"
		State.GANO_COMBATE:
			return "GANO_COMBATE"
		State.MUERTO:
			return "MUERTO"
	return "DESCONOCIDO"
