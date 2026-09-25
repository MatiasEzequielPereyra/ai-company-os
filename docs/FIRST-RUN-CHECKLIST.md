# AI Company OS — First Run Checklist

> Checklist para validar una instalación desde la perspectiva de un usuario nuevo.

El objetivo no es completar un proyecto real. Es comprobar que el framework está instalado, que los contratos básicos funcionan y que el usuario entiende qué pasos son automáticos y cuáles requieren aprobación explícita.

## 1. Confirmar ubicación y Git

```powershell
Get-Location
git status --short --branch
```

Resultado esperado:

- estás en la raíz del proyecto correcto;
- conocés la branch actual;
- cualquier cambio local existente es intencional.

## 2. Confirmar componentes

```powershell
Test-Path .\AGENTS.md
Test-Path .\.codex
Test-Path .\tasks
Test-Path .\scripts
Test-Path .\schemas
```

Todos deberían devolver `True`.

## 3. Ejecutar intake

```powershell
.\scripts\initialize-project.ps1
```

Revisar:

```text
docs/engineering/project-intake.md
docs/product/product-intake.md
docs/architecture/architecture-intake.md
docs/operations/operations-intake.md
```

No asumir que detección automática = decisión aprobada.

## 4. Validar artefactos

```powershell
.\scripts\validate-artifacts.ps1
```

Si falla, resolver el error antes de crear trabajo nuevo.

## 5. Comprobar providers

### Codex

```powershell
Get-Command codex -ErrorAction SilentlyContinue
```

### OpenRouter

```powershell
Test-Path Env:OPENROUTER_API_KEY
```

### Gemini

```powershell
Test-Path Env:GEMINI_API_KEY
```

No hace falta configurar los tres. Para `Auto`, al menos uno debe estar disponible.

## 6. Crear un Work Request de prueba

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Review project documentation quality" `
  -Type DOCUMENTATION `
  -Priority P3
```

Esto debe preparar el trabajo sin activar tasks.

## 7. Verificar que PREPARE no activó trabajo

```powershell
.\scripts\list-tasks.ps1
```

La task generada debería estar en `BACKLOG`.

## 8. Aplicar readiness y dispatch

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-001 `
  -Apply
```

Después:

```powershell
.\scripts\list-tasks.ps1 -Status ACTIVE
```

Debería existir trabajo ACTIVE si la task cumple readiness.

## 9. Inspeccionar el dispatch

Usar el ID real:

```powershell
Get-Content .\docs\engineering\dispatch\AICO-001.md
```

Confirmar que describe:

- task;
- owner;
- objetivo;
- restricciones;
- contract de resultado.

## 10. Ejecutar el agente

```powershell
.\scripts\run-active-agents.ps1 -Provider Auto
```

Resultado esperado para una task completada:

```text
ACTIVE → REVIEW
```

y artifacts bajo:

```text
.codex/runtime/
docs/engineering/agent-reports/
docs/engineering/results/
```

Si el provider no está disponible, consultar `TROUBLESHOOTING.md`.

## 11. Ejecutar gates

```powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Si todos los gates progresan satisfactoriamente, la task debería terminar en `SECURITY` con artifacts de Review, QA y Security.

### Importante

`run-pending-gates.ps1` **no realiza la aprobación final**.

## 12. Aprobar o rechazar explícitamente

Después de revisar la evidencia:

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-001 `
  -Decision APPROVE `
  -Verification "Reviewed objective and all applicable gate evidence."
```

Resultado esperado:

```text
SECURITY → DONE
```

No automatizar esta decisión durante la primera prueba: el objetivo es que el operador vea qué está aprobando.

## 13. Sincronizar y validar

```powershell
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
.\scripts\summarize-metrics.ps1
```

## 14. Comprobar fuentes de verdad

Abrir:

```text
tasks/AICO-001.md
.codex/state/company-state.md
docs/engineering/results/AICO-001-result-001.md
docs/engineering/reviews/AICO-001-review-001.md
docs/engineering/qa/AICO-001-qa.md
docs/engineering/security/AICO-001-security.md
docs/engineering/final-approvals/AICO-001-final.md
```

La task es autoritativa para su lifecycle. Company state es derivado.

## 15. Ejecutar smoke suite del framework

En el repositorio de AI Company OS:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

## Criterio de éxito

La primera ejecución se considera comprendida cuando el usuario puede explicar:

```text
qué creó el Work Request
qué hizo el orchestrator
por qué la task pasó a ACTIVE
qué produjo el agent
por qué REVIEW es independiente
qué verificó QA
qué hizo Security
por qué Security no significa DONE
qué aprobó finalize-task
qué archivos son fuente de verdad
qué acciones siguen requiriendo autorización humana
```

Si alguno de esos puntos no está claro, volver al User Guide o al End-to-End Walkthrough antes de usar AI Company OS sobre trabajo sensible.
