# AI Company OS — Product North Star

Status: Canonical product direction
Product authority owner: Product / Company Orchestrator
Current implementation baseline audited: 2026-10-04
Baseline: origin/main at 6e70d64029526cd65df791ddefc8de0065f3c83a

## Document Authority

This document is the canonical authority for the product-level WHAT, WHO, WHY, and PRODUCT DIRECTION of AI Company OS.

It exists so founders, Product, Engineering, Codex, ChatGPT, Work, future agents, and new collaborators can understand the intended product without reconstructing historical conversations.

This document is intentionally not a technical specification. It does not replace code, schemas, tests, runtime documentation, architecture decisions, or acceptance evidence.

For claims about implemented behavior, **CURRENT** means that the behavior exists in the recorded main baseline and is supported by repository code or evidence. If implementation changes after this baseline, CURRENT claims must be re-audited against main.

For strategic direction, this document may define **DECIDED**, **PLANNED**, and **EXPERIMENTAL** product intent even when that intent is not yet implemented.

Where older high-level product framing conflicts with this document, this document governs product mission and direction. Existing implementation documentation remains authoritative for the exact behavior of the current runtime.

### Current implementation anchor

**Status: CURRENT**

At the recorded baseline, AI Company OS is pre-beta, Windows-first software with a repository-native workflow, durable task/evidence artifacts, lifecycle enforcement, provider routing, isolated writable execution, Review/QA/Security gates, final approval controls, and lightweight local operational telemetry.

The current implementation is not the finished product. It does not establish full cross-platform support, generalized intelligent provider routing, universal paid-spend consent enforcement, automatic merge/deploy/release, or a complete autonomous software company.

## Product Mission

**Status: DECIDED**

AI Company OS should allow a person to give a product or engineering request to a controlled company of AI agents that plans, designs, implements, reviews, tests, and validates the work through a governed lifecycle.

The user should not need to manually coordinate every model, role, chat, retry, gate, or handoff. AI Company OS should organize that complexity while preserving explicit boundaries around mutation, integration, security, and cost.

The product is not defined by a particular user interface or model. Its core identity is the runtime that turns an intent into governed, evidence-backed engineering work.

Conceptually:

~~~text
USER REQUEST
    ↓
PRODUCT / PLANNING
    ↓
TECHNICAL DESIGN
    ↓
ENGINEERING PLAN
    ↓
IMPLEMENTATION
    ↓
REVIEW
    ↓
QA
    ↓
SECURITY
    ↓
DONE
~~~

The exact interfaces and role implementation may evolve. The controlled lifecycle, runtime authority, and evidence model are central product properties.

## Problem We Solve

**Status: DECIDED**

AI-assisted software development often fails because coordination is fragmented rather than because models cannot generate code.

Typical failure modes include:

- product intent trapped in chat history;
- unclear ownership between planning, implementation, review, and validation;
- manual coordination across multiple models or agents;
- work progressing without evidence that required gates passed;
- hidden or confusing provider failures;
- accidental cost exposure;
- unsafe writable parallelism;
- repeated rediscovery of context;
- false success caused by optimistic automation;
- inability to explain why a task is blocked or incomplete.

AI Company OS turns this coordination problem into a durable, inspectable, controlled engineering lifecycle.

## Target Users

**Status: DECIDED**

AI Company OS is especially for people who:

- want to build or change real software with AI assistance;
- do not want to manually orchestrate multiple chats, agents, and models;
- want to use local models, free providers, paid providers, or a combination;
- may not be experts in agent infrastructure;
- want control over execution, source changes, integration, and cost;
- want to open existing projects or create new ones;
- need clear evidence of what the system did, what failed, and what remains;
- value repeatability and recoverability over impressive but unverifiable demos.

The product must not assume that a normal user is an expert in prompting, provider APIs, Git internals, model routing, or agent orchestration.

The product may also serve experienced developers and small teams, but advanced expertise must not be a prerequisite for understanding the core workflow.

## Core Product Promise

**Status: DECIDED for the promise; PLANNED for the complete end-state experience**

The intended experience is:

~~~text
1. Install AI Company OS.
2. Open or create a project.
3. Connect one or more providers/models.
4. Give a request in natural language.
5. AI Company OS:
   - understands the request;
   - plans the work;
   - assigns responsibilities;
   - selects eligible providers/models;
   - implements authorized changes;
   - verifies results;
   - corrects work when appropriate;
   - preserves blockers when work cannot safely continue;
   - reports the outcome and evidence.
6. The user receives completed work or an accurate explanation of why it is not complete.
~~~

The user should not need to choose a provider for every small step. Provider choice should become an implementation detail that the runtime manages within user-defined safety and cost constraints.

DONE must mean that the applicable contracts and gates were actually satisfied. It must not mean that the system ran out of retries or decided to make the workflow look complete.

## Product Experience

### Existing-project and new-project entry

**Status: CURRENT in basic form; PLANNED for the simplified end-state**

The current product can install into an existing repository and can create a managed project. The finished experience should make project selection, initialization, provider setup, and first useful request understandable without requiring users to know internal runtime structure.

### Accessible provider onboarding

**Status: DECIDED direction; PLANNED capability**

The desired provider onboarding experience is approximately:

~~~text
Add Provider
→ API key / endpoint / local runtime
→ Test Connection
→ Discover Models
→ Register Capabilities
→ Ready
~~~

AI Company OS should progressively take responsibility for model discovery, compatibility checks, capability registration, and task assignment.

A normal user should not need to edit multiple JSON files, scripts, or routing tables merely to add a provider.

### Observe, understand, recover

**Status: DECIDED direction; partially CURRENT**

The system should make the lifecycle visible enough that the user can understand what is happening without supervising each internal step.

When intervention is required, the system should explain the blocker and the next available action instead of leaving the user with an ambiguous stalled state.

## Provider-Agnostic Direction

**Status: DECIDED**

AI Company OS is provider-agnostic as a product strategy.

The product must not strategically depend on OpenAI, Codex, Gemini, Ollama, OpenRouter, NVIDIA, OpenCode, DeepSeek, Grok/xAI, or any other single provider or model.

Providers are execution resources behind product contracts. They can differ in capabilities, cost, latency, context limits, availability, and reliability without redefining the product.

**Status: CURRENT**

The current runtime already has a provider boundary and multiple provider adapters. Different workloads and roles can use different configured routing orders. This is evidence of the direction, not proof that full provider abstraction is complete.

## Free-First Direction

**Status: DECIDED**

A central product objective is that a person should be able to use AI Company OS without being forced to pay per-request API fees.

The product should favor, where technically suitable:

- local models;
- providers with genuinely usable free access;
- free tiers;
- free model routes;
- other no-charge options compatible with the required task contract.

Potential examples can include Ollama/local models, OpenRouter free routes, Gemini free-tier availability, OpenCode free models, NVIDIA/NIM developer access, or future providers.

These examples are not permanent commercial guarantees.

Third-party availability, quotas, model names, terms, and pricing can change. Therefore the product must not encode the assumption that a third-party provider will remain free forever.

**Status: CURRENT**

The current baseline already has local-first defaults for general Auto and writable Auto, plus safeguards around some automatic cloud candidates. Those mechanisms are an implementation step toward free-first behavior, not the completed free-first product experience.

## Paid Provider Consent

**Status: DECIDED product invariant**

~~~text
API KEY CONFIGURED
≠
PERMISSION TO SPEND
~~~

Possessing credentials for a paid provider must not be interpreted as authorization to incur cost.

The finished product must require explicit user authorization before AI Company OS intentionally spends money on paid provider execution.

Without that authorization:

~~~text
FREE / LOCAL ELIGIBLE OPTIONS EXHAUSTED
→ FAIL CLOSED
→ EXPLAIN THE LIMITATION
→ DO NOT SPEND
~~~

Silent paid fallback is incompatible with the product.

**Status: CURRENT limitation**

The current runtime contains narrower cost protections, including configuration that prevents some paid providers from entering automatic fallback and free-model allowlisting for writable cloud candidates. Those controls are not equivalent to a universal user-level spend-consent system.

**Status: PLANNED**

Generalized paid-spend authorization must become a first-class product control that is respected consistently by every workload and interface.

## Multi-Provider Intelligence

**Status: DECIDED direction; PLANNED full capability**

With one connected provider, AI Company OS should use that provider for work it can satisfy safely. If the provider cannot satisfy a required contract, the system must report the limitation rather than fabricate success or weaken the contract.

With multiple connected providers, AI Company OS should be able to select the most appropriate eligible resource for each responsibility.

Conceptually:

~~~text
Product / Planning → provider/model A
Technical Design   → provider/model B
Engineering Plan   → provider/model C
Implementation     → provider/model D
Review             → provider/model B
QA                 → provider/model A
Security           → provider/model C
~~~

This mapping is illustrative, not a hardcoded role assignment.

Future selection should be able to consider evidence such as:

- schema success;
- semantic reliability;
- role-specific performance;
- coding ability;
- context limits;
- latency;
- availability;
- cost permission;
- prior failures;
- compatibility with the task and workload.

**Status: CURRENT**

The baseline already supports different routing orders for different workloads and some roles. Those orders are configuration-driven and more limited than the intended capability-aware selection system.

The product must not present a configured fallback order as if it were full intelligent routing.

## Runtime-First Architecture

**Status: DECIDED and aligned with CURRENT architecture**

The runtime is the product core. A user interface is a client of the runtime, not the owner of lifecycle logic.

Conceptually:

~~~text
       TUI
        │
        ▼
     RUNTIME
        ▲
        │
     WEB UI
~~~

The current TUI must not become a second engine, and a future Web UI must not create a parallel implementation of the workflow.

All interfaces should use the same lifecycle, policy, evidence, cost, and authorization rules.

UI implementations may differ. Runtime truth must not.

## Trust and Failure Philosophy

**Status: DECIDED**

AI Company OS prefers:

~~~text
CORRECT FAILURE
>
FALSE SUCCESS
~~~

This is a product identity, not only an engineering preference.

The system must preserve meaningful failures:

- semantic contract violations should fail;
- gate failures should remain failures until resolved;
- provider failure must be visible;
- work may remain READY, ACTIVE, BLOCKED, REVIEW, QA, or SECURITY when that is truthful;
- retries must not erase authoritative evidence;
- a demo must not advance by falsifying state.

**Status: CURRENT**

The current runtime already rejects malformed or semantically unusable provider output in applicable flows, applies lifecycle guards, and can return failed gate work for correction rather than silently declaring success.

The long-term objective is to make this trust model consistent across every execution path.

## Observability Expectations

**Status: DECIDED direction; partially CURRENT**

When something fails or stalls, the user should be able to determine:

- which task was affected;
- which phase was active;
- which provider/model was attempted;
- what kind of error occurred;
- what the system attempted;
- what remains pending;
- what action is available to the user.

"No visible result" is not an acceptable product outcome for a meaningful execution attempt.

**Status: CURRENT**

The current runtime records lightweight local telemetry for task transitions and provider attempts, including useful operational fields. This is a foundation for observability, not the complete user-facing diagnostic experience.

**Status: PLANNED**

Observability should evolve from raw operational evidence into a coherent explanation of lifecycle state, failures, recovery options, and unresolved obligations.

## Learning Direction

**Status: DECIDED direction**

AI Company OS should improve from evidence generated by:

- incidents;
- provider failures;
- semantic failures;
- regressions;
- successful routing;
- review/QA/security outcomes;
- acceptance runs.

Important lessons should, when possible, move through:

~~~text
INCIDENT
→ LESSON
→ RULE
→ TEST / ENFORCEMENT
~~~

The product should not rely on conversational memory alone for critical safety or reliability lessons.

**Status: CURRENT limitation**

The baseline records operational evidence and has regression/acceptance assets, but it is not a generalized self-learning system.

**Status: EXPERIMENTAL**

Specific mechanisms for automatically converting history into provider rankings, adaptive routing policies, learned heuristics, or self-modifying enforcement are not committed product behavior. They remain experimental until separately designed, reviewed, and proven safe.

## What AI Company OS Is Not

**Status: DECIDED**

AI Company OS is not intended to become:

- a simple chat wrapper;
- a thin LLM selector;
- a collection of prompts without a verifiable runtime;
- a system that automatically says PASS in order to advance;
- a product strategically dependent on one provider;
- a system that silently spends money;
- a UI that owns or duplicates core business/lifecycle logic;
- a generator of demos without quality controls;
- a system that hides failures in order to appear successful;
- an automatic merge/deploy/release authority without explicit authorization;
- an excuse to remove Git, CI, review, security, or human ownership where those controls remain required.

The target experience can be highly automated without being uncontrolled.

## Current Company Priority

**Status: DECIDED current priority**

The company priority is not advanced UI polish, a Web UI, a provider marketplace, dozens of provider integrations, or decorative features.

The priority is to make the real runtime reproducible and reliable enough to carry real requests from beginning to end without falsifying state.

Current work should concentrate on:

- Headless Runtime end-to-end behavior;
- provider reliability;
- lifecycle correctness;
- writable execution;
- Review;
- QA;
- Security;
- recovery;
- evidence;
- regression protection.

This priority describes sequencing. It does not claim that runtime reliability is already solved.

Provider abstraction, intelligent routing, and richer UX should grow only on top of a trustworthy engine.

## Product Maturity Direction

**Status: DECIDED sequencing direction**

The intended maturity progression is:

~~~text
RELIABLE ENGINE
      ↓
PROVIDER ABSTRACTION
      ↓
FREE-FIRST / COST SAFETY
      ↓
CAPABILITY DISCOVERY
      ↓
INTELLIGENT ROUTING
      ↓
PROVIDER ECOSYSTEM
      ↓
PRODUCT UX
      ↓
HARDENING
      ↓
V1.0
~~~

This sequence explains product logic. It is not a dated roadmap, does not assign releases, and does not authorize implementation of every stage at once.

Each later layer depends on the credibility of the earlier one.

## What Success Looks Like

**Status: DECIDED target state**

A new user installs AI Company OS.

The user can connect a local model, a free provider, several providers, paid providers by choice, or an appropriate combination.

The user opens an existing project or creates a new one and gives a request in normal language.

AI Company OS organizes the work through the controlled lifecycle. Different eligible providers can execute different responsibilities. Authorized changes are implemented. Review and tests run. Security obligations are evaluated. Real defects produce correction work or blockers rather than synthetic success.

The user can observe what is happening and understand failures.

Work reaches DONE only when the applicable contracts are satisfied and the required evidence exists.

The user is not required to manually orchestrate each provider or agent.

And the following invariant holds:

~~~text
Paid API usage without explicit permission = 0
~~~

Success is not the absence of failure. Success is that failures are truthful, explainable, recoverable where possible, and never hidden to manufacture completion.

## Status Vocabulary

### CURRENT

Exists in main and is backed by current code, configuration, tests, or evidence.

CURRENT is an implementation claim and must be re-audited as main changes.

### DECIDED

Approved strategic product direction or invariant. It may or may not be implemented yet.

DECIDED is a commitment about direction, not evidence that the runtime already behaves that way.

### PLANNED

Accepted future capability or work that belongs in later product stages but is not yet complete.

PLANNED does not imply a delivery date.

### EXPERIMENTAL

A hypothesis, mechanism, or possibility that has not been approved as a durable product commitment.

EXPERIMENTAL content must not be presented to users or implementers as guaranteed future behavior.

## Related Canonical Documents

### Existing implementation/context references

These documents remain useful for the current implementation and should be consulted when exact runtime behavior matters:

- README.md
- docs/PROJECT-BRIEF.md
- docs/architecture/system-architecture.md
- docs/operations/provider-runtime.md
- docs/operations/observability.md
- docs/DOCUMENTATION-STATUS.md
- docs/engineering/canonical-acceptance-reference-v1.md

### Future canonical product documents

The following documents are intentionally not created by this change:

- PRODUCT-PRINCIPLES.md
- ROADMAP.md
- PROVIDER-STRATEGY.md
- RELEASE-CRITERIA.md
- DOCUMENTATION-MAP.md

They should refine this North Star without silently redefining its mission, trust model, provider-agnostic direction, free-first direction, or paid-spend consent invariant.
