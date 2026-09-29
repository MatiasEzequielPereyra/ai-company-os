# AI Company OS — First Run Checklist

> **Windows PowerShell 5.1:** este repositorio usa UTF-8 sin BOM para documentación. Si `Get-Content` muestra caracteres como `Ã¡` o `â€”`, el archivo no está necesariamente corrupto: usá `Get-Content -Encoding UTF8`. PowerShell 7 no necesita este ajuste para UTF-8 sin BOM.

> Prueba controlada para aprender el lifecycle sin tocar primero un proyecto importante.

Esta prueba usa un **repositorio Git descartable** y un Work Request `RESEARCH` con dos planning tasks dependientes:

```text
PM → CTO
```

Eso permite comprobar creación de Work Request, dependencias, dispatch, ejecución, Review, QA, Security, final approval y dependency refresh sin convertir esta guía en una prueba de implementación con escritura.

## 1. Comprobar la instalación

```powershell
aico version
aico doctor --system
```

Si `aico` no existe:

```powershell
npm install -g @pereyram/ai-company-os
```

## 2. Crear un repositorio descartable

```powershell
$DemoRoot = Join-Path $env:TEMP "aico-first-run"

if (Test-Path -LiteralPath $DemoRoot) {
    throw "El demo ya existe: $DemoRoot. Revisalo antes de borrarlo o elegí otra ruta."
}

New-Item -ItemType Directory -Path $DemoRoot | Out-Null
Set-Location $DemoRoot
git init
```

## 3. Instalar AI Company OS en el demo

```powershell
aico install .
aico use .
```

Este camino usa el instalador de proyecto existente, que en el `main` actual copia también configuración y componentes de runtime local administrados.

## 4. Ejecutar intake y validar

```powershell
.\scripts\initialize-project.ps1
.\scripts\validate-artifacts.ps1
```

Que el intake detecte `UNKNOWN` en un repositorio vacío es esperable.

## 5. Elegir provider

El `main` actual es local-first. Si `aico doctor --system` confirma Ollama disponible:

```powershell
$AicoProvider = "Auto"
```

Si querés usar otro provider configurado, elegilo explícitamente:

```powershell
$AicoProvider = "OpenRouter"
```

Providers soportados por el runner actual:

```text
Codex
OpenRouter
Gemini
Ollama
DeepSeek
Grok
```

> Si un provider devuelve `structured result root must be an object`, `invalid JSON` o un error de schema, no avances estados ni artifacts a mano. Conservá el estado real de la task y consultá `docs/TROUBLESHOOTING.md`.

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
$CurrentObjective = Get-Content .\.codex\state\current-objective.md -Raw

if ($CurrentObjective -match 'Work request:\s+docs/engineering/work-requests/(WR-\d+)\.md') {
  $WorkRequestId = $Matches[1]
}
else {
  throw "No pude resolver el Work Request actual."
}

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

if ($null -eq $PmTask) {
  throw "No se encontró la task PM para $WorkRequestId."
}

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
  -Provider $AicoProvider
```

Si completa correctamente:

```text
ACTIVE → REVIEW
```

## 13. Ejecutar sus gates

```powershell
.\scripts\run-pending-gates.ps1 -Provider $AicoProvider
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

if ($null -eq $CtoTask) {
  throw "No se encontró la task CTO para $WorkRequestId."
}

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
  -Provider $AicoProvider

.\scripts\run-pending-gates.ps1 -Provider $AicoProvider
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

Los documentos de usuario viven en el repositorio fuente de AI Company OS y en GitHub. El runtime instalado en un proyecto target no copia necesariamente toda la documentación de usuario.
