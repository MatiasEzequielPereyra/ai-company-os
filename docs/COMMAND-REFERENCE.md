# AI Company OS — Command Reference

> **Versión:** 0.1  
> Esta referencia describe parámetros verificados en la rama `main`.  
> Ejecutar los comandos desde la raíz del proyecto salvo que se indique lo contrario.

---

Los IDs `WR-XXX` y `AICO-XXX` son placeholders. Reemplazarlos por IDs reales antes de ejecutar un comando.

## Convenciones

```text
[SAFE]       inspección, validación o preparación
[APPLY]      modifica estado durable del workflow
[PROVIDER]   puede consumir cuota de un provider
[GIT]        modifica estructura Git/worktrees
[ADVANCED]   normalmente no es el primer comando que necesita un usuario
```

---

# CLI aico

The supported user-facing installation is distributed through npm:

~~~powershell
npm install -g @pereyram/ai-company-os
~~~

The npm launcher owns project-install/scaffold/update commands and delegates the remaining CLI to the bundled Python/Typer application.

## Public commands

### aico

Syntax:

~~~powershell
aico
~~~

Purpose: launch the TUI for the configured project.

TUI shortcuts: `F2` switches ES/EN interface language and `F3` toggles the Default/Hacker theme. Interface preferences persist across sessions; the TUI also exposes a Settings view.

Side effect: may bootstrap/update the package-local Python environment when the installed package version changed.

Common failure: Python >=3.11 or PowerShell is unavailable.

### aico shell

~~~powershell
aico shell
~~~

Opens the interactive text shell. Shell commands are status, tasks, use, project, help, clear, exit and quit.

### aico version

~~~powershell
aico version
~~~

Prints the installed Python package version.

### aico --help

~~~powershell
aico --help
~~~

Shows the Typer command surface.

Current limitation: the npm-wrapper commands new, install/init and update are intercepted before Typer and do not expose an equivalent command-specific Typer help surface. Their syntax is documented below.

### aico new

~~~powershell
aico new <project-name> [destination]
~~~

Purpose: create a new AI Company OS project.

Side effects:

- creates destination/project-name;
- installs project scaffolding/runtime;
- creates the managed-files manifest;
- bootstraps the Python CLI;
- selects the new project as current.

It does not run git init.

Common failures: missing project name, destination/project already exists, PowerShell missing, Python bootstrap failure.

### aico install / aico init

~~~powershell
aico install [target]
aico init [target]
~~~

Target defaults to the current directory.

Optional explicit reinstall flag:

~~~text
--force
~~~

Purpose: install AI Company OS into an existing directory and select that project.

Normal installation skips existing framework-path files. Skipped pre-existing scripts are not used as post-install executable code; derived-state synchronization runs through the package-owned sync implementation. Force can replace framework-path files and is not the project-upgrade mechanism.

Common failures: invalid target, PowerShell missing, existing malformed managed manifest, Python bootstrap failure.

### aico update

~~~powershell
aico update [target]
~~~

Target defaults to the current directory.

Purpose: update only the supported managed runtime namespace from the currently installed npm package.

Requires a valid .codex/managed-files.json. It refuses unmanaged runtime conflicts and does not change active-project selection.

Common failures: missing/unsupported manifest, unrecognized ownership contract, unmanaged target conflict, unsafe reparse/path, malformed managed config.

### aico use

~~~powershell
aico use <project>
~~~

Validates a project snapshot and records it as the default project.

Common failure: the path is not a recognizable AI Company OS project.

### aico current

~~~powershell
aico current
~~~

Prints the configured project. Exits non-zero when none is configured.

### aico status

~~~powershell
aico status [--project PATH] [--json]
~~~

Shows the current project snapshot.

### aico tasks

~~~powershell
aico tasks [--project PATH] [--status STATUS] [--owner OWNER] [--priority PRIORITY] [--json]
~~~

Lists tasks with optional filters.

### aico workflow

~~~powershell
aico workflow [--project PATH] [--json]
~~~

Shows task dependencies and execution flow.

### aico activity

~~~powershell
aico activity [--project PATH] [--limit N] [--json]
~~~

Shows persisted project activity. Default limit: 50.

### aico handoffs

~~~powershell
aico handoffs [--project PATH] [--json]
~~~

Shows declared/observed agent handoffs.

### aico runtime

~~~powershell
aico runtime [--project PATH] [--json]
~~~

Inspects the available runtime/event source used by the CLI.

### aico doctor

Project consistency:

~~~powershell
aico doctor [--project PATH] [--json]
~~~

Local dependency/runtime diagnosis:

~~~powershell
aico doctor --system [--json]
~~~

The system doctor checks Python, platform information, Git, Node, npm, PowerShell and Ollama. Python >=3.11 and PowerShell are runtime requirements; several other entries are reported as warnings when absent.

## Interactive shell commands

Inside aico shell:

~~~text
status
status --json
tasks
tasks --status ACTIVE
tasks --owner pm
tasks --priority P1
tasks --json
use "C:\path\project"
project
help
clear
exit
quit
~~~

# Advanced / internal PowerShell tooling

The PowerShell commands below are the lower-level workflow contract. They are not additional npm CLI subcommands and should not be used to bypass lifecycle or authorization guards.

# Instalación y proyecto

## initialize-project.ps1 — [APPLY]

Realiza intake/discovery del proyecto y genera documentación inicial.

```powershell
.\scripts\initialize-project.ps1
```

Otro path:

```powershell
.\scripts\initialize-project.ps1 -ProjectPath "C:\Proyecto"
```

Parámetros:

```text
-ProjectPath   default "."
```

---

## install-existing-project.ps1 — [APPLY]

Instala AI Company OS dentro de un proyecto existente.

```powershell
.\scripts\install-existing-project.ps1 `
  -TargetProject "C:\Proyecto"
```

Parámetros:

```text
-TargetProject   obligatorio
-Force           reemplaza componentes existentes cuando el instalador lo permite
```

Usar -Force solamente para una reinstalación explícita y revisada: puede reemplazar archivos del framework existentes. Para usuarios del paquete npm, aico install . es la instalación normal. **No usar aico install . --force como sustituto de aico update .** Ver operations/update-ownership.md para el contrato de upgrade.

---

## new-project.ps1 — [APPLY]

Crea un proyecto nuevo con la estructura de AI Company OS.

```powershell
.\scripts\new-project.ps1 `
  -ProjectName "MiProyecto" `
  -Destination "C:\Proyectos"
```

Parámetros:

```text
-ProjectName    obligatorio
-Destination    default "."
```

---

# Work Requests y planificación

## new-work-request.ps1 — [APPLY]

Crea un Work Request durable.

```powershell
.\scripts\new-work-request.ps1 `
  -Objective "Agregar recuperación de contraseña" `
  -Type FEATURE `
  -Priority P1
```

Parámetros:

```text
-Objective      obligatorio
-Type           FEATURE | BUG | REFACTOR | INFRASTRUCTURE | AUDIT |
                RELEASE | RESEARCH | DOCUMENTATION
-Priority       P0 | P1 | P2 | P3
-RequestedBy    default "user"
-ProjectPath    default "."
```

Defaults:

```text
Type      = FEATURE
Priority  = P1
```

---

## orchestrate.ps1 — [APPLY]

Comando maestro de preparación/orquestación.

Crear un Work Request nuevo:

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Prepare project for production" `
  -Type AUDIT `
  -Priority P1
```

Continuar uno existente:

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-XXX
```

Aplicar readiness y dispatch:

```powershell
.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-XXX `
  -Apply
```

Parámetros:

```text
-Objective
-Type           FEATURE | BUG | REFACTOR | INFRASTRUCTURE | AUDIT |
                RELEASE | RESEARCH | DOCUMENTATION
-Priority       P0 | P1 | P2 | P3
-WorkRequestId
-RequestedBy
-ProjectPath
-Apply
```

Sin `-Apply`, trabaja en modo PREPARE.

---

# Tasks

## new-task.ps1 — [APPLY]

Crea una task manual.

```powershell
.\scripts\new-task.ps1 `
  -Title "Implement password reset" `
  -Owner backend `
  -Priority P1 `
  -WorkflowProfile standard `
  -Objective "Implement backend password reset flow"
```

Parámetros:

```text
-Title             obligatorio
-Owner             default engineering-manager
-Priority          P0 | P1 | P2 | P3
-WorkflowProfile   lightweight | standard | high-assurance
-Objective
-TasksPath         default tasks
```

Defaults:

```text
Owner             = engineering-manager
Priority          = P2
WorkflowProfile   = standard
```

---

## list-tasks.ps1 — [SAFE]

Lista tasks.

```powershell
.\scripts\list-tasks.ps1
```

Filtrar:

```powershell
.\scripts\list-tasks.ps1 -Status ACTIVE
```

Estados:

```text
ALL
BACKLOG
READY
ACTIVE
REVIEW
QA
SECURITY
DONE
BLOCKED
```

---

## update-task.ps1 — [ADVANCED] [APPLY]

Actualiza metadata/evidencia sin realizar una transición de lifecycle.

Ejemplo:

```powershell
.\scripts\update-task.ps1 `
  -Id AICO-123 `
  -Priority P1 `
  -Note "Priority updated after scope review"
```

Parámetros:

```text
-Id                obligatorio
-Priority           P0 | P1 | P2 | P3
-Owner
-WorkflowProfile    lightweight | standard | high-assurance
-Note
-Evidence
-TasksPath
```

No utilizarlo para simular gates.

---

## advance-task.ps1 — [ADVANCED] [APPLY]

Motor de transición de estado.

Ejemplo:

```powershell
.\scripts\advance-task.ps1 `
  -Id AICO-123 `
  -Status READY `
  -Actor engineering-manager `
  -Reason "Dependencies resolved"
```

Parámetros:

```text
-Id          obligatorio
-Status      BACKLOG | READY | ACTIVE | REVIEW | QA | SECURITY | DONE | BLOCKED
-Actor
-Reason
-Evidence
-TasksPath
```

Este script contiene guards. No es un bypass de lifecycle.

Para uso normal preferir readiness, dispatch, result/gate scripts y finalization.

---

# Readiness y dispatch

## evaluate-readiness.ps1 — [SAFE]/[APPLY]

Dry-run:

```powershell
.\scripts\evaluate-readiness.ps1
```

Aplicar:

```powershell
.\scripts\evaluate-readiness.ps1 -Apply
```

Parámetros:

```text
-ProjectPath
-Apply
```

---

## dispatch-ready-tasks.ps1 — [SAFE]/[APPLY]

Preparar:

```powershell
.\scripts\dispatch-ready-tasks.ps1
```

Activar:

```powershell
.\scripts\dispatch-ready-tasks.ps1 -Apply
```

Parámetros:

```text
-ProjectPath
-Apply
```

---

# Ejecución de agentes

## run-active-agents.ps1 — [PROVIDER]

Ejecuta todas las tasks ACTIVE.

```powershell
.\scripts\run-active-agents.ps1
```

Provider explícito:

```powershell
.\scripts\run-active-agents.ps1 -Provider Codex
```

Modelo explícito con provider explícito:

```powershell
.\scripts\run-active-agents.ps1 `
  -Provider Gemini `
  -Model "modelo"
```

Parámetros:

```text
-ProjectPath
-Parallel
-Provider      Auto | Codex | Ollama | OpenRouter | Gemini | DeepSeek | Grok
-Model
-AuthMode      Auto | ChatGPT | ApiKey
```

Notas:

- `-Parallel` usa un checkout compartido y está restringido al runner de análisis.
- `AuthMode ApiKey` legacy está deshabilitado cuando implicaría el flujo OpenAI API anterior.
- El `Auto` actual es local-first y usa `auto_order` de `.codex/provider-config.json` (por defecto Ollama).
- OpenRouter, Gemini, DeepSeek y Grok pueden seleccionarse explícitamente cuando sus credenciales están configuradas.
- `allow_paid_fallback=false` evita que DeepSeek/Grok aparezcan silenciosamente como fallback pago en Auto.

---

## run-agent-task.ps1 — [PROVIDER] [ADVANCED]

Ejecuta una task ACTIVE específica.

```powershell
.\scripts\run-agent-task.ps1 `
  -Id AICO-123 `
  -Provider Auto
```

Parámetros:

```text
-Id           obligatorio
-ProjectPath
-Provider     Auto | Codex | Ollama | OpenRouter | Gemini | DeepSeek | Grok
-Model
-AuthMode
```

Requiere que la task esté en `ACTIVE` y tenga dispatch packet.

---

# Resultados y gates

## submit-task-result.ps1 — [ADVANCED] [APPLY]

Registra una entrega.

```powershell
.\scripts\submit-task-result.ps1 `
  -Id AICO-123 `
  -Outcome COMPLETED `
  -Summary "Implemented requested behavior" `
  -Verification "Tests passed"
```

Parámetros:

```text
-Id                obligatorio
-Outcome           COMPLETED | BLOCKED
-Summary           obligatorio
-ChangedArtifacts
-Verification
-Decisions
-Blockers
-RecommendedNext
-ProjectPath
```

El agent runner llama este script automáticamente.

---

## run-pending-gates.ps1 — [PROVIDER] [APPLY]

Procesa gates pendientes.

```powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Parámetros:

```text
-ProjectPath
-Provider     Auto | Codex | Ollama | OpenRouter | Gemini | DeepSeek | Grok
-Model
```

Orden:

```text
REVIEW → QA → SECURITY
```

No realiza final approval.

---

## run-gate-agent.ps1 — [PROVIDER] [ADVANCED]

Ejecuta un gate específico con IA.

```powershell
.\scripts\run-gate-agent.ps1 `
  -Id AICO-123 `
  -Gate Review `
  -Provider Auto
```

Parámetros:

```text
-Id          obligatorio
-Gate        Review | QA | Security
-ProjectPath
-Provider    Auto | Codex | Ollama | OpenRouter | Gemini | DeepSeek | Grok
-Model
```

---

## review-task.ps1 — [APPLY]

Registra Review manual/externo.

```powershell
.\scripts\review-task.ps1 `
  -Id AICO-123 `
  -Recommendation APPROVE `
  -Reviewer engineering-manager `
  -Verification "Reviewed implementation and evidence"
```

Parámetros:

```text
-Id              obligatorio
-Recommendation  APPROVE | CHANGES_REQUIRED
-Reviewer        obligatorio
-Findings
-Verification
-ProjectPath
```

---

## qa-task.ps1 — [APPLY]

```powershell
.\scripts\qa-task.ps1 `
  -Id AICO-123 `
  -Outcome PASS `
  -Evidence "Acceptance checks passed"
```

Parámetros:

```text
-Id          obligatorio
-Outcome     PASS | FAIL
-Evidence    obligatorio
-Findings
-ProjectPath
```

---

## security-task.ps1 — [APPLY]

```powershell
.\scripts\security-task.ps1 `
  -Id AICO-123 `
  -Outcome PASS `
  -Evidence "Security checks complete"
```

Parámetros:

```text
-Id          obligatorio
-Outcome     PASS | FAIL | NOT_APPLICABLE
-Evidence    obligatorio
-Findings
-ProjectPath
```

---

## finalize-task.ps1 — [APPLY] [HUMAN DECISION]

Realiza la aprobación final.

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-123 `
  -Decision APPROVE `
  -Verification "Original objective and applicable gates verified"
```

Parámetros:

```text
-Id             obligatorio
-Decision       APPROVE | REJECT
-Verification   obligatorio
-ProjectPath
```

El script exige evidence de QA y Security compatible con el workflow profile.

---

# Engineering backlog

## generate-engineering-backlog.ps1 — [PROVIDER] [APPLY]

Convierte una task de planificación del Engineering Manager ya aprobada en backlog estructurado.

```powershell
.\scripts\generate-engineering-backlog.ps1 `
  -SourceTaskId AICO-006 `
  -Provider Auto
```

Parámetros:

```text
-SourceTaskId          obligatorio
-ProjectPath
-Provider              Auto | Codex | Ollama | OpenRouter | Gemini | DeepSeek | Grok
-Model
-ReuseExistingOutput
```

La source task debe estar `DONE`.

---

## materialize-engineering-backlog.ps1 — [APPLY]

Convierte los items lógicos del backlog en nuevas AICO tasks.

```powershell
.\scripts\materialize-engineering-backlog.ps1 `
  -SourceTaskId AICO-006
```

Parámetros:

```text
-SourceTaskId   obligatorio
-ProjectPath
```

Valida dependencias, ciclos y authorization key antes de crear tasks.

---

## reconcile-engineering-backlog.ps1 — [ADVANCED] [APPLY]

Reconcilia un backlog de ingeniería ya existente con su fuente.

```powershell
.\scripts\reconcile-engineering-backlog.ps1 `
  -SourceTaskId AICO-006
```

Usar solamente cuando se entiende el estado de las tasks ya materializadas.

---

# Worktrees

## new-agent-workspace.ps1 — [GIT] [APPLY]

Crea aislamiento para una task con escritura autorizada.

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Opciones:

```powershell
.\scripts\new-agent-workspace.ps1 `
  -Id AICO-123 `
  -BaseRef main `
  -WorkspaceRoot "C:\Worktrees"
```

Parámetros:

```text
-Id              obligatorio
-ProjectPath
-BaseRef          default HEAD
-WorkspaceRoot
```

No realiza merge/push/deploy.

---

# Estado, validación y observabilidad

## refresh-dependencies.ps1 — [APPLY]

Reevalúa readiness después de que dependencies cambian.

```powershell
.\scripts\refresh-dependencies.ps1
```

`finalize-task.ps1` lo ejecuta automáticamente después de un APPROVE cuando está disponible.

---

## sync-company-state.ps1 — [APPLY]

Regenera estado derivado desde tasks.

```powershell
.\scripts\sync-company-state.ps1
```

Parámetros:

```text
-TasksPath
-SprintPath
```

---

## validate-artifacts.ps1 — [SAFE]

Valida contratos canónicos.

```powershell
.\scripts\validate-artifacts.ps1
```

Parámetros:

```text
-ProjectPath
```

---

## summarize-metrics.ps1 — [SAFE]

```powershell
.\scripts\summarize-metrics.ps1
```

Salida JSON:

```powershell
.\scripts\summarize-metrics.ps1 -AsJson
```

---

## repair-artifact-encoding.ps1 — [SAFE]/[APPLY]

Inspección:

```powershell
.\scripts\repair-artifact-encoding.ps1
```

Aplicar reparación:

```powershell
.\scripts\repair-artifact-encoding.ps1 -Apply
```

Revisar siempre el diff después de `-Apply`.

---

# Flujo normal recomendado

Para un usuario, la mayoría de las veces alcanza con conocer:

```powershell
.\scripts\initialize-project.ps1

.\scripts\orchestrate.ps1 `
  -Objective "..." `
  -Type FEATURE `
  -Priority P1

.\scripts\list-tasks.ps1

.\scripts\orchestrate.ps1 `
  -WorkRequestId WR-XXX `
  -Apply

.\scripts\run-active-agents.ps1 -Provider Auto

.\scripts\run-pending-gates.ps1 -Provider Auto

.\scripts\finalize-task.ps1 `
  -Id AICO-XXX `
  -Decision APPROVE `
  -Verification "..."

.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
```

Los comandos avanzados existen para operar componentes individuales, depurar o construir integraciones; no deberían utilizarse para saltar el lifecycle.
