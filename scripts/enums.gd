# scripts/enums.gd
# Enumeraciones compartidas de todo el proyecto.
# Usar con class_name Enums:  Enums.Equipo.AZUL, Enums.Experiencia.ALTA, etc.
extends Node
class_name Enums

# ─────────────────────────────────────────
# EQUIPO
# 0 = Espectador (sin equipo, sin amigos ni enemigos)
# 1 = Azul
# 2 = Rojo
# 3 = Amarillo (futuro)
# 4 = Verde    (futuro)
# ─────────────────────────────────────────
enum Equipo {
	ESPECTADOR = 0,
	AZUL       = 1,
	ROJO       = 2,
	AMARILLO   = 3,
	VERDE      = 4
}

# ─────────────────────────────────────────
# EXPERIENCIA DEL NPC
# ─────────────────────────────────────────
enum Experiencia {
	BAJA  = 0,
	MEDIA = 1,
	ALTA  = 2
}

# ─────────────────────────────────────────
# ESTADO TÁCTICO DEL NPC
# ─────────────────────────────────────────
enum EstadoTactico {
	IDLE        = 0,
	PATRULLANDO = 1,
	BUSCANDO    = 2,
	BUSCANDO_ITEM = 6,  # Navegando hacia item de salud/municion (UT99)
	CUBRIENDO   = 7,     # Detras de cover recuperandose (UT99)
	ALERTA      = 3,
	ATACANDO    = 4,
	ARRANSE     = 5
}

# ─────────────────────────────────────────
# ROL DEL NPC (nuevo)
# Define el comportamiento táctico general
# ─────────────────────────────────────────
enum Rol {
	SOLDADO       = 0,  # Propósito general, equilibrado
	FRANCOTIRADOR = 1,  # Larga distancia, lento, mucho daño
	APOYO         = 2,  # Más vida, rango medio, prioriza cubrir
	EXPLORADOR    = 3,  # Rápido, corta distancia, agresivo
	COMANDANTE    = 4   # Líder, buffea aliados (futuro)
}

