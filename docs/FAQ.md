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
Auto
Codex
Ollama
OpenRouter
Gemini
DeepSeek
Grok
```

`Auto` usa el orden configurado en `.codex/provider-config.json`.

---

## ¿Cuál es el orden de Auto?

La configuración actual de `main` es local-first:

```text
Auto
↓
Ollama
```

según `.codex/provider-config.json`.

`allow_paid_fallback` está deshabilitado por defecto. DeepSeek y Grok pueden seleccionarse explícitamente, pero no se agregan silenciosamente como fallback pago.

---

## ¿Auto garantiza que siempre habrá un provider?

No. Con la configuración por defecto, `Auto` necesita que el runtime local Ollama sea resoluble. Si querés usar otro provider, podés seleccionarlo explícitamente o cambiar `auto_order` de forma consciente.

---

## ¿El sistema usa OpenAI API automáticamente si Codex se queda sin cuota?

No.

El adapter Codex evita utilizar accidentalmente `CODEX_API_KEY` como fallback de pago.

Los providers API externos requieren sus credenciales correspondientes. La configuración por defecto no habilita fallback pago automático.

---

## ¿Los providers externos pueden leer todo el repositorio?

No necesariamente.

Ollama y los providers API externos reciben un Repository Context Pack limitado.

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

El runner estándar de agents sigue siendo de análisis/read-only.

`main` también incluye un writable runtime explícitamente autorizado que opera sobre worktrees aislados y aplica políticas de paths/verification. La integración Git posterior —merge, push o deploy— no queda autorizada automáticamente y sigue requiriendo control separado.

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

## ¿La CLI/TUI ya forma parte de main?

Sí.

El paquete npm expone el comando `aico`, incluyendo navegación CLI/TUI y `aico shell`. Los scripts PowerShell siguen siendo el contrato de bajo nivel para lifecycle, providers, gates y operaciones avanzadas.

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


## ¿Review siempre usa un rol diferente al owner?

No, no en la implementación actual.

El Review gate utiliza `engineering-manager`. Para tasks cuyo owner es PM, CTO, Backend, Frontend, DevOps, QA o Security, eso produce separación de rol.

Para una task cuyo owner original también es `engineering-manager`, esa independencia no está garantizada por identidad de rol.

La documentación lo registra como limitación conocida en lugar de afirmar una independencia que el runtime actual no asegura.


---

## ¿Necesita cloud AI?

No.

La instalación, diagnóstico, planning determinista y muchas validaciones no requieren un provider cloud.

Para ejecutar IA con el Auto general por defecto, necesitás un Ollama local usable. También podés seleccionar explícitamente un provider cloud configurado.

---

## ¿Auto usa providers pagos automáticamente?

No en la configuración actual.

General Auto usa Ollama solamente. Engineering Manager puede tener candidatos cloud por configuración, pero DeepSeek/Grok se omiten como fallback automático mientras allow_paid_fallback=false.

Eso no convierte todos los demás providers cloud en garantizadamente gratuitos: cuota y costo dependen del provider, cuenta y modelo/ruta.

---

## ¿Cómo actualizo AI Company OS?

Dos pasos distintos:

~~~powershell
npm install -g @pereyram/ai-company-os@latest
aico update .
~~~

El primero actualiza el paquete global. El segundo actualiza el runtime administrado dentro del proyecto.

---

## ¿aico update puede sobrescribir mi proyecto?

El updater está diseñado para no modificar source, tasks, Work Requests, docs/evidence de proyecto o state.

Solo opera sobre su runtime/config administrado y falla si encuentra un conflicto cuyo ownership no puede demostrar.

Eso no elimina la recomendación de usar Git y revisar el diff.

---

## ¿Es seguro usar aico install en un repositorio existente?

La instalación normal preserva archivos existentes en paths del framework mediante SKIP y el packaged E2E comprueba que un archivo source preexistente se conserva.

Sin embargo, AI Company OS agrega un conjunto significativo de archivos/directorios al repositorio. Usá una branch limpia y revisá el diff antes de adoptar el framework.

Force puede reemplazar archivos del framework y no debe usarse como updater rutinario.

---

## ¿Qué versiones de Python y Node están soportadas?

Contrato declarado:

~~~text
Python >=3.11
Node >=20
~~~

Evidencia CI actual:

~~~text
Python 3.11
Python 3.12
Node 20
~~~

No se debe convertir el rango declarado en una afirmación de que cada versión futura ya fue probada.

---

## ¿Soporta Linux o macOS?

No están establecidos como plataformas soportadas por el CI actual.

El producto es Windows-first. La presencia de algunos code paths portables no equivale a soporte probado.

---

## ¿Windows 10 y Windows 11 están ambos probados?

El CI prueba GitHub windows-latest, no una matriz explícita de clientes Windows 10 y Windows 11.

---

## ¿Está production-ready?

La documentación no lo presenta como production-ready.

Es un framework pre-beta con tests deterministas y release/package validation importantes, pero aún tiene límites conocidos: integración Git posterior a writable execution, plataforma, legacy migrations, provider variability y otras áreas de madurez.

---

## ¿Puede ejecutar varias tareas simultáneamente?

El runner compartido permite -Parallel solo para análisis/read-only.

Trabajo writable concurrente requiere worktrees separados por task. La integración posterior sigue siendo una acción separada.
