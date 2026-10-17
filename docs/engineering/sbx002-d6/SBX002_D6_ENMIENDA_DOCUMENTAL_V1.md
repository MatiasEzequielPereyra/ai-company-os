# SBX-002 — sucesor documental mínimo para D6

Project: AI_COMPANY_OS
Revision: 1
Updated: 2026-10-17T15:05:15Z
Updated by: Codex /root, delegado para preparación documental
Status: PREPARED_FOR_REVIEW; NOT_RATIFIED
Predecessor: NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1.md
Predecessor SHA256: 11de899585c2782f480c88243a2f0991731b09841f33183b97a4f7c4f4dd6949

Esta enmienda sucesora modifica sólo tres referencias de identificador del predecesor. Se interpreta junto a sus bytes exactos; no sustituye ni reescribe sus antecedentes de autorización o revisión. No cambia predicados, prioridades, transiciones, permisos ni requisitos operacionales. Su ratificación y la de los bytes definitivos de DR-4b siguen pendientes.

## Cambios normativos propuestos

1. Sección 10, tabla B, guarda de publicación desde SEALED: donde dice `Publicar y commit condicional D6 válido, autoridad actual válida, digest aún no publicado`, debe decir `Publicar y commit condicional DEP-D6 válido, autoridad actual válida, digest aún no publicado`.
2. Sección 10, tabla D, identificador de fila: donde dice `D6 REQUESTED/PREFLIGHT`, debe decir `MAP-D6 REQUESTED/PREFLIGHT`. Se conserva íntegro el resto de esa fila: guardas, acción, resultado, recursos y terminal/V1. Sigue en la misma posición entre D5 y D7.
3. Sección 11, dependencias explícitas: donde dice `D6 consumidor compuesto y commit canónico fenced`, debe decir `DEP-D6 consumidor compuesto y commit canónico fenced`.

`DEP-D6` identifica exclusivamente la dependencia del consumidor compuesto y commit canónico con fencing. `MAP-D6` identifica exclusivamente la fila de mapping para REQUESTED/PREFLIGHT. No existe equivalencia semántica entre ambas etiquetas. Las restantes etiquetas conservan su significado original.

## Invariantes preservadas

Terminales inmutables y despacho B antes de C/D; precedencia INVALIDATED > TIMED_OUT > CANCELLED > FAILED > COMPLETED > PENDING; rechazo residual D20; ninguna aceptación sin cleanup confirmado ni ante incertidumbre; ningún V1 guest fabricado. ACCEPTED del sandbox no aprueba funcionalmente tests ni tareas. Las garantías operacionales permanecen sin certificar.

Verificación: tres localizaciones exactas del predecesor comprobadas y delta limitado a los tres identificadores; ninguna suite, simulación, fixture, proveedor o VM ejecutados. Comparación mecánica acompañante: D6_IDENTIFICADORES.diff. La enmienda no corrige timestamps: el hallazgo previo no reproducido no se reintroduce.

DR-4b: CHANGES_REQUIRED hasta revisión del sucesor; no se marca cerrado por la mera preparación de este archivo.
