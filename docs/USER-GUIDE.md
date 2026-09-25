# AI Company OS — Manual de Usuario

> **Versión:** 0.1 (documentación viva)  
> **Estado:** AI Company OS está en desarrollo activo. Este manual documenta únicamente comportamiento verificado en la rama `main` al momento de su redacción.

## 1. Qué es AI Company OS

AI Company OS es un framework de ingeniería **PowerShell-first** que organiza el trabajo de agentes de IA alrededor de un repositorio de software real.

Su objetivo no es reemplazar Git, CI/CD, revisión humana o autorización de producción. Su objetivo es que el trabajo asistido por IA sea:

- durable;
- inspeccionable;
- repetible;
- trazable;
- dividido por responsabilidades;
- sujeto a gates de calidad;
- recuperable entre sesiones.

En lugar de dejar decisiones, tareas y resultados solamente dentro de un chat, AI Company OS los convierte en artefactos del repositorio: Markdown, JSON, scripts y evidencia de ejecución.

## 2. Estado actual del producto

### ✅ Operativo en `main`

Actualmente están implementados y documentados en el repositorio:

- intake y descubrimiento inicial de proyectos;
- Work Requests;
- tareas persistentes `AICO-*.md`;
- estados y dependencias de tareas;
- planificación y materialización de tareas;
- readiness y dispatch;
- ejecución de agentes de análisis;
- routing entre Codex, OpenRouter y Gemini;
- contratos JSON para resultados;
- review, QA y security gates;
- aprobación final;
- perfiles de workflow;
- validación de artefactos;
- telemetría y métricas locales;
- worktrees aislados para trabajo con escritura autorizado;
- smoke tests y prueba end-to-end.

### 🚧 En evolución

- TUI/CLI visual: existen ramas de desarrollo específicas, pero todavía no forman parte estable de `main`.
- Automatización más profunda de merge/reconciliation entre worktrees.
- Simulación y resiliencia avanzada de providers.
- Métricas longitudinales de calidad sobre proyectos reales.
- Flujo completamente autónomo de modificación, merge y release.

Por esta razón, este manual **no presenta AI Company OS como una empresa autónoma terminada**.

## 3. Modelo mental

AI Company OS modela una organización de ingeniería con responsabilidades separadas.

```text
Usuario
  ↓
Work Request
  ↓
CEO / Orchestrator
  ↓
Product / Architecture / Planning
  ↓
Tasks AICO-xxx
  ↓
Execution
  ↓
Review
  ↓
QA
  ↓
Security
  ↓
Final approval
  ↓
DONE
```

El workflow conceptual completo es:

```text
IDEA
→ PRODUCT
→ ARCHITECTURE
→ PLANNING
→ IMPLEMENTATION
→ REVIEW
→ QA
→ SECURITY
→ RELEASE
→ DONE
```

Importante: las fases de proyecto y los estados de ticket son conceptos diferentes.

## 4. Roles

AI Company OS define los siguientes roles:

| Rol | Responsabilidad principal |
|---|---|
| CEO / Orchestrator | Coordina el workflow y mantiene el objetivo global. |
| Product Manager | Define y valida intención de producto, alcance y requisitos. |
| CTO | Define arquitectura, restricciones y decisiones técnicas. |
| Engineering Manager | Convierte trabajo aprobado en tareas ejecutables y coordina dependencias. |
| Backend Engineer | Trabajo de backend dentro del alcance autorizado. |
| Frontend Engineer | Trabajo de frontend dentro del alcance autorizado. |
| DevOps Engineer | Infraestructura, CI/CD y operaciones dentro del alcance autorizado. |
| QA Engineer | Verificación funcional y evidencia de calidad. |
| Security Engineer | Evaluación de seguridad y riesgo. |

Los agentes no deberían tomar decisiones fuera de su autoridad ni inventar requisitos faltantes.

### Identificador especial del Engineering Manager

Actualmente existen dos formas del identificador:

```text
engineering-manager   → Owner de task / archivos de rol / scripts
engineering_manager   → clave del agente en .codex/config.toml
```

Son dos namespaces del mismo rol conceptual. Para metadata de tasks y dispatch se utiliza la forma con guion.

## 5. Estados de una tarea

Los estados canónicos son:

```text
BACKLOG
READY
ACTIVE
REVIEW
QA
SECURITY
DONE
BLOCKED
```

El flujo normal es:

```text
BACKLOG → READY → ACTIVE → REVIEW → QA → SECURITY → DONE
```

`BLOCKED` puede interrumpir el trabajo mientras exista un bloqueo material.

Una tarea fallida en un gate puede volver a `READY` para corrección.

## 6. Prioridades

Las prioridades soportadas son:

- `P0` — crítica;
- `P1` — alta;
- `P2` — normal;
- `P3` — baja.

La prioridad ayuda a ordenar trabajo, pero **no reemplaza dependencias ni autorización**.

## 7. Workflow profiles

El archivo `.codex/workflow-profiles.json` define tres perfiles.

### lightweight

Para trabajo de bajo riesgo y reversible.

Requiere review y QA. Security es condicional.

### standard

Perfil por defecto para trabajo normal de producto.

Requiere review y QA. Security depende del riesgo.

### high-assurance

Para trabajo sensible o release-critical, incluyendo cambios relacionados con autenticación, pagos, datos, infraestructura o seguridad.

Requiere review, QA y security explícito.

Una tarea `high-assurance` no puede satisfacer Security con `NOT_APPLICABLE`.

## 8. Estructura principal del repositorio

```text
ai-company-os/
├── .codex/
│   ├── agents/
│   ├── policies/
│   ├── protocols/
│   ├── state/
│   ├── templates/
│   ├── workflows/
│   ├── provider-config.json
│   └── workflow-profiles.json
├── docs/
│   ├── product/
│   ├── architecture/
│   ├── engineering/
│   ├── operations/
│   └── decisions/
├── schemas/
├── scripts/
├── tasks/
├── AGENTS.md
└── README.md
```

### Fuentes de verdad

- `tasks/AICO-*.md`: estado, owner, prioridad, aceptación, dependencias, evidencia e historial de transición.
- `docs/product/`: requisitos y alcance de producto confirmados.
- `docs/architecture/` y `docs/decisions/`: arquitectura y decisiones aceptadas.
- `docs/engineering/`: planes, dispatch, resultados, reviews, QA, security y handoffs.
- `.codex/state/`: índices derivados. Pueden regenerarse y nunca deben sobreescribir las fuentes anteriores.

## 9. Requisitos

El proyecto está diseñado principalmente para Windows y PowerShell.

Requisitos prácticos:

- Windows PowerShell compatible con los scripts del proyecto;
- Git para repositorios y worktrees;
- un repositorio de software cuando se instala sobre un proyecto existente;
- Codex CLI en `PATH` si se utiliza el provider Codex;
- `OPENROUTER_API_KEY` si se utiliza OpenRouter;
- `GEMINI_API_KEY` si se utiliza Gemini.

No se debe guardar ninguna API key dentro del repositorio.

## 10. Instalar AI Company OS en un proyecto existente

Desde el repositorio de AI Company OS:

```powershell
.\scripts\install-existing-project.ps1 -TargetProject "C:\ruta\de\mi-proyecto"
```

El instalador copia la estructura, scripts, roles, policies, schemas y configuración necesaria.

Luego:

```powershell
cd "C:\ruta\de\mi-proyecto"
.\scripts\initialize-project.ps1
```

`initialize-project.ps1` realiza discovery del repositorio y genera intake de:

- producto;
- arquitectura;
- operaciones;
- ingeniería.

Las detecciones automáticas son evidencia inicial, no decisiones aprobadas.

## 11. Crear un proyecto nuevo administrado por AI Company OS

Desde el repositorio del framework:

```powershell
.\scripts\new-project.ps1 -ProjectName "MiProyecto" -Destination "C:\Proyectos"
```

Después:

```powershell
cd "C:\Proyectos\MiProyecto"
.\scripts\initialize-project.ps1
```

## 12. Crear un Work Request

Un Work Request representa una solicitud de trabajo de alto nivel.

Ejemplo:

```powershell
.\scripts\new-work-request.ps1 `
  -Objective "Agregar recuperación de contraseña" `
  -Type FEATURE `
  -Priority P1
```

Tipos soportados:

```text
FEATURE
BUG
REFACTOR
INFRASTRUCTURE
AUDIT
RELEASE
RESEARCH
DOCUMENTATION
```

El Work Request se almacena bajo:

```text
docs/engineering/work-requests/WR-xxx.md
```

Crear un Work Request **no implica automáticamente autorización para modificar código**.

## 13. Orquestar un objetivo

El orchestrator puede crear o continuar un Work Request, generar el plan, materializar tareas, evaluar readiness, realizar dispatch y sincronizar estado.

### Modo preparación

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Agregar recuperación de contraseña" `
  -Type FEATURE `
  -Priority P1
```

Sin `-Apply`, el orchestrator prepara el trabajo pero no activa tareas READY.

### Modo Apply

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Agregar recuperación de contraseña" `
  -Type FEATURE `
  -Priority P1 `
  -Apply
```

Con `-Apply`, tareas elegibles pueden pasar a `ACTIVE`.

## 14. Crear una tarea manualmente

```powershell
.\scripts\new-task.ps1 `
  -Title "Implement password reset" `
  -Owner backend `
  -Priority P1 `
  -WorkflowProfile standard `
  -Objective "Implementar el flujo backend de recuperación de contraseña"
```

La tarea se crea inicialmente en `BACKLOG`.

## 15. Ver tareas

Todas:

```powershell
.\scripts\list-tasks.ps1
```

Filtradas:

```powershell
.\scripts\list-tasks.ps1 -Status ACTIVE
```

Estados válidos para el filtro:

```text
ALL, BACKLOG, READY, ACTIVE, REVIEW, QA, SECURITY, DONE, BLOCKED
```

## 16. Evaluar readiness y dispatch

```powershell
.\scripts\evaluate-readiness.ps1 -Apply
.\scripts\dispatch-ready-tasks.ps1 -Apply
```

Readiness verifica si el trabajo puede avanzar de acuerdo con dependencias y metadata.

Dispatch prepara el paquete que utilizará el agente responsable.

## 17. Ejecutar agentes

Ejecutar todas las tareas `ACTIVE`:

```powershell
.\scripts\run-active-agents.ps1
```

Elegir provider:

```powershell
.\scripts\run-active-agents.ps1 -Provider Codex
.\scripts\run-active-agents.ps1 -Provider OpenRouter
.\scripts\run-active-agents.ps1 -Provider Gemini
```

También existe `Auto`, que utiliza el orden configurado en `.codex/provider-config.json`.

La configuración actual de `main` prioriza:

```text
Codex → OpenRouter → Gemini
```

### Ejecución paralela

```powershell
.\scripts\run-active-agents.ps1 -Parallel
```

⚠️ El modo paralelo en un checkout compartido está restringido a **análisis/read-only**.

No se debe utilizar como mecanismo para que múltiples agentes editen simultáneamente el mismo árbol de trabajo.

## 18. Providers

### Codex

Requiere Codex CLI disponible en `PATH`.

El adapter incluido ejecuta Codex en modo de inspección y evita utilizar accidentalmente `CODEX_API_KEY` como vía de ejecución paga.

### OpenRouter

Requiere:

```powershell
$env:OPENROUTER_API_KEY = "..."
```

El modelo por defecto actual configurado es:

```text
openrouter/free
```

### Gemini

Requiere:

```powershell
$env:GEMINI_API_KEY = "..."
```

El modelo por defecto actual configurado es:

```text
gemini-3.5-flash-lite
```

Los outputs de providers deben validar contra los contratos JSON locales antes de ser confiados por el workflow.

## 19. Trabajo con escritura y aislamiento

El runner estándar de agentes está diseñado para análisis.

Cuando una tarea recibe autorización explícita para modificar código, se debe utilizar un workspace Git aislado.

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Esto crea:

- una branch `aico/aico-123`;
- un Git worktree separado;
- aislamiento de filesystem entre trabajos.

El worktree **no autoriza** automáticamente:

- merge;
- rebase;
- push;
- deployment;
- cambios destructivos.

Esas acciones requieren autorización separada.

## 20. Gates de calidad

### Review

Una tarea debe estar en `REVIEW`.

Ejemplo:

```powershell
.\scripts\review-task.ps1 `
  -Id AICO-123 `
  -Recommendation APPROVE `
  -Reviewer "engineering-manager" `
  -Verification "Diff and acceptance criteria reviewed"
```

Valores posibles:

```text
APPROVE
CHANGES_REQUIRED
```

`CHANGES_REQUIRED` devuelve trabajo para corrección.

### QA

Una tarea debe estar en `QA`.

```powershell
.\scripts\qa-task.ps1 `
  -Id AICO-123 `
  -Outcome PASS `
  -Evidence "Automated and manual checks passed"
```

Valores:

```text
PASS
FAIL
```

Un `FAIL` devuelve la tarea a `READY`.

### Security

Una tarea debe estar en `SECURITY`.

```powershell
.\scripts\security-task.ps1 `
  -Id AICO-123 `
  -Outcome PASS `
  -Evidence "Security review completed"
```

Valores:

```text
PASS
FAIL
NOT_APPLICABLE
```

`NOT_APPLICABLE` no está permitido para `high-assurance`.

### Aprobación final

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-123 `
  -Decision APPROVE `
  -Verification "Original objective and all applicable gates verified"
```

Para finalizar, QA debe estar en `PASS` y Security debe estar satisfecho de acuerdo con el profile.

## 21. Validación y estado

Validar artefactos:

```powershell
.\scripts\validate-artifacts.ps1
```

Sincronizar estado derivado:

```powershell
.\scripts\sync-company-state.ps1
```

Resumir métricas:

```powershell
.\scripts\summarize-metrics.ps1
```

Las métricas operativas se registran localmente bajo:

```text
.codex/runtime/metrics/events.jsonl
```

## 22. Reglas de seguridad importantes

AI Company OS separa deliberadamente:

```text
Task readiness
≠
Mutation authority
≠
Merge authority
≠
Deployment authority
```

Una tarea `READY` o `ACTIVE` no significa que un agente tenga permiso irrestricto para modificar código o producción.

Reglas principales:

1. No guardar secrets en prompts, logs o repositorio.
2. No permitir múltiples agentes con escritura sobre el mismo checkout.
3. Utilizar worktrees para mutaciones paralelas.
4. No confundir resultado de un agente con aprobación independiente.
5. No declarar evidencia que no exista.
6. No inventar requisitos faltantes.
7. Mantener Git como fuente de verdad para integración de código.

## 23. Qué ocurre cuando falla un provider

Posibles fallos incluyen:

- provider no instalado;
- cuota agotada;
- API key faltante;
- error HTTP transitorio;
- JSON inválido;
- resultado que no cumple el schema;
- contexto insuficiente.

El sistema intenta mantener el fallo dentro del límite del provider y evita aceptar resultados estructuralmente inválidos.

Con `Provider Auto`, el router puede utilizar el orden de providers configurado.

En la rama `main`, OpenRouter y Gemini utilizan actualmente un timeout de 240 segundos por request y hasta 3 intentos para errores transitorios. Esa configuración está implementada en los adapters y todavía no debe confundirse con una propiedad estable `provider_timeout_seconds` en `.codex/provider-config.json`.

## 24. Recuperación entre sesiones

AI Company OS está diseñado para no depender exclusivamente del historial de una conversación.

Antes de continuar una sesión, las fuentes principales son:

```text
.codex/protocols/company-state.md
.codex/state/company-state.md
.codex/state/current-sprint.md
tasks/AICO-*.md
```

La recuperación debe verificar:

- objetivo actual;
- tasks activas;
- dependencias;
- blockers;
- evidencia;
- autorizaciones;
- handoffs.

## 25. Tests

Para ejecutar el smoke suite local:

```powershell
.\test-project\tests\run-all-smoke-tests.ps1
```

La suite incluye una prueba end-to-end determinística que lleva un cambio real por el lifecycle de resultados, review, QA, security y aprobación final.

## 26. TUI / CLI visual

🚧 **En desarrollo.**

El repositorio contiene ramas dedicadas a TUI/CLI, pero esa interfaz todavía no forma parte estable de `main`.

Por esa razón, este manual no publica todavía un comando de instalación o arranque de TUI como interfaz oficial.

Cuando la TUI sea integrada y pase las validaciones E2E, esta sección deberá reemplazarse por un tutorial completo.

## 27. Flujo recomendado para un usuario nuevo

```text
1. Instalar AI Company OS
2. Ejecutar initialize-project
3. Revisar el intake generado
4. Crear un Work Request
5. Generar/orquestar el plan
6. Revisar las AICO tasks
7. Evaluar readiness
8. Hacer dispatch
9. Ejecutar agentes
10. Revisar evidencia
11. Pasar Review
12. Pasar QA
13. Pasar Security cuando corresponda
14. Realizar aprobación final
15. Sincronizar estado
16. Revisar métricas
```

## 28. Glosario

**Agent**  
Rol de IA especializado que ejecuta trabajo dentro de una autoridad definida.

**Work Request (WR)**  
Solicitud de alto nivel que expresa un objetivo.

**Task / AICO Task**  
Unidad durable y trazable de trabajo.

**Owner**  
Rol responsable de una task.

**Evidence**  
Prueba persistida que respalda una acción, verificación o gate.

**Provider**  
Sistema que ejecuta el modelo de IA, por ejemplo Codex, OpenRouter o Gemini.

**Dispatch**  
Preparación del paquete de ejecución para una task.

**Gate**  
Punto de control obligatorio como Review, QA o Security.

**Workflow profile**  
Nivel de assurance aplicable a una tarea.

**Worktree**  
Checkout Git separado que permite aislar trabajo con escritura.

**Derived state**  
Estado regenerable utilizado como índice operativo, no como fuente canónica.

## 29. Estado de esta documentación

Este archivo es una documentación viva.

Regla de mantenimiento:

> Una feature no debe documentarse como estable hasta existir en la rama objetivo y tener comportamiento verificable.

Las funciones experimentales deben permanecer marcadas como `🚧 En desarrollo` hasta su integración.


## 30. Recorrido end-to-end verificado

Para ver cómo un objetivo se convierte en Work Request, planning tasks, engineering backlog y una task atraviesa Review, QA, Security y aprobación final, consultar:

[Recorrido End-to-End](./END-TO-END-WALKTHROUGH.md)

El walkthrough separa explícitamente el comportamiento probado del comportamiento todavía en desarrollo.


## 31. Puntos de decisión humana

AI Company OS automatiza coordinación y validaciones, pero no convierte toda acción en autoridad implícita.

| Acción | Puede automatizarse | Requiere decisión/autorización explícita |
|---|---:|---:|
| Crear intake | Sí | No |
| Crear Work Request | Sí | El objetivo proviene del usuario |
| Generar plan | Sí | No equivale a implementar |
| Evaluar readiness | Sí | No autoriza escritura |
| Dispatch a ACTIVE | Sí | Activa ejecución dentro del contrato de la task |
| Ejecutar análisis con provider | Sí | Consume provider configurado |
| Crear worktree aislado | Sí | No autoriza merge/push/deploy |
| Modificar código | Parcial / en evolución | Sí, alcance de escritura autorizado |
| Review/QA/Security | Sí o manual | Deben producir evidencia independiente |
| Finalizar task | Script asistido | `APPROVE` o `REJECT` explícito |
| Merge/Rebase/Push | No implícito | Sí |
| Deployment | No implícito | Sí |

La regla operativa es:

```text
automatización
≠
autorización
```

## 32. Documentación de apoyo

- [Quick Start](./QUICKSTART.md)
- [First Run Checklist](./FIRST-RUN-CHECKLIST.md)
- [End-to-End Walkthrough](./END-TO-END-WALKTHROUGH.md)
- [Troubleshooting](./TROUBLESHOOTING.md)
- [Command Reference](./COMMAND-REFERENCE.md)
- [FAQ](./FAQ.md)
- [Documentation Status](./DOCUMENTATION-STATUS.md)
