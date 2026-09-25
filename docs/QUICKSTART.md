# AI Company OS — Quick Start

> Guía mínima para pasar de cero a un primer workflow real sin asumir IDs ni saltar dependencias.

## 0. Requisitos

Necesitás:

- Windows con PowerShell;
- Git, especialmente si vas a trabajar sobre un repositorio real o usar worktrees;
- acceso al repositorio de AI Company OS;
- al menos un provider disponible para ejecutar agentes: Codex CLI, OpenRouter o Gemini.

Clonar AI Company OS:

```powershell
git clone https://github.com/MatiasEzequielPereyra/ai-company-os.git
cd .\ai-company-os
```

Si el repositorio requiere autenticación, Git debe estar autenticado previamente.

## 1. Instalarlo sobre un proyecto existente

Desde el repositorio de AI Company OS:

```powershell
.\scripts\install-existing-project.ps1 -TargetProject "C:\ruta\de\mi-proyecto"
```

El target debería ser un repositorio Git si vas a usar aislamiento por worktrees.

Luego:

```powershell
Set-Location "C:\ruta\de\mi-proyecto"
```

## 2. Inicializar el proyecto

```powershell
.\scripts\initialize-project.ps1
```

Revisá:

```text
docs/engineering/project-intake.md
docs/product/product-intake.md
docs/architecture/architecture-intake.md
docs/operations/operations-intake.md
```

El intake es evidencia automática. No convierte detecciones en decisiones aprobadas.

## 3. Comprobar que existe un provider

Codex:

```powershell
Get-Command codex -ErrorAction SilentlyContinue
```

OpenRouter:

```powershell
Test-Path Env:OPENROUTER_API_KEY
```

Gemini:

```powershell
Test-Path Env:GEMINI_API_KEY
```

No necesitás los tres. Para `-Provider Auto`, al menos uno debe estar realmente disponible.

## 4. Crear un objetivo en modo PREPARE

Ejemplo:

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Revisar el proyecto y definir el cambio que necesito" `
  -Type FEATURE `
  -Priority P1
```

Sin `-Apply`, el orchestrator:

```text
crea Work Request
→ genera plan
→ materializa planning tasks
→ evalúa readiness
→ prepara dispatch
→ NO activa tasks
```

## 5. Obtener el Work Request real

No asumir que siempre será `WR-001`.

```powershell
$CurrentObjective = Get-Content .\.codex\state\current-objective.md -Raw

if ($CurrentObjective -notmatch 'Work request:\s+docs/engineering/work-requests/(WR-\d+)\.md') {
  throw "No pude resolver el Work Request actual."
}

$WorkRequestId = $Matches[1]
$WorkRequestId
```

Revisar el plan:

```powershell
Get-Content ".\docs\engineering\plans\$WorkRequestId-plan.md"
```

Y las tasks:

```powershell
.\scripts\list-tasks.ps1
```

## 6. Aplicar el primer lote elegible

Cuando el plan sea correcto:

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId $WorkRequestId `
  -Apply
```

Ver las activas:

```powershell
.\scripts\list-tasks.ps1 -Status ACTIVE
```

Solo las tasks cuyas dependencias estén satisfechas deberían estar `ACTIVE`.

## 7. Ejecutar los agentes activos

```powershell
.\scripts\run-active-agents.ps1 -Provider Auto
```

Una entrega `COMPLETED` pasa normalmente:

```text
ACTIVE → REVIEW
```

## 8. Ejecutar Review, QA y Security

```powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Con gates satisfactorios, la task queda normalmente en:

```text
SECURITY
```

No llega sola a `DONE`.

## 9. Revisar evidencia y aprobar explícitamente

Ver qué tasks están esperando decisión final:

```powershell
.\scripts\list-tasks.ps1 -Status SECURITY
```

Elegí una task y revisá sus artifacts antes de aprobarla.

Ejemplo, reemplazando el ID por el real:

```powershell
Get-Content .\tasks\AICO-123.md
Get-Content .\docs\engineering\qa\AICO-123-qa.md
Get-Content .\docs\engineering\security\AICO-123-security.md
```

Si corresponde aprobar:

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-123 `
  -Decision APPROVE `
  -Verification "Original objective and applicable gate evidence reviewed."
```

La aprobación final es una decisión. No automatices un `APPROVE` masivo sin inspeccionar la evidencia.

## 10. Repetir el lifecycle mientras aparezca trabajo nuevo

Después de una task `DONE`, sus dependientes pueden pasar automáticamente de `BACKLOG` a `READY`.

Comprobar:

```powershell
.\scripts\list-tasks.ps1
```

Si aparecen nuevas tasks `READY`:

```powershell
.\scripts\dispatch-ready-tasks.ps1 -Apply
.\scripts\run-active-agents.ps1 -Provider Auto
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Después volver a revisar y finalizar cada task que corresponda.

El ciclo real es:

```text
READY
  ↓
ACTIVE
  ↓
RESULT
  ↓
REVIEW
  ↓
QA
  ↓
SECURITY
  ↓
FINAL APPROVAL
  ↓
DONE
  ↓
desbloquea dependencias
  ↓
nuevas READY
  ↺
```

## 11. Validar y sincronizar

Cuando termines una ronda:

```powershell
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
.\scripts\summarize-metrics.ps1
```

## 12. Si la task necesita modificar código

El runner compartido de agents es de análisis/read-only.

Para una task con escritura explícitamente autorizada:

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Eso crea aislamiento. No autoriza automáticamente merge, push o deployment.

## Siguiente lectura

- [First Run Checklist](./FIRST-RUN-CHECKLIST.md) — demo controlado sin usar IDs fijos.
- [User Guide](./USER-GUIDE.md) — manual completo.
- [End-to-End Walkthrough](./END-TO-END-WALKTHROUGH.md) — modelo profundo del workflow.
- [Troubleshooting](./TROUBLESHOOTING.md) — errores y recuperación.
