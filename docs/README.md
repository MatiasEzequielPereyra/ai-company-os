# AI Company OS Documentation

Esta carpeta contiene documentación de producto, arquitectura, ingeniería, operaciones y uso del framework.

## Para usuarios

### 1. Empezar rápido

[QUICKSTART.md](./QUICKSTART.md)

Instalación y primer flujo con el mínimo contexto necesario.

### 2. Manual completo

[USER-GUIDE.md](./USER-GUIDE.md)

Conceptos, roles, states, profiles, providers, gates, aislamiento, seguridad y operación.

### 3. Recorrido end-to-end

[END-TO-END-WALKTHROUGH.md](./END-TO-END-WALKTHROUGH.md)

Explica cómo un objetivo se transforma en Work Request, planning tasks, engineering backlog y lifecycle hasta DONE.

### 4. Primera ejecución controlada

[FIRST-RUN-CHECKLIST.md](./FIRST-RUN-CHECKLIST.md)

Checklist para comprobar que una instalación nueva es comprensible y funcional.

### 5. Problemas y recuperación

[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

Errores de instalación, readiness, providers, gates, artifacts, Git/worktrees, encoding y recuperación de estado.

### 6. Referencia de comandos

[COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md)

Parámetros verificados de los scripts PowerShell principales, con distinción entre comandos seguros, apply, provider, Git y avanzados.

### 7. Preguntas frecuentes

[FAQ.md](./FAQ.md)

Respuestas cortas sobre autonomía, Work Requests, tasks, providers, gates, worktrees y límites del sistema.

### 8. Estado de cobertura

[DOCUMENTATION-STATUS.md](./DOCUMENTATION-STATUS.md)

Matriz de qué está documentado como estable, parcial, pendiente o no soportado implícitamente.

### 9. Revisión de usabilidad

[DOCUMENTATION-USABILITY-REVIEW.md](./DOCUMENTATION-USABILITY-REVIEW.md)

Resultado de la prueba de onboarding v0.1, hallazgos corregidos, CI y limitaciones pendientes.

## Documentación del sistema

- [PROJECT-BRIEF.md](./PROJECT-BRIEF.md) — alcance, visión, usuarios objetivo, restricciones y criterios de éxito.
- [architecture/system-architecture.md](./architecture/system-architecture.md) — arquitectura canónica.
- `product/` — fuentes de producto.
- `architecture/` — arquitectura e intake técnico.
- `engineering/` — planes, results, reviews, QA, security y handoffs.
- `operations/` — operación y observabilidad.

## Orden recomendado para un usuario nuevo

```text
README.md
   ↓
docs/QUICKSTART.md
   ↓
docs/FIRST-RUN-CHECKLIST.md
   ↓
docs/USER-GUIDE.md
   ↓
docs/END-TO-END-WALKTHROUGH.md
   ↓
docs/TROUBLESHOOTING.md
```

## Política de documentación

La documentación distingue cuatro estados:

- **estable** — comportamiento integrado y verificable en la branch documentada;
- **experimental** — existe pero puede cambiar;
- **en desarrollo** — todavía no debe tratarse como contrato de usuario;
- **conceptual** — describe intención/arquitectura, no una capacidad operativa.

Una feature no debe presentarse como estable solo porque existe en una branch.

## Fuente de verdad

Cuando documentación y runtime discrepan:

1. no ocultar la discrepancia;
2. verificar la branch y commit;
3. comprobar scripts/schemas/tests;
4. corregir documentación o implementación;
5. no inventar un comportamiento intermedio.

La documentación es una interfaz del producto y debe mantenerse con el mismo criterio que el código.
