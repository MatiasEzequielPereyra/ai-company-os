# AI Company OS — Quick Start

> Guía mínima para pasar de cero a un primer workflow real sin asumir IDs ni saltar dependencias.

## 0. Requisitos

Instalación soportada:

- Node.js 20 o superior;
- npm;
- Python 3.11 o superior;
- PowerShell;
- Git.

Instalar el CLI:

```powershell
npm install -g @pereyram/ai-company-os
aico version
aico doctor --system
```

Para el runtime local por defecto también necesitás Ollama. El `main` actual configura `Auto` como local-first y su `auto_order` por defecto contiene `Ollama`.

## 1. Instalarlo sobre un proyecto existente

Desde el repositorio que querés administrar:

```powershell
Set-Location "C:\ruta\de\mi-proyecto"
aico install .
aico use .
aico doctor
```

El target debería ser un repositorio Git si vas a usar aislamiento por worktrees.

El instalador mantiene un manifest de archivos administrados bajo `.codex/managed-files.json`. Una actualización con `--force` puede reemplazar componentes administrados: hacela sobre una branch revisable y comprobá el diff.

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

## 3. Elegir provider para la sesión

Comprobar el runtime local recomendado:

```powershell
aico doctor --system
ollama list
```

Si Ollama está disponible y configurado:

```powershell
$AicoProvider = "Auto"
```

También podés usar explícitamente un provider soportado:

```text
Codex
OpenRouter
Gemini
Ollama
DeepSeek
Grok
```

Ejemplo:

```powershell
$AicoProvider = "OpenRouter"
```

Los providers externos requieren sus credenciales correspondientes. `DeepSeek` y `Grok` no se usan como fallback pago automático cuando `allow_paid_fallback` está deshabilitado; siguen pudiendo elegirse explícitamente si están configurados.

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

if ($CurrentObjective -match 'Work request:\s+docs/engineering/work-requests/(WR-\d+)\.md') {
  $WorkRequestId = $Matches[1]
}
else {
  throw "No pude resolver el Work Request actual."
}

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
.\scripts\run-active-agents.ps1 -Provider $AicoProvider
```

Una entrega `COMPLETED` pasa normalmente:

```text
ACTIVE → REVIEW
```

## 8. Ejecutar Review, QA y Security

```powershell
.\scripts\run-pending-gates.ps1 -Provider $AicoProvider
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
.\scripts\run-active-agents.ps1 -Provider $AicoProvider
.\scripts\run-pending-gates.ps1 -Provider $AicoProvider
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
