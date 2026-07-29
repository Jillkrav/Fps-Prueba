# scripts/shared/core/bot_difficulty.gd
# ──────────────────────────────────────────────────────────────────
# BOT DIFFICULTY - Autoload global
#
# Guarda la dificultad elegida en el menu y expone los valores que
# usan los sistemas de percepcion y combate de cada bot.
#
# REGISTRO:
# Project > Project Settings > Autoload
#
# Path: res://scripts/shared/core/bot_difficulty.gd
# Name: BotDifficulty
# ──────────────────────────────────────────────────────────────────
extends Node


# ══════════════════════════════════════════════════════════════════
# ENUM
# ══════════════════════════════════════════════════════════════════

enum Level {
	FACIL = 0,
	NORMAL = 1,
	DIFICIL = 2,
}


# ══════════════════════════════════════════════════════════════════
# CONFIGURACION
# ──────────────────────────────────────────────────────────────────
# reaction_delay:
# Segundos que espera el bot tras ver un enemigo antes de confirmar
# el objetivo y reaccionar en combate.
#
# fire_cooldown:
# Tiempo minimo en segundos entre disparos del bot.
# Es un limite adicional y no reemplaza weapon.can_fire().
# ══════════════════════════════════════════════════════════════════

const CONFIGS: Dictionary = {
	Level.FACIL: {
		"label": "Facil",
		"reaction_delay": 1.20,
		"fire_cooldown": 0.90,
	},
	Level.NORMAL: {
		"label": "Normal",
		"reaction_delay": 0.55,
		"fire_cooldown": 0.45,
	},
	Level.DIFICIL: {
		"label": "Dificil",
		"reaction_delay": 0.10,
		"fire_cooldown": 0.12,
	},
}


# ══════════════════════════════════════════════════════════════════
# ESTADO
# ══════════════════════════════════════════════════════════════════

## Nivel usado por defecto si no se selecciona otro antes de iniciar.
var current_level: int = Level.NORMAL


# ══════════════════════════════════════════════════════════════════
# API PUBLICA
# ══════════════════════════════════════════════════════════════════

## Define la dificultad de los bots de la proxima partida.
func set_level(level: int) -> void:
	if CONFIGS.has(level):
		current_level = level
		return

	push_warning(
		"[BotDifficulty] Nivel invalido: %d. Se usara NORMAL." % level
	)
	current_level = Level.NORMAL


## Devuelve el nivel actual como entero.
func get_level() -> int:
	return current_level


## Devuelve el nombre legible del nivel actual.
func get_label() -> String:
	var config: Dictionary = CONFIGS.get(
		current_level,
		CONFIGS[Level.NORMAL]
	)
	return str(config["label"])


## Devuelve el delay de reaccion de los bots en segundos.
func get_reaction_delay() -> float:
	var config: Dictionary = CONFIGS.get(
		current_level,
		CONFIGS[Level.NORMAL]
	)
	return float(config["reaction_delay"])


## Devuelve el cooldown minimo entre disparos en segundos.
func get_fire_cooldown() -> float:
	var config: Dictionary = CONFIGS.get(
		current_level,
		CONFIGS[Level.NORMAL]
	)
	return float(config["fire_cooldown"])


## Restablece la dificultad por defecto.
## Util para volver al menu o para tests.
func reset() -> void:
	current_level = Level.NORMAL
