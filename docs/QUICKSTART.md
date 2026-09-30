# AI Company OS — Quick Start

Guía mínima para pasar de cero a un proyecto reconocido por AI Company OS y a un primer Work Request preparado, sin asumir IDs y sin requerir un provider pago.

## 1. Requisitos

Contrato actual:

- Windows como plataforma primaria;
- Node.js >=20 (CI: Node 20);
- npm;
- Python >=3.11 (CI: 3.11 y 3.12);
- PowerShell;
- Git recomendado.

Ollama es opcional para instalar, pero el Auto general actual intenta solamente Ollama.

## 2. Instalar y verificar el CLI

~~~powershell
npm install -g @pereyram/ai-company-os
aico version
aico --help
aico doctor --system
~~~

En la primera operación que necesita el CLI Python, el launcher npm crea un virtualenv privado dentro del paquete instalado.

## 3. Elegir un camino

### Proyecto existente

~~~powershell
Set-Location "C:\ruta\a\mi-proyecto"
aico install .
aico use .
~~~

La instalación normal preserva archivos existentes en paths del framework en vez de sobrescribirlos silenciosamente y crea **.codex/managed-files.json**.

Si el repositorio no tiene .git, la instalación puede continuar, pero el installer emite un warning y el aislamiento writable por worktrees no estará disponible correctamente.

### Proyecto nuevo

~~~powershell
aico new mi-proyecto C:\Proyectos
Set-Location "C:\Proyectos\mi-proyecto"
~~~

aico new crea la estructura y selecciona el proyecto, pero **no ejecuta git init**.

~~~powershell
git init
git add .
git commit -m "chore: initialize project"
~~~

## 4. Confirmar el proyecto

~~~powershell
aico current
aico doctor
aico status
aico tasks
aico workflow
~~~

El objetivo es confirmar que el proyecto activo es el correcto y que el framework puede leer su estado.

## 5. Ejecutar intake

~~~powershell
.\scripts\initialize-project.ps1
~~~

Revisá los artefactos de intake bajo docs/product, docs/architecture, docs/engineering y docs/operations.

El intake es evidencia automática. No convierte una detección en un requisito o decisión aprobada.

## 6. Crear el primer Work Request en PREPARE

~~~powershell
.\scripts\orchestrate.ps1 -Objective "Revisar el proyecto y definir el próximo cambio" -Type FEATURE -Priority P1
~~~

Sin -Apply:

~~~text
crea Work Request
→ genera plan
→ materializa planning tasks
→ evalúa readiness
→ prepara dispatch
→ no activa agentes
~~~

Este paso no llama a un provider.

## 7. Resolver el ID real

No asumas WR-001.

~~~powershell
$CurrentObjective = Get-Content .\.codex\state\current-objective.md -Raw -Encoding UTF8
if ($CurrentObjective -match 'Work request:\s+docs/engineering/work-requests/(WR-\d+)\.md') {
    $WorkRequestId = $Matches[1]
}
else {
    throw "No se pudo resolver el Work Request actual."
}
$WorkRequestId
~~~

Inspeccionar:

~~~powershell
Get-Content ".\docs\engineering\work-requests\$WorkRequestId.md" -Encoding UTF8
Get-Content ".\docs\engineering\plans\$WorkRequestId-plan.md" -Encoding UTF8
.\scripts\list-tasks.ps1
~~~

## 8. Activar solamente trabajo elegible

~~~powershell
.\scripts\orchestrate.ps1 -WorkRequestId $WorkRequestId -Apply
.\scripts\list-tasks.ps1 -Status ACTIVE
aico workflow
~~~

Las dependencias deben estar satisfechas antes de activar una task.

## 9. Provider: solo cuando vayas a ejecutar IA

~~~powershell
aico doctor --system
ollama list
~~~

Configuración general por defecto:

~~~text
Auto → Ollama
~~~

Ejecutar tasks de análisis activas:

~~~powershell
.\scripts\run-active-agents.ps1 -Provider Auto
~~~

No ejecutes este paso si no querés consumir compute/cuota. Un provider cloud explícito requiere su credencial y puede estar sujeto a cuota o costo.

Engineering Manager tiene routing de análisis específico; no asumas que su Auto es idéntico al Auto general. Ver [Provider Runtime](./operations/provider-runtime.md).

## 10. Gates y finalización

Después de un resultado COMPLETED:

~~~text
REVIEW → QA → SECURITY → final approval → DONE
~~~

~~~powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
~~~

Security puede concluir NOT_APPLICABLE en perfiles que no exigen un PASS de seguridad. La task sigue necesitando final approval.

Después de revisar evidencia:

~~~powershell
.\scripts\finalize-task.ps1 -Id AICO-XXX -Decision APPROVE -Verification "Reviewed objective, result and applicable gate evidence."
~~~

No automatices aprobaciones masivas.

## 11. Actualizar más adelante

~~~powershell
npm install -g @pereyram/ai-company-os@latest
aico update .
~~~

Son operaciones distintas. Ver [Update and Ownership](./operations/update-ownership.md).

## 12. Qué significa éxito

Al terminar esta guía deberías saber:

- qué proyecto está activo;
- dónde están sus tasks y Work Requests;
- cómo diagnosticarlo;
- qué hace Auto por defecto;
- qué diferencia hay entre planning e implementation authorization;
- qué evidencia exige el lifecycle;
- cómo actualizar sin reemplazar archivos arbitrarios.

## Siguiente lectura

- [First Run Checklist](./FIRST-RUN-CHECKLIST.md)
- [User Guide](./USER-GUIDE.md)
- [Command Reference](./COMMAND-REFERENCE.md)
- [Troubleshooting](./TROUBLESHOOTING.md)
