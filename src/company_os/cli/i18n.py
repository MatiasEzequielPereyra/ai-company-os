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
        "diagnostics": "Diagnosticos",
        "settings": "Configuracion",
        "help": "Ayuda / Guia",
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
        "settings": "Settings",
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

1. Abri AI Company OS con `company`.
2. Selecciona el proyecto en Proyectos.
3. Revisa Resumen para conocer el estado actual.
4. Entra en Planes / Work Requests.
5. Abri un Work Request existente o prepara uno nuevo.
6. Activa las tareas listas.
7. Ejecuta analisis o implementacion segun corresponda.
8. Pasa el trabajo por Review, QA y Security.
9. Realiza la aprobacion final cuando corresponda.

F1 abre esta guia desde cualquier lugar.
F2 cambia la interfaz entre Espanol e English.""",
        ),
        "workflow": (
            "Flujo de trabajo",
            """Los estados canonicos NO se traducen ni se modifican.

BACKLOG
Trabajo identificado pero todavia no preparado.

READY
La tarea cumple las condiciones para poder activarse.

ACTIVE
Hay trabajo en ejecucion.

REVIEW
La implementacion esta esperando revision independiente.

QA
La tarea esta en validacion de calidad.

SECURITY
La tarea esta en validacion de seguridad.

DONE
El flujo requerido fue completado.

BLOCKED
Existe un impedimento real que evita continuar.

La interfaz solo representa estos estados.
Los artefactos del repositorio siguen siendo la fuente de verdad.""",
        ),
        "plans": (
            "Planes / Work Requests",
            """Un Work Request representa una solicitud de trabajo persistente.

Desde esta pantalla podes:

- revisar Work Requests anteriores;
- reabrir un plan preparado;
- continuar ejecucion existente;
- consultar las tareas asociadas;
- eliminar unicamente planes que todavia sean seguros de eliminar.

Reabrir un Work Request NO debe recrearlo ni perder su historial.""",
        ),
        "plan-control": (
            "Plan Control",
            """Plan Control es el centro operativo de un Work Request.

A - Activate
Activa trabajo preparado.

R - Analysis
Ejecuta el agente de analisis.
No debe modificar codigo de produccion.

W - Writable implementation
Ejecuta implementacion real dentro de un worktree aislado.
Nunca debe escribir directamente sobre el checkout principal.

G - Gates
Ejecuta los quality gates aplicables:
Review -> QA -> Security.

F - Final approval
Finaliza una tarea que ya supero los controles requeridos.

F5 - Refresh
Vuelve a leer el estado canonico del proyecto.

C - Copy details
Copia errores, bloqueos o detalles de ejecucion.

Esc - Back
Vuelve a la pantalla anterior.""",
        ),
        "tasks": (
            "Tareas",
            """Tasks muestra el trabajo canonico definido en `tasks/`.

Cada tarea puede mostrar:

- ID;
- titulo;
- Owner;
- prioridad;
- Status;
- Workflow phase;
- dependencias;
- evidencia;
- objetivo.

Los valores internos como ACTIVE, BLOCKED o REVIEW permanecen
exactamente iguales aunque la interfaz este en espanol.""",
        ),
        "agents": (
            "Agentes",
            """Agents permite observar la organizacion de AI Company OS.

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
que exista un proceso vivo ejecutandose en ese instante.""",
        ),
        "providers": (
            "Proveedores",
            """Providers muestra los proveedores expuestos por el core.

La interfaz no decide que providers existen.
ProviderService es la fuente para disponibilidad y configuracion.

La politica operativa prioriza opciones gratuitas cuando el core
las habilita para Auto.

OpenRouter y Gemini tienen configuracion de credenciales visible
en la TUI actual.

DeepSeek, Grok / xAI y Ollama podran aparecer sin redisenar la
tabla cuando el core los exponga.

Ollama debe tratarse como provider local y no como una API key.

FREE no significa ilimitado: pueden existir limites de requests,
rate limits o limites propios del proveedor.""",
        ),
        "quality-gates": (
            "Quality Gates",
            """Los gates validan trabajo de forma independiente.

REVIEW
Evalua la implementacion contra los requisitos.

QA
Valida comportamiento y criterios de calidad.

SECURITY
Evalua requisitos y riesgos de seguridad.

Una ejecucion tecnica exitosa del gate NO significa necesariamente
que el resultado haya sido aprobado.

Siempre mira el resultado canonico:
APPROVE, CHANGES_REQUIRED, PASS, FAIL, etc.""",
        ),
        "statuses": (
            "Estados y resultados",
            """Hay que distinguir dos conceptos:

1. El proceso termino.
2. La tarea termino correctamente.

Ejemplo:

El writable runner puede finalizar correctamente como proceso,
pero dejar:

Status: BLOCKED

Eso significa que el runtime funciono, detecto un impedimento y lo
registro correctamente.

La TUI debe mostrar el estado canonico, no asumir exito por un
return code 0.""",
        ),
        "security": (
            "Seguridad",
            """Principios operativos de la interfaz:

- la UI no es la fuente de verdad;
- no redefine silenciosamente estados;
- no modifica main automaticamente;
- writable usa worktrees aislados;
- no hace merge, push o deploy sin autorizacion;
- los secretos no se almacenan en el repositorio;
- la UI consume los protocolos existentes del motor.

Arquitectura:

TUI
  ->
Application services
  ->
Repositories / adapters
  ->
Artefactos canonicos de Company OS

Los widgets no implementan reglas del dominio por su cuenta.""",
        ),
        "troubleshooting": (
            "Errores frecuentes",
            """TASK BLOCKED
Abri el resultado y revisa Blocker y Recommended next.

PROVIDER NOT CONFIGURED
Revisa Providers y la disponibilidad de la API key.

WORKTREE NOT FOUND
La implementacion writable necesita un worktree registrado.

CHANGES_REQUIRED
Review encontro cambios necesarios.

QA FAIL
La implementacion no supero QA.

SECURITY FAIL
Existe un problema que debe corregirse antes de finalizar.

CONTEXT MISSING
El agente no recibio un archivo necesario.
El modelo no debe adivinar contenido faltante.

Usa C cuando este disponible para copiar el detalle completo.""",
        ),
        "shortcuts": (
            "Atajos de teclado",
            """Atajos globales:

F1   Ayuda / Help
F2   Espanol <-> English
R    Refresh cuando corresponde
Q    Salir desde la pantalla principal
Esc  Volver
Left Volver
Right Abrir / Enter

Plan Control:

A    Activate
R    Analysis
W    Writable implementation
G    Quality Gates
F    Final approval
F5   Refresh
C    Copy details
Esc  Back""",
        ),
        "architecture": (
            "Arquitectura de la interfaz",
            """AI Company OS separa presentacion y estado.

La TUI NO es Company OS.

La interfaz consume informacion de:

docs/
tasks/
.codex/state/
handoffs/
ADRs
y otros artefactos definidos por los protocolos del motor.

Separacion:

Presentation
    TUI / CLI
        ->
Application
    services / use cases
        ->
Domain / repositories
        ->
Company OS artifacts

Una futura interfaz web puede reutilizar el mismo nucleo sin
redefinir el funcionamiento de Company OS.""",
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
F2 switches between English and Spanish.""",
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

Repository artifacts remain the source of truth.""",
        ),
        "plans": (
            "Plans / Work Requests",
            """A Work Request is a persistent work request.

You can inspect previous requests, reopen prepared plans,
continue existing execution, inspect associated tasks and delete
only plans that are still safe to delete.

Reopening a Work Request must not recreate it or lose history.""",
        ),
        "plan-control": (
            "Plan Control",
            """Plan Control is the operational center of a Work Request.

A - Activate
R - Analysis
W - Writable implementation
G - Quality Gates
F - Final approval
F5 - Refresh
C - Copy details
Esc - Back

Canonical task states remain unchanged.""",
        ),
        "tasks": (
            "Tasks",
            """Tasks displays canonical work defined under `tasks/`.

Internal values such as ACTIVE, BLOCKED or REVIEW remain exactly
the same regardless of interface language.""",
        ),
        "agents": (
            "Agents",
            """Agents displays the AI Company OS organization.

Organizational state and runtime state are separate.
An assigned task does not necessarily mean a live process exists.""",
        ),
        "providers": (
            "Providers",
            """Providers displays providers exposed by the core.

The UI does not decide which providers exist.
ProviderService is authoritative for availability/configuration.

OpenRouter and Gemini currently expose credential inputs.

DeepSeek, Grok / xAI and Ollama can be added without redesigning
the provider table once the core exposes them.

Ollama should be treated as a local provider, not as an API key.

FREE does not mean unlimited.""",
        ),
        "quality-gates": (
            "Quality Gates",
            """REVIEW, QA and SECURITY validate work independently.

A technically successful execution does not automatically mean
the gate approved the work.

Inspect the canonical outcome:
APPROVE, CHANGES_REQUIRED, PASS, FAIL, etc.""",
        ),
        "statuses": (
            "States and results",
            """Process completion and task success are separate concepts.

A runner may finish successfully while the canonical task status
is BLOCKED. The TUI must display canonical state.""",
        ),
        "security": (
            "Security",
            """The UI is not the source of truth.

It does not silently redefine states, write to main, merge, push
or deploy without authorization.

Writable execution uses isolated worktrees.""",
        ),
        "troubleshooting": (
            "Troubleshooting",
            """Inspect canonical task results and blockers.

Use Providers for credential availability.

Writable work requires a registered worktree.

Use C where available to copy complete execution details.""",
        ),
        "shortcuts": (
            "Keyboard shortcuts",
            """Global:

F1    Help
F2    English <-> Spanish
R     Refresh where applicable
Q     Quit from main screen
Esc   Back
Left  Back
Right Open / Enter

Plan Control:

A     Activate
R     Analysis
W     Writable implementation
G     Quality Gates
F     Final approval
F5    Refresh
C     Copy details""",
        ),
        "architecture": (
            "Interface architecture",
            """The TUI is presentation, not Company OS itself.

Presentation
    TUI / CLI
        ->
Application
    services / use cases
        ->
Domain / repositories
        ->
Company OS artifacts""",
        ),
    },
}


UI_TEXT = {
    "es": {
        "back": "Atras",
        "open": "Abrir",
        "select": "Seleccionar",
        "refresh": "Actualizar",
        "quit": "Salir",
        "yes": "SI",
        "no": "NO",

        "task": "Tarea",
        "tasks": "Tareas",
        "agent": "Agente",
        "agents": "Agentes",
        "title": "Titulo",
        "status": "Estado",
        "priority": "Prioridad",
        "owner": "Responsable",
        "workflow_phase": "Fase del workflow",
        "created": "Creado",
        "updated": "Actualizado",
        "objective": "Objetivo",
        "dependencies": "Dependencias",
        "evidence": "Evidencia",
        "source": "Fuente",
        "none": "Ninguna",

        "runtime": "Runtime",
        "execution": "Ejecucion",
        "waiting_for": "Esperando",
        "waiting": "En espera",
        "can_advance": "Puede avanzar ahora",
        "dependency_dag": "DAG de dependencias",
        "time": "Hora",
        "kind": "Tipo",
        "activity": "Actividad",
        "from": "Desde",
        "to": "Hacia",
        "state": "Estado",
        "message": "Mensaje",
        "property": "Propiedad",
        "value": "Valor",
        "available": "Disponible",
        "events": "Eventos",
        "parsed_events": "Eventos procesados",
        "authoritative_live_state": "Estado live autoritativo",
        "runtime_status": "Estado del runtime",
        "reason": "Motivo",
        "gate": "Gate",
        "stale": "Desactualizado",
        "severity": "Severidad",
        "code": "Codigo",
        "work_state": "Estado de trabajo",
        "runtime_state": "Estado runtime",
        "current_tasks": "Tareas actuales",

        "tasks_heading": (
            "TAREAS   ARRIBA/ABAJO Seleccionar   "
            "Derecha/Enter Abrir   Izquierda/Esc Atras"
        ),
        "agents_heading": (
            "AGENTES   ARRIBA/ABAJO Seleccionar   "
            "Derecha/Enter Abrir   Izquierda/Esc Atras"
        ),

        "overview_project": "Proyecto",
        "overview_phase": "Fase",
        "overview_objective": "Objetivo",
        "overview_repository": "Repositorio",
        "overview_task_summary": "Resumen de tareas",
        "overview_count": "Cantidad",
        "derived": "derivada",

        "projects_heading": (
            "PROYECTOS\n"
            "ARRIBA/ABAJO = Seleccionar   "
            "Derecha/Enter = Abrir   "
            "R = Actualizar   Izquierda/Esc = Atras"
        ),
        "projects_enter_path": "O ingresa una ruta local del repositorio:",
        "projects_no_recent": "No hay proyectos recientes.",
        "projects_active": "ACTIVE",
        "projects_active_notify": "Proyecto activo",

        "providers_title": "Proveedores",
        "providers_provider": "Provider",
        "providers_configured": "Configurado",
        "providers_source": "Origen",
        "providers_notes": "Notas",
        "providers_security_note": (
            "Las credenciales se guardan mediante el almacen seguro "
            "del sistema operativo, no dentro del repositorio."
        ),
        "providers_openrouter_placeholder": (
            "OpenRouter API key - Enter para guardar de forma segura"
        ),
        "providers_gemini_placeholder": (
            "Gemini API key - Enter para guardar de forma segura"
        ),
        "providers_configured_notify": "configurado de forma segura",
        "providers_core_note": (
            "La tabla muestra los providers expuestos por ProviderService. "
            "DeepSeek, Grok / xAI y Ollama apareceran cuando el core "
            "exponga soporte para ellos."
        ),

        "workflow_unavailable": "Datos de workflow no disponibles.",
        "no_activity": "No se encontro actividad persistida.",
        "no_handoffs": "No se encontro evidencia de handoffs.",
        "runtime_unavailable": "Informacion de runtime no disponible.",
        "no_blockers": "No hay bloqueos activos.",
        "no_doctor_findings": "Doctor no encontro problemas.",
        "no_diagnostics": "No hay diagnosticos.",
    },

    "en": {
        "back": "Back",
        "open": "Open",
        "select": "Select",
        "refresh": "Refresh",
        "quit": "Quit",
        "yes": "YES",
        "no": "NO",

        "task": "Task",
        "tasks": "Tasks",
        "agent": "Agent",
        "agents": "Agents",
        "title": "Title",
        "status": "Status",
        "priority": "Priority",
        "owner": "Owner",
        "workflow_phase": "Workflow phase",
        "created": "Created",
        "updated": "Updated",
        "objective": "Objective",
        "dependencies": "Dependencies",
        "evidence": "Evidence",
        "source": "Source",
        "none": "None",

        "runtime": "Runtime",
        "execution": "Execution",
        "waiting_for": "Waiting for",
        "waiting": "Waiting",
        "can_advance": "Can advance now",
        "dependency_dag": "Dependency DAG",
        "time": "Time",
        "kind": "Kind",
        "activity": "Activity",
        "from": "From",
        "to": "To",
        "state": "State",
        "message": "Message",
        "property": "Property",
        "value": "Value",
        "available": "Available",
        "events": "Events",
        "parsed_events": "Parsed events",
        "authoritative_live_state": "Authoritative live state",
        "runtime_status": "Runtime status",
        "reason": "Reason",
        "gate": "Gate",
        "stale": "Stale",
        "severity": "Severity",
        "code": "Code",
        "work_state": "Work state",
        "runtime_state": "Runtime state",
        "current_tasks": "Current tasks",

        "tasks_heading": (
            "TASKS   UP/DOWN Select   "
            "Right/Enter Open   Left/Esc Back"
        ),
        "agents_heading": (
            "AGENTS   UP/DOWN Select   "
            "Right/Enter Open   Left/Esc Back"
        ),

        "overview_project": "Project",
        "overview_phase": "Phase",
        "overview_objective": "Objective",
        "overview_repository": "Repository",
        "overview_task_summary": "Task Summary",
        "overview_count": "Count",
        "derived": "derived",

        "projects_heading": (
            "PROJECTS\n"
            "UP/DOWN = Select   "
            "Right/Enter = Open   "
            "R = Refresh   Left/Esc = Back"
        ),
        "projects_enter_path": "Or enter a local repository path:",
        "projects_no_recent": "No recent projects.",
        "projects_active": "ACTIVE",
        "projects_active_notify": "Active project",

        "providers_title": "Providers",
        "providers_provider": "Provider",
        "providers_configured": "Configured",
        "providers_source": "Source",
        "providers_notes": "Notes",
        "providers_security_note": (
            "Keys are stored through the operating system credential "
            "store, not inside the repository."
        ),
        "providers_openrouter_placeholder": (
            "OpenRouter API key - Enter to save securely"
        ),
        "providers_gemini_placeholder": (
            "Gemini API key - Enter to save securely"
        ),
        "providers_configured_notify": "configured securely",
        "providers_core_note": (
            "The table displays providers exposed by ProviderService. "
            "DeepSeek, Grok / xAI and Ollama will appear when the core "
            "exposes support for them."
        ),

        "workflow_unavailable": "Workflow data unavailable.",
        "no_activity": "No persisted activity found.",
        "no_handoffs": "No persisted handoff evidence found.",
        "runtime_unavailable": "Runtime information unavailable.",
        "no_blockers": "No active blockers.",
        "no_doctor_findings": "No doctor findings.",
        "no_diagnostics": "No diagnostics.",
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



SCREEN_TEXT = {
    "es": {
        "command_title": "Centro de Comando",
        "command_current_project": "Proyecto actual",
        "command_intro": (
            "Decile al CEO que resultado queres conseguir. "
            "El CEO propondra una estrategia y construira "
            "una vista previa segura antes de escribir "
            "cualquier cambio en el repositorio."
        ),
        "command_examples_title": "Ejemplos",
        "command_examples": (
            "Ejemplos:\n\n"
            "- Auditar este proyecto para produccion\n"
            "- Corregir el problema de autenticacion\n"
            "- Agregar pagos\n"
            "- Preparar la aplicacion para release"
        ),
        "command_placeholder": (
            "Decile al CEO que queres conseguir..."
        ),

        "proposal_request": "Solicitud",
        "proposal_heading": (
            "Elegi como debe abordar el trabajo AI Company OS\n"
            "ARRIBA/ABAJO = Seleccionar   "
            "Derecha/Enter = Construir plan   "
            "Izquierda/Esc = Atras"
        ),

        "plan_building": "Construyendo plan del CEO...",
        "planning_error": "Error de planificacion",

        "plan_project": "Proyecto",
        "plan_intent": "Intencion",
        "plan_engine_type": "Tipo de engine",
        "plan_strategy": "Estrategia",
        "plan_existing_tasks": "Tareas abiertas existentes",
        "plan_engine_ready": "Engine preparado",

        "plan_proposed_tasks": "Tareas propuestas",
        "plan_key": "Key",
        "plan_wave": "Ola",
        "plan_task": "Tarea",
        "plan_depends_on": "Depende de",
        "plan_execution_wave": "Ola de ejecucion",
        "plan_your_request": "Tu solicitud",
        "plan_repo_inspection": "Inspeccion del repositorio",
        "plan_warnings": "Advertencias",
        "plan_safe_preview": "Vista previa segura",
        "plan_safe_preview_body": (
            "No se creo ningun archivo.\n"
            "Ningun Status de tarea cambio.\n"
            "Ningun agente fue ejecutado.\n\n"
            "R = Ejecutar plan\n"
            "Izquierda/Esc = Atras"
        ),
    },

    "en": {
        "command_title": "Command Center",
        "command_current_project": "Current project",
        "command_intro": (
            "Tell the CEO what result you want. "
            "The CEO will propose an approach and build "
            "a safe execution preview before anything "
            "is written to the repository."
        ),
        "command_examples_title": "Examples",
        "command_examples": (
            "Examples:\n\n"
            "- Audit this project for production\n"
            "- Fix the authentication bug\n"
            "- Add payments\n"
            "- Prepare the application for release"
        ),
        "command_placeholder": (
            "Tell the CEO what you want to achieve..."
        ),

        "proposal_request": "Request",
        "proposal_heading": (
            "Choose how AI Company OS should approach it\n"
            "UP/DOWN = Select   "
            "Right/Enter = Build plan   "
            "Left/Esc = Back"
        ),

        "plan_building": "Building CEO plan...",
        "planning_error": "Planning error",

        "plan_project": "Project",
        "plan_intent": "Intent",
        "plan_engine_type": "Engine type",
        "plan_strategy": "Strategy",
        "plan_existing_tasks": "Existing open tasks",
        "plan_engine_ready": "Engine ready",

        "plan_proposed_tasks": "Proposed Tasks",
        "plan_key": "Key",
        "plan_wave": "Wave",
        "plan_task": "Task",
        "plan_depends_on": "Depends on",
        "plan_execution_wave": "Execution Wave",
        "plan_your_request": "Your request",
        "plan_repo_inspection": "Repository inspection",
        "plan_warnings": "Warnings",
        "plan_safe_preview": "Safe preview",
        "plan_safe_preview_body": (
            "No files have been created.\n"
            "No task status has changed.\n"
            "No agent has been executed.\n\n"
            "R = Run plan\n"
            "Left/Esc = Back"
        ),
    },
}



FLOW_TEXT = {
    "es": {
        "wr_heading": (
            "PLANES / WORK REQUESTS\n"
            "ARRIBA/ABAJO = Seleccionar   "
            "Derecha/Enter = Abrir   "
            "D = Eliminar   R = Actualizar   "
            "Izquierda/Esc = Atras"
        ),
        "wr_no_requests": (
            "No se encontraron Work Requests para este proyecto."
        ),
        "wr_tasks": "Tareas",
        "wr_no_materialized": (
            "Este Work Request todavia no tiene tareas materializadas."
        ),
        "wr_delete_title": "Eliminar Plan",
        "wr_delete_allowed": (
            "Y = ELIMINAR permanentemente\n"
            "Izquierda/Esc = Cancelar"
        ),
        "wr_delete_denied": (
            "Este Work Request no puede eliminarse de forma permanente.\n"
            "Izquierda/Esc = Atras"
        ),
        "wr_deleted": "eliminado",

        "pc_busy": "Hay una operacion en ejecucion.",
        "pc_reactivated": "Reactivadas",
        "pc_no_backlog_ready": (
            "No hay tareas BACKLOG/READY de este plan."
        ),
        "pc_evaluating": (
            "Evaluando readiness del plan y activando "
            "tareas elegibles..."
        ),
        "pc_activated": "Activadas",
        "pc_none": "ninguna",
        "pc_activate_failed": "Fallo ACTIVATE",

        "pc_no_active_analysis": (
            "No hay tareas ACTIVE de este plan."
        ),
        "pc_running_agents": "Ejecutando agentes ACTIVE",
        "pc_run_agents_title": "EJECUTAR AGENTES",
        "pc_agent_batch_finished": "Batch de agentes finalizado",
        "pc_agent_execution_failed": (
            "Fallo la ejecucion de agentes"
        ),

        "pc_no_active_writable": (
            "No hay tareas ACTIVE disponibles para "
            "implementacion writable."
        ),
        "pc_preparing_worktrees": (
            "Preparando Git worktrees aislados"
        ),
        "pc_writable_workspaces": "WORKSPACES WRITABLE",

        "pc_writable_runner_available": (
            "Writable runner: AVAILABLE"
        ),
        "pc_writable_runner_missing": (
            "Writable runner: NOT INSTALLED\n"
            "El workspace esta preparado, pero el engine "
            "todavia no puede ejecutar agentes que escriban codigo."
        ),
        "pc_implementation_complete": "IMPLEMENTACION COMPLETA",
        "pc_writable_blocked": "EJECUCION WRITABLE BLOCKED",
        "pc_execution_unchanged": (
            "EJECUCION FINALIZADA - ESTADO SIN CAMBIOS"
        ),
        "pc_writable_finished": "EJECUCION WRITABLE FINALIZADA",

        "pc_provider": "Provider",
        "pc_model": "Model",
        "pc_outcome": "Outcome",
        "pc_worktree": "Worktree",
        "pc_summary": "Resumen",
        "pc_blocker": "Blocker",
        "pc_recommended_next": "Siguiente recomendado",

        "pc_copy_details": "C = Copiar detalles",
        "pc_return_plan": "F5 = Volver al plan",
        "pc_writable_title": "Ejecucion Writable",
        "pc_writable_blocked_notify": (
            "La ejecucion writable esta BLOCKED."
        ),
        "pc_writable_finished_notify": (
            "La ejecucion writable finalizo."
        ),
        "pc_writable_failed": (
            "Fallo la ejecucion writable"
        ),

        "pc_no_gate_tasks": (
            "No hay tareas pendientes de quality gates."
        ),
        "pc_running_gates": "Ejecutando gates independientes",
        "pc_quality_gates": "QUALITY GATES",
        "pc_gate_batch_finished": "Batch de gates finalizado",
        "pc_no_changes": "sin cambios",
        "pc_gate_failed": "Fallo la ejecucion de gates",

        "pc_no_finalizable": (
            "No hay tareas listas para aprobacion final."
        ),
        "pc_recording_final": (
            "Registrando aprobacion final del CEO"
        ),
        "pc_final_impact": (
            "Estas tareas pasaran a DONE."
        ),
        "pc_final_approval": "APROBACION FINAL",
        "pc_final_failed": "Fallo la aprobacion final",

        "pc_recovery": "Recuperacion",
        "pc_copy_error": "C = Copiar error",
        "pc_no_error": "No hay ningun error para copiar.",
        "pc_error_copied": "Error copiado al portapapeles.",
        "pc_copy_failed": "No se pudo copiar el error",

        "pc_plan_tasks": "Tareas del Plan",
        "pc_count": "Cantidad",
        "pc_controls": "Controles",
        "pc_next_action": "Siguiente accion",
        "pc_next_blocked": (
            "Hay tareas BLOCKED. Revisa el resultado canonico "
            "y el blocker antes de continuar."
        ),
        "pc_next_activate": (
            "Presiona A para activar la siguiente ola elegible."
        ),
        "pc_next_active": (
            "Hay tareas ACTIVE. Usa R para analisis o W para "
            "implementacion writable."
        ),
        "pc_next_gates": (
            "Hay tareas esperando validacion. Presiona G para "
            "ejecutar Review / QA / Security."
        ),
        "pc_next_final": (
            "Hay tareas listas para aprobacion final. "
            "Presiona F para llevarlas a DONE."
        ),
        "pc_next_done": (
            "Todas las tareas de este plan estan DONE."
        ),
        "pc_next_wait": (
            "No hay una accion disponible en este momento. "
            "Revisa estados y dependencias."
        ),
        "pc_project": "Proyecto",
        "pc_work_request": "Work Request",
        "pc_control_title": "Plan Control",

        "pc_activate_control": "A = Activar ola elegible",
        "pc_analysis_control": (
            "R = Ejecutar agente de solo analisis"
        ),
        "pc_writable_control": (
            "W = Ejecutar implementacion writable"
        ),
        "pc_gates_control": (
            "G = Ejecutar gates Review/QA/Security"
        ),
        "pc_final_control": (
            "F = Aprobacion final del CEO -> DONE"
        ),
        "pc_refresh_control": "F5 = Actualizar",
        "pc_back_control": "Izquierda/Esc = Atras",

        "pc_workflow_title": "Workflow",
        "pc_workflow_body": (
            "Lifecycle:\n\n"
            "BACKLOG -> READY -> ACTIVE\n"
            "ACTIVE -> REVIEW\n"
            "REVIEW -> QA\n"
            "QA -> SECURITY\n"
            "SECURITY -> DONE\n\n"
            "Cuando una ola llega a DONE, presiona A otra vez "
            "para activar las tareas dependientes que ahora "
            "sean elegibles."
        ),
    },

    "en": {
        "wr_heading": (
            "PLANS / WORK REQUESTS\n"
            "UP/DOWN = Select   Right/Enter = Open   "
            "D = Delete   R = Refresh   Left/Esc = Back"
        ),
        "wr_no_requests": (
            "No Work Requests found for this project."
        ),
        "wr_tasks": "Tasks",
        "wr_no_materialized": (
            "This Work Request has no materialized tasks yet."
        ),
        "wr_delete_title": "Delete Plan",
        "wr_delete_allowed": (
            "Y = DELETE permanently\n"
            "Left/Esc = Cancel"
        ),
        "wr_delete_denied": (
            "This Work Request cannot be hard-deleted.\n"
            "Left/Esc = Back"
        ),
        "wr_deleted": "deleted",

        "pc_busy": "An operation is currently running.",
        "pc_reactivated": "Reactivated",
        "pc_no_backlog_ready": (
            "No BACKLOG/READY tasks from this plan."
        ),
        "pc_evaluating": (
            "Evaluating scoped readiness and activating "
            "eligible tasks..."
        ),
        "pc_activated": "Activated",
        "pc_none": "none",
        "pc_activate_failed": "ACTIVATE failed",

        "pc_no_active_analysis": (
            "No ACTIVE tasks from this plan."
        ),
        "pc_running_agents": "Running ACTIVE agents",
        "pc_run_agents_title": "RUN AGENTS",
        "pc_agent_batch_finished": "Agent batch finished",
        "pc_agent_execution_failed": "Agent execution failed",

        "pc_no_active_writable": (
            "No ACTIVE tasks are available for writable execution."
        ),
        "pc_preparing_worktrees": (
            "Preparing isolated Git worktrees"
        ),
        "pc_writable_workspaces": "WRITABLE WORKSPACES",

        "pc_writable_runner_available": (
            "Writable runner: AVAILABLE"
        ),
        "pc_writable_runner_missing": (
            "Writable runner: NOT INSTALLED\n"
            "The workspace is ready, but the engine cannot "
            "execute code-writing agents yet."
        ),
        "pc_implementation_complete": "IMPLEMENTATION COMPLETE",
        "pc_writable_blocked": "WRITABLE EXECUTION BLOCKED",
        "pc_execution_unchanged": (
            "EXECUTION FINISHED - STATE UNCHANGED"
        ),
        "pc_writable_finished": "WRITABLE EXECUTION FINISHED",

        "pc_provider": "Provider",
        "pc_model": "Model",
        "pc_outcome": "Outcome",
        "pc_worktree": "Worktree",
        "pc_summary": "Summary",
        "pc_blocker": "Blocker",
        "pc_recommended_next": "Recommended next",

        "pc_copy_details": "C = Copy details",
        "pc_return_plan": "F5 = Return to plan",
        "pc_writable_title": "Writable Execution",
        "pc_writable_blocked_notify": (
            "Writable execution is BLOCKED."
        ),
        "pc_writable_finished_notify": (
            "Writable execution finished."
        ),
        "pc_writable_failed": "Writable execution failed",

        "pc_no_gate_tasks": "No pending gate tasks.",
        "pc_running_gates": "Running independent gates",
        "pc_quality_gates": "QUALITY GATES",
        "pc_gate_batch_finished": "Gate batch finished",
        "pc_no_changes": "no changes",
        "pc_gate_failed": "Gate execution failed",

        "pc_no_finalizable": (
            "No tasks are ready for final approval."
        ),
        "pc_recording_final": (
            "Recording final CEO approval"
        ),
        "pc_final_impact": (
            "This will move these tasks to DONE."
        ),
        "pc_final_approval": "FINAL APPROVAL",
        "pc_final_failed": "Final approval failed",

        "pc_recovery": "Recovery",
        "pc_copy_error": "C = Copy error",
        "pc_no_error": "There is no error to copy.",
        "pc_error_copied": "Error copied to clipboard.",
        "pc_copy_failed": "Could not copy error",

        "pc_plan_tasks": "Plan Tasks",
        "pc_count": "Count",
        "pc_controls": "Controls",
        "pc_next_action": "Next action",
        "pc_next_blocked": (
            "There are BLOCKED tasks. Inspect the canonical "
            "result and blocker before continuing."
        ),
        "pc_next_activate": (
            "Press A to activate the next eligible wave."
        ),
        "pc_next_active": (
            "There are ACTIVE tasks. Use R for analysis or W "
            "for writable implementation."
        ),
        "pc_next_gates": (
            "Tasks are waiting for validation. Press G to run "
            "Review / QA / Security."
        ),
        "pc_next_final": (
            "Tasks are ready for final approval. "
            "Press F to move them to DONE."
        ),
        "pc_next_done": (
            "All tasks in this plan are DONE."
        ),
        "pc_next_wait": (
            "There is no available action right now. "
            "Inspect task states and dependencies."
        ),
        "pc_project": "Project",
        "pc_work_request": "Work Request",
        "pc_control_title": "Plan Control",

        "pc_activate_control": "A = Activate eligible wave",
        "pc_analysis_control": (
            "R = Run analysis-only agent"
        ),
        "pc_writable_control": (
            "W = Run writable implementation"
        ),
        "pc_gates_control": (
            "G = Run Review/QA/Security gates"
        ),
        "pc_final_control": (
            "F = Final CEO approval -> DONE"
        ),
        "pc_refresh_control": "F5 = Refresh",
        "pc_back_control": "Left/Esc = Back",

        "pc_workflow_title": "Workflow",
        "pc_workflow_body": (
            "Lifecycle:\n\n"
            "BACKLOG -> READY -> ACTIVE\n"
            "ACTIVE -> REVIEW\n"
            "REVIEW -> QA\n"
            "QA -> SECURITY\n"
            "SECURITY -> DONE\n\n"
            "When a wave reaches DONE, press A again to activate "
            "newly eligible dependent tasks."
        ),
    },
}



UX_TEXT = {
    "es": {
        "workflow_map_title": "Mapa de ejecucion",
        "workflow_summary_title": "Resumen de ejecucion",
        "workflow_runnable": "Ejecutables ahora",
        "workflow_waiting_tasks": "Esperando dependencias",
        "workflow_blocked_tasks": "Bloqueadas",
        "workflow_done_tasks": "Completadas",
        "workflow_none": "Ninguna",
        "workflow_no_edges": (
            "No hay dependencias entre tareas."
        ),

        "gates_title": "Quality Gates",
        "gates_result": "Resultado canonico",
        "gates_evidence": "Evidencia",
        "gates_current": "CURRENT",
        "gates_stale": "STALE",
        "gates_attention": "Requiere atencion",
        "gates_no_attention": (
            "No hay gates con evidencia STALE."
        ),
        "gates_stale_intro": (
            "Estos gates tienen evidencia STALE:"
        ),
        "gates_interpretation": "Interpretacion",
        "gates_interpretation_body": (
            "Resultado canonico muestra exactamente el estado "
            "expuesto por Company OS.\n\n"
            "CURRENT / STALE indica la vigencia de la evidencia, "
            "no reemplaza ni modifica el resultado del gate.\n\n"
            "La TUI no convierte estos valores en una aprobacion "
            "inventada."
        ),
    },

    "en": {
        "workflow_map_title": "Execution map",
        "workflow_summary_title": "Execution summary",
        "workflow_runnable": "Runnable now",
        "workflow_waiting_tasks": "Waiting on dependencies",
        "workflow_blocked_tasks": "Blocked",
        "workflow_done_tasks": "Completed",
        "workflow_none": "None",
        "workflow_no_edges": (
            "There are no task dependency edges."
        ),

        "gates_title": "Quality Gates",
        "gates_result": "Canonical result",
        "gates_evidence": "Evidence",
        "gates_current": "CURRENT",
        "gates_stale": "STALE",
        "gates_attention": "Needs attention",
        "gates_no_attention": (
            "There are no gates with STALE evidence."
        ),
        "gates_stale_intro": (
            "These gates have STALE evidence:"
        ),
        "gates_interpretation": "Interpretation",
        "gates_interpretation_body": (
            "Canonical result displays exactly the state exposed "
            "by Company OS.\n\n"
            "CURRENT / STALE describes evidence freshness and "
            "does not replace or modify the gate result.\n\n"
            "The TUI does not invent a separate approval state."
        ),
    },
}



PREFS_TEXT = {
    "es": {
        "settings_title": "Configuracion de interfaz",
        "settings_language": "Idioma",
        "settings_file": "Archivo de configuracion",
        "settings_change_language": (
            "F2 cambia el idioma y guarda la preferencia "
            "automaticamente."
        ),
        "settings_scope": (
            "Estas preferencias pertenecen solamente a la interfaz. "
            "No modifican tasks, agentes, providers, workflow ni "
            "artefactos canonicos de Company OS."
        ),

        "providers_kind": "Tipo",
        "providers_cloud": "Cloud",
        "providers_local": "Local",
        "providers_readiness": "Integraciones de providers",
        "providers_visible_core": "VISIBLE EN CORE",
        "providers_waiting_core": "ESPERANDO CORE",
        "providers_auto_policy": (
            "Auto sigue siendo definido por el engine. "
            "La TUI no agrega providers silenciosamente "
            "a la politica de routing."
        ),
        "providers_future_note": (
            "DeepSeek y Grok / xAI tendran configuracion de "
            "credenciales cuando el core exponga un contrato "
            "estable para ellos. Ollama se tratara como provider "
            "local y no como un campo de API key."
        ),
    },

    "en": {
        "settings_title": "Interface settings",
        "settings_language": "Language",
        "settings_file": "Settings file",
        "settings_change_language": (
            "F2 changes language and automatically saves "
            "the preference."
        ),
        "settings_scope": (
            "These preferences belong only to the interface. "
            "They do not modify tasks, agents, providers, workflow "
            "or canonical Company OS artifacts."
        ),

        "providers_kind": "Type",
        "providers_cloud": "Cloud",
        "providers_local": "Local",
        "providers_readiness": "Provider integrations",
        "providers_visible_core": "VISIBLE IN CORE",
        "providers_waiting_core": "WAITING FOR CORE",
        "providers_auto_policy": (
            "Auto remains defined by the engine. "
            "The TUI does not silently add providers "
            "to the routing policy."
        ),
        "providers_future_note": (
            "DeepSeek and Grok / xAI will expose credential "
            "configuration when the core provides a stable "
            "contract. Ollama will be treated as a local provider "
            "rather than an API-key field."
        ),
    },
}



UX3_TEXT = {
    "es": {
        "pc_execution_evidence": "Evidencia de ejecucion",
        "pc_no_execution_evidence": (
            "Todavia no hay resultado o evidencia de ejecucion "
            "registrada para estas tareas."
        ),
        "pc_task_next": "Siguiente",
        "pc_task_blocker": "Blocker",
        "pc_result_details": "Detalles de resultado",
        "pc_result_read_errors": "Errores leyendo resultados",
        "pc_result_recorded": "Registrado",
        "pc_result_missing": "Sin evidencia",
        "pc_task_next_activate": "A - Activar",
        "pc_task_next_execute": "R / W - Ejecutar",
        "pc_task_next_gates": "G - Gates",
        "pc_task_next_final": "F - Aprobar",
        "pc_task_next_blocked": "Revisar blocker",
        "pc_task_next_done": "Completada",

        "agents_view_title": "Visibilidad de agentes",
        "agents_summary": "Resumen de agentes",
        "agents_total": "Agentes",
        "agents_with_tasks": "Con tareas actuales",
        "agents_runtime_distribution": "Estados runtime",
        "agent_work_label": "Trabajo",
        "agent_runtime_label": "Runtime",
        "agent_repository_tasks": "Tareas del repositorio",
        "agent_runtime_evidence": "Evidencia runtime",
        "agent_no_repository_tasks": (
            "No hay tareas del repositorio asignadas a este agente."
        ),
        "agent_runtime_unknown": (
            "Company OS no expone evidencia autoritativa de un proceso "
            "live para este agente. La asignacion de trabajo y el estado "
            "runtime son conceptos separados."
        ),
        "agent_runtime_known": (
            "El estado runtime mostrado es el valor canonico expuesto "
            "por Company OS. La TUI no infiere procesos adicionales."
        ),

        "runtime_overview": "Resumen de runtime",
        "runtime_source_path": "Fuente",
        "runtime_available_label": "Disponible",
        "runtime_events_label": "Eventos",
        "runtime_parsed_label": "Eventos procesados",
        "runtime_live_label": "Estado live autoritativo",
        "runtime_authority": "Autoridad runtime",
        "runtime_authoritative": (
            "Company OS indica que existe estado live autoritativo."
        ),
        "runtime_not_authoritative": (
            "No existe estado live autoritativo. Los estados de agentes "
            "no deben interpretarse como garantia de que haya un proceso "
            "ejecutandose en este instante."
        ),
        "runtime_adapter_message": "Mensaje del runtime",
    },

    "en": {
        "pc_execution_evidence": "Execution evidence",
        "pc_no_execution_evidence": (
            "There is no recorded execution result or evidence "
            "for these tasks yet."
        ),
        "pc_task_next": "Next",
        "pc_task_blocker": "Blocker",
        "pc_result_details": "Result details",
        "pc_result_read_errors": "Result read errors",
        "pc_result_recorded": "Recorded",
        "pc_result_missing": "No evidence",
        "pc_task_next_activate": "A - Activate",
        "pc_task_next_execute": "R / W - Execute",
        "pc_task_next_gates": "G - Gates",
        "pc_task_next_final": "F - Approve",
        "pc_task_next_blocked": "Review blocker",
        "pc_task_next_done": "Completed",

        "agents_view_title": "Agent visibility",
        "agents_summary": "Agent summary",
        "agents_total": "Agents",
        "agents_with_tasks": "With current tasks",
        "agents_runtime_distribution": "Runtime states",
        "agent_work_label": "Work",
        "agent_runtime_label": "Runtime",
        "agent_repository_tasks": "Repository tasks",
        "agent_runtime_evidence": "Runtime evidence",
        "agent_no_repository_tasks": (
            "No repository tasks are assigned to this agent."
        ),
        "agent_runtime_unknown": (
            "Company OS does not expose authoritative live-process "
            "evidence for this agent. Work assignment and runtime "
            "state are separate concepts."
        ),
        "agent_runtime_known": (
            "The runtime state shown is the canonical value exposed "
            "by Company OS. The TUI does not infer extra processes."
        ),

        "runtime_overview": "Runtime overview",
        "runtime_source_path": "Source",
        "runtime_available_label": "Available",
        "runtime_events_label": "Events",
        "runtime_parsed_label": "Parsed events",
        "runtime_live_label": "Authoritative live state",
        "runtime_authority": "Runtime authority",
        "runtime_authoritative": (
            "Company OS reports authoritative live runtime state."
        ),
        "runtime_not_authoritative": (
            "There is no authoritative live runtime state. Agent "
            "states must not be interpreted as proof that a process "
            "is currently running."
        ),
        "runtime_adapter_message": "Runtime message",
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

    if key in UX3_TEXT.get(
        language,
        {},
    ):
        return UX3_TEXT[language][key]


    if key in PREFS_TEXT.get(
        language,
        {},
    ):
        return PREFS_TEXT[language][key]


    if key in UX_TEXT.get(
        language,
        {},
    ):
        return UX_TEXT[language][key]


    if key in FLOW_TEXT.get(
        language,
        {},
    ):
        return FLOW_TEXT[language][key]

    if key in SCREEN_TEXT.get(
        language,
        {},
    ):
        return SCREEN_TEXT[language][key]

    return UI_TEXT[language].get(
        key,
        key,
    )
