# scripts/shared/gameplay/weapons/weapon_equip_state.gd
# ──────────────────────────────────────────────────────────────────
# WEAPON EQUIP STATE — Componente compartido (Fase 1)
#
# Gestiona el estado de "arma equipada/guardada" con cooldown de
# 1 segundo para simular la animación de sacar/guardar el arma.
#
# Este componente se agrega como hijo de:
#   - Player   (controlado por tecla H)
#   - BotBase  (controlado automáticamente por FSM de combate)
#
# ── SEÑALES ──
#   weapon_equipped()          → El arma está lista para usar
#   weapon_unequipped()        → El arma está guardada
#   equip_state_changed(bool)  → Cambió el estado (true=equipada)
#   equip_cooldown_started()   → Inicio del cooldown de 1s
#   equip_cooldown_finished()  → Fin del cooldown
# ──────────────────────────────────────────────────────────────────
extends Node
class_name WeaponEquipState


# ══════════════════════════════════════════════════════════════════
# SEÑALES
# ══════════════════════════════════════════════════════════════════

## Se emite cuando el arma pasa a estado equipada.
signal weapon_equipped()

## Se emite cuando el arma pasa a estado guardada.
signal weapon_unequipped()

## Se emite en cada cambio de estado (true = equipada, false = guardada).
signal equip_state_changed(is_now_equipped: bool)

## Se emite cuando inicia el cooldown de toggle (1s de animación).
signal equip_cooldown_started()

## Se emite cuando termina el cooldown de toggle.
signal equip_cooldown_finished()


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Duración del cooldown en segundos (simula animación de sacar/guardar).
const EQUIP_COOLDOWN: float = 1.0


# ══════════════════════════════════════════════════════════════════
# PROPIEDADES
# ══════════════════════════════════════════════════════════════════

## ¿Está el arma actualmente equipada y lista para usar?
var is_equipped: bool = false

## Timer interno para el cooldown de toggle.
var _cooldown_timer: Timer = null


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.name = "WeaponEquipCooldown"
	_cooldown_timer.one_shot = true
	_cooldown_timer.timeout.connect(_on_cooldown_finished)
	add_child(_cooldown_timer)


# ══════════════════════════════════════════════════════════════════
# MÉTODOS PÚBLICOS — Consulta de estado
# ══════════════════════════════════════════════════════════════════

## ¿Se puede disparar?
## Requiere: arma equipada Y cooldown de animación terminado.
func can_shoot() -> bool:
	return is_equipped and not _is_cooldown_active()


## ¿Se puede recargar?
## Ídem que can_shoot().
func can_reload() -> bool:
	return is_equipped and not _is_cooldown_active()


## ¿Está el toggle bloqueado por cooldown?
func is_toggle_locked() -> bool:
	return _is_cooldown_active()


## ¿Está actualmente en medio del cooldown?
func is_cooldown_active() -> bool:
	return _is_cooldown_active()


# ══════════════════════════════════════════════════════════════════
# MÉTODOS PÚBLICOS — Control de estado
# ══════════════════════════════════════════════════════════════════

## Equipa el arma. Respeta cooldown.
func equip() -> void:
	if is_equipped or is_toggle_locked():
		return
	_set_equipped(true)


## Desequipa (guarda) el arma. Respeta cooldown.
func unequip() -> void:
	if not is_equipped or is_toggle_locked():
		return
	_set_equipped(false)


## Alterna entre equipado/guardado. Respeta cooldown.
func toggle() -> void:
	if is_toggle_locked():
		return
	_set_equipped(not is_equipped)


# ══════════════════════════════════════════════════════════════════
# MÉTODOS INTERNOS
# ══════════════════════════════════════════════════════════════════

## Retorna true si el cooldown está activo.
func _is_cooldown_active() -> bool:
	return _cooldown_timer.time_left > 0.0


## Cambia el estado interno y dispara señales + cooldown.
func _set_equipped(value: bool) -> void:
	is_equipped = value

	# Emitir señales de cambio de estado
	equip_state_changed.emit(is_equipped)
	if is_equipped:
		weapon_equipped.emit()
	else:
		weapon_unequipped.emit()

	# Iniciar cooldown (simula animación de sacar/guardar)
	equip_cooldown_started.emit()
	_cooldown_timer.start(EQUIP_COOLDOWN)


## Se llama cuando el timer de cooldown termina.
func _on_cooldown_finished() -> void:
	equip_cooldown_finished.emit()
