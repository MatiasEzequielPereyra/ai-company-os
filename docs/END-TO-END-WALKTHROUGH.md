# AI Company OS — Recorrido End-to-End

> **Versión:** 0.1  
> **Verificado contra:** rama `main`  
> **Objetivo:** mostrar cómo un pedido del usuario se convierte en trabajo trazable y cómo una tarea real atraviesa los gates hasta `DONE`.

Este documento une dos comportamientos que hoy están validados por separado en el repositorio:

1. **Orquestación:** objetivo → Work Request → plan → tasks → readiness → dispatch.
2. **Lifecycle de entrega:** ACTIVE → resultado → REVIEW → QA → SECURITY → aprobación final → DONE.

No existe todavía un único test que ejecute todo este recorrido con un provider externo y además modifique código autónomamente. La documentación distingue esas fronteras de forma explícita.

---

## 1. Vista completa

```text
USUARIO
  │
  ▼
OBJETIVO
  │
  ▼
WORK REQUEST (WR-xxx)
  │
  ▼
ORCHESTRATION PLAN
  │
  ▼
PLANNING TASKS (AICO-xxx)
  │
  ├── PM
  ├── CTO
  ├── QA
  ├── Security
  ├── DevOps
  └── Engineering Manager
          │
          ▼
APPROVED ENGINEERING PLAN
          │
          ▼
ENGINEERING BACKLOG
          │
          ├── DECISION
          ├── IMPLEMENTATION
          ├── VALIDATION
          └── OPERATIONS
                  │
                  ▼
               READY
                  │
                  ▼
               ACTIVE
                  │
                  ▼
        RESULT / EVIDENCE
                  │
                  ▼
               REVIEW
                  │
                  ▼
                 QA
                  │
                  ▼
              SECURITY
                  │
                  ▼
          FINAL APPROVAL
                  │
                  ▼
                DONE
```

---

# Parte A — Del objetivo al plan de trabajo

## 2. Ejemplo: auditar un proyecto antes de producción

El smoke test del orchestrator utiliza este objetivo:

```text
Prepare project for production
```

El equivalente para un usuario sería:

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Prepare project for production" `
  -Type AUDIT `
  -Priority P1
```

Sin `-Apply`, el orchestrator trabaja en **modo PREPARE**.

No activa tareas.

### Qué crea

Primero se crea:

```text
docs/engineering/work-requests/WR-001.md
```

Después:

```text
docs/engineering/plans/WR-001-plan.md
```

Y finalmente un conjunto de tasks:

```text
tasks/AICO-001.md
tasks/AICO-002.md
tasks/AICO-003.md
...
```

Además se genera:

```text
docs/engineering/plans/WR-001-tasks.md
```

Ese archivo es un mapping derivado entre el Work Request y las tasks. Las tasks siguen siendo la fuente autoritativa.

---

## 3. Por qué un AUDIT genera varias tasks

Para un Work Request de tipo `AUDIT`, el plan requiere estos roles:

```text
pm
cto
engineering-manager
qa
security
devops
```

El objetivo es evitar que una única IA diga simultáneamente:

> "Producto está bien, arquitectura está bien, seguridad está bien y estamos listos para producción."

Cada dominio produce evidencia separada.

Para `AUDIT`, las tasks de PM, CTO, QA, Security y DevOps pueden ser independientes. La task del Engineering Manager depende de sus outputs.

Una representación simplificada es:

```text
PM ────────────────┐
CTO ───────────────┤
QA ────────────────┤
Security ──────────┼──► Engineering Manager
DevOps ────────────┘
```

El Engineering Manager no debería preparar el backlog de ejecución antes de que las evaluaciones que necesita estén terminadas.

---

## 4. Revisar las tasks antes de ejecutar

```powershell
.\scripts\list-tasks.ps1
```

En modo PREPARE deberían permanecer sin tareas `ACTIVE`.

Ese comportamiento está validado por `test-orchestrator.ps1`.

---

## 5. Activar solamente trabajo elegible

Después de revisar el plan:

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-001 `
  -Apply
```

Con `-Apply`, el orchestrator ejecuta:

```text
evaluate-readiness
        ↓
dispatch
        ↓
sync-company-state
```

En el smoke test de `AUDIT`, pasan a `ACTIVE` los roles independientes:

```text
pm
cto
qa
security
devops
```

La task del Engineering Manager permanece esperando sus dependencias.

Esto es importante:

> `-Apply` no significa "hacer todo". Significa aplicar transiciones para las tasks que ya cumplen las condiciones.

---

# Parte B — Ejecución de agentes de análisis

## 6. Ejecutar las tasks ACTIVE

```powershell
.\scripts\run-active-agents.ps1
```

O especificando provider:

```powershell
.\scripts\run-active-agents.ps1 -Provider Codex
```

También están disponibles:

```text
Auto
Codex
OpenRouter
Gemini
```

---

## 7. Qué hace realmente `run-agent-task.ps1`

El runner estándar verifica que:

- la task exista;
- esté en `ACTIVE`;
- tenga owner;
- exista su dispatch packet;
- exista la definición del rol;
- exista el schema del resultado.

Después ejecuta el provider.

El contrato del runner actual es explícito:

```text
AUDIT / ANALYSIS ONLY
```

El agente no debe modificar código de producción ni cambiar el estado de Git desde este runner.

---

## 8. Qué artefactos produce el agente

Por ejemplo, para `AICO-002`:

```text
.codex/runtime/AICO-002-result.json
docs/engineering/agent-reports/AICO-002.md
docs/engineering/results/AICO-002-result-001.md
```

El JSON es la salida estructurada del provider.

El agent report contiene el análisis completo del rol.

El task result registra formalmente la entrega.

---

## 9. Resultado COMPLETED

Cuando el provider devuelve:

```text
Outcome: COMPLETED
```

`run-agent-task.ps1` llama automáticamente a:

```text
submit-task-result.ps1
```

y la task pasa:

```text
ACTIVE
  ↓
REVIEW
```

Para entrar a `REVIEW`, el transition guard exige un result artifact cuyo:

```text
Outcome = COMPLETED
```

No alcanza con cambiar manualmente el texto `Status:`.

---

## 10. Resultado BLOCKED

Si falta una condición material que impide completar el trabajo:

```text
Outcome: BLOCKED
```

la task pasa:

```text
ACTIVE
  ↓
BLOCKED
```

`BLOCKED` no significa:

- que el producto tenga bugs;
- que QA haya encontrado problemas;
- que el sistema no esté listo para producción.

Significa que **el agente no pudo completar su propia entrega** por falta de evidencia, acceso, autorización o prerequisito.

Un audit puede encontrar veinte defectos graves y aun así tener outcome `COMPLETED` si el análisis fue completado correctamente.

---

# Parte C — Review, QA y Security

## 11. Ejecución automática de gates

Las tasks pendientes pueden procesarse con:

```powershell
.\scripts\run-pending-gates.ps1
```

O:

```powershell
.\scripts\run-pending-gates.ps1 -Provider Codex
```

El script procesa, en orden:

```text
REVIEW
  ↓
QA
  ↓
SECURITY
```

Cada gate utiliza un agente independiente del owner original cuando corresponde.

---

## 12. Review

Para una task en `REVIEW`, el gate produce:

```text
docs/engineering/reviews/AICO-xxx-review-001.md
```

Resultados:

```text
APPROVE
CHANGES_REQUIRED
```

Si aprueba:

```text
REVIEW → QA
```

Si solicita cambios:

```text
REVIEW → READY
```

La aprobación de Review **no significa** que QA o Security hayan aprobado.

---

## 13. QA

El gate de QA produce:

```text
docs/engineering/qa/AICO-xxx-qa.md
```

Resultados:

```text
PASS
FAIL
```

Si pasa:

```text
QA → SECURITY
```

Si falla:

```text
QA → READY
```

---

## 14. Security

El gate produce:

```text
docs/engineering/security/AICO-xxx-security.md
```

Resultados:

```text
PASS
FAIL
NOT_APPLICABLE
```

Para tareas `high-assurance`:

```text
NOT_APPLICABLE
```

no está permitido.

Un Security `FAIL` devuelve la task a `READY`.

Un Security `PASS` o un `NOT_APPLICABLE` permitido **no marca automáticamente la task como DONE**.

---

# Parte D — Aprobación final

## 15. Por qué existe un gate final

Después de QA y Security, todavía falta verificar que:

- el objetivo original fue satisfecho;
- la evidencia corresponde a esa task;
- los gates aplicables están completos.

La aprobación final se ejecuta mediante:

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-123 `
  -Decision APPROVE `
  -Verification "Objective and applicable gates verified"
```

El script exige:

```text
QA = PASS
Security = PASS o NOT_APPLICABLE permitido
Final Decision = APPROVE
```

y entonces:

```text
SECURITY → DONE
```

Para `high-assurance`, Security debe ser `PASS`.

---

# Parte E — De la planificación a las tareas de implementación

## 16. El Engineering Manager no implementa todo

Una de las distinciones más importantes de AI Company OS es:

```text
Planning tasks
≠
Implementation tasks
```

Las primeras tasks producidas por `orchestrate.ps1` describen responsabilidades organizacionales.

Por ejemplo:

```text
Define product scope
Define technical architecture
Prepare engineering execution plan
Prepare QA validation
...
```

Después de que la task del Engineering Manager está `DONE`, su plan aprobado puede convertirse en un backlog de ingeniería ejecutable.

---

## 17. Generar el engineering backlog

Suponiendo que la task del Engineering Manager sea `AICO-006`:

```powershell
.\scripts\generate-engineering-backlog.ps1 `
  -SourceTaskId AICO-006 `
  -Provider Codex
```

El script exige que:

- `AICO-006` exista;
- esté en `DONE`;
- exista su agent report;
- exista el schema de backlog;
- el resultado respete el contrato JSON.

Produce:

```text
docs/engineering/plans/AICO-006-engineering-backlog.json
```

---

## 18. Tipos de items del backlog

El backlog puede contener:

```text
DECISION
IMPLEMENTATION
VALIDATION
OPERATIONS
```

Esto permite separar, por ejemplo:

```text
DECISION
"Confirmar estrategia de migración"
        ↓
IMPLEMENTATION
"Modificar esquema de base de datos"
        ↓
VALIDATION
"Verificar migración y regresiones"
        ↓
OPERATIONS
"Preparar rollback"
```

---

## 19. Autorización de implementación

El backlog tiene un campo:

```text
implementation_authorization_key
```

Cuando la implementación necesita autorización explícita, debe existir un item `DECISION` que represente esa autorización.

El materializer fuerza que las tasks de implementación dependan de esa decisión.

Esto significa:

```text
Plan aprobado
≠
Implementación autorizada
```

---

## 20. Materializar el backlog

```powershell
.\scripts\materialize-engineering-backlog.ps1 `
  -SourceTaskId AICO-006
```

Antes de crear archivos, el materializer valida:

- keys duplicadas;
- dependencias inexistentes;
- self-dependencies;
- ciclos;
- authorization key;
- tipo del item de autorización.

Las nuevas tasks se crean en:

```text
BACKLOG
```

y reciben IDs `AICO-xxx`.

También se genera:

```text
docs/engineering/plans/AICO-006-engineering-backlog-tasks.md
```

---

# Parte F — Cuando una task necesita modificar código

## 21. La frontera de escritura

El runner estándar:

```text
run-agent-task.ps1
```

es de análisis.

Para una task de implementación con autorización de escritura, se crea un worktree aislado:

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Esto crea aproximadamente:

```text
branch: aico/aico-123
worktree: <proyecto>-worktrees/AICO-123
```

El worktree da aislamiento de Git/filesystem.

No concede por sí mismo permiso para:

```text
merge
rebase
push
deploy
destructive changes
```

---

## 22. Estado real de la automatización de escritura

Actualmente el framework tiene infraestructura para:

- separar análisis de mutación;
- crear worktrees aislados;
- materializar tareas de implementación;
- exigir evidencia y gates.

Pero el flujo de modificación autónoma completa + integración automática no debe considerarse terminado.

Por eso, una task de implementación puede requerir todavía una ejecución explícitamente autorizada dentro de su worktree antes de enviar el resultado.

---

# Parte G — El E2E real de cambio de código

## 23. Qué valida el test

El repositorio incluye:

```text
test-project/tests/test-end-to-end-code-change.ps1
```

El test crea un proyecto temporal con esta función incorrecta:

```powershell
function Add-Numbers {
    param([int]$A,[int]$B)
    return $A - $B
}
```

El objetivo de la task es:

```text
Make Add-Numbers return the sum of its two inputs.
```

---

## 24. Lifecycle probado

La task se crea en:

```text
BACKLOG
```

y el fixture autorizado la mueve a:

```text
READY
  ↓
ACTIVE
```

El cambio real es:

```diff
- return $A - $B
+ return $A + $B
```

Después ejecuta:

```powershell
Add-Numbers 2 3
```

y exige:

```text
5
```

Solo después se registra el resultado.

---

## 25. Evidencia generada por el E2E

El test exige que existan:

```text
docs/engineering/results/AICO-001-result-001.md
docs/engineering/reviews/AICO-001-review-001.md
docs/engineering/qa/AICO-001-qa.md
docs/engineering/security/AICO-001-security.md
docs/engineering/final-approvals/AICO-001-final.md
```

Y la task debe terminar:

```text
DONE
```

---

## 26. Qué demuestra y qué NO demuestra el E2E

### Demuestra

Que un cambio real puede ser gobernado por:

```text
Task
→ implementation evidence
→ independent review
→ QA
→ security disposition
→ final approval
→ DONE
```

También valida:

- transición de estados;
- guards;
- artefactos;
- company state;
- telemetría del lifecycle.

### No demuestra

Que un modelo externo pueda, sin intervención:

```text
recibir objetivo
→ diseñar
→ editar código
→ hacer merge
→ deployar a producción
```

El test es determinístico y **no llama a un provider externo**.

Eso es deliberado: su objetivo es probar el workflow, no disponibilidad de una API.

---

## 27. Ejecutar el E2E

Desde la raíz:

```powershell
.\test-project\tests\test-end-to-end-code-change.ps1
```

Para ejecutar toda la suite:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

---

# Parte H — Qué ve el usuario en una ejecución real

## 28. Resumen de artefactos

### Entrada

```text
Objetivo del usuario
```

### Work Request

```text
docs/engineering/work-requests/WR-001.md
```

### Plan

```text
docs/engineering/plans/WR-001-plan.md
```

### Tasks

```text
tasks/AICO-xxx.md
```

### Dispatch

```text
docs/engineering/dispatch/AICO-xxx.md
```

### Agent report

```text
docs/engineering/agent-reports/AICO-xxx.md
```

### Result

```text
docs/engineering/results/AICO-xxx-result-001.md
```

### Review

```text
docs/engineering/reviews/AICO-xxx-review-001.md
```

### QA

```text
docs/engineering/qa/AICO-xxx-qa.md
```

### Security

```text
docs/engineering/security/AICO-xxx-security.md
```

### Final approval

```text
docs/engineering/final-approvals/AICO-xxx-final.md
```

### Estado derivado

```text
.codex/state/
```

### Métricas

```text
.codex/runtime/metrics/events.jsonl
```

---

# Parte I — El flujo operativo resumido

## 29. Para planificación/análisis

```powershell
.\scripts\initialize-project.ps1

.\scripts\orchestrate.ps1 `
  -Objective "Mi objetivo" `
  -Type AUDIT `
  -Priority P1

.\scripts\list-tasks.ps1

.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-001 `
  -Apply

.\scripts\run-active-agents.ps1 -Provider Auto

.\scripts\run-pending-gates.ps1 -Provider Auto
```

Después de Security, la aprobación final sigue siendo explícita por task.

---

## 30. Para convertir un plan de Engineering Manager en backlog ejecutable

```powershell
.\scripts\generate-engineering-backlog.ps1 `
  -SourceTaskId AICO-XXX `
  -Provider Auto

.\scripts\materialize-engineering-backlog.ps1 `
  -SourceTaskId AICO-XXX

.\scripts\evaluate-readiness.ps1 -Apply

.\scripts\dispatch-ready-tasks.ps1 -Apply
```

---

## 31. Para trabajo con escritura autorizado

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-YYY
```

La modificación debe ocurrir dentro del workspace autorizado y luego entregar evidencia al lifecycle normal.

---

# Parte J — Qué debe entender un usuario

## 32. La regla central

AI Company OS no intenta convertir:

```text
"hacé esta feature"
```

en:

```text
"un modelo modifica producción sin controles"
```

Intenta convertirlo en:

```text
objetivo
→ decisiones
→ tareas
→ dependencias
→ autorización
→ ejecución
→ evidencia
→ revisión
→ QA
→ seguridad
→ aprobación
```

El valor principal del sistema no es solamente generar código.

El valor es que pueda responderse, después de una ejecución:

- ¿qué pidió el usuario?;
- ¿qué decidió producto?;
- ¿qué decidió arquitectura?;
- ¿qué task autorizó el cambio?;
- ¿quién fue el owner?;
- ¿qué evidencia produjo?;
- ¿quién la revisó?;
- ¿qué validó QA?;
- ¿qué dijo Security?;
- ¿por qué llegó a DONE?;
- ¿qué falló si no llegó?

Eso es lo que convierte una secuencia de prompts en un workflow de ingeniería inspeccionable.
