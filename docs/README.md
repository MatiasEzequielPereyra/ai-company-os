# AI Company OS — Documentación

Esta carpeta contiene la documentación pública detallada de AI Company OS.

La regla principal es simple: **la documentación describe el comportamiento que existe en main; no convierte intenciones, ramas históricas o features planeadas en capacidades soportadas.**

## Empezar

1. [Quick Start](./QUICKSTART.md) — instalación y primer flujo.
2. [First Run Checklist](./FIRST-RUN-CHECKLIST.md) — aceptación descartable y mayormente offline.
3. [Manual de Usuario](./USER-GUIDE.md) — conceptos, roles, lifecycle, providers, gates, writable execution y recovery.
4. [Command Reference](./COMMAND-REFERENCE.md) — CLI público y tooling PowerShell avanzado.
5. [Troubleshooting](./TROUBLESHOOTING.md) — diagnóstico por síntomas.

## Operación

- [Provider Runtime](./operations/provider-runtime.md) — autenticación, routing, modelos, timeouts, costos y límites.
- [Hardware-Aware Local Runtime](./operations/local-runtime.md) — detección, perfiles y selección de Ollama.
- [Update and Ownership](./operations/update-ownership.md) — managed-files, preservación, conflictos y alcance real de aico update.
- [End-to-End Walkthrough](./END-TO-END-WALKTHROUGH.md) — del objetivo a planning, ejecución, gates y completion.
- [FAQ](./FAQ.md) — respuestas breves.
- [Documentation Status](./DOCUMENTATION-STATUS.md) — qué está validado, limitado o no establecido.

## Contexto del sistema

- [Project Brief](./PROJECT-BRIEF.md)
- [System Architecture](./architecture/system-architecture.md)
- [Error Intelligence v1 MVP and integration map](./engineering/error-intelligence-v1.md)
- [ADR-001: Error Intelligence local storage](./decisions/ADR-001-error-intelligence-storage.md)
- product/ — requisitos y contexto de producto.
- architecture/ — decisiones y contexto técnico.
- engineering/ — work requests, planes, dispatch, resultados y evidencia.
- operations/ — contexto operativo.

## Documentación pública en la raíz

- [README](../README.md)
- [Security](../SECURITY.md)
- [Contributing](../CONTRIBUTING.md)
- [Changelog](../CHANGELOG.md)
- [License](../LICENSE)

## Fuente de verdad

Orden de autoridad para una afirmación operativa:

1. implementación de main;
2. tests/contracts de main;
3. comportamiento del CLI/runtime;
4. configuración;
5. CI;
6. documentación.

Si código y documentación discrepan, no se debe modificar silenciosamente el producto solo para hacer verdadera la documentación. Primero se documenta el comportamiento real y se registra cualquier gap del producto.

## Plataforma y madurez

AI Company OS es actualmente **Windows-first y pre-beta**.

El CI prueba Windows, Node 20 y Python 3.11/3.12. El paquete declara Node >=20 y Python >=3.11, pero Linux/macOS y todas las versiones posteriores no forman parte de una matriz de compatibilidad probada.

La documentación evita describir el proyecto como production-ready, enterprise-ready, fully autonomous, fully cross-platform o self-healing.

## Historial documental

[DOCUMENTATION-USABILITY-REVIEW.md](./DOCUMENTATION-USABILITY-REVIEW.md) se conserva únicamente como nota histórica. No es fuente de verdad operativa y no debe usarse para recuperar comandos o configuración actuales.
