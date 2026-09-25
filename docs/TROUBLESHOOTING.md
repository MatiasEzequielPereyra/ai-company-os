# AI Company OS — Troubleshooting

> **Versión:** 0.1  
> **Alcance:** comportamiento verificado en la rama `main`.  
> Si un error proviene de una rama experimental, comprobar primero si esa funcionalidad ya fue integrada.

Este documento está organizado por **síntoma → causa probable → comprobación → solución**.

---

## 1. Primer diagnóstico

Antes de corregir nada, ejecutar desde la raíz del proyecto:

```powershell
git status --short --branch
.\scripts\list-tasks.ps1
.\scripts\validate-artifacts.ps1
```

Si el problema está relacionado con estado derivado:

```powershell
.\scripts\sync-company-state.ps1
```

Si el problema está relacionado con providers, comprobar qué credenciales o runtimes existen:

```powershell
Get-Command codex -ErrorAction SilentlyContinue
Test-Path Env:OPENROUTER_API_KEY
Test-Path Env:GEMINI_API_KEY
```

No imprimir el valor de las API keys en logs compartidos.

---

# Instalación y PowerShell

## 2. PowerShell bloquea la ejecución de scripts

### Síntoma

Mensajes relacionados con:

```text
running scripts is disabled on this system
ExecutionPolicy
UnauthorizedAccess
```

### Causa probable

La política de ejecución de PowerShell no permite ejecutar scripts locales.

### Comprobación

```powershell
Get-ExecutionPolicy -List
```

### Resolución

La política adecuada depende del equipo y de las reglas de la organización. No cambiar políticas corporativas sin autorización.

En un entorno personal, una configuración habitual para el usuario actual es:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Volver a abrir PowerShell después del cambio.

---

## 3. "script.ps1 not found"

### Síntoma

```text
The term '.\scripts\...' is not recognized
Required script not found
```

### Causas probables

- no se está ejecutando desde la raíz del proyecto;
- AI Company OS no fue instalado completamente;
- se está usando una copia o worktree desactualizado.

### Comprobación

```powershell
Get-Location
Get-ChildItem .\scripts
```

### Resolución

Entrar al proyecto correcto:

```powershell
Set-Location "C:\ruta\al\proyecto"
```

Para un proyecto existente, reinstalar componentes faltantes desde el repo del framework:

```powershell
.\scripts\install-existing-project.ps1 -TargetProject "C:\ruta\al\proyecto"
```

No usar `-Force` sin revisar qué archivos existentes serían reemplazados.

---

## 4. El target no parece ser un repositorio Git

### Síntoma

```text
WARNING: target does not appear to be a Git repository.
```

### Significado

El instalador puede copiar el framework, pero varias capacidades —especialmente worktrees— requieren Git.

### Comprobación

```powershell
Test-Path .git
git status
```

### Resolución

Si el proyecto debe estar bajo Git:

```powershell
git init
```

y configurar el repositorio de acuerdo con el flujo del proyecto.

---

# Intake y planificación

## 5. initialize-project detecta UNKNOWN

### Síntoma

El intake muestra:

```text
Languages: UNKNOWN
Frameworks: UNKNOWN
Package manager: UNKNOWN
```

### Significado

El discovery automático no encontró señales que reconoce.

No significa necesariamente que el proyecto esté roto.

### Qué detecta actualmente

Entre otras señales:

- `package.json`;
- React;
- Next.js;
- Vite;
- Supabase;
- Express;
- Python;
- Go;
- Rust;
- lockfiles npm/pnpm/yarn.

### Resolución

Tratar el intake como evidencia automática y completar la información mediante PM/CTO si el stack no puede inferirse.

No editar el intake para convertir una suposición en una decisión sin revisión.

---

## 6. "Work request not found"

### Síntoma

```text
Work request not found: ...WR-xxx.md
```

### Comprobación

```powershell
Get-ChildItem .\docs\engineering\work-requests
```

### Resolución

Crear un Work Request:

```powershell
.\scripts\new-work-request.ps1 `
  -Objective "Objetivo" `
  -Type FEATURE `
  -Priority P1
```

o utilizar el ID exacto de un Work Request existente.

---

## 7. "Tasks already materialized for WR-xxx"

### Significado

`materialize-plan-tasks.ps1` evita generar dos veces el mismo conjunto de planning tasks para un Work Request.

### Resolución

No borrar las tasks para volver a ejecutar el comando.

Primero inspeccionar:

```powershell
Get-Content .\docs\engineering\plans\WR-XXX-tasks.md
.\scripts\list-tasks.ps1
```

Si se necesita una nueva intención de trabajo, crear otro Work Request.

---

# Readiness y dependencias

## 8. Una task no pasa de BACKLOG a READY

### Comprobación

Ejecutar sin `-Apply`:

```powershell
.\scripts\evaluate-readiness.ps1
```

El comando muestra una columna `Reason`.

### Razones soportadas actualmente

Pueden aparecer:

```text
Missing owner
Missing objective
Missing context
Missing acceptance criteria
Dependency not found: AICO-xxx
Dependency not done: AICO-xxx (...)
```

### Resolución

Corregir la causa real.

No forzar manualmente `Status: READY`, porque las transiciones posteriores también tienen guards.

---

## 9. "Dependency not done"

### Significado

Una task depende de otra AICO task que todavía no llegó a `DONE`.

### Comprobación

```powershell
.\scripts\list-tasks.ps1
```

o:

```powershell
Get-Content .\tasks\AICO-123.md
```

Buscar la sección:

```text
## Dependencies
```

### Resolución

Completar primero las dependencias.

Una dependencia no se considera satisfecha por estar en REVIEW, QA o SECURITY. Debe estar en `DONE`.

---

## 10. "Dependency not found"

### Causa

Una task referencia un ID que no existe en `tasks/`.

### Resolución

No crear un archivo vacío solamente para satisfacer el guard.

Determinar si:

- el ID fue escrito incorrectamente;
- la task fue eliminada;
- un materializer quedó incompleto;
- se está trabajando sobre una branch equivocada.

Después ejecutar:

```powershell
.\scripts\validate-artifacts.ps1
```

---

# Dispatch y ACTIVE

## 11. "No READY tasks found"

### Significado

No hay trabajo elegible para dispatch.

### Comprobación

```powershell
.\scripts\list-tasks.ps1 -Status READY
.\scripts\evaluate-readiness.ps1
```

### Resolución

Resolver readiness/dependencies. No es un error del provider.

---

## 12. Dispatch en dry-run no activa nada

### Comportamiento esperado

```powershell
.\scripts\dispatch-ready-tasks.ps1
```

prepara/reporta pero no activa tareas.

Para aplicar:

```powershell
.\scripts\dispatch-ready-tasks.ps1 -Apply
```

Entonces las READY elegibles pueden pasar a `ACTIVE`.

---

## 13. "Dispatch packet missing immediately before activation"

### Causa

El sistema no encuentra:

```text
docs/engineering/dispatch/AICO-xxx.md
```

al momento de activar la task.

### Resolución

Volver a ejecutar el dispatch desde un estado coherente y revisar que no se esté borrando el packet entre preparación y activación.

Ejecutar:

```powershell
.\scripts\validate-artifacts.ps1
git status --short
```

antes de modificar archivos manualmente.

---

# Ejecución de agentes

## 14. "Task AICO-xxx must be ACTIVE"

### Causa

`run-agent-task.ps1` solo acepta tasks `ACTIVE`.

### Comprobación

```powershell
.\scripts\list-tasks.ps1
```

### Resolución

No editar el status manualmente.

Completar readiness y dispatch:

```powershell
.\scripts\evaluate-readiness.ps1 -Apply
.\scripts\dispatch-ready-tasks.ps1 -Apply
```

---

## 15. "Dispatch packet not found"

El runner necesita el packet generado durante dispatch.

### Comprobación

```powershell
Test-Path .\docs\engineering\dispatch\AICO-123.md
```

### Resolución

Volver al flujo de readiness/dispatch.

---

## 16. "Role instructions not found"

### Ejemplo

```text
Role instructions not found: .codex\agents\...
```

### Causa

El valor `Owner` de la task no corresponde con una definición de agente instalada.

### Comprobación

```powershell
Get-ChildItem .\.codex\agents
Select-String -Path .\tasks\AICO-123.md -Pattern "^Owner:"
```

### Resolución

Usar el nombre de rol canónico.

Los agentes actuales incluyen:

```text
backend
ceo
cto
devops
engineering-manager
frontend
pm
qa
security
```

---

# Providers

## 17. "Codex CLI is not available in PATH"

### Comprobación

```powershell
Get-Command codex -ErrorAction SilentlyContinue
```

### Resolución

Instalar/configurar Codex CLI y comprobar que el comando `codex` sea visible desde la misma consola.

Alternativamente ejecutar otro provider configurado:

```powershell
.\scripts\run-active-agents.ps1 -Provider OpenRouter
```

o:

```powershell
.\scripts\run-active-agents.ps1 -Provider Gemini
```

---

## 18. "Codex is unavailable because its current usage quota is exhausted"

### Significado

El adapter detectó un mensaje de quota/usage limit de Codex.

### Resolución

Con provider explícito `Codex`, la ejecución termina.

Con `Auto`, el router puede intentar el siguiente provider disponible según:

```text
.codex/provider-config.json
```

El orden actual de `main` es:

```text
Codex → OpenRouter → Gemini
```

si los providers siguientes están configurados.

---

## 19. "OPENROUTER_API_KEY is not configured"

### Comprobación

```powershell
Test-Path Env:OPENROUTER_API_KEY
```

### Configuración para la sesión actual

```powershell
$env:OPENROUTER_API_KEY = "TU_KEY"
```

No escribir la key en archivos versionados.

---

## 20. "GEMINI_API_KEY is not configured"

### Comprobación

```powershell
Test-Path Env:GEMINI_API_KEY
```

### Configuración para la sesión actual

```powershell
$env:GEMINI_API_KEY = "TU_KEY"
```

---

## 21. "No configured provider is currently available"

### Significado

`Auto` revisó los providers configurados pero ninguno podía ejecutarse.

### Comprobar

```powershell
Get-Command codex -ErrorAction SilentlyContinue
Test-Path Env:OPENROUTER_API_KEY
Test-Path Env:GEMINI_API_KEY
Get-Content .\.codex\provider-config.json
```

Al menos un provider debe estar disponible.

---

## 22. "All configured providers failed"

### Significado

Había providers disponibles, pero todos los intentos terminaron en error.

El router clasifica fallos aproximadamente como:

```text
rate_limit
authentication
timeout
contract
transport
unknown
```

### Resolución

Leer el error individual de cada provider antes de cambiar configuración.

No asumir que un fallo del primer provider implica que todos fallaron por la misma causa.

---

## 23. Timeout de OpenRouter o Gemini

### Estado de `main`

Los adapters actuales utilizan:

```text
TimeoutSec = 240 segundos por request
maxAttempts = 3
```

Los errores transitorios incluyen:

- HTTP 429;
- HTTP 5xx;
- timeout;
- determinadas desconexiones de transporte.

El backoff actual es:

```text
1 segundo
2 segundos
```

entre los reintentos previos al último intento.

### Importante

La rama `main` **no utiliza actualmente `provider_timeout_seconds` como configuración canónica**.

Si una rama experimental exige esa propiedad, seguir las instrucciones de esa rama; no asumir que ese contrato ya forma parte de `main`.

---

## 24. OpenRouter o Gemini devuelve JSON inválido

### Síntomas

```text
invalid JSON
structured result contract
result root must be an object
schema
contract
```

### Significado

Un provider respondió, pero el resultado no cumple el contrato esperado.

AI Company OS debe rechazar ese resultado en lugar de convertirlo silenciosamente en evidencia confiable.

### Resolución

- reintentar si el provider/modelo fue inestable;
- probar otro provider;
- comprobar el schema requerido;
- no editar manualmente el JSON solo para hacerlo pasar sin revisar su semántica.

---

## 25. Provider Auto ignora -Model

### Comportamiento esperado

En modo:

```powershell
-Provider Auto
```

el router utiliza los modelos por provider definidos en:

```text
.codex/provider-config.json
```

Un `-Model` manual se usa con provider explícito, no con Auto.

---

# Contexto y límites

## 26. El provider externo "no ve" un archivo del repo

### Significado

OpenRouter y Gemini no inspeccionan el filesystem directamente.

Reciben un **Repository Context Pack** construido por AI Company OS y limitado por:

```text
context_max_chars
```

El valor actual de `main` es:

```text
320000
```

Los gates usan:

```text
gate_context_max_chars = 180000
```

### Resolución

Comprobar si el archivo es relevante para el rol y si el context builder lo incluye.

No aceptar como evidencia una afirmación sobre un archivo que el provider no recibió.

---

# Resultados y BLOCKED

## 27. Una task pasó a BLOCKED

### Significado correcto

`BLOCKED` está reservado para un impedimento que evitó completar la entrega asignada.

Ejemplos:

- falta una decisión necesaria;
- falta acceso material;
- falta autorización;
- falta evidencia imprescindible.

### No significa

- "encontré bugs";
- "el proyecto no está listo";
- "hay vulnerabilidades";
- "QA detectó problemas".

Un audit puede documentar problemas graves y seguir siendo `COMPLETED`.

---

## 28. Quiero desbloquear una task

Primero resolver el blocker y registrar evidencia.

Una task BLOCKED puede volver a:

```text
READY
BACKLOG
```

Las transiciones deben hacerse mediante los scripts del workflow, no cambiando manualmente `Status:`.

---

# Review, QA, Security y Final Approval

## 29. "Task must be REVIEW to submit a review"

La task todavía no tiene un result `COMPLETED` aceptado por el lifecycle.

### Comprobación

```powershell
Get-ChildItem .\docs\engineering\results
.\scripts\list-tasks.ps1
```

---

## 30. "Task must be QA"

Review todavía no aprobó la entrega.

Para entrar a QA debe existir un review artifact cuyo:

```text
Recommendation: APPROVE
```

---

## 31. "Task must be SECURITY"

QA todavía no pasó.

Para entrar a Security debe existir:

```text
Outcome: PASS
```

en el artifact de QA.

---

## 32. Security está satisfecho pero la task no llega a DONE

### Comportamiento esperado

`security-task.ps1` registra el gate, pero **no finaliza automáticamente la task**.

Después de un `PASS` o un `NOT_APPLICABLE` permitido, ejecutar la aprobación final:

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-123 `
  -Decision APPROVE `
  -Verification "Original objective and applicable gates verified"
```

Esta separación es intencional.

---

## 33. "QA artifact missing"

`finalize-task.ps1` no permite cerrar una task sin evidencia de QA.

### Resolución

No crear el archivo a mano para evitar el guard.

Ejecutar el gate correspondiente.

---

## 34. "Security artifact missing"

Mismo principio: la aprobación final requiere una disposición de Security registrada.

Incluso cuando Security no aplica, debe existir el artifact con:

```text
NOT_APPLICABLE
```

cuando el workflow profile lo permite.

---

## 35. high-assurance rechaza NOT_APPLICABLE

### Comportamiento esperado

Las tasks `high-assurance` requieren Security:

```text
PASS
o
FAIL
```

Nunca:

```text
NOT_APPLICABLE
```

---

## 36. Un gate falla y la task vuelve a READY

Es comportamiento esperado.

```text
Review CHANGES_REQUIRED → READY
QA FAIL                 → READY
Security FAIL           → READY
Final REJECT            → READY
```

El objetivo es realizar trabajo correctivo y generar nueva evidencia, no forzar el estado anterior.

---

# Ingeniería y backlog

## 37. "Source planning task must be DONE before executable backlog generation"

### Significado

No se puede transformar un plan del Engineering Manager en backlog ejecutable antes de que su propia task haya atravesado los gates.

### Resolución

Completar:

```text
REVIEW
QA
SECURITY
FINAL APPROVAL
```

para la task fuente.

Después:

```powershell
.\scripts\generate-engineering-backlog.ps1 -SourceTaskId AICO-XXX -Provider Auto
```

---

## 38. "Backlog already materialized"

El materializer evita duplicar tasks.

### Resolución

Inspeccionar el mapping existente:

```text
docs/engineering/plans/AICO-XXX-engineering-backlog-tasks.md
```

No borrar el mapping sin entender si las tasks generadas siguen existiendo.

---

## 39. Dependency cycle en engineering backlog

### Síntoma

```text
Engineering backlog contains a dependency cycle
```

### Significado

Existe una cadena como:

```text
A depende de B
B depende de C
C depende de A
```

El materializer la rechaza antes de crear tasks.

### Resolución

Corregir el backlog/plan. No eliminar arbitrariamente una dependency para hacer pasar el script: verificar qué decisión o secuencia era correcta.

---

## 40. Implementation authorization key inválida

### Significado

El backlog declaró una autorización de implementación que:

- no existe;
- no apunta a un item `DECISION`;
- es ambigua.

El generador contiene reparaciones limitadas por identidad/semántica, pero no debe inventar una autorización.

### Resolución

Revisar el plan del Engineering Manager y el JSON de backlog.

---

# Worktrees y escritura

## 41. "Project must be a Git repository for isolated writable execution"

`new-agent-workspace.ps1` requiere Git.

### Resolución

Ejecutar sobre el proyecto Git correcto.

---

## 42. "Workspace already exists"

### Significado

Ya existe el directorio destinado a esa AICO task.

### Comprobación

```powershell
git worktree list
```

### Resolución

Determinar si ese worktree sigue siendo el workspace activo de la task.

No borrarlo manualmente sin comprobar cambios no integrados.

---

## 43. "git worktree add failed"

### Comprobar

```powershell
git status
git branch --list
git worktree list
```

Causas frecuentes:

- branch ya asociada a otro worktree;
- ruta existente;
- repositorio con problemas;
- ref base inválida.

Resolver el problema Git antes de volver a crear el workspace.

---

## 44. El worktree existe: ¿puede el agente hacer push/merge/deploy?

No automáticamente.

El helper solo garantiza aislamiento.

```text
worktree creado
≠
merge autorizado
≠
push autorizado
≠
deploy autorizado
```

---

# Validación de artefactos

## 45. "Task ID does not match filename"

### Ejemplo

Archivo:

```text
tasks/AICO-007.md
```

Metadata:

```text
ID: AICO-006
```

### Resolución

Determinar cuál identidad es correcta antes de modificar nada.

La identidad de la task no debería renombrarse informalmente después de haber generado referencias y dependencias.

---

## 46. "Duplicate task ID"

Dos archivos declaran el mismo ID.

Resolver la duplicación antes de continuar. Las dependencias y artifacts pueden haber quedado ambiguos.

---

## 47. "Workflow phase ... but status ... requires ..."

AI Company OS mantiene un mapping entre status y workflow phase.

Ejemplos:

```text
READY    → PLANNING
ACTIVE   → IMPLEMENTATION
REVIEW   → CODE_REVIEW
QA       → QA
SECURITY → SECURITY
DONE     → DONE
BLOCKED  → BLOCKED
```

Usar los scripts de transición mantiene ambos valores sincronizados.

Editar solamente `Status:` a mano puede romper este contrato.

---

## 48. "Task must contain checklist-based Acceptance Criteria"

Los acceptance criteria deben utilizar checkboxes Markdown, por ejemplo:

```markdown
- [ ] El comportamiento esperado está implementado.
- [ ] La regresión relevante está cubierta.
```

---

## 49. company-state no coincide con tasks

### Principio

`tasks/AICO-*.md` son autoritativas.

`.codex/state/` es derivado.

### Resolución

```powershell
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
```

No editar company-state para contradecir las tasks.

---

# Encoding

## 50. Caracteres dañados / mojibake

### Síntomas

Texto similar a:

```text
Ã
Â
â
�
```

El framework incluye:

```powershell
.\scripts\repair-artifact-encoding.ps1
```

Antes de ejecutarlo sobre muchos artifacts, revisar Git status y conservar una forma de inspeccionar el diff.

Después:

```powershell
git diff
.\scripts\validate-artifacts.ps1
```

---

# Estado y métricas

## 51. El tablero/estado parece desactualizado

Sincronizar:

```powershell
.\scripts\sync-company-state.ps1
```

Después comprobar:

```text
.codex/state/company-state.md
.codex/state/company-state.json
.codex/state/current-sprint.md
```

---

## 52. Métricas faltantes

Las métricas están diseñadas como telemetría local append-only:

```text
.codex/runtime/metrics/events.jsonl
```

Resumir:

```powershell
.\scripts\summarize-metrics.ps1
```

Un warning de metrics después de una transición exitosa no debe confundirse automáticamente con fallo de la transición: algunos scripts protegen la operación principal y emiten warning si la telemetría falla.

---

# Git y ramas

## 53. Estoy en la branch equivocada

Comprobar siempre antes de ejecutar cambios:

```powershell
git branch --show-current
git status --short --branch
git worktree list
```

Esto es especialmente importante cuando existen worktrees de tareas o ramas experimentales del framework.

---

## 54. Una feature aparece en otra branch pero no en main

No documentarla ni usarla como contrato estable de `main`.

Ejemplos actuales de áreas en evolución incluyen TUI, writable runtime y ajustes recientes de provider timeout.

Antes de utilizar una instrucción específica de una branch:

```powershell
git branch --show-current
git log -1 --oneline
```

---

# Test suite

## 55. Quiero saber si el framework base está sano

Ejecutar:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

La suite es network-independent y cubre:

- intake;
- planning;
- readiness;
- dispatch;
- lifecycle;
- provider contracts;
- workflow profiles;
- worktree isolation;
- engineering backlog;
- E2E real de cambio de código.

---

## 56. El smoke suite falla

No continuar tratando el framework como sano.

Identificar el primer test que falló: el runner se detiene en el primer fallo.

Ejecutar ese test individualmente para aislar el problema.

Ejemplo:

```powershell
.\test-project\tests\test-end-to-end-code-change.ps1
```

---

# Checklist de recuperación

## 57. Cuando no sé en qué estado quedó el proyecto

Ejecutar en este orden:

```powershell
git status --short --branch
git worktree list

.\scripts\list-tasks.ps1
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
```

Después revisar:

```text
.codex/state/company-state.md
.codex/state/current-sprint.md
.codex/state/blockers.md
```

y la task involucrada:

```text
tasks/AICO-xxx.md
```

Por último revisar la evidencia correspondiente bajo:

```text
docs/engineering/
```

---

# Regla de diagnóstico

Cuando AI Company OS rechaza una transición, no intentar "ganarle al script".

El guard normalmente está señalando una de estas categorías:

```text
identidad
→ contexto
→ dependencia
→ autorización
→ evidencia
→ gate
→ estado
```

La corrección correcta es reparar la condición que falta y conservar la trazabilidad.


# Actualización del framework

## 58. Actualicé AI Company OS y perdí cambios locales

### Riesgo

`install-existing-project.ps1 -Force` reemplaza componentes del framework existentes. Si esos archivos tenían personalizaciones locales, pueden aparecer como cambios sobrescritos.

### Prevención

Antes de actualizar:

```powershell
git status --short --branch
git diff
```

Hacer la actualización en una branch dedicada y con el trabajo previo guardado/commitado de acuerdo con el workflow del proyecto.

### Después de actualizar

```powershell
git diff
.\scripts\validate-artifacts.ps1
```

Revisar especialmente:

```text
AGENTS.md
.codex/
scripts/
schemas/
```

El instalador actual no hace merge semántico de personalizaciones.

---

## 59. Ejecuté el instalador sin -Force y no se actualizaron scripts

### Comportamiento esperado

Sin `-Force`, el instalador muestra `SKIP existing:` para varios componentes y conserva los archivos existentes.

Eso protege personalizaciones, pero también significa que **no es un mecanismo automático de upgrade**.

### Resolución

Si realmente se desea actualizar la copia instalada:

1. trabajar sobre una branch limpia;
2. revisar personalizaciones;
3. actualizar el checkout fuente de AI Company OS;
4. ejecutar el instalador con `-Force`;
5. revisar el diff;
6. validar artifacts/tests correspondientes.

No usar `-Force` como rutina ciega.
