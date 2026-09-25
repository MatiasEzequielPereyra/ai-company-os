# AI Company OS — FAQ

> Respuestas cortas a las preguntas que un usuario debería resolver antes de operar el sistema.

## ¿AI Company OS es una empresa de software autónoma?

No.

Es un framework que modela roles, responsabilidades, tasks, evidencia y gates de una organización de ingeniería.

Puede automatizar partes importantes del workflow, pero no reemplaza autorización humana, Git, CI/CD, revisión independiente ni responsabilidad de producción.

---

## ¿Qué problema intenta resolver?

Evitar que el trabajo con agentes de IA dependa exclusivamente del historial de un chat.

Convierte el trabajo en artefactos persistentes:

```text
Work Requests
Plans
Tasks
Dependencies
Dispatch packets
Agent reports
Results
Reviews
QA evidence
Security evidence
Final approvals
Metrics
```

---

## ¿Cuál es la unidad principal de trabajo?

Una task:

```text
AICO-xxx
```

Se guarda como Markdown bajo:

```text
tasks/
```

---

## ¿Qué es un Work Request?

Es la intención de trabajo de alto nivel.

Ejemplo:

```text
"Auditar el proyecto para producción"
```

se convierte en:

```text
WR-001
```

y luego en un plan y un conjunto de tasks.

---

## ¿Work Request y AICO task son lo mismo?

No.

```text
Work Request = objetivo de alto nivel
AICO task     = unidad ejecutable/trazable de trabajo
```

Un Work Request puede generar múltiples tasks.

---

## ¿Qué hace el orchestrator?

Coordina:

```text
Work Request
→ Plan
→ Materialización de planning tasks
→ Readiness
→ Dispatch
→ Sync state
```

Con `-Apply`, puede activar tasks elegibles.

No significa que automáticamente escriba código.

---

## ¿Por qué primero aparecen tasks de PM/CTO/Engineering Manager?

Porque AI Company OS separa:

```text
definir qué hacer
de
hacerlo
```

Las planning tasks resuelven producto, arquitectura, validación y planificación.

Después, el plan aprobado del Engineering Manager puede convertirse en un backlog de implementación.

---

## ¿Qué estados tiene una task?

```text
BACKLOG
READY
ACTIVE
REVIEW
QA
SECURITY
DONE
BLOCKED
```

Flujo habitual:

```text
BACKLOG → READY → ACTIVE → REVIEW → QA → SECURITY → DONE
```

---

## ¿Qué significa READY?

Que la task tiene el contexto mínimo necesario y sus dependencias requeridas están satisfechas.

No significa permiso ilimitado para modificar código.

---

## ¿Qué significa ACTIVE?

Que la task fue despachada para ejecución dentro de su contrato.

Tampoco significa permiso de merge, push o deployment.

---

## ¿Qué significa BLOCKED?

Que el owner no pudo completar su entrega por falta de una condición material.

No significa simplemente que encontró defectos.

---

## ¿Una auditoría con hallazgos críticos debería marcarse BLOCKED?

No necesariamente.

Si el agente pudo completar la auditoría y documentar los hallazgos, su entrega puede ser:

```text
COMPLETED
```

aunque la conclusión sea que el producto no está listo para producción.

---

## ¿AI Company OS puede usar Codex?

Sí.

El provider Codex utiliza Codex CLI.

El adapter actual está configurado para análisis/read-only en el runner estándar.

---

## ¿Puede usar otros modelos?

Actualmente el provider router de `main` soporta:

```text
Codex
OpenRouter
Gemini
```

y:

```text
Auto
```

para intentar providers en orden.

---

## ¿Cuál es el orden de Auto?

La configuración actual de `main` es:

```text
Codex
↓
OpenRouter
↓
Gemini
```

según `.codex/provider-config.json`.

---

## ¿Auto garantiza que siempre habrá un provider?

No.

Si Codex no está disponible y no hay API keys válidas para los otros providers, el router termina con error.

---

## ¿El sistema usa OpenAI API automáticamente si Codex se queda sin cuota?

No.

El adapter Codex evita utilizar accidentalmente `CODEX_API_KEY` como fallback de pago.

OpenRouter y Gemini requieren sus credenciales correspondientes.

---

## ¿Los providers externos pueden leer todo el repositorio?

No necesariamente.

OpenRouter y Gemini reciben un Repository Context Pack limitado.

Codex CLI puede inspeccionar el repositorio dentro del sandbox configurado.

---

## ¿Qué es un workflow profile?

Define el nivel de assurance de una task.

Actualmente:

```text
lightweight
standard
high-assurance
```

---

## ¿high-assurance qué cambia?

Entre otras reglas, exige un resultado explícito de Security.

No permite:

```text
NOT_APPLICABLE
```

como disposición de Security.

---

## ¿Review, QA y Security son la misma cosa?

No.

```text
Review    → evalúa la entrega y su coherencia técnica
QA        → verifica aceptación/evidencia funcional
Security  → evalúa aspectos de seguridad aplicables
```

Son gates separados.

---

## ¿Quién marca DONE?

La aprobación final.

Incluso después de Security satisfecho, la task requiere:

```text
finalize-task.ps1
```

con una decisión:

```text
APPROVE
o
REJECT
```

---

## ¿Por qué no pasa automáticamente de Security a DONE?

Porque el sistema separa verificación especializada de aprobación final del objetivo.

Security puede decir que no hay un problema de seguridad y aun así el objetivo original podría no estar completamente satisfecho.

---

## ¿AI Company OS puede modificar código?

El framework incluye infraestructura para trabajo con escritura autorizado mediante Git worktrees aislados.

El runner estándar de agents en `main` es de análisis/read-only.

La automatización completa de mutación e integración sigue siendo un área en evolución.

---

## ¿Qué es un worktree?

Un checkout Git separado asociado a una task.

Ejemplo:

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Evita que dos trabajos con escritura compartan el mismo filesystem.

---

## ¿Crear un worktree autoriza push o merge?

No.

```text
worktree
≠
merge
≠
push
≠
deploy
```

---

## ¿Qué es implementation_authorization_key?

Es una referencia del engineering backlog a una decisión explícita que habilita implementación cuando esa autorización es requerida.

El materializer puede hacer que las tasks de implementación dependan de esa decisión.

---

## ¿Por qué hay tantas evidencias Markdown?

Porque uno de los objetivos del framework es que una persona pueda reconstruir qué ocurrió sin depender de memoria conversacional.

El formato Markdown también mantiene los artifacts revisables con Git.

---

## ¿Por qué no usar una base de datos?

El diseño actual es repository-native y filesystem-backed.

Eso prioriza:

- portabilidad;
- inspección;
- Git history;
- recuperación simple;
- ausencia de un control plane obligatorio.

No significa que una base de datos nunca pueda existir en una evolución futura.

---

## ¿Qué es source of truth y qué es estado derivado?

Ejemplo:

```text
tasks/AICO-123.md
```

es autoritativo para el lifecycle de esa task.

```text
.codex/state/company-state.*
```

es derivado y puede regenerarse.

---

## ¿Puedo editar una task manualmente?

Técnicamente es Markdown, pero cambiar metadata crítica a mano puede romper contratos.

Para prioridad/owner/profile/notas usar los scripts correspondientes.

Para transiciones utilizar el lifecycle.

Evitar modificar manualmente solamente `Status:`.

---

## ¿Qué pasa si una task falla Review, QA o Security?

Vuelve a `READY` para trabajo correctivo.

```text
CHANGES_REQUIRED → READY
QA FAIL          → READY
Security FAIL    → READY
```

---

## ¿Qué pasa si el CEO/final approval rechaza?

También vuelve a `READY`.

La evidencia previa permanece como historial.

---

## ¿Puedo ejecutar varias tasks en paralelo?

Sí, con condiciones.

El modo compartido `-Parallel` está restringido al runner de análisis.

Trabajo paralelo con escritura debe usar worktrees aislados.

---

## ¿Qué test demuestra que el lifecycle puede gobernar un cambio real?

```text
test-project/tests/test-end-to-end-code-change.ps1
```

Modifica una función real dentro de un fixture temporal, verifica el comportamiento y atraviesa Result, Review, QA, Security y Final Approval hasta DONE.

No llama a un provider externo.

---

## ¿Por qué el E2E no llama a un modelo?

Para que la prueba del framework sea determinística y no dependa de:

- red;
- cuota;
- API;
- comportamiento variable de modelos.

Los providers se prueban como contratos y la disponibilidad live se trata como integración.

---

## ¿La TUI ya es la interfaz oficial?

No en `main`.

Existen ramas de desarrollo de TUI/CLI visual, pero hasta que se integren y validen no se documentan como interfaz estable.

---

## ¿Qué debería leer primero?

Para un usuario nuevo:

```text
README
↓
Quick Start
↓
First Run Checklist
↓
User Guide
↓
End-to-End Walkthrough
```

Troubleshooting y Command Reference se consultan según necesidad.

---

## ¿Cómo sé si una instrucción del manual corresponde a mi versión?

Comprobar:

```powershell
git branch --show-current
git log -1 --oneline
```

La documentación v0.1 actual está construida contra el comportamiento de `main` indicado en el repositorio al momento de su revisión.

---

## ¿Cuál es la regla más importante para operar AI Company OS?

No confundir:

```text
estado
con
autorización
```

y no confundir:

```text
output de un modelo
con
evidencia aprobada
```

El sistema existe precisamente para hacer visibles esas diferencias.
