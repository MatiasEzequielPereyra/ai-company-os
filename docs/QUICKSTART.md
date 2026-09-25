# AI Company OS — Quick Start

> Guía mínima para pasar de un repositorio existente al primer workflow.

## 1. Instalar sobre un proyecto existente

Desde el repositorio de AI Company OS:

```powershell
.\scripts\install-existing-project.ps1 -TargetProject "C:\ruta\de\mi-proyecto"
```

## 2. Entrar al proyecto e inicializar

```powershell
cd "C:\ruta\de\mi-proyecto"
.\scripts\initialize-project.ps1
```

Revisá los archivos generados bajo `docs/` antes de tratar las detecciones automáticas como decisiones confirmadas.

## 3. Crear y preparar un objetivo

```powershell
.\scripts\orchestrate.ps1 `
  -Objective "Describir claramente el cambio que quiero realizar" `
  -Type FEATURE `
  -Priority P1
```

Esto prepara Work Request, plan, tasks, readiness y dispatch sin activar tareas automáticamente.

## 4. Revisar las tasks

```powershell
.\scripts\list-tasks.ps1
```

## 5. Activar trabajo elegible

Cuando el plan haya sido revisado:

```powershell
.\scripts\evaluate-readiness.ps1 -Apply
.\scripts\dispatch-ready-tasks.ps1 -Apply
```

## 6. Ejecutar agentes de análisis

```powershell
.\scripts\run-active-agents.ps1
```

Provider explícito:

```powershell
.\scripts\run-active-agents.ps1 -Provider Codex
```

## 7. Validar y sincronizar

```powershell
.\scripts\validate-artifacts.ps1
.\scripts\sync-company-state.ps1
```

## Importante

El runner compartido de agentes es de análisis/read-only. Para cambios de código autorizados y aislados:

```powershell
.\scripts\new-agent-workspace.ps1 -Id AICO-123
```

Readiness no equivale a permiso de modificación, merge o deployment.

Para el manual completo, ver [USER-GUIDE.md](./USER-GUIDE.md).


## 8. Ejecutar gates y cerrar la task

```powershell
.\scripts\run-pending-gates.ps1 -Provider Auto
```

Si Review, QA y Security quedan satisfechos, la task puede permanecer en `SECURITY`.

Eso es esperado: los gates **no realizan la aprobación final**.

Después de revisar la evidencia:

```powershell
.\scripts\finalize-task.ps1 `
  -Id AICO-001 `
  -Decision APPROVE `
  -Verification "Original objective and applicable gates verified"
```

Recién entonces la task puede llegar a:

```text
DONE
```

## 9. Validar estado final

```powershell
.\scripts\sync-company-state.ps1
.\scripts\validate-artifacts.ps1
```

Para una primera instalación completa, seguir [FIRST-RUN-CHECKLIST.md](./FIRST-RUN-CHECKLIST.md).

Para errores, consultar [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

Para parámetros y comandos disponibles, consultar [COMMAND-REFERENCE.md](./COMMAND-REFERENCE.md).
