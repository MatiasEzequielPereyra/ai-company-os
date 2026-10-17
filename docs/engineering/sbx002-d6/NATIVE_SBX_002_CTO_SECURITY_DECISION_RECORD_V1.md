# NATIVE_SBX_002_CTO_SECURITY_DECISION_RECORD_V1

Project: AI_COMPANY_OS. Track: SBX-002. Task: NATIVE-SBX-002-CONTRACT-RECONCILIATION.
Revision: 1, nueva propuesta de decisión técnica; no modifica los originales.
Mode: STRICT_READ_ONLY. Repositorio: MatiasEzequielPereyra/ai-company-os.
Base revalidada: 1b1f15f5a2c3ee58185646221a521be99730a068.

## 1. Autoridad, alcance y estado del registro

La instrucción humana más reciente autoriza revisión documental CTO/Security y este entregable. No autoriza implementación, tests/simulaciones ejecutadas, VM, servicios, merge, writable ni Run A. Se produce un artefacto nuevo fuera del repositorio. Los seis archivos del paquete previo permanecen intactos.

Estado del registro: RESOLUCIONES_TECNICAS_PROPUESTAS_PARA_AUDITORIA. Las decisiones siguientes seleccionan alternativas de diseño y proponen reglas normativas concretas. No se presentan como decisiones canónicas ya aprobadas por la organización. La aceptación condicionada previa de A/B es un antecedente informado por el usuario, no aprobación de DR-1–DR-4.

Autor de síntesis: agente /root, workstream SBX-002. Revisores técnicos convocados por la regla de delegación de AGENTS.md: /root/cto_dr_resolution, en rol de revisión CTO, y /root/broker_security_review, en rol Security. Sus dictámenes realmente recibidos se registran por separado en la sección 12. No son firmas humanas ni sustituyen aceptación canónica. Aprobación humana de estas propuestas: NO_OTORGADA. Firma canónica/institucional CTO: UNKNOWN. Firma canónica/institucional Security: UNKNOWN. Implementación: BLOQUEADA.

Las expresiones DEBE/RECHAZAR de este documento se refieren al diseño propuesto; no a capacidades implementadas. Una prueba especificada no es una prueba ejecutada. No hay certificación operacional por este registro.

## 2. Fuentes completas y trazabilidad

Los cuatro textos completos se leyeron y sus hashes se recalcularon. El ZIP y el manifest se preservan como artefactos históricos de entrega.

| Fuente original, en directorio hermano native-sbx-002-reconciliation-delivery-v1 | Bytes | SHA-256 |
|---|---:|---|
| NATIVE_SANDBOX_P0_CONTRACT_V1.md | 37935 | c4e52cda1b62fa3ed8c9a0196e4ac13954a56d51aa1c53d493f1f2b0ac8a2f2a |
| NATIVE_SANDBOX_P0_CONTRACT_AMENDMENT_V1.md | 18253 | f89c271a4862850102490ab4bcfe559771f8193e2394bc4b30653700cecc6cf7 |
| NATIVE_SBX_002_CONTRACT_RECONCILIATION_ORIGINAL_V1.md | 27434 | 2e3ba034a26c96640c7b537384405b27d24a3f2f5bba7f101618cbf97caa840a |
| NATIVE_SBX_002_SUPPLEMENT_PROPOSED_V0_1.md | 21785 | 7c838da9efb646f0effda5a9e545f059d5fcff41bfafded1efdd30f50bfa9fc7 |
| NATIVE_SBX_002_COMPLETE_DESIGN_DELIVERY_V1.zip | 41909 | 3692d03213a7b93ffa9403cb74470f77bfb261224633cd6ec37b32d2e020484c |
| DELIVERY_MANIFEST_V1.json | 2481 | 6f5e2189729210c70455d3d67aa9ebffcd24da1faef7a22cea09bf136bf910f0 |

Ruta padre absoluta: C:/Users/LA NAVE/.codex/visualizations/2026/10/16/01a1455b-6785-77f1-be93-f6c36bebd7ac/.

Precedencia: P1-01/02/03 modifican sólo sus puntos; el resto de C1–C5 permanece vigente. La aprobación para planificación de esos contratos procede de instrucciones humanas. No se afirma que estén versionados en main. Código de contraste: src/company_os/sandbox/contracts.py, integrado en PR76; shape cerrado de REQUEST_FIELDS/RECEIPT_FIELDS y validate_receipt. Frozen dataclass e isinstance no acreditan validación, identidad ni autorización.

GitHub revalidado en esta tarea:
- main: https://github.com/MatiasEzequielPereyra/ai-company-os/commit/1b1f15f5a2c3ee58185646221a521be99730a068.
- PR76 MERGED: https://github.com/MatiasEzequielPereyra/ai-company-os/pull/76.
- PR75 OPEN/DRAFT, sin merge, head b0ad1d2f1cbcae7597b790af35fbbf8ab9c89688: https://github.com/MatiasEzequielPereyra/ai-company-os/pull/75.

La auditoría de B, su comprobación de cinco archivos y sus límites sobre ZIP/rollout se conservan como afirmaciones de la decisión central recibida. No se atribuye a B una comprobación que no realizó. No se usa evidencia RUN-A para cerrar estos DR.

## 3. Registro de alternativas y selección técnica

| DR | Alternativas | Selección propuesta y justificación | Riesgo/condición de ratificación |
|---|---|---|---|
| DR-1, P1 | A extender V1; B compuesto obligatorio; C V2 monolítico; D sidecar opcional | Seleccionar B. Rechazar A y D en este alcance: A rompe SBX-001; D permite omitir P1. C se difiere por migración innecesaria | CTO/Security deben ratificar la representación como cumplimiento de «añadir al recibo»; formatos, cuotas, retención y consumidor obligatorios |
| DR-2, P1 | A nueva ejecución en todo fallo; B generación g0/g1 y recaptura tras cleanup; C reutilizar VM/VSS/payload; D volver arbitrariamente a PREPARING | Seleccionar B con arista explícita y snapshot_id lógico. Rechazar C/D. A sólo sirve como bloqueo conservador hasta ratificar B | La distinción snapshot lógico/VSS físico es una aclaración propuesta, no inferencia aprobada. Si no se acepta, la excepción no se habilita |
| DR-3, P1 | A último PASS/heartbeat; B polling sin continuidad; C actor+journal+monitor+journal NTFS+commit cercado | Seleccionar C. A/B no cubren cambio/restauración ni carreras de publicación | Atomicidad real entre fuentes canónicas y publicación: UNKNOWN; es dependencia bloqueante, no resuelta con un mutex local |
| DR-4a, P2 | A schema válido equivale a perfil; B perfil exacto registrado/certificado; C recursos menores sin certificar | Seleccionar B, rechazar A/C como garantía operacional | Certificación E1–E5 pendiente; ningún perfil obtiene READY operacional por este análisis |
| DR-4b, P2 | A exit0 equivale a PASS; B un booleano éxito; C tres ejes y proyección total ordenada | Seleccionar C; rechazar A/B | Mapping propuesto en sección 10; evidencia admisible no equivale a aprobación funcional |

Trazabilidad de IDs: DR-4a conserva la materia de perfiles del original; DR-4b formaliza el mapping identificado en original DR-1 y ampliado en suplemento/decisión central DR-4. No se renombra silenciosamente ningún documento anterior.

## 4. DR-1: shapes cerrados del compuesto obligatorio

### 4.1 Reglas de codec y confianza

Cada objeto tiene exactamente las claves enumeradas; todas son obligatorias. Null sólo donde se permite explícitamente. JSON UTF-8 sin BOM, sin claves duplicadas, nonfinite, coerción ni campos adicionales. Los enteros no admiten booleanos/floats. SHA-256 lowercase64 sobre bytes exactos, sin reserialización. UUID canonical lowercase no nil. UTC yyyy-MM-ddTHH:mm:ssZ. Ticks monotónicos enteros uint64 del mismo host_epoch, nunca comparados entre boots. Profundidad máxima de piezas nuevas: 12. Las piezas C1/V1 conservan sus límites propios.

Los nombres de schemas nuevos de esta sección son propuestos, no schemas existentes o registrados. Los codecs semánticos de IDs NTFS/VSS/Git y observaciones reales requieren adaptador certificado; formato lexical acotado no autentica un ID.

Tipos comunes cerrados:

| Tipo | Claves exactas y dominio |
|---|---|
| Identity | repository_id (forma V1), task_id (AICO-dígitos), attempt_id (UUID), execution_id (UUID), snapshot_id (UUID) |
| Ref | sha256 (SHA), bytes (uint64 con tope por tipo). Sin ruta ni URL; resolución por almacén host protegido y digest |
| Cause | code (registro cerrado de esta revisión), event_sequence (uint64>0), observed_tick (uint64), generation (0 o1). El evento original nunca se borra ni se reescribe |
| RetryResolution | cause_event_sequence (uint64>0), retry_commit_sequence (uint64 mayor que cause_event_sequence), from_generation (0), to_generation (1), request_sha256 (SHA); sólo existe tras commit durable del único retry válido |
| Coverage | journal_id (token ASCII1..256), start_cursor (token1..128), end_cursor (token1..128), continuous (bool), range_sha256 (SHA) |
| OutputRef | command_id (token V1), stream (STDOUT o STDERR), artifact (Ref) |
| AuditRef | kind (RESOURCE_INVENTORY, RESOURCE_JOURNAL, AUTHORITY_OBSERVATIONS, INVALIDATIONS, GIT_INVENTORY, WITNESS_TRANSCRIPT), generation (0 o1), phase (INITIAL, RETRY, FINAL, CLEANUP, AUTHORITY), artifact (Ref) |
| Binding | binding_id, principal_sid, authorization_fingerprint, scope_fingerprint, dependencies_fingerprint, worktree_registration_id, image_id, image_sha256, supervisor_sha256, dependency_inventory_sha256, policy_id, policy_sha256, compatibility_profile_id, environment_profile_id |

Binding usa tokens V1 para IDs, SHA para fingerprints/digests y SID canónico validado por adaptador Windows. principal_sid tiene límite256 bytes y no proviene de claims JSON del cliente. Binding lexicalmente válido no reemplaza consulta al lease vivo. Ningún valor desconocido de registro puede aceptarse por coincidir con una expresión regular.

Registro de causas cerrado propuesto: AUTHORIZATION_CHANGED, AUTHORIZATION_EXPIRED, DEPENDENCY_CHANGED, CANONICAL_SOURCE_AMBIGUOUS, AUTHORITY_MONITOR_FAILED, AUTHORITY_MONITOR_STALE, AUTHORITY_JOURNAL_GAP, LEASE_LOST, OWNER_LOST, HOST_RESTARTED, TIME_DISCONTINUITY, SOURCE_CHANGED, GIT_COHERENCE_FAILED, GUEST_RESULT_INVALID, OUTPUT_LIMIT, RESOURCE_LIMIT, OPERATION_FAILED, PREFLIGHT_FAILED, PROFILE_NOT_CERTIFIED, REQUEST_CONFLICT, CANCEL_REQUESTED, DEADLINE_EXCEEDED, PRE_RUN_TRANSPORT_FAILURE, POWER_STATE_UNCONFIRMED, DESTRUCTION_INCOMPLETE, CLEANUP_UNPROVEN, OWNERSHIP_AMBIGUOUS, JOURNAL_UNAVAILABLE, PERSISTENCE_FAILED, RETRY_NOT_ALLOWED, RETENTION_UNCONFIGURED, EVIDENCE_QUOTA, EVIDENCE_ROLLBACK, PUBLICATION_FENCE_UNAVAILABLE. Nuevo código requiere nueva revisión/schema; unknown code no se convierte en éxito. En runtime, un error no clasificable bloquea con OPERATION_FAILED y detalle sensible fuera del mensaje público.

### 4.2 Piezas completas

capture-evidence.v1 tiene exactamente: schema, identity, generation, capture_phase, volume_id, vss_snapshot_id, worktree_file_id, gitdir_file_id, commondir_file_id, git_object_format, candidate_head_oid, candidate_branch, index_sha256, git_metadata_inventory_sha256, snapshot_root_sha256, pre_witness_sha256, captured_witness_sha256, post_witness_sha256, journal_identity_and_coverage, coherence_result.

schema=aico.sandbox.capture-evidence.v1; identity=Identity; generation0..1; capture_phase=INITIAL|RETRY|FINAL. Los IDs físicos son tokens opacos1..256 emitidos por CapturePort, no paths. git_object_format=sha1|sha256 registrado/certificado; candidate_head_oid40/64 lowercase según formato; candidate_branch NFC UTF-8<=1024 bytes además de validación semántica Git confiable. Los hashes son SHA; coverage=Coverage. coherence_result=COHERENT|INCOHERENT|UNPROVEN. Este objeto completo sólo existe cuando se obtuvieron sus campos; ausencia no se rellena con IDs/hashes ficticios. Un intento sin captura completa usa referencia null y rechazo host.

MonitorSummary tiene exactamente: status, first_sequence, last_sequence, observation_count, max_age_ns, max_evaluation_duration_ns, coverage, observations_sha256, invalidations_sha256. status=COMPLETE|UNPROVEN; sequence uint64, count uint32; los máximos son uint64. coverage=Coverage. No hay COMPLETE sin continuidad y transcript íntegro. Para intento sin monitor iniciado, monitor=null, sólo compatible con rechazo. Observación individual se define en DR-3; summaries no sustituyen la procedencia del monitor ni la conservación de su transcript acotado.

ResourceRecord tiene exactamente: resource_operation_id, resource_type, expected_parent_id, reserved_relative_name, ownership_nonce, actual_id, existence, ownership, disposition, observation_sha256. IDs operación/nonce UUID; resource_type=VM|VM_CONFIGURATION|DIFFERENCING_DISK|TEMP_DIRECTORY|VSS|CHANNEL|AUXILIARY_PROCESS; parent y actual_id tokens1..512 o null si todavía no existen/no se conocen; nombre relativo≤180 UTF-16 y validación segura sin paths libres. existence=ABSENT|PRESENT|UNKNOWN; ownership=OWNED|NOT_OWNED|AMBIGUOUS; disposition=NOT_CREATED|REMOVED|PENDING|UNPROVEN. Hash SHA. Conserva operaciones inciertas; NOT_OWNED prohíbe destruir, AMBIGUOUS cuarentena. UNKNOWN no se normaliza a ABSENT.

cleanup-evidence.v1 tiene exactamente: schema, identity, generation, scope, journal_epoch, journal_sequence, started_tick, finished_tick, resources, inventory_sha256, journal_sha256, cleanup_status, causes. schema=aico.sandbox.cleanup-evidence.v1; scope=GENERATION|FINAL_EXECUTION; generation0..1; epoch UUID; sequence>0; finished>=started; resources array0..256 ResourceRecord, único por resource_operation_id; causes array0..64 Cause; cleanup_status=CONFIRMED|UNPROVEN. FINAL_EXECUTION debe cubrir ambas generaciones y la captura final de revalidación, no sólo VM. Un registro UNPROVEN es evidencia de estado/recuperación, nunca recibo terminal admisible.

host-evidence.v1 tiene exactamente: schema, identity, binding, request_sha256, receipt_v1_sha256, cleanup_sha256, initial_capture_sha256, retry_capture_sha256, final_capture_sha256, lifecycle_at_seal, execution_result, resource_state, terminal_outcome, started_untrusted_code, generation, retry_count, retry_resolution, invalidation_latched, causes, monitor, journal_epoch, seal_sequence, sealed_utc.

schema=aico.sandbox.host-evidence.v1; identity=Identity; binding=Binding; hashes SHA salvo receipt y capturas null donde se permite abajo; lifecycle_at_seal=SEALED; resource_state=CLEANUP_CONFIRMED; execution_result=COMPLETED|FAILED|CANCELLED|TIMED_OUT|INVALIDATED; terminal_outcome=ACCEPTED|FAILED|CANCELLED|TIMED_OUT|INVALIDATED; started e invalidation bool; generation/retry_count0..1 y concordantes; retry_resolution=RetryResolution si retry_count1, null si0; causes0..64; monitor=MonitorSummary|null; epoch UUID; sequence>0; UTC. No se permite PENDING en una pieza sellada.

receipt-package.v1 tiene exactamente: schema, package_kind, provenance, identity, broker_epoch, seal_sequence, previous_package_sha256, request, receipt_v1, host_evidence, cleanup, initial_capture, retry_capture, final_capture, outputs, audit_refs, evidence_policy_id, evidence_policy_sha256.

schema=aico.sandbox.receipt-package.v1; package_kind=EXECUTION_EVIDENCE|HOST_TERMINAL; provenance=OPERATIONAL|SIMULATION; Identity; epoch UUID; sequence>0; previous_package_sha256 SHA|null (sólo primer paquete del epoch); request/host_evidence/cleanup son Ref obligatorios; receipt_v1 y las tres capturas Ref|null; outputs0..24 OutputRef únicos por comando/stream; audit_refs0..32 AuditRef; policy ID token V1 y SHA. El consumidor exige referencias de audit que soporten efectivamente las afirmaciones realizadas; permitir array0 no autoriza aceptación sin transcripts necesarios.

Discriminantes obligatorios:
- EXECUTION_EVIDENCE exige V1 real, initial_capture y final_capture coherentes, monitor COMPLETE, cleanup FINAL_EXECUTION CONFIRMED, started_untrusted_code=true, terminal ACCEPTED, result COMPLETED, latch=false y provenance OPERATIONAL para uso real. Si generation1, retry_capture también obligatorio. Todos los comandos y streams completos y exactos. V1 acceptance=ELIGIBLE_FOR_HOST_REVALIDATION; termination=NORMAL; source_integrity=UNCHANGED.
- HOST_TERMINAL exige terminal no ACCEPTED y decisión de rechazo. V1 puede ser null; capturas/monitor pueden ser null si nunca se obtuvieron. Nunca inventar guest_result/source_integrity para encajar en V1. Si existe V1, ha de ser realmente observado y validado, acceptance=REJECTED, outputs sólo su prefijo exacto. Cleanup FINAL_EXECUTION CONFIRMED sigue obligatorio.
- Sin cleanup confirmado no hay paquete sellado de ninguna variante. GetStatus entrega estado/recovery record; GetReceipt devuelve explícitamente NOT_SEALED. Rechazo de preflight sin recursos se registra como REJECTED, no como un falso SEALED/receipt V1.
- provenance es asignado por el backend/almacén y sesión de emisión; no por parámetro del cliente. Etiquetar un objeto OPERATIONAL no eleva un fake. Consumidor real rechaza cualquier origen de simulación aunque haya hashes correctos.

Registros auxiliares cerrados: RejectionRecord={schema,identity,execution_started,execution_result,reason,journal_epoch,sequence,created_utc}, schema=aico.sandbox.rejection-record.v1, execution_started=false, reason=Cause, result según DR-4; no aceptación V1 ni terminal C5 sellado. LiveState={schema,identity,lifecycle_state,execution_result,resource_state,started_untrusted_code,generation,retry_count,retry_resolution,invalidation_latched,causes,journal_epoch,version}, schema=aico.sandbox.live-state.v1; enums y compatibilidad de sección10; retry_resolution tiene la misma nulabilidad que host-evidence. Estos registros no conceden publicación de verificación.

### 4.3 Vinculación, anti-replay y consumidor

Orden acíclico: Hrequest=SHA256(request bytes); Hcapture por captura y Haudit por transcript; Hcleanup=SHA256(cleanup final); Hreceipt=SHA256(V1 real que ya vincula Hrequest y Hcleanup), o null; Hhost=SHA256(host-evidence que referencia esas piezas); Hpackage=SHA256(package exacto que referencia todas las anteriores). Hpackage viaja fuera del índice; no se hashea a sí mismo. Los outputs concuerdan por command_id, tamaño y digest con V1. Todas las referencias de identidad, generation, epoch, cleanup, request y sequence concuerdan o se rechaza.

Ni hashes ni ACL son firma o prueba de frescura. VerifyReceiptPackage es el único gate que puede emitir VerifiedHostEvidence; revalida bytes con SBX-001 y todos los shapes nuevos, completa pertenencia/referencias, procedencia host, head comprometido y mapping DR-4. Un ValidatedReceipt o ValidatedRequest construible públicamente no sustituye esa operación. El consumidor del runner futuro DEBE rechazar V1 aislado como evidencia suficiente. Mientras ese consumidor no exista, integración operacional bloqueada.

TrustedHead={broker_epoch,sequence,package_sha256,journal_commit_sha256} se mantiene mediante commit durable del ledger host, independiente de un paquete importado. Sólo índices comprometidos y alcanzables desde el head reconciliado son candidatos. Índice/paquete huérfano, sequence anterior intentando nueva publicación, epoch ajeno, journal incompleto o replay del mismo execution con distinto digest se rechazan. Misma clave/digest devuelve estado/publicación existente, nunca ejecuta otra vez. Restaurar todo el volumen a una imagen antigua puede restaurar también un head coherente: detección con anchor fuera de ese dominio de rollback es UNKNOWN. Ante restauración/head incierto, cerrar admisión y publicación hasta reconciliar; no se promete resistencia al administrador comprometido ni firma remota inexistente.

### 4.4 Límites y retención elegidos como propuesta nueva

Los límites nuevos siguientes se seleccionan por acotamiento de parsing/almacenamiento y deben ratificarse en política versionada. No son valores extraídos de C1 ni políticas humanas ya aprobadas.

| Pieza | Techo propuesto |
|---|---:|
| Request / receipt V1 | 8 MiB /1 MiB, conservando C1/SBX-001 |
| Package index | 64 KiB |
| host-evidence | 4 MiB |
| Cada capture summary / cleanup | 1 MiB /1 MiB |
| Cada transcript audit | 8 MiB |
| Evidencia total resuelta por ejecución | 128 MiB, incluyendo request, outputs, capturas, audit y metadatos |
| Recursos | 128 por generación, 256 total, incluyendo final validation |
| Generaciones / causas resumen / audit refs | 2 /64 /32 |
| Outputs | 4 MiB combinados/comando;16 MiB total; como C1 |
| Profundidad JSON nueva | 12 |

Overflow invalida/cierra; no descartar campos o eventos silenciosamente. Causes>64 usan resumen y transcript completo dentro de cuota; si no puede conservarse el transcript, no se acepta. No se usa paginación opcional para esconder piezas obligatorias. Cuotas globales de host/tombstones: UNKNOWN; política debe fijarlas antes de READY operacional. No desalojar tombstones o registros de recovery para obtener capacidad. Todo fichero/evidencia resuelto cuenta dentro de cuota de la ejecución, también los externos por digest; nada ilimitado por estar fuera del JSON principal.

Propuesta de retención: evidencia protegida de ejecución 30 días desde seal; controles activos, inventario/journal de ownership y cuarentena sin purga mientras exista obligación de limpieza; luego ventana de30 días desde el cierre final. Payload candidato, VM/VSS y temporales no se retienen como evidencia: se eliminan en cleanup y antes de retry. Tombstone mínimo {identity,owner_sid,request_digest,terminal_digest} durante la vida del registro del broker, sin expiración automática. Datos de tombstone permanecen protegidos y no implican conservar outputs/código. Al agotar cuotas, bloquear admisión, no borrar evidencia obligatoria.

La retención de30d es recomendación técnica, NO aprobación humana de tratamiento/borrado. Restricciones legales, privacidad, hold y responsable organizacional son UNKNOWN. EvidencePolicy cerrado propuesto={schema,policy_id,version,metadata_days,outputs_days,recovery_purge_allowed,tombstone_mode,per_execution_bytes,global_evidence_bytes,global_tombstone_bytes}; schema=aico.sandbox.evidence-policy.v1; version entero positivo; enteros días1..3650; ambas ventanas30 en perfil propuesto; recovery_purge_allowed=false; tombstone_mode=BROKER_LIFETIME; per_execution_bytes=134217728; globales>0 fijados por dueño. Su aprobación vive FUERA de los bytes aprobados en el registro protegido: PolicyApproval={policy_sha256,approval_id,approver_principal,approved_utc,scope,revoked}; SHA, UUID, principal host validado, UTC, scope=EVIDENCE_POLICY, revoked bool. La autoridad del approver la comprueba el registro host; no basta ese objeto. Así no hay ciclo entre digest de política y recibo que aprueba esa misma política. UNKNOWN nunca es valor de wire aceptable: configuración incompleta o sin aprobación bloquea preflight. Ninguna purga se ejecuta por esta propuesta documental.

Precisión de retención/cadena: además del tombstone, conservar en el almacén protegido los índices de paquetes y metadatos mínimos de commit/parent necesarios para demostrar la cadena desde TrustedHead. No requieren conservar payload candidato, outputs ni inventarios completos después de su ventana. Esos índices/checkpoints cuentan en la cuota global de tombstones/anti-replay; agotamiento bloquea admisión. La política no permite aceptar un paquete huérfano ni borrar un ancestro requerido sin checkpoint equivalente aprobado. Procedimiento de compactación/checkpoint y su autenticidad: UNKNOWN; hasta ratificarlo no se compacta ni se presume cadena completa si faltan elementos. Una evidencia antigua cuyas piezas fueron purgadas ya no se acepta para una verificación nueva; el tombstone sólo prueba identidad/consumo histórico.

## 5. DR-2: retry exacto, snapshot lógico y presupuestos

Se propone aclaración explícita: request.snapshot_id identifica candidato/manifiesto lógico inmutable; no el ID físico de la shadow copy. Cada captura INITIAL/RETRY/FINAL registra su propio vss_snapshot_id y witnesses P1-03. Las fuentes no establecen inequívocamente esa semántica; su ratificación canónica sigue UNKNOWN. Si se rechaza, no se habilita la excepción con esa request; se requiere enmienda o nueva ejecución expresamente autorizada.

Única arista adicional propuesta: CLEANUP_VERIFY[g0] -> CAPTURING[g1]. No vuelve directamente a PREPARING, no parte de terminal ni RECOVERING. Es una ampliación explícita sometida a aprobación, no una arista que ya apareciera en C5.

Origen del fallo: PREPARING[g0] o READY[g0], exclusivamente transporte anterior a RUNNING. Ruta de cierre normal/P1-01, STOPPING si VM/proceso existe o puede existir, DESTROYING, CLEANUP_VERIFY. Debe haberse limpiado TODO g0, incluidas VSS, payload temporal, discos y canales. Se puede conservar sólo evidencia acotada y manifiesto original, no payload disfrazado de evidencia.

Guardas conjuntas: retry_count=0; generation=0; ningún START_COMMITTED, RUNNING ni envío de comando; no latencia/ACK incierto respecto a código; propietario/binding/lease/authority/monitor vigentes; ninguna invalidación/restart/gap; request bytes/digest idénticos; cleanup g0 CONFIRMED y durable; full preflight otra vez válido; budgets remanentes positivos y capacidad retenida exclusivamente por esta ejecución. La reserva host/tarea sigue ocupada durante el retry para no entremezclar ejecuciones.

Transacción de la arista: compare expected epoch/version y gate de autoridad; commit durable único que consume retry_count=1, cambia generation=1, registra transición y reserva intención de nueva captura. Después de confirmarlo puede crearse VSS g1. Si la transacción falla antes de efecto no crear. Si el resultado de commit es incierto, no volver a consumir/reintentar: RECOVERING y rechazo. Un crash jamás devuelve retry_count a0 ni reanuda g1.

g1 recaptura fuentes y toda metadata Git del mismo volumen con P1-03; usa VSS y VM nuevas. Exige equality exacta de archivos/digests/manifest congelado y asociación Git/autoridad con witnesses; cambio relevante incluso restaurado o journal discontinuo invalida. No modifica expires/created/snapshot_id lógico ni recompone request con datos nuevos. Capturas físicas y cleanup por generation quedan separados en evidencia.

Prohibidos: retry de comandos; ejecución terminal o ya iniciada; reinicio/suspensión; auth/dependency/lease change; lectura ambigua; timeout; captura/Git incoherente; VSS fallido; límite; perfil incompatible; cleanup incierto; segundo fallo de transporte; incertidumbre sobre envío de código; reset de budgets. En esos casos cerrar y rechazar, no usar la excepción.

Presupuestos conservadores propuestos: captura/exportación de entrada<=120s acumulados entre g0/g1; preparación/arranque<=180s acumulados; comando<=300s y ejecución<=900s; colección<=30s. Expiry y deadlines originales no cambian. first_close_tick se fija una vez; límite automático global<=450s desde ese primer cierre no se reinicia por g1 ni por final validation. Si se reintenta, el tiempo de g1 también consume ese horizonte; no se promete ejecución900s después de consumirlo. No emitir nuevo comando cuyo timeout más reserva conservadora de cierre100s exceda el horizonte restante. Falta de tiempo bloquea el retry o cancela antes del límite; cuotas no autorizan retrasar stop. Esta restricción puede reducir disponibilidad; E5 debe medirla. No se afirma que estas interpretaciones conservadoras fueran ratificadas por el contrato original.

Precisión de causas y generaciones: el commit válido de retry emite RetryResolution para el único Cause PRE_RUN_TRANSPORT_FAILURE de g0. El hecho permanece en causes/journal. Sólo ese hecho queda resuelto como error operacional activo al evaluar g1; no se arrastra como FAILED al intento sano posterior. El consumidor comprueba que causa, generación, request y commit de transición realmente concuerdan. Ningún otro código puede resolverse así. El latch de invalidación y cualquier revocación, reinicio, discontinuidad o fallo no permitido por DR2 permanecen globales al intento y jamás son resueltos por retry. Si falta prueba del commit de resolución, no se elimina la causa activa ni se habilita g1.

Precisión de epoch y450s: first_close_tick y los contadores monotónicos pertenecen a su epoch. Tras reinicio/suspensión no se comparan ticks de boots distintos ni se reinicia un presupuesto450s por defecto. La ejecución queda INVALIDATED y se detiene el ejecutor propio por la vía segura disponible. Si la continuidad/presupuesto restante no puede demostrarse, permanece cuarentena sin nuevos pases automáticos; un operador/recuperador autorizado deberá resolver expresamente esa incertidumbre y un presupuesto de mantenimiento separado, sin permiso de ejecución de candidato. Mecanismo real de continuidad y política de ese mantenimiento: UNKNOWN. El horizonte450s sólo es garantía contractual bajo host operativo y continuidad temporal demostrable.

## 6. Lifecycle completo y obligación de limpiar

Estados C5 exactos: REQUESTED, PREFLIGHT, CAPTURING, PREPARING, READY, RUNNING, COLLECTING, STOPPING, DESTROYING, CLEANUP_VERIFY, REVALIDATING, SEALED, PUBLISHED, REJECTED, QUARANTINED, RECOVERING. No son estados de tareas canónicas.

| Desde | Hacia | Guarda/efecto |
|---|---|---|
| REQUESTED | PREFLIGHT | Principal autenticado e idempotencia resuelta |
| PREFLIGHT | CAPTURING | Todos los checks y autoridad vigentes; reserva capacidad |
| PREFLIGHT | REJECTED | Sin recursos ni intenciones inciertas; razón durable |
| CAPTURING | PREPARING | Captura/manifiesto válidos y coherentes |
| PREPARING | READY | VM privada; INPUT_VERIFIED y aislamiento verificado |
| READY | RUNNING | Evaluación completa, lease, deadline, gates; START_COMMITTED durable antes de código |
| RUNNING | COLLECTING | Comandos finalizados, incluso exit no cero |
| COLLECTING | STOPPING | Resultado recibido o agotada colección |
| Estado con recursos antes de cierre | STOPPING | Cancelación, timeout, error, revocación, pérdida de dueño |
| STOPPING | DESTROYING | Apagado confirmado |
| DESTROYING | CLEANUP_VERIFY | Recursos propios retirados |
| CLEANUP_VERIFY | REVALIDATING | Limpieza confirmada, sin excepción retry |
| CLEANUP_VERIFY | QUARANTINED | Cleanup incompleto o identidad dudosa |
| REVALIDATING | SEALED | Final validation, cleanup final, autoridad, recibo y commit íntegros; aceptación o rechazo |
| SEALED | PUBLISHED | Commit condicional del orquestador, nunca del guest |
| QUARANTINED | RECOVERING | Operador/servicio autorizado |
| RECOVERING | STOPPING | VM propia existente o posiblemente activa |
| RECOVERING | DESTROYING | Ausencia/apagado del ejecutor demostrado, propiedad válida |
| CLEANUP_VERIFY[g0] | CAPTURING[g1] | Sólo DR-2 ratificada y todas sus guardas; máximo una vez |

Ampliaciones P1-01: cualquier fallo sin recursos ni incertidumbre puede terminar REJECTED. Captura parcial sin VM puede ir directo DESTROYING para recursos propios conocidos. Creación de VM incierta requiere RECOVERING/inventario antes de STOPPING. Error STOPPING => QUARANTINED/POWER_STATE_UNCONFIRMED; destrucción incompleta=>DESTRUCTION_INCOMPLETE; ausencia no probada=>CLEANUP_UNPROVEN; propiedad contradictoria=>OWNERSHIP_AMBIGUOUS. Inventario que demuestra ausencia de todos los recursos puede llevar a CLEANUP_VERIFY y REVALIDATING. Reboot de cualquier no terminal=>admisión cerrada, RECOVERING; nunca reanudar código.

Prioridad de la arista genérica de stop: no crea bucle STOPPING->STOPPING ni revive desde DESTROYING/QUARANTINED; los fallos de cierre aplican las rutas de cuarentena P1-01. Omitir STOPPING sólo con ausencia/apagado demostrado, nunca por excepción de consulta. REJECTED no oculta recursos. SEALED/PUBLISHED/REJECTED jamás vuelven RUNNING. Cuarentena nunca acepta evidencia.

### Captura final después de cleanup: recurso real que también debe limpiarse

C4/P1-03 exigen nueva captura coherente DESPUÉS del cleanup de la ejecución. Esa VSS crea un recurso nuevo y vuelve obsoleta la confirmación previa para la ejecución completa. Se propone subfase interna de REVALIDATING: CAPTURE_PENDING -> CAPTURE_CREATED -> CAPTURE_VERIFIED -> CAPTURE_CLEANED -> FINAL_GATE. No son estados C5 nuevos.

Antes de crear VSS final, intención durable con scope FINAL_VALIDATION y resource_state=PARTIAL_CREATION; cleanup anterior no autoriza sellado. Después de comparar, destruir VSS y auxiliares finales y confirmar inventario global de ambas generaciones más final validation. Emitir cleanup FINAL_EXECUTION nuevo. Sólo entonces FINAL_GATE/SEALED. El monitor sigue activo. Ese VSS se registra como capture_phase FINAL; el input snapshot lógico no se reescribe.

Si falla recaptura/coherencia, latch INVALIDATED. Si hay recursos inciertos, rutas de cierre/recovery/quarantine. Si el intento ya está invalidado y todos los recursos se limpiaron, REVALIDATING puede sellar rechazo sin generar una cadena infinita de recapturas. No se repite captura para rehabilitar un intento invalidado. Si falla persistencia del cleanup/receipt final, no SEALED. Esta secuencia es precisión propuesta para conciliar C4 y C5 y requiere revisión explícita.

Cleanup normal:10s apagado solicitado +30s adicionales forzado/confirmación +60s destrucción/comprobación. Cualquier deadline pertinente agotado entra en cuarentena inmediatamente. Recuperación adicional máximo3 pases, esperas5/15/30s, cada pase<=100s, horizonte absoluto<=450s desde primer cierre. No esperar a agotar3 pases para registrar cuarentena. Si el horizonte no alcanza para todos, se detienen antes. Al agotarse: INVALIDATED, QUARANTINED, sin reintentos automáticos y operador. No equivale a eliminación física.

Precisión de capacidad de recursos finales: el máximo256 incluye operaciones de g0/g1 y de validación final. El perfil certificado deberá declarar cuántas plazas de intención/inventario reserva para VSS y auxiliares de final validation; dicho valor real es UNKNOWN hasta certificar el backend. Ninguna creación ordinaria puede consumir esa reserva ni saltarse la cuota128 por generación. Si no se conoce la reserva requerida o falta capacidad, bloquear antes de READY; si se descubre después, invalidar/cerrar en lugar de ampliar límites. La reserva100s de DR2 no promete que recaptura, colección y recuperación siempre quepan: el deadline absoluto prevalece y E5 debe medir viabilidad.

## 7. DR-3: autoridad, persistencia y puntos de linealización

AuthorityObservation cerrado={execution_id,host_epoch,sequence,evaluation_started_ns,evaluation_finished_ns,result,authorization_fingerprint,scope_fingerprint,dependencies_fingerprint,binding_fingerprint,journal_coverage}; result=VALID|INVALID|UNPROVEN; IDs UUID, seq>0; hashes SHA; coverage=Coverage; fin>=inicio. Tiempos monotónicos del epoch. Un resultado UNPROVEN es negativo. Ningún campo null en una observación emitida; si no puede emitirse, watchdog detecta ausencia/fallo.

Nueva evaluación comienza como máximo cada1s y tarda<=1s. Antes de RUNNING, cada comando y aceptación: evaluación completa. Medir edad desde inicio; >3s =>AUTHORITY_MONITOR_STALE; a3s exactos no se aplica ese código aún, pero expiry/resultado negativo sí. heartbeat propietario cada5s; pérdida>=15s=>OWNER_LOST; evento de pérdida de lease/process no espera al heartbeat. Expiry tiene timer independiente y se invalida en expires, sin siguiente polling. Cambios UTC ambiguos/suspensión/reinicio invalidan. Journal NTFS y sus ancestros/entradas pertinentes detectan cambiar/restaurar; gap/ambigüedad es negativo. Canal guest y heartbeat nunca son autoridad.

ExecutionActor único escritor por ejecución y ledger CAS(expected_epoch,expected_version). Las puertas de nuevo comando, resultado y seal consultan el mismo latch irreversible. El watchdog posee canal de stop independiente del actor bloqueado en IO. Cada evento observado tiene secuencia y origen autenticado; un ID/dataclass no acredita origen. Observaciones repetidas, invertidas, ajenas o de otro epoch no actualizan frescura.

Prioridades y persistencia:
1. Revocación/expiry, lease/monitor/journal perdidos, reinicio/discontinuidad o integridad fallida fijan latch en memoria y cierran puertas inmediatamente. INVALIDATED domina toda elegibilidad. Conservar TODAS las causas, sin «restaurar PASS».
2. Intentar registrar invalidación durable y ordenar force-stop inmediatamente; no conceder10s de gracia. Si falla el journal, igualmente detener por canal independiente, cerrar admisión y marcar incertidumbre/recovery. No esperar recuperación de disco para detener. Objetivo: cancelar<=3s desde cambio detectable y confirmar apagado<=2s después. Sin confirmación=>cuarentena inmediata y P1-01.
3. Efectos normales sólo tras intención durable; el Start registra START_COMMITTED antes del primer envío de código. Crash en commit/envío incierto nunca reanuda ni reintenta comandos. Retry consume generation/retry/intención en commit único.
4. Resultados guest son provisionales. Timeout/CANCEL/FAILED se registran aunque una causa superior determine proyección; no pueden revertir latch.
5. Seal y publish sólo cuando todas las guardas y CAS pasan; ninguna respuesta optimista antes de commit/flush confirmado.

Puntos de linealización propuestos:
- Prepare: reserva host/tarea+binding+intención durable comprometida; capacidad1 sin cola.
- Start: START_COMMITTED con token de autoridad vigente y CAS, antes de transmitir comando; un ACK ausente no da permiso de repetir.
- Invalidate: latch cierra puertas en memoria inmediatamente; evento durable confirma orden recuperable. Si no hay durabilidad, no se declara éxito de operación normal ni se omite stop.
- Retry: commit único de arista+consume+g1+intención.
- Seal: commit durable de blobs exactos, índice/TrustedHead y evento SEALED contra epoch/version, autoridad/cursor y latch; no sólo renombrar un archivo. Crash antes de confirmar=>no SEALED; bytes huérfanos se reconcilian, no se aceptan por existir.
- Publish: AuthorityCommitPort valida y consume fencing token sobre task/receipt/dependency/scope versions y package digest dentro del MISMO commit canónico que publica y registra idempotencia. Token opaco resuelto en registro, no autorización autodeclarada ni hash suficiente.

Cada token interno de operación es temporal, de un solo uso y ligado a principal, binding, execution, epoch, versión y operación; el worker lo consume mediante autoridad confiable. La forma pública de C2 no se amplía con un campo que el cliente pueda usar para concederse permiso.

Una mutex del broker no serializa escritores externos de archivos canónicos. La implementación existente de compare-and-commit interproceso que incorpore cambios externos y continuidad NTFS es UNKNOWN. Hasta demostrarla, publication/operational acceptance permanecen bloqueadas. Un check fresco seguido de una escritura independiente deja TOCTOU y se rechaza como solución. El contrato P1-02 tiene latencia de detección acotada en host certificado; no se transforma en promesa de revocación instantánea no detectada. Si se requiere exclusión absoluta frente a cualquier escritor externo, ese requisito adicional y su mecanismo siguen UNKNOWN; no modificar locks Shared/Maintenance por inferencia.

Autoridad negativa observada antes de seal vence a resultado concurrente. Después de seal, una revocación observada antes de publish bloquea publicación; conserva bytes históricos sellados y añade evento de publicación, no los reescribe. El latch y resultado de la ejecución sellada son históricos e inmutables; el evento posterior afecta al permiso de publicar/operar, no reabre el lifecycle ni convierte retrospectivamente su ACCEPTED histórico en INVALIDATED. Publish ya comprometido identifica su momento/fuentes y no concede permiso para operaciones futuras. Un paquete histórico válido no es autorización actual. Los tests fake verifican protocolos de eventos/CAS, no atomicidad Windows ni latencias reales.

Precisión del prefijo acíclico: cleanup.journal_sequence=n identifica exactamente el último evento de observación/ausencia de recursos incluido; cleanup.journal_sha256 cubre los bytes completos del prefijo de journal hasta n, con codec de framing versionado e inmutable. El evento que registra el digest de ese cleanup se añade DESPUÉS de n y no está en su propio hash. Lo mismo aplica a transcripts de captura/monitor. El seal_sequence reservado es posterior; el commit de SEALED/TrustedHead que referencia Hpackage no forma parte retroactiva del journal_sha256 de cleanup. Si otro evento relevante llega antes del seal, revalidar y CAS; nunca ampliar el prefijo implícitamente o rehashear un documento ya sellado. Codec de journal/flush real aún UNKNOWN y sujeto a D5.

## 8. DR-4a: perfiles y estados de preflight

Válido estructuralmente no significa certificado. Registro protegido resuelve exactamente host Windows11 25H2 x64 Pro/Enterprise, hardware y recursos C3, Hyper-V listo/reboot completado, NTFS/VSS local y dependencias offline/imagen/política/canal aprobados. Host anidado, red/SMB y otros sistemas fuera de V1 bloquean según C3. PowerShell5.1/7 exige versiones exactas certificadas; el cliente no depende de equivalencia del módulo Hyper-V.

Los request que estrechan recursos admitidos por SBX-001 no constituyen nuevos perfiles certificados. Perfil sin evidencia E1–E5=>NOT_CERTIFIED, incluso con todos los hashes correctos. UNKNOWN/registro duplicado/incoherente nunca READY. Preflight conserva READY/BLOCKED/BUSY/QUARANTINED/NOT_CERTIFIED como resultados propios, no estados canónicos de tareas. Sin descargas, auto-instalar servicios, auto-habilitar Hyper-V, ampliación de permisos o pertenencia Hyper-V Administrators del cliente.

## 9. Dimensiones y compatibilidad del registro

Tres ejes persistentes independientes:
- lifecycle_state: los16 estados C5 de sección6.
- execution_result: PENDING, COMPLETED, FAILED, CANCELLED, TIMED_OUT, INVALIDATED. Representa resultado del intento, no sólo un proceso; started_untrusted_code distingue rechazo previo sin inventar ejecución.
- resource_state: NONE, PARTIAL_CREATION, PREPARED, POSSIBLY_ACTIVE, POWER_OFF_CONFIRMED, DESTRUCTION_PENDING, CLEANUP_CONFIRMED, QUARANTINED.

terminal_outcome C5 y acceptance V1 son proyecciones adicionales, no ejes sustitutos. NONE sólo con ausencia demostrada y sin intenciones inciertas. QUARANTINED no significa apagado ni cleanup. POSSIBLY_ACTIVE admite incertidumbre. REJECTED no puede coexistir con recursos pendientes/inciertos. SEALED exige result no PENDING y CLEANUP_CONFIRMED; PUBLISHED conserva contenido terminal inmutable. Una VM ausente no permite ignorar VSS/discos/auxiliares. No se agrega resource UNKNOWN: incertidumbre operacional se representa mediante PARTIAL_CREATION/POSSIBLY_ACTIVE mientras se investiga y QUARANTINED al no poder demostrar cierre/propiedad.

La precedencia de resultado al coincidir causas es INVALIDATED > TIMED_OUT > CANCELLED > FAILED > COMPLETED > PENDING. Conservar causa/observación de menor prioridad. COMPLETED sólo significa que terminaron los comandos observados; exit!=0, por sí solo, no causa FAILED ni REJECTED. Fallo operacional del supervisor/lanzamiento es FAILED; source_integrity CHANGED, resultado malformed o fuente/registro incoherente son INVALIDATED. Cancel puede ser legítimo antes del código; no fabricar guest data.

## 10. DR-4b: tabla total normativa propuesta

La tabla se aplica en CUATRO pasos en orden; no es un único first-match sin fase. A valida origen e invariantes; B despacha estados terminales antes de reglas operativas; C reduce causas sólo para no terminales; D decide la acción según lifecycle/subfase exactos. Así «comandos terminados» no devuelve SEALED a COLLECTING y «cleanup todavía no realizado» no pone RUNNING normal en cuarentena. «V1 real» significa dato efectivamente observado y validable; si no existe, no sintetizarlo.

**A — Origen y consistencia.** Un mensaje de cliente con principal/forma/clave incorrectos se rechaza sin mutar el intento de otro propietario. Un guest result malformado ligado a una ejecución propia sí registra GUEST_RESULT_INVALID. Un registro host corrupto, head incierto o combinación imposible cierra gates, conserva datos y activa recovery/cuarentena si hay posibles efectos; nunca fabrica ausencia. Para paquetes históricos de origen válido, toda proyección se evalúa al momento del seal que identifican, no con causas futuras mezcladas.

**B — Terminales primero.**

| Lifecycle exacto | Evento/guarda | Acción | Resultado/recursos/terminal/V1 |
|---|---|---|---|
| PUBLISHED | Cualquier Start/retry o consulta duplicada | Devolver estado o rechazar operación fuera de estado; ninguna reejecución | Todos históricos e inmutables; permiso actual separado |
| REJECTED | Consulta o Start duplicado | Devolver RejectionRecord; ninguna ejecución | Resultado de rechazo, NONE; terminal C5=null, V1=null |
| SEALED | GetStatus/GetReceipt/Start duplicado | Lectura o rechazo de Start; no resellar | Resultado y CLEANUP_CONFIRMED históricos; no reabrir lifecycle |
| SEALED | Publicar y commit condicional D6 válido, autoridad actual válida, digest aún no publicado | Commit idempotente ->PUBLISHED | Contenido histórico inmutable; no aprobación funcional automática |
| SEALED | Publicar sin fence, con autoridad actual negativa o con persistencia incierta | Permanecer SEALED; registrar bloqueo de publicación, reconciliar si commit incierto | No cambiar retrospectivamente resultado/recursos/bytes; ninguna nueva publicación confirmada |

Sólo si lifecycle no es uno de esos tres se continúa con C y D. Registro terminal contradictorio se rechaza en A, no se repara mediante filas no terminales.

**C — Reducción de causas para no terminales.** Primero latch/reinicio/integridad/journal/autoridad =>INVALIDATED; luego deadline=>TIMED_OUT; luego cancel=>CANCELLED; luego error operacional activo=>FAILED; luego todos los comandos efectivamente terminados=>COMPLETED; en otro caso PENDING. Se conserva toda la causalidad. Agotamiento de recuperación o interrupción exige INVALIDATED. El único fallo PRE_RUN_TRANSPORT_FAILURE candidato a retry mantiene PENDING durante cierre de g0 mientras todas las guardas DR2 sigan potencialmente satisfechas; al descartarse la excepción se fija FAILED, salvo causa de prioridad superior. En g1 se excluye como error activo exclusivamente el PRE_RUN_TRANSPORT_FAILURE de g0 vinculado al RetryResolution durable válido de sección5; se conserva el hecho histórico. No se excluyen otras causas ni se resuelve un latch. Nunca disminuir un resultado ya invalidado. El rechazo anterior al código registra started=false aunque el resultado del intento sea FAILED/CANCELLED/TIMED_OUT/INVALIDATED.

**D — Acción para no terminales, primera fila aplicable dentro de esta tabla.** Los predicados comandos terminados, close_failure, final evidence y subfase se derivan del journal host y observaciones de puertos confiables, no de flags del cliente. close_failure significa confirmación de cierre exigida y fallida/agotada o propiedad positivamente ambigua; NO significa que el cleanup futuro todavía no se hizo.

| Prioridad y lifecycle explícito | Guarda | Acción | Resultado y recursos | Terminal C5 / V1 |
|---|---|---|---|---|
| D1 QUARANTINED o RECOVERING | Estado ya registrado | Sólo recuperación autorizada y rutas P1-01; admisión cerrada | Conservados, INVALIDATED si interrupción/agotamiento; recursos inciertos en cuarentena | Ninguno; NOT_SEALED |
| D2 Cualquier no terminal salvo D1 | close_failure o ownership ambiguo confirmado | QUARANTINED y stop independiente si puede haber ejecutor | Causas conservadas; QUARANTINED | Ninguno |
| D3 REQUESTED/PREFLIGHT/CAPTURING/PREPARING/READY | Resultado no PENDING, started=false, ausencia de todo recurso e intención incierta demostrada | REJECTED con razón durable | Resultado C, NONE (historia de recursos no se borra) | null; RejectionRecord, no V1 |
| D4 REQUESTED/PREFLIGHT/CAPTURING/PREPARING/READY/RUNNING/COLLECTING | INVALIDATED, TIMED_OUT, CANCELLED o FAILED con recursos/intenciones pendientes | STOPPING si ejecutor existe/puede existir; si ausencia/apagado demostrado DESTROYING | Resultado C; inventario real | Ninguno hasta cierre |
| D5 REVALIDATING | Causa de fallo/invalidez nueva y recursos finales pendientes | Cierre P1-01; jamás seguir captura para rehabilitar | Resultado C; inventario real | Ninguno hasta cierre |
| D6 REQUESTED/PREFLIGHT | PENDING y sin fallo | Sólo REQUESTED->PREFLIGHT; PREFLIGHT->CAPTURING si todos gates; si no, rechazo/busy sin crear | PENDING, NONE antes de intención | null |
| D7 CAPTURING/PREPARING/READY | PENDING y sin fallo, o retry g1 en su fase correcta | Sólo aristas/guardas sección6; READY->RUNNING requiere Start válido | PENDING; PARTIAL_CREATION/PREPARED/POSSIBLY_ACTIVE según inventario | null |
| D8 RUNNING | PENDING y comandos no terminados | Ejecutar sólo comandos autorizados; no Start nuevo | PENDING, POSSIBLY_ACTIVE | null |
| D9 RUNNING | Comandos terminados y resultado C=COMPLETED | RUNNING->COLLECTING | COMPLETED, inventario real | null, todo provisional |
| D10 COLLECTING | Sin causa superior; resultado recibido o deadline de colección agotado | COLLECTING->STOPPING; colección agotada reduce timeout/fallo según causa antes de cerrar | Resultado C, inventario real | null |
| D11 COLLECTING | Aún esperando resultado dentro del plazo | Permanecer COLLECTING | Resultado provisional, inventario real | null |
| D12 STOPPING/DESTROYING/CLEANUP_VERIFY | Sin close_failure | Avanzar exclusivamente cierre sección6; en CLEANUP_VERIFY sólo arista retry DR2 ratificada puede volver CAPTURING | Resultado C o PENDING de retry; POWER_OFF_CONFIRMED/DESTRUCTION_PENDING/CLEANUP_CONFIRMED según prueba | null |
| D13 REVALIDATING | Subfase CAPTURE_PENDING/CREATED/VERIFIED/CLEANED; resultado COMPLETED no invalidado | Avanzar subfase y cleanup final; nunca seal anticipado | COMPLETED; PARTIAL_CREATION/DESTRUCTION_PENDING/CLEANUP_CONFIRMED según subfase | null |
| D14 REVALIDATING | Subfase FINAL_GATE, final cleanup confirmado, resultado COMPLETED, evidencia completa, sin latch, autoridad y commit válidos | Commit durable SEALED | COMPLETED, CLEANUP_CONFIRMED | ACCEPTED /ELIGIBLE_FOR_HOST_REVALIDATION; EXECUTION_EVIDENCE y V1 real obligatorios |
| D15 REVALIDATING | Subfase FINAL_GATE y resultado COMPLETED, pero evidencia definitiva ausente/incoherente o monitor inválido | Latch INVALIDATED; si hay recursos D5; si cleanup final ya confirmado avanzar a D19 tras preparar rechazo | INVALIDATED; no inferir cleanup | Nunca ACCEPTED ni V1 fabricado |
| D16 REVALIDATING | Resultado FAILED, final cleanup confirmado, identidad/causa verificadas y rechazo íntegro/durable | Commit SEALED rechazo | FAILED, CLEANUP_CONFIRMED | FAILED /REJECTED si V1 real; si no null y HOST_TERMINAL |
| D17 REVALIDATING | Resultado CANCELLED y mismas guardas de rechazo | Commit SEALED rechazo | CANCELLED, CLEANUP_CONFIRMED | CANCELLED /REJECTED o null HOST_TERMINAL |
| D18 REVALIDATING | Resultado TIMED_OUT y mismas guardas de rechazo | Commit SEALED rechazo | TIMED_OUT, CLEANUP_CONFIRMED | TIMED_OUT /REJECTED o null HOST_TERMINAL |
| D19 REVALIDATING | Resultado INVALIDATED y mismas guardas de rechazo | Commit SEALED rechazo, sin recaptura infinita | INVALIDATED, CLEANUP_CONFIRMED | INVALIDATED /REJECTED sólo si V1 real válido; si no null HOST_TERMINAL |
| D20 Resto de combinación/evento no cubierto | Ninguna fila anterior aplicable | Rechazar transición, gate cerrado; investigar/recovery si posible efecto | No inferir ausencia ni éxito; inconsistencia host invalida | Ninguna aceptación |

Una salida PENDING en REVALIDATING sin excepción DR2 válida es inconsistente y cae en D20. Fallo de persistencia de rechazo/seal no cumple D14/D16–D19 y no expone terminal. D1 y D12 no se aplican al RUNNING normal. D9 sólo se aplica a RUNNING; D14/D16–D19 sólo a REVALIDATING; B consume SEALED/PUBLISHED/REJECTED antes de ellas. Cleanup no probado pasa a cuarentena cuando una comprobación obligatoria falló o agotó su plazo, no por estar todavía planificado.

La tabla es una especificación total por partición y rechazo residual, NO un modelo probado. Su enumeración formal de combinaciones y carreras permanece NOT_RUN. Una fuente modificada/control auth alterado nunca se excluye como «sólo control plane». Semántica PASS/FAIL de pruebas, Review/QA/Security y cierre de tarea siguen fuera del resultado ACCEPTED del sandbox.

## 11. Aceptación futura, pruebas y dependencias operacionales

Todas las pruebas de esta sección son ESPECIFICADAS/NOT_RUN. No se creó fixture de ejecución ni se ejecutó simulación/candidato. Verificar archivos/hashes es comprobación documental, no suite de implementación.

| Grupo | Aceptación sintética/adversarial exigida | Evidencia operacional adicional |
|---|---|---|
| DR1-S | Cada shape exacto; campo extra/duplicate/null indebido; límites n/n+1; identidad/digest cruzados; pieza ausente; cuota global; V1 aislado; fake marcado operacional; host-only sin fabricar guest | E1 autenticidad/ACL; E4 journal/head/rollback; consumidor real integrado y política de retención aprobada |
| DR1-R | Purga no toca recovery/tombstones; política faltante bloquea; getreceipt cuarentena NOT_SEALED; restauración head incierto bloquea | Backend durable, anchor/restore procedure y cuotas globales; UNKNOWN hoy |
| DR2-S | Arista exacta g0/g1; commit retry atómico; ninguna acción antes de intención; crash por frontera; IDs físicos nuevos; payload g0 ausente; mismatch recaptura; ningún tercer intento; presupuesto no reset | E2 captura real misma request; E4 crashes; E5 viability de budgets acumulados |
| DR3-S | Scheduler determinista explora Start/invalidar/resultado/seal/publish; invalidación gana; journal falla y watchdog igual detiene; stale>3, eval1/1, force2, heartbeat5/15, expiry exacto; cambio/restauración y gap | E1/E4/E5 prueban canal real, continuidad NTFS, durabilidad y latencias3+2; comparador/commit cross-process real |
| DR4-S | Enumerar producto de16 lifecycle,6 resultados,8 recursos, started/latch/generation; cada combinación tiene única regla o rechazo; nonzero no FAIL automático; null V1 sólo rechazo; UNKNOWN/NOT_CERTIFIED no READY | QA de perfiles exactos, E3 herramientas readonly y E5 recursos |
| Final-Capture | Crear VSS final invalida cleanup previo; fallo en cada subfase; final cleanup cubre todo; no recaptura infinita tras invalidación | E2/E4 recaptura tras VM cleanup y retirada de VSS final |

E1: Hyper-V sockets/VMID/ServiceID, IPC Windows y ACL, cliente remoto/suplantación/guest no admin. Fallo=>bloquear perfil.
E2: NTFS/VSS y metadata Git del mismo volumen, witnesses+journal y final recapture; staged/unstaged, nuevos/borrados, refs packed, hardlink/ADS/EFS/reparse, gitdir externo, alternates, objeto faltante, locks, cambio/restauración y lectura accidental de Git vivo. Fallo=>bloquear backend. No adquirir Maintenance exclusivo sobre Shared ni ejecutar helpers/filtros/configuración del candidato.
E3: Python/Node/npm con fuentes/dependencias readonly y outputs scratch declarados. Fallo=>incompatibilidad; no abrir permisos automáticamente.
E4: Crash/reinicio por transición y por intención/efecto/confirmación, journal incompleto, VM huérfana/homónima ajena, disco bloqueado, VSS residual, monitor perdido y cleanup idempotente. Fallo=>bloquear certificación.
E5: Medir memoria/disco/procesos/CPU/deadlines en versiones exactas PS5.1/7 admitidas y host C3; revocación3+2, heartbeat5/15, budgets120/180/300/900/30 y cierre450. Fallo=>revisar perfil mediante decisión/versionado, sin elevar límites por inferencia.

Dependencias explícitas: D0 SBX-001 datos integrado; D1 adaptador de autoridad/lease vivo; D2 frontal/worker e IPC autenticado; D3 exporter VSS/Git/journal y captura final; D4 imagen/supervisor/transport/tool/runtime readonly; D5 ledger durable, head, cleanup/ownership; D6 consumidor compuesto y commit canónico fenced; D7 certificación E1–E5. SBX-002 puede definir tipos y probar núcleo con puertos fake sólo bajo autorización futura. No crear servicios ni integrar runner/PR75 en este slice por inferencia. PR75 sin merge no se da por integrado.

## 12. Conclusiones separadas de los revisores y aprobaciones

### 12.1 Conclusión técnica CTO

Revisor real de la sesión: agente /root/cto_dr_resolution, convocado en rol de revisión CTO. Leyó las fuentes completas, verificó sus hashes y realizó relectura completa del borrador SHA-256 25ce67f7717da2f9515e0229198bd22303359a1f0cc57d9263d6f1b6ee13b5cd. Luego verificó y revisó los deltas del borrador SHA-256 3ac3be75ea97ab9bb5faf484caa0a9ce47cbf01e703ea336ada89433dc5c93be.

Dictamen técnico recibido: ACCEPTABLE_FOR_ARCHITECTURAL_AUDIT_WITH_CONDITIONS. Avala como propuestas el compuesto obligatorio/host-only rechazo sin guest fabricado, la arista retry con snapshot lógico explícito, actor/invalidación, tabla A/B/C/D y VSS final con nuevo cleanup. Sus cuatro P2 sobre retención/cadena, presupuesto entre epochs, reserva de recursos finales y prefijo de journal fueron tratados documentalmente y comprobados en el delta. También considera resuelto el P2 de causas activas del retry. No identifica nuevo P0/P1 ni P2 adicional en ese delta que impida entregar la propuesta. No afirma viabilidad temporal ni implementación preparada.

Firma institucional/canónica CTO: UNKNOWN. Aprobación humana: NO_OTORGADA. Tests/simulaciones/certificación: NOT_RUN. El dictamen cubre lectura completa25ce67 más delta3ac3be; no se atribuye relectura literal del archivo cuyo hash cambió únicamente al incorporar esta sección de conclusiones.

### 12.2 Conclusión técnica Security

Revisor real de la sesión: agente /root/broker_security_review, convocado en rol Security. Leyó fuentes completas; en el primer borrador señaló P1 por predicados lifecycle demasiado amplios. La relectura del SHA25ce67f7717da2f9515e0229198bd22303359a1f0cc57d9263d6f1b6ee13b5cd cerró documentalmente ese P1 y la circularidad de EvidencePolicy. Conservó un P2: causa g0 de transporte no debía convertirse en error activo de g1. Verificó y revisó el delta SHA3ac3be75ea97ab9bb5faf484caa0a9ce47cbf01e703ea336ada89433dc5c93be, cerrando documentalmente ese P2 mediante Cause.generation y RetryResolution.

Dictamen técnico recibido: ACEPTO_LOS_DELTAS_COMO_PROPUESTA_DE_DISENO_CON_CONDICIONES, manteniendo ACEPTABLE_COMO_DISENO_CON_CONDICIONES de la lectura completa. Sin nuevos defectos bloqueantes identificados en los deltas. Los cinco ajustes P2 de causas, retención, epochs, reserva final y prefijo acíclico son coherentes y conservadores. La conclusión exige mantener las ratificaciones y los UNKNOWN operacionales; no transforma el análisis en evidencia de controles reales.

Firma institucional/canónica Security: UNKNOWN. Aprobación humana: NO_OTORGADA. Tests/simulaciones/certificación: NOT_RUN. La cobertura de bytes es la misma lectura completa25ce67 más delta3ac3be; no se inventa una relectura literal del hash final tras insertar esta sección.

### 12.3 Evidencia de revisión y separación de aprobaciones

Los bytes25ce67 se conservan en REVIEW_BASE_25ce67f7.md y los bytes3ac3be en TECHNICAL_REVIEW_BASE_3ac3be75.md. Los mensajes reales de cada revisor se exportan por separado a CTO_REVIEW_MESSAGES_V1.json y SECURITY_REVIEW_MESSAGES_V1.json, con autor, destinatario, timestamp y contenido del registro local del chat. Se conserva también la interrupción inicial por límite de uso; la revisión continuó tras la instrucción humana «seguir» y sí recibió las conclusiones anteriores. Los mensajes no se presentan como firmas institucionales.

El manifest de entrega comprueba que fuera de esta sección12 el texto técnico final es idéntico al snapshot3ac3be revisado. Actualizar el registro con los dictámenes cambia su hash de entrega y no el contenido técnico revisado. La circularidad de EvidencePolicy y el error P1 de tabla se corrigieron únicamente en este nuevo registro: originales y suplemento previos permanecen intactos.

Aceptación A/B previa: ACCEPTED_WITH_CONDITIONS según decisión central humana; no se convierte en aprobación de estos schemas/valores nuevos. Autorización de implementación, merge, writable y Run A: FALSE. Sandbox P0: OPEN.

## 13. UNKNOWN explícitos, riesgos y siguiente paso

UNKNOWN bloqueantes operacionales: ratificación canónica de DR1–4 y aclaración snapshot lógico; implementación real de AuthorityCommitPort frente a escritores externos; codec/procedencia NTFS/VSS y certificación de perfiles; backend transaccional/flush/anchor ante rollback; cuotas globales y política organizacional de retención/hold; soporte real de consumidor compuesto/host-only rechazado en control plane; rendimiento/deadlines del host. Firma criptográfica remota/gestión de claves no existe en este diseño y no se afirma por un digest. Formato Git desconocido/captura multivolumen sigue bloqueado.

Riesgos residuales: worker/adaptador o administrador comprometido, hipervisor/parser, almacenamiento/host inoperativos, secretos embebidos con nombres inocuos, falsedad semántica de tests, licencias/disponibilidad y escritores Git concurrentes. Ni arquitectura documental ni fake prueban aislamiento real. Ante plataforma que no responde se garantiza la decisión de rechazo/cuarentena, no una eliminación material imposible de confirmar.

Siguiente paso único: CODEX-ORCHESTRATOR A audita este registro completo, los dictámenes técnicos separados y los cambios propuestos frente a los originales; deriva ratificación formal a responsables CTO/Security. No se empieza implementación al entregar.

SKILLS_SELECTED: architecture, code-review.
SKILLS_APPLIED: resolución de alternativas, contratos cerrados, lifecycle y revisión de seguridad por roles técnicos.
SKILL_SOURCES: .agents/skills/architecture/SKILL.md; .agents/skills/code-review/SKILL.md, leídas en worktree native-sbx-001-contract-validators.
SKILL_SELECTION_REASON: diseño técnico y auditoría de autoridad, evidencia, persistencia y recuperación.

IMPLEMENTATION_AUTHORIZED: FALSE. MERGE_AUTHORIZED: FALSE. WRITABLE_ENABLED: FALSE. RUN_EXECUTION_AUTHORIZED: FALSE. REPOSITORY_MUTATIONS: NONE. TESTS: NOT_RUN. NATIVE_SANDBOX_P0: OPEN.
