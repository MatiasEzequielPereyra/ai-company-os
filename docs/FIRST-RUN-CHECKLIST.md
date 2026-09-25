# AI Company OS — First Run Checklist

> Prueba controlada para aprender el lifecycle sin tocar primero un proyecto importante.

Esta prueba usa un **proyecto descartable** y un Work Request `RESEARCH` con dos planning tasks dependientes:

```text
PM → CTO
```

Eso permite comprobar:

- creación de Work Request;
- materialización de tasks;
- readiness;
- dependencia;
- dispatch;
- ejecución con provider;
- Review;
- QA;
- Security;
- final approval;
- desbloqueo de una dependencia.

Además evita usar una task de `engineering-manager` como primer ejemplo, porque el Review gate actual también usa ese rol y no garantiza independencia de rol en ese caso.

## 1. Partir desde AI Company OS

Desde el checkout del framework:

```powershell
git status --short --branch
```

Confirmá que estás en el repositorio correcto.

## 2. Crear un proyecto descartable

```powershell
$DemoRoot = Join-Path $env:TEMP "aico-first-run"

if (Test-Path $DemoRoot) {
  throw "El demo ya existe: $DemoRoot. Elegí otra ruta o revisá el anterior antes de borrarlo."
}

.\scripts\new-project.ps1 `
  -ProjectName "aico-first-run" `
  -Destination $env:TEMP

Set-Location $DemoRoot
```

Este demo no necesita contener una aplicación real. Su objetivo es aprender el workflow.

## 3. Ejecutar intake

```powershell
.\scripts\initialize-project.ps1
```

Revisar los artifacts generados bajo:

```text
docs/product/
docs/architecture/
docs/engineering/
docs/operations/
```

## 4. Validar la instalación

```powershell
.\scripts\validate-artifacts.ps1
```

Si falla, no continuar. Consultar `docs/TROUBLESHOOTING.md` en el repositorio de AI Company OS.

## 5. Comprobar providers

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

Para continuar con ejecución de agentes, al menos un provider debe estar disponible.

## 6. Crear un Work Request de RESEARCH

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Assess the project structure and identify the next technical decision." `
  -Type RESEARCH `
  -Priority P3
```

El plan de RESEARCH utiliza:

```text
PM
 ↓
CTO
```

## 7. Capturar el Work Request real

```powershell
$WorkRequestId = (
  Get-ChildItem .\docs\engineering\work-requests -Filter "WR-*.md" |
  Sort-Object Name |
  Select-Object -Last 1
).BaseName

$WorkRequestId
```

No asumir `WR-001`.

## 8. Inspeccionar tasks antes de aplicar

```powershell
.\scripts\list-tasks.ps1
```

Deberías ver dos tasks en `BACKLOG`:

- PM;
- CTO.

La task de CTO debe depender de la de PM.

## 9. Aplicar readiness y dispatch

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId $WorkRequestId `
  -Apply
```

Ahora:

```powershell
.\scripts\list-tasks.ps1
```

Resultado conceptual esperado:

```text
PM   → ACTIVE
CTO  → BACKLOG
```

CTO no debe activarse porque depende de PM.

## 10. Capturar el ID de la task PM

```powershell
$PmTask = Get-ChildItem .\tasks -Filter "AICO-*.md" |
  Where-Object {
    $content = Get-Content $_.FullName -Raw
    $content -match "(?m)^Work request:\s*$([regex]::Escape($WorkRequestId))\s*$" -and
    $content -match "(?m)^Owner:\s*pm\s*$"
  } |
  Select-Object -First 1

$PmTaskId = $PmTask.BaseName
$PmTaskId
```

## 11. Inspeccionar dispatch PM

```powershell
Get-Content ".\docs\engineering\dispatch\$PmTaskId.md"
```

Confirmar:

- owner `pm`;
- objetivo;
- acceptance criteria;
- contexto;
- restricciones.

## 12. Ejecutar PM

```powershell
.\scripts\run-agent-task.ps1 `
  -Id $PmTaskId `
  -Provider Auto
```

Si completa correctamente:

```text
ACTIVE → REVIEW
```

## 13. Ejecutar sus gates

```powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Después:

```powershell
.\scripts\list-tasks.ps1
```

PM debería quedar en `SECURITY` si todos los gates fueron satisfactorios.

## 14. Revisar evidencia PM

```powershell
Get-Content ".\tasks\$PmTaskId.md"
Get-Content ".\docs\engineering\qa\$PmTaskId-qa.md"
Get-Content ".\docs\engineering\security\$PmTaskId-security.md"
```

Revisá el contenido. No apruebes por costumbre.

## 15. Finalizar PM

Si la evidencia corresponde:

```powershell
.\scripts\finalize-task.ps1 `
  -Id $PmTaskId `
  -Decision APPROVE `
  -Verification "Reviewed PM deliverable and applicable gate evidence."
```

Esperado:

```text
PM: DONE
```

El finalizer también refresca dependencies cuando el script está disponible.

## 16. Comprobar que CTO se desbloqueó

```powershell
.\scripts\list-tasks.ps1
```

Esperado conceptualmente:

```text
PM   → DONE
CTO  → READY
```

Esto demuestra que una dependencia necesita `DONE`, no simplemente REVIEW o QA.

## 17. Capturar CTO y despacharlo

```powershell
$CtoTask = Get-ChildItem .\tasks -Filter "AICO-*.md" |
  Where-Object {
    $content = Get-Content $_.FullName -Raw
    $content -match "(?m)^Work request:\s*$([regex]::Escape($WorkRequestId))\s*$" -and
    $content -match "(?m)^Owner:\s*cto\s*$"
  } |
  Select-Object -First 1

$CtoTaskId = $CtoTask.BaseName

.\scripts\dispatch-ready-tasks.ps1 -Apply
```

Comprobar:

```powershell
.\scripts\list-tasks.ps1
```

CTO debería estar `ACTIVE`.

## 18. Ejecutar CTO y gates

```powershell
.\scripts\run-agent-task.ps1 `
  -Id $CtoTaskId `
  -Provider Auto

.\scripts\run-pending-gates.ps1 -Provider Auto
```

## 19. Revisar y finalizar CTO

```powershell
Get-Content ".\tasks\$CtoTaskId.md"
Get-Content ".\docs\engineering\qa\$CtoTaskId-qa.md"
Get-Content ".\docs\engineering\security\$CtoTaskId-security.md"
```

Si corresponde:

```powershell
.\scripts\finalize-task.ps1 `
  -Id $CtoTaskId `
  -Decision APPROVE `
  -Verification "Reviewed CTO deliverable and applicable gate evidence."
```

## 20. Validar estado final

```powershell
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
.\scripts\summarize-metrics.ps1
.\scripts\list-tasks.ps1
```

Esperado:

```text
PM   → DONE
CTO  → DONE
```

## 21. Qué acabás de probar

```text
User objective
  ↓
Work Request
  ↓
Plan
  ↓
PM BACKLOG
  ↓
PM READY / ACTIVE
  ↓
Result
  ↓
Review
  ↓
QA
  ↓
Security
  ↓
Final approval
  ↓
PM DONE
  ↓
dependency refresh
  ↓
CTO READY / ACTIVE
  ↓
same gated lifecycle
  ↓
CTO DONE
```

## 22. Qué NO probaste

Este demo no prueba:

- modificación autónoma de código;
- worktree de escritura;
- merge;
- push;
- deployment;
- TUI.

Esas capacidades tienen contratos y madurez diferentes.

## Criterio de éxito

La primera ejecución se considera comprendida cuando podés explicar:

```text
por qué PM se activó antes que CTO
por qué CTO necesitó PM = DONE
qué produjo el provider
por qué Review/QA/Security son gates separados
por qué Security no significó DONE
qué aprobó finalize-task
por qué hubo que despachar CTO después
qué artifacts conservaron la evidencia
```

Si alguno de esos puntos no está claro, consultar:

- `docs/USER-GUIDE.md`;
- `docs/END-TO-END-WALKTHROUGH.md`;
- `docs/TROUBLESHOOTING.md`.

Nota: esos documentos viven en el repositorio fuente de AI Company OS; el instalador runtime no copia necesariamente toda la documentación de usuario al proyecto target.
