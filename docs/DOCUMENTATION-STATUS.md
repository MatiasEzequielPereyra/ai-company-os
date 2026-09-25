# AI Company OS — Documentation Status

> Estado de cobertura de la documentación de usuario.

## Versión documental

```text
Manual: v0.1
Target documentado: main
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
| OpenRouter | Cubierto | User Guide + Troubleshooting |
| Gemini | Cubierto | User Guide + Troubleshooting |
| Auto fallback | Cubierto | FAQ + Troubleshooting |
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
| FAQ | Cubierto | FAQ.md |
| TUI visual | Pendiente | No estable en main |
| Writable autonomous runtime | Parcial | Infraestructura documentada; automatización completa en evolución |
| Merge/reconciliation automático | Pendiente | No tratar como estable |
| Deployment autónomo | No soportado implícitamente | Requiere autoridad externa/expresa |
| Provider timeout configurable por config | Pendiente | main usa valores en adapters; no contrato provider_timeout_seconds |

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

Cuando TUI/writable runtime y cambios de provider que están en ramas de integración lleguen a `main`, revisar como mínimo:

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
