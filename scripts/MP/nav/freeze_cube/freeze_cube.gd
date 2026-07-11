# scripts/freeze_cube.gd
# ──────────────────────────────────────────────────────────────────
# CUBO DE CONGELACIÓN — Congela a los NPCs que lo tocan por 5 segundos
#
# Coloca este nodo en el mapa como hijo de cualquier nodo.
# Cuando un NPC (NpcBase) toca el área, se congela: no se mueve,
# no procesa IA, no dispara, no hace nada durante 5 segundos.
# ──────────────────────────────────────────────────────────────────
extends Area3D
class_name FreezeCube


# ══════════════════════════════════════════════════════════════════
# CONSTANTES
# ══════════════════════════════════════════════════════════════════

## Duración del congelamiento en segundos
const FREEZE_DURATION: float = 3


# ══════════════════════════════════════════════════════════════════
# CICLO DE VIDA
# ══════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Detectar NPCs (capa 2 = Player, capa 3 = NpcBase)
	collision_layer = 0
	collision_mask = 6  # capas 2 y 3
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var npc: NpcBase = body as NpcBase
	if npc == null:
		return
	if npc.is_dead:
		return
	if npc.is_frozen:
		return
	
	npc.freeze(FREEZE_DURATION)
