# AI Company OS — Documentation Status

> Estado de cobertura de la documentación de usuario.

## Versión documental

```text
Manual: v0.1
Target documentado: main
Verified runtime baseline: 816404c51c34e0bc3e7c23ab9772a0b4d8be1753
Estado: living documentation / review candidate
```

## Cobertura actual

| Área | Estado documental | Nota |
|---|---|---|
| Qué es AI Company OS | Cubierto | User Guide + README |
| Límites / non-goals | Cubierto | README + User Guide + FAQ |
| Instalación en proyecto existente | Cubierto | Quick Start + User Guide |
| Proyecto nuevo | Cubierto | User Guide + Command Reference |
| Intake | Cubierto | User Guide + First Run |
| Work Requests | Cubierto | User Guide + Walkthrough |
| Planning | Cubierto | Walkthrough |
| AICO tasks | Cubierto | User Guide |
| Prioridades | Cubierto | User Guide |
| Estados | Cubierto | User Guide + FAQ |
| Dependencias | Cubierto | Walkthrough + Troubleshooting |
| Readiness | Cubierto | Quick Start + Troubleshooting |
| Dispatch | Cubierto | User Guide + Walkthrough |
| Providers | Cubierto | User Guide + Troubleshooting |
| Codex | Cubierto | User Guide + FAQ |
| Ollama / local runtime | Cubierto | Quick Start + User Guide + Troubleshooting |
| OpenRouter | Cubierto | User Guide + Troubleshooting |
| Gemini | Cubierto | User Guide + Troubleshooting |
| DeepSeek | Cubierto | User Guide + FAQ |
| Grok / xAI | Cubierto | User Guide + FAQ |
| Auto routing | Cubierto | Local-first por defecto; FAQ + Troubleshooting |
| Agent results | Cubierto | Walkthrough |
| Review | Cubierto | User Guide + Walkthrough |
| QA | Cubierto | User Guide + Walkthrough |
| Security | Cubierto | User Guide + Walkthrough |
| Final approval | Cubierto | Quick Start + First Run |
| Workflow profiles | Cubierto | User Guide |
| Engineering backlog | Cubierto | Walkthrough |
| Implementation authorization | Cubierto | Walkthrough + FAQ |
| Worktrees | Cubierto | User Guide + Troubleshooting |
| Validación de artifacts | Cubierto | Troubleshooting + Command Reference |
| State sync | Cubierto | User Guide + Troubleshooting |
| Métricas | Cubierto | User Guide + Command Reference |
| Encoding recovery | Cubierto | Troubleshooting |
| Smoke tests | Cubierto | User Guide + Troubleshooting |
| E2E real code change | Cubierto | Walkthrough |
| Command reference | Cubierto | COMMAND-REFERENCE.md |
| Actualización del runtime instalado | Cubierto con cautela | Installer no es version-aware; requiere branch + diff |
| FAQ | Cubierto | FAQ.md |
| CLI / TUI `aico` | Cubierto | Integrada en main y distribuida por npm |
| Writable runtime autorizado | Cubierto con límites | Worktree + policy + change-set; merge/push/deploy siguen separados |
| Merge/reconciliation automático | Pendiente | No tratar como estable |
| Deployment autónomo | No soportado implícitamente | Requiere autoridad externa/expresa |
| Provider timeout configurable por config | Pendiente | main usa valores en adapters; no contrato provider_timeout_seconds |
| First-run humano con provider externo | Validado con hallazgos | PM → CTO completado hasta DONE; ver Documentation Usability Review |

## Criterio para actualizar esta tabla

Una capacidad pasa a **Cubierto** como estable cuando:

1. está integrada en la branch documentada;
2. su comportamiento puede verificarse en código/tests;
3. los comandos publicados corresponden al runtime real;
4. sus límites están documentados;
5. no se presenta una branch experimental como contrato general.

## Qué no debe bloquear el desarrollo

La documentación no necesita describir en profundidad una feature que cambia diariamente.

Sí debe actualizarse inmediatamente cuando cambia alguno de estos contratos:

- nombre de comandos;
- parámetros;
- estados;
- transiciones;
- roles;
- source-of-truth;
- providers;
- requisitos de autorización;
- gates;
- artifacts generados;
- comportamiento de instalación;
- seguridad.

## Siguiente actualización prevista

Cuando cambien contratos públicos de CLI, writable runtime, providers o lifecycle en `main`, revisar como mínimo:

```text
README.md
docs/QUICKSTART.md
docs/USER-GUIDE.md
docs/FIRST-RUN-CHECKLIST.md
docs/END-TO-END-WALKTHROUGH.md
docs/TROUBLESHOOTING.md
docs/COMMAND-REFERENCE.md
docs/FAQ.md
```

Después ejecutar nuevamente la revisión de consistencia documental.


## Known runtime limitations discovered during documentation testing

### Review independence for engineering-manager-owned tasks

Current `run-gate-agent.ps1` assigns the `engineering-manager` role to the Review gate.

Therefore, when the original task owner is also `engineering-manager`, independence is not guaranteed **by role identity**.

The documentation does not treat this case as a fully independent review. The First Run demo intentionally uses PM and CTO tasks so the review role differs from the original owner.

Resolving the runtime policy itself requires an explicit architecture/product decision about who should review Engineering Manager-owned work.


## Windows PowerShell 5.1 / UTF-8

Documentación revisada para el caso real de lectura desde Windows PowerShell 5.1. Los Markdown UTF-8 sin BOM pueden verse con caracteres corruptos si se usa `Get-Content` sin `-Encoding UTF8`. La guía de First Run y Quick Start incluyen la instrucción explícita.

## Live first-run validation — 2026-09-29

Se completó un first-run real en un proyecto descartable siguiendo el flujo documentado:

```text
RESEARCH
→ PM
→ Review
→ QA
→ Security
→ final approval
→ CTO
→ Review
→ QA
→ Security
→ final approval
→ DONE
```

Resultado documental:

```text
Lifecycle explicado por el manual: VALIDADO
Dependency unlock PM → CTO: VALIDADO
Final approval separado de Security: VALIDADO
Provider externo real: VALIDADO CON HALLAZGOS
```

Hallazgos de runtime/provider que no deben confundirse con defectos conceptuales del manual:

- el baseline actual permite context packs externos demasiado grandes para algunos modelos;
- `openrouter/free` puede seleccionar un modelo incompatible con el structured-output contract;
- un provider puede responder HTTP correctamente y aun devolver un root JSON `null`;
- AI Company OS rechaza correctamente ese resultado inválido;
- la selección/budget de provider necesita hardening independiente de la documentación.

El manual remite estos casos a Troubleshooting y no intenta convertir el First Run en una sesión de debugging de providers.


## Revalidación contra main actual

El 2026-09-29 se revalidaron los contratos públicos del manual contra:

```text
main @ 816404c51c34e0bc3e7c23ab9772a0b4d8be1753
```

Cambios absorbidos por la documentación:

- instalación global por npm;
- CLI `aico` y `aico shell` como interfaces integradas;
- runtime local-first con Ollama en `Auto`;
- providers Codex, Ollama, OpenRouter, Gemini, DeepSeek y Grok;
- budgets de análisis reducidos/per-role;
- managed-files manifest;
- writable runtime autorizado con worktrees y policy.

El first-run humano con OpenRouter fue realizado sobre el baseline anterior de la rama documental. Sus hallazgos siguen siendo útiles como evidencia de integración, pero no deben interpretarse como una reproducción exacta del routing local-first del `main` actual.
