# Step-up & Vaulting — Plan de implementación

## Contexto visual
- Estilo Nintendo 64 (low-poly, colisiones simples)
- Obstáculos siempre son **cajas** por ahora (colisión cuadrada/rectangular)
- En el futuro: piedras, árboles, pero misma forma de colisión
- **Escalar (paredes muy grandes)**: pospuesto para futuro, solo contexto

---

## Los 3 niveles (por prioridad)

### Nivel 1 — Step-up nativo (YA LISTO ✅)
- **Obstáculo**: pequeño (< radio de cápsula ~0.42u)
- **Comportamiento**: el CharacterBody3D sube instantáneamente al caminar
- **Tiempo**: instantáneo
- **Estado**: el jugador/bot sigue controlando normal
- **Dónde**: `player.gd` (líneas 55-63) y `npc_base.gd` (líneas 90-99)

### Nivel 2 — Subirse / Vault (A IMPLEMENTAR)
- **Obstáculo**: mediano (entre ~0.42u y una altura máxima configurable)
- **Comportamiento**:
  - El personaje se **sube completamente arriba** del obstáculo
  - **Queda ligeramente por encima** de la superficie (para evitar colisión residual)
  - No puede disparar ni mover la cámara durante la acción
  - Una vez iniciado, **no se puede cancelar** — termina sí o sí
  - Tiene una **animación** de subirse
- **Tiempo**: breve pero no instantáneo (~0.5s - 1.0s)
- **Estado**: estado "vaulting" que bloquea input y arma

### Nivel 3 — Escalar (FUTURO, no implementar)
- Obstáculos muy grandes
- Múltiples "agarres" / animación cíclica
- Solo se menciona como contexto para diseño futuro

---

## Reglas para los bots (NPCs)
- **NO** se modifican decisiones tácticas, rutas, ni pathfinding
- **NO** tienen que "evaluar" si conviene escalar o rodear
- Si chocan con un obstáculo por casualidad → **lo escalan, punto**
- El sistema es puramente **reactivo**: el obstáculo está ahí, lo detectan, lo suben
- Mismo comportamiento que el jugador, pero sin animación (o con una genérica)

---

## Arquitectura implementada

```
res://scripts/vault_controller.gd  (class_name VaultController, extends RefCounted)
├── Completamente reutilizable (Player + NPCs)
├── Detección con 3 raycasts: FOOT (0.15u), MID (capsule_radius*1.2), TOP (vault_max_height)
├── Encuentra tope exacto del obstáculo con raycasts descendentes
├── Calcula target: tope_obstáculo + feet_offset + overshoot + avance_forward
├── Interpolación suave con ease-out cúbico
└── Cooldown post-vault (0.3s)

Integrado en:
├── Player (player.gd):
│   ├── VaultController creado en _ready()
│   ├── _physics_process: vault antes que step-up/crouch/jump
│   ├── _unhandled_input: bloqueado durante vault (sin cámara)
│   └── _process: bloqueado durante vault (sin arma)
│
└── MovementSystem (movement_system.gd):
	├── VaultController creado en _ready()
	├── process(): vault en curso → salta todo (incl. gravedad)
	├── _execute_navigate(): detecta vault durante navegación
	├── _execute_direct(): detecta vault durante strafe
	└── flag _vault_started_this_frame para salir de process()
```

### Propiedades configurables
| Propiedad | Descripción |
|---|---|
| `vault_max_height` | Altura máxima escalable (ej. 1.5 uds) |
| `vault_speed` | Velocidad de la interpolación de subida |
| `vault_clearance_check` | ¿Verificar espacio al otro lado? (Sí) |
| `vault_overshoot` | Separación extra por encima del obstáculo (ej. 0.1 uds) |

---

## Comportamiento durante el vault
| Aspecto | Estado |
|---|---|
| Movimiento | Bloqueado (interpolación forzada) |
| Cámara (player) | Congelada — no puede mirar alrededor |
| Disparo | Deshabilitado |
| Cancelación | No permitida |
| Colisión | Hitbox se reduce/desactiva durante el vault |
| Vulnerabilidad | Normal (recibe daño mientras escala) |

---

## Próximos pasos
1. Implementar detección de obstáculo frontal (raycasts en abanico vertical)
2. Añadir estado "vaulting" en player y npc_base
3. Interpolación de posición hacia arriba + adelante
4. Animación de subirse
5. Pruebas con cajas de diferentes alturas en `map_dust2.tscn`
