from __future__ import annotations


DEFAULT_LANGUAGE = "es"
SUPPORTED_LANGUAGES = ("es", "en")


NAVIGATION_LABELS = {
    "es": {
        "overview": "Resumen",
        "command": "Centro de Comando",
        "projects": "Proyectos",
        "plans": "Planes / Work Requests",
        "providers": "Proveedores",
        "tasks": "Tareas",
        "agents": "Agentes",
        "workflow": "Workflow / DAG",
        "activity": "Actividad",
        "handoffs": "Handoffs",
        "runtime": "Runtime",
        "blockers": "Bloqueos",
        "gates": "Quality Gates",
        "doctor": "Doctor",
        "diagnostics": "Diagn?sticos",
        "help": "Ayuda / Gu?a",
    },
    "en": {
        "overview": "Overview",
        "command": "Command Center",
        "projects": "Projects",
        "plans": "Plans / Work Requests",
        "providers": "Providers",
        "tasks": "Tasks",
        "agents": "Agents",
        "workflow": "Workflow / DAG",
        "activity": "Activity",
        "handoffs": "Handoffs",
        "runtime": "Runtime",
        "blockers": "Blockers",
        "gates": "Quality Gates",
        "doctor": "Doctor",
        "diagnostics": "Diagnostics",
        "help": "Help / Guide",
    },
}


HELP_SECTION_IDS = (
    "getting-started",
    "workflow",
    "plans",
    "plan-control",
    "tasks",
    "agents",
    "providers",
    "quality-gates",
    "statuses",
    "security",
    "troubleshooting",
    "shortcuts",
    "architecture",
)


HELP = {
    "es": {
        "getting-started": (
            "Primeros pasos",
            """AI Company OS organiza trabajo de desarrollo mediante agentes,
tareas, dependencias y controles de calidad.

Flujo recomendado:

1. Abr? AI Company OS con `company`.
2. Seleccion? el proyecto en Proyectos.
3. Revis? Resumen para conocer el estado actual.
4. Entr? en Planes / Work Requests.
5. Abr? un Work Request existente o prepar? uno nuevo.
6. Activ? las tareas listas.
7. Ejecut? an?lisis o implementaci?n seg?n corresponda.
8. Pas? el trabajo por Review, QA y Security.
9. Realiz? la aprobaci?n final cuando corresponda.

F1 abre esta gu?a desde cualquier lugar.
F2 cambia la interfaz entre Espa?ol e English.""",
        ),
        "workflow": (
            "Flujo de trabajo",
            """Los estados can?nicos NO se traducen ni se modifican.

BACKLOG
Trabajo identificado pero todav?a no preparado.

READY
La tarea cumple las condiciones para poder activarse.

ACTIVE
Hay trabajo en ejecuci?n.

REVIEW
La implementaci?n est? esperando revisi?n independiente.

QA
La tarea est? en validaci?n de calidad.

SECURITY
La tarea est? en validaci?n de seguridad.

DONE
El flujo requerido fue completado.

BLOCKED
Existe un impedimento real que evita continuar.

La interfaz s?lo representa estos estados.
Los artefactos del repositorio siguen siendo la fuente de verdad.""",
        ),
        "plans": (
            "Planes / Work Requests",
            """Un Work Request representa una solicitud de trabajo persistente.

Desde esta pantalla pod?s:

- revisar Work Requests anteriores;
- reabrir un plan preparado;
- continuar ejecuci?n existente;
- consultar las tareas asociadas;
- eliminar ?nicamente planes que todav?a sean seguros de eliminar.

Reabrir un Work Request NO debe recrearlo ni perder su historial.""",
        ),
        "plan-control": (
            "Plan Control",
            """Plan Control es el centro operativo de un Work Request.

A ? Activate
Activa trabajo preparado.

R ? Analysis
Ejecuta el agente de an?lisis.
No debe modificar c?digo de producci?n.

W ? Writable implementation
Ejecuta implementaci?n real dentro de un worktree aislado.
Nunca debe escribir directamente sobre el checkout principal.

G ? Gates
Ejecuta los quality gates aplicables:
Review ? QA ? Security.

F ? Final approval
Finaliza una tarea que ya super? los controles requeridos.

F5 ? Refresh
Vuelve a leer el estado can?nico del proyecto.

C ? Copy details
Copia errores, bloqueos o detalles de ejecuci?n.

Esc ? Back
Vuelve a la pantalla anterior.""",
        ),
        "tasks": (
            "Tareas",
            """Tasks muestra el trabajo can?nico definido en `tasks/`.

Cada tarea puede mostrar:

- ID;
- t?tulo;
- Owner;
- prioridad;
- Status;
- Workflow phase;
- dependencias;
- evidencia;
- objetivo.

Los valores internos como ACTIVE, BLOCKED o REVIEW permanecen
exactamente iguales aunque la interfaz est? en espa?ol.""",
        ),
        "agents": (
            "Agentes",
            """Agents permite observar la organizaci?n de AI Company OS.

Los roles pueden incluir:

- CEO / Orchestrator;
- Product Manager;
- CTO;
- Engineering Manager;
- Backend;
- Frontend;
- DevOps;
- QA;
- Security.

La pantalla distingue estado organizacional de estado runtime.
Que un agente tenga una tarea asignada no significa necesariamente
que exista un proceso vivo ejecut?ndose en ese instante.""",
        ),
        "providers": (
            "Proveedores",
            """Providers administra la disponibilidad de modelos externos.

La pol?tica actual prioriza proveedores gratuitos.

Auto:
selecciona ?nicamente proveedores/modelos permitidos por la
pol?tica configurada para ese tipo de ejecuci?n.

OpenRouter y Gemini:
sus credenciales se guardan mediante el almac?n seguro del sistema
operativo, no dentro del repositorio.

Un provider gratuito puede tener l?mites de requests o rate limits.
FREE no significa ilimitado.""",
        ),
        "quality-gates": (
            "Quality Gates",
            """Los gates validan trabajo de forma independiente.

REVIEW
Eval?a la implementaci?n contra los requisitos.

QA
Valida comportamiento y criterios de calidad.

SECURITY
Eval?a requisitos y riesgos de seguridad.

Una ejecuci?n t?cnica exitosa del gate NO significa necesariamente
que el resultado haya sido aprobado.

Siempre mir? el resultado can?nico:
APPROVE, CHANGES_REQUIRED, PASS, FAIL, etc.""",
        ),
        "statuses": (
            "Estados y resultados",
            """Hay que distinguir dos conceptos:

1. El proceso termin?.
2. La tarea termin? correctamente.

Ejemplo:

El writable runner puede finalizar correctamente como proceso,
pero dejar:

Status: BLOCKED

Eso significa que el runtime funcion?, detect? un impedimento y lo
registr? correctamente.

La TUI debe mostrar el estado can?nico, no asumir ?xito por un
return code 0.""",
        ),
        "security": (
            "Seguridad",
            """Principios operativos de la interfaz:

- la UI no es la fuente de verdad;
- no redefine silenciosamente estados;
- no debe modificar main autom?ticamente;
- implementaci?n writable usa worktrees aislados;
- no debe hacer merge, push o deploy sin autorizaci?n;
- los secretos no deben almacenarse en el repositorio;
- la UI consume los protocolos existentes del motor.

Arquitectura esperada:

TUI
 ?
Application services
 ?
Repositories / adapters
 ?
Artefactos can?nicos de Company OS

Los widgets no deben implementar reglas del dominio por su cuenta.""",
        ),
        "troubleshooting": (
            "Errores frecuentes",
            """TASK BLOCKED
Abr? el resultado y revis? Blocker y Recommended next.

PROVIDER NOT CONFIGURED
Revis? Providers y la disponibilidad de la API key.

WORKTREE NOT FOUND
La implementaci?n writable necesita un worktree registrado.

CHANGES_REQUIRED
Review encontr? cambios necesarios.
La tarea puede volver a READY para una implementaci?n correctiva.

QA FAIL
La implementaci?n no super? QA.

SECURITY FAIL
Existe un problema que debe corregirse antes de finalizar.

CONTEXT MISSING
El agente no recibi? un archivo necesario.
No conviene hacer que el modelo adivine el contenido faltante.

Us? C cuando est? disponible para copiar el detalle completo.""",
        ),
        "shortcuts": (
            "Atajos de teclado",
            """Atajos globales:

F1   Ayuda / Help
F2   Espa?ol ? English
R    Refresh, cuando corresponde
Q    Salir desde la pantalla principal
Esc  Volver en pantallas secundarias

Plan Control:

A    Activate
R    Analysis
W    Writable implementation
G    Quality Gates
F    Final approval
F5   Refresh
C    Copy details
Esc  Back

Las teclas disponibles tambi?n aparecen en el footer de cada pantalla.""",
        ),
        "architecture": (
            "Arquitectura de la interfaz",
            """AI Company OS separa presentaci?n y estado.

La TUI NO es Company OS.

La interfaz consume informaci?n de:

docs/
tasks/
.codex/state/
handoffs/
ADRs
y otros artefactos definidos por los protocolos del motor.

La separaci?n deseada es:

Presentation
    TUI / CLI
        ?
Application
    services / use cases
        ?
Domain / repositories
        ?
Company OS artifacts

Esto permite que una futura interfaz web consuma el mismo n?cleo
sin redefinir el funcionamiento de Company OS.""",
        ),
    },

    "en": {
        "getting-started": (
            "Getting started",
            """AI Company OS organizes development work through agents,
tasks, dependencies and quality controls.

Recommended flow:

1. Start AI Company OS with `company`.
2. Select the project from Projects.
3. Check Overview for the current state.
4. Open Plans / Work Requests.
5. Open an existing Work Request or prepare a new one.
6. Activate ready work.
7. Run analysis or implementation as appropriate.
8. Move work through Review, QA and Security.
9. Perform final approval when applicable.

F1 opens this guide from anywhere.
F2 switches the interface between Espa?ol and English.""",
        ),
        "workflow": (
            "Workflow",
            """Canonical states are NEVER translated or modified.

BACKLOG
Work has been identified but is not yet ready.

READY
The task satisfies the conditions required for activation.

ACTIVE
Work is being executed.

REVIEW
Implementation is waiting for independent review.

QA
The task is undergoing quality validation.

SECURITY
The task is undergoing security validation.

DONE
The required workflow has been completed.

BLOCKED
A real impediment prevents progress.

The interface only represents these states.
Repository artifacts remain the source of truth.""",
        ),
        "plans": (
            "Plans / Work Requests",
            """A Work Request is a persistent work request.

From this screen you can:

- inspect previous Work Requests;
- reopen prepared plans;
- continue existing execution;
- inspect associated tasks;
- delete only plans that are still safe to delete.

Reopening a Work Request must not recreate it or lose its history.""",
        ),
        "plan-control": (
            "Plan Control",
            """Plan Control is the operational center for a Work Request.

A ? Activate
Activates prepared work.

R ? Analysis
Runs an analysis agent.
It must not modify production code.

W ? Writable implementation
Runs real implementation inside an isolated worktree.
It must never write directly to the primary checkout.

G ? Gates
Runs applicable quality gates:
Review ? QA ? Security.

F ? Final approval
Finalizes work that passed the required controls.

F5 ? Refresh
Reloads canonical project state.

C ? Copy details
Copies errors, blockers or execution details.

Esc ? Back
Returns to the previous screen.""",
        ),
        "tasks": (
            "Tasks",
            """Tasks displays canonical work defined under `tasks/`.

A task may expose:

- ID;
- title;
- Owner;
- priority;
- Status;
- Workflow phase;
- dependencies;
- evidence;
- objective.

Internal values such as ACTIVE, BLOCKED or REVIEW remain exactly
the same regardless of interface language.""",
        ),
        "agents": (
            "Agents",
            """Agents displays the AI Company OS organization.

Roles may include:

- CEO / Orchestrator;
- Product Manager;
- CTO;
- Engineering Manager;
- Backend;
- Frontend;
- DevOps;
- QA;
- Security.

The UI distinguishes organizational state from runtime state.
An assigned task does not necessarily mean a live process is
currently running.""",
        ),
        "providers": (
            "Providers",
            """Providers manages external model availability.

The current policy prioritizes free providers.

Auto:
selects only providers/models permitted by the policy configured
for that execution type.

OpenRouter and Gemini:
credentials are stored through the operating system credential
store, not inside the repository.

A free provider may still have request and rate limits.
FREE does not mean unlimited.""",
        ),
        "quality-gates": (
            "Quality Gates",
            """Gates independently validate work.

REVIEW
Evaluates implementation against requirements.

QA
Validates behavior and quality criteria.

SECURITY
Evaluates security requirements and risks.

A technically successful gate execution does NOT necessarily mean
that the work was approved.

Always inspect the canonical outcome:
APPROVE, CHANGES_REQUIRED, PASS, FAIL, etc.""",
        ),
        "statuses": (
            "States and results",
            """Two concepts must remain separate:

1. The process finished.
2. The task completed successfully.

Example:

The writable runner may finish successfully as a process while
leaving:

Status: BLOCKED

That means the runtime worked, detected an impediment and recorded
it correctly.

The TUI must represent canonical state rather than infer success
from return code 0.""",
        ),
        "security": (
            "Security",
            """Interface operating principles:

- the UI is not the source of truth;
- it does not silently redefine states;
- it must not automatically modify main;
- writable execution uses isolated worktrees;
- it must not merge, push or deploy without authorization;
- secrets must not be stored in the repository;
- the UI consumes existing engine protocols.

Expected architecture:

TUI
 ?
Application services
 ?
Repositories / adapters
 ?
Canonical Company OS artifacts

Widgets must not implement domain rules on their own.""",
        ),
        "troubleshooting": (
            "Troubleshooting",
            """TASK BLOCKED
Open the result and inspect Blocker and Recommended next.

PROVIDER NOT CONFIGURED
Check Providers and API-key availability.

WORKTREE NOT FOUND
Writable implementation requires a registered worktree.

CHANGES_REQUIRED
Review found required changes.
The task may return to READY for corrective implementation.

QA FAIL
The implementation did not pass QA.

SECURITY FAIL
A security issue must be corrected before finalization.

CONTEXT MISSING
The agent was not given a required file.
The model should not guess missing source content.

Use C when available to copy complete details.""",
        ),
        "shortcuts": (
            "Keyboard shortcuts",
            """Global shortcuts:

F1   Help / Ayuda
F2   English ? Espa?ol
R    Refresh where applicable
Q    Quit from the main screen
Esc  Back from secondary screens

Plan Control:

A    Activate
R    Analysis
W    Writable implementation
G    Quality Gates
F    Final approval
F5   Refresh
C    Copy details
Esc  Back

Available actions are also shown in each screen footer.""",
        ),
        "architecture": (
            "Interface architecture",
            """AI Company OS separates presentation from state.

The TUI is NOT Company OS itself.

The interface consumes information from:

docs/
tasks/
.codex/state/
handoffs/
ADRs
and other artifacts defined by engine protocols.

Desired separation:

Presentation
    TUI / CLI
        ?
Application
    services / use cases
        ?
Domain / repositories
        ?
Company OS artifacts

This allows a future web interface to reuse the same core without
redefining how Company OS works.""",
        ),
    },
}



PROGRESS_TEXT = {
    "es": {
        "progress_title": "Operacion en curso",
        "progress_task": "Tarea",
        "progress_action": "Accion",
        "progress_stage": "Etapa actual",
        "progress_agent": "Agente",
        "progress_context": "Contexto",
        "progress_elapsed": "Tiempo",
        "progress_activity": "Actividad",
        "progress_last_event": "Ultimo evento",
        "progress_recent_events": "Eventos recientes",
        "progress_working": "Trabajando...",
        "progress_already_running": "Operacion ya en curso",
        "progress_success": "SUCCESS",
        "progress_error": "ERROR",
        "progress_blocked": "BLOCKED",
        "progress_duration": "Duracion",
        "progress_summary": "Resumen",
        "progress_last_operation": "Ultima operacion",
        "progress_preparing_worktree": "Preparando worktree aislado...",
        "progress_waiting_provider": "Esperando respuesta del provider...",
    },
    "en": {
        "progress_title": "Operation running",
        "progress_task": "Task",
        "progress_action": "Action",
        "progress_stage": "Current stage",
        "progress_agent": "Agent",
        "progress_context": "Context",
        "progress_elapsed": "Elapsed",
        "progress_activity": "Activity",
        "progress_last_event": "Last event",
        "progress_recent_events": "Recent events",
        "progress_working": "Working...",
        "progress_already_running": "Operation already running",
        "progress_success": "SUCCESS",
        "progress_error": "ERROR",
        "progress_blocked": "BLOCKED",
        "progress_duration": "Duration",
        "progress_summary": "Summary",
        "progress_last_operation": "Last operation",
        "progress_preparing_worktree": "Preparing isolated worktree...",
        "progress_waiting_provider": "Waiting for provider response...",
    },
}

def normalize_language(language: str) -> str:
    if language in SUPPORTED_LANGUAGES:
        return language

    return DEFAULT_LANGUAGE


def navigation_label(
    language: str,
    view: str,
) -> str:
    language = normalize_language(language)

    return NAVIGATION_LABELS[language].get(
        view,
        view,
    )


def help_section_label(
    language: str,
    section_id: str,
) -> str:
    language = normalize_language(language)

    section = HELP[language].get(section_id)

    if section is None:
        return section_id

    return section[0]


def help_section_content(
    language: str,
    section_id: str,
) -> tuple[str, str]:
    language = normalize_language(language)

    return HELP[language].get(
        section_id,
        (section_id, ""),
    )


def ui_text(
    language: str,
    key: str,
) -> str:
    language = normalize_language(language)

    if key in PROGRESS_TEXT.get(
        language,
        {},
    ):
        return PROGRESS_TEXT[language][key]

    return key
