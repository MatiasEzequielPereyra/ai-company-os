# AI Company OS — First Run Checklist

Checklist descartable para responder:

> ¿AI Company OS quedó instalado e inicializado de forma coherente?

El camino principal evita providers pagos y no requiere ejecutar una tarea de IA.

> Windows PowerShell 5.1 puede mostrar incorrectamente Markdown UTF-8 sin BOM si se usa Get-Content sin encoding. Para documentación, preferí Get-Content -Encoding UTF8.

## 1. CLI disponible

~~~powershell
aico version
aico --help
~~~

## 2. Diagnóstico de sistema

~~~powershell
aico doctor --system
~~~

Comprobar especialmente Python >=3.11, PowerShell disponible, información de Git/Node/npm y estado de Ollama.

Ollama solo es necesario para ejecución local automática.

## 3. Crear un repositorio demo

~~~powershell
$DemoRoot = Join-Path $env:TEMP "aico-first-run"
if (Test-Path -LiteralPath $DemoRoot) {
    throw "El demo ya existe: $DemoRoot. Elegí otra ruta o revisalo antes de borrarlo."
}
New-Item -ItemType Directory -Path $DemoRoot | Out-Null
Set-Location $DemoRoot
git init
Set-Content -Path ".\user-owned.txt" -Value "preserve me"
$Before = (Get-FileHash ".\user-owned.txt" -Algorithm SHA256).Hash
~~~

## 4. Instalar AI Company OS

~~~powershell
aico install .
~~~

Verificar ownership:

~~~powershell
Test-Path ".\.codex\managed-files.json"
Get-Content ".\.codex\managed-files.json" -Raw -Encoding UTF8 | ConvertFrom-Json
~~~

Verificar preservación:

~~~powershell
$After = (Get-FileHash ".\user-owned.txt" -Algorithm SHA256).Hash
if ($Before -ne $After) { throw "El archivo del usuario fue modificado." }
~~~

## 5. Proyecto activo

~~~powershell
aico current
aico use .
aico current
~~~

## 6. Estado y doctor del proyecto

~~~powershell
aico status
aico doctor
aico tasks
aico workflow
~~~

En un proyecto vacío pueden aparecer warnings como ausencia de tasks; eso no equivale a una instalación corrupta.

## 7. Runtime administrado

~~~powershell
$Required = @(
    ".\.codex\provider-config.json",
    ".\.codex\local-runtime-config.json",
    ".\.codex\workflow-profiles.json",
    ".\.codex\writable-policy.json",
    ".\scripts\provider-router.ps1",
    ".\scripts\run-agent-task.ps1",
    ".\schemas\agent-result.schema.json"
)
foreach ($Path in $Required) {
    if (-not (Test-Path $Path)) { throw "Falta runtime administrado: $Path" }
}
~~~

## 8. Intake

~~~powershell
.\scripts\initialize-project.ps1
.\scripts\validate-artifacts.ps1
~~~

En un repositorio demo sin stack real, valores UNKNOWN pueden ser correctos.

## 9. Planning sin provider

~~~powershell
.\scripts\orchestrate.ps1 -Objective "Assess the demo and define the next engineering decision." -Type RESEARCH -Priority P3
~~~

Esperado:

- se crea un WR;
- existe un plan;
- existen planning tasks;
- no se ejecutó ningún provider;
- no se activó trabajo porque no se usó -Apply.

## 10. Aplicar readiness/dispatch sin ejecutar IA

~~~powershell
$CurrentObjective = Get-Content ".\.codex\state\current-objective.md" -Raw -Encoding UTF8
if ($CurrentObjective -notmatch 'Work request:\s+docs/engineering/work-requests/(WR-\d+)\.md') {
    throw "No se pudo resolver el Work Request."
}
$WorkRequestId = $Matches[1]
.\scripts\orchestrate.ps1 -WorkRequestId $WorkRequestId -Apply
.\scripts\list-tasks.ps1
~~~

Esto valida planning, readiness y dispatch. Todavía no requiere provider.

## 11. Update seguro

~~~powershell
aico update .
$AfterUpdate = (Get-FileHash ".\user-owned.txt" -Algorithm SHA256).Hash
if ($Before -ne $AfterUpdate) {
    throw "El updater modificó un archivo project-owned."
}
~~~

Esperado: reconoce managed-files, preserva user-owned.txt y termina con un resumen de runtime.

## 12. TUI

~~~powershell
aico
~~~

Comprobar manualmente que la interfaz abre y reconoce el proyecto.

## 13. Ollama opcional

~~~powershell
ollama list
aico doctor --system
~~~

El doctor busca el modelo recomendado qwen3:8b. El resolver hardware-aware puede elegir otro modelo instalado que cumpla el perfil.

No hace falta ejecutar un provider para aprobar este checklist.

## 14. Qué NO valida

No demuestra disponibilidad en vivo de cloud providers, calidad de una respuesta LLM, merge/push/deploy automáticos, Windows 10/11 específicos, Linux/macOS, performance de modelos ni producción.

## Criterio de éxito

El first run es satisfactorio cuando CLI/bootstrap funcionan, el proyecto se reconoce, doctor/status/tasks/workflow funcionan, existe el manifest, un archivo project-owned se conserva, intake/planning deterministas funcionan, aico update acepta el proyecto administrado y la TUI abre sin requerir gasto en un provider pago.
