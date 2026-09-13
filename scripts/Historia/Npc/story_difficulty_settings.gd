class_name StoryDifficultySettings
extends Resource

## Ajustes de dificultad global de los NPCs de Historia.
##
## Editable en el Inspector a través del .tres
## (config/Historia/story_difficulty.tres). Los multiplicadores son ARRAYS
## INDEXADOS POR NIVEL: [FACIL, NORMAL, DIFICIL]. El autoload StoryDifficulty
## los lee en vivo; los NPCs los componen con la personalidad:
## valor base × personalidad × dificultad.

enum Level {
	FACIL,
	NORMAL,
	DIFICIL,
}

## Nivel activo.
@export var level: Level = Level.NORMAL

@export_category("Multiplicadores por nivel [FACIL, NORMAL, DIFICIL]")
## Multiplicador del DAÑO QUE HACEN los NPCs (melee y disparos).
@export var damage_dealt: Array[float] = [0.6, 1.0, 1.4]
## Multiplicador del intervalo de disparo de los NPCs (>1 disparan más lento).
## NORMAL no restringe nada; DIFICIL no puede disparar más rápido que el arma.
@export var fire_interval: Array[float] = [1.5, 1.0, 1.0]
## Segundos EXTRA entre disparos por cada punto de multiplicador por encima
## de 1.0 (controla cuánto frena la cadencia en fácil).
@export_range(0.0, 2.0, 0.05) var fire_extra_interval_base: float = 0.35
## Delta de precisión de los NPCs (se suma a fire_accuracy, con clamp 0..1).
@export var accuracy_delta: Array[float] = [-0.15, 0.0, 0.1]
## Multiplicador del umbral de vida para buscar cobertura (<1 se cubren antes).
@export var cover_threshold: Array[float] = [0.6, 1.0, 1.4]
## Multiplicador del tiempo de reacción (>1 reaccionan más lento).
@export var reaction: Array[float] = [1.5, 1.0, 0.75]
