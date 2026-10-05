# AI Company OS — Product Principles

Status: Canonical product constitution
Authority: Derived from `docs/product/PRODUCT-NORTH-STAR.md`
Applies to: Product, Engineering, agents, runtime, interfaces, and future product decisions

## Document Authority

This document defines the non-negotiable product rules that preserve the identity of AI Company OS as architecture, providers, interfaces, and implementation details evolve.

The authority order is:

~~~text
PRODUCT-NORTH-STAR.md
        ↓
PRODUCT-PRINCIPLES.md
        ↓
ROADMAP.md
        ↓
architecture / implementation
~~~

The Product North Star defines WHAT, WHO, WHY, and PRODUCT DIRECTION.

This document defines the rules that lower-level decisions must not violate silently.

These principles are fundamentally **DECIDED** product governance. References to CURRENT behavior are evidence of alignment, not the purpose of this document.

A technical PR, implementation shortcut, provider limitation, UI decision, or delivery deadline does not have authority to weaken these principles accidentally. Changing a principle requires an explicit Product decision.

---

## 1. Trust and Truth Principles

### 1.1 Correct Failure Over False Success

**Principle**

~~~text
CORRECT FAILURE
>
FALSE SUCCESS
~~~

**Meaning**

AI Company OS must prefer a truthful incomplete or failed state over a synthetic success. Schemas, gates, tests, semantic contracts, or acceptance conditions must not be weakened merely to reach DONE.

READY, ACTIVE, BLOCKED, REVIEW, QA, or SECURITY are valid outcomes when they accurately represent reality.

**Protects Against**

- false-positive completion;
- optimistic state advancement;
- hiding provider or gate failures;
- lowering quality requirements to make a workflow appear successful;
- demo-driven corruption of product truth.

**Decision Test**

Would this change make the system more likely to report success when required evidence or contracts are not satisfied?

If yes, it violates this principle.

### 1.2 Evidence Before Claims

**Principle**

Important claims require the evidence appropriate to the lifecycle stage.

**Meaning**

Claims such as provider success, implementation completion, verification, Review, QA, Security, and DONE must be supported by durable evidence when the lifecycle requires it.

"Looks correct", transport success, a provider response, or an optimistic status transition is not a substitute for required evidence.

**Protects Against**

- unverifiable completion;
- claims based only on agent confidence;
- loss of auditability;
- lifecycle state that cannot be reconstructed from evidence.

### 1.3 Product Truth Beats Demo Success

**Principle**

Acceptance exists to discover defects, not to conceal them.

**Meaning**

No operator, agent, or interface should manually rewrite state, skip required gates, erase failures, or alter evidence merely to produce a successful demonstration.

A failed acceptance run that reveals a real defect is valuable product evidence.

**Protects Against**

- acceptance theater;
- manual state manipulation;
- hidden regressions;
- demos that prove presentation rather than product behavior.

### 1.4 Recovery Must Preserve Provenance

**Principle**

Recovery may change the future state; it must not erase the evidence needed to explain the past.

**Meaning**

Retries, corrections, fallback, and recovery paths should preserve material evidence about previous attempts and the sequence that led to the current state.

The product should be able to answer not only "where are we now?" but also "how did we get here?"

**Protects Against**

- retry loops that destroy diagnostic context;
- evidence rewriting;
- unexplained final state;
- inability to audit recurring failures.

---

## 2. Provider and Cost Principles

### 2.1 Free First, Never Quality Last

**Principle**

AI Company OS should be usable without requiring paid API execution, while preserving the same product contracts.

**Meaning**

When technically appropriate, eligible execution should prefer:

~~~text
LOCAL
↓
FREE
↓
FREE-TIER / USER-ELIGIBLE FREE ACCESS
↓
PAID ONLY IF AUTHORIZED
~~~

Free-first is a cost strategy, not permission to accept invalid or lower-quality results. Free or local candidates must still satisfy the required schemas, semantics, gates, and task contracts.

No third-party service is assumed to remain free permanently.

**Protects Against**

- unnecessary spend;
- economic lock-in;
- treating "free" as more important than correctness;
- permanent assumptions about third-party pricing or quotas.

### 2.2 Paid Execution Requires Explicit Consent

**Principle**

~~~text
API KEY CONFIGURED
≠
PERMISSION TO SPEND
~~~

**Meaning**

Credentials prove configuration or access. They do not grant economic authority.

Paid execution requires explicit user permission under product-defined controls. Without that permission, the system must fail closed rather than silently spend.

**Protects Against**

- silent paid fallback;
- surprise charges;
- treating secrets as authorization;
- interfaces that hide economically significant decisions.

**Decision Test**

Would this change permit paid execution merely because credentials exist or a provider is reachable?

If yes, it violates this principle.

### 2.3 Unknown Cost Is Not Free

**Principle**

~~~text
UNKNOWN COST
→ NOT AUTOMATICALLY ELIGIBLE FOR SPEND
~~~

**Meaning**

If the system cannot determine a provider/model's economic status safely enough for the applicable policy, it must not automatically classify that execution as free.

The exact cost model, classification mechanism, and provider metadata belong in later Provider Strategy and implementation documents.

**Protects Against**

- optimistic cost assumptions;
- accidental billing caused by stale pricing knowledge;
- treating ambiguous quota or account conditions as permission.

### 2.4 The Product Is Provider-Agnostic

**Principle**

Providers execute AI Company OS contracts; they do not define AI Company OS.

**Meaning**

No provider or model — including Ollama, OpenRouter, Gemini, OpenAI/Codex, NVIDIA, OpenCode, Anthropic, DeepSeek, xAI, or future providers — may become a strategic dependency that silently redefines the product.

Provider-specific advantages are welcome. Provider-specific product identity is not.

**Protects Against**

- vendor lock-in;
- provider-driven product semantics;
- architecture that cannot survive provider replacement;
- confusing a current default with a permanent product commitment.

### 2.5 Capability Over Brand

**Principle**

Resource selection should be based on demonstrated suitability for the task, not provider reputation or hardcoded brand ownership of a role.

**Meaning**

Future selection should conceptually reason from:

~~~text
TASK REQUIREMENTS
        ↓
ELIGIBLE CAPABILITIES
        ↓
COST PERMISSION
        ↓
RELIABILITY
        ↓
PROVIDER / MODEL
~~~

A role such as CTO, Engineering, Review, QA, or Security must not permanently belong to a named provider merely because that provider is currently convenient.

**Protects Against**

- hardcoded provider-role coupling;
- brand-based routing;
- stale assumptions after models change;
- strategic dependence on current benchmarks or marketing.

### 2.6 Configuration, Availability, and Capability Are Different Facts

**Principle**

~~~text
CONFIGURED
≠
AVAILABLE
≠
CAPABLE
~~~

**Meaning**

A provider can have credentials, be reachable, and return a response while still being unable to satisfy a required task contract.

The product must preserve these distinctions in its decisions and explanations.

**Protects Against**

- treating API-key presence as readiness;
- treating HTTP success as semantic success;
- routing work to resources that cannot meet the task requirements;
- misleading provider status.

### 2.7 Contracts Must Be Provider-Portable

**Principle**

Canonical product and domain contracts belong to AI Company OS, not to any provider.

**Meaning**

Provider-specific limitations or response formats may require adapters and normalization, but must not silently deform canonical semantics.

Conceptually:

~~~text
CANONICAL CONTRACT
↓
PROVIDER ADAPTER
↓
PROVIDER-SPECIFIC REPRESENTATION
↓
NORMALIZATION
↓
CANONICAL VALIDATION
~~~

The exact adapter design is an architecture concern. The product rule is that provider constraints must not redefine the contract without an explicit higher-level decision.

**Protects Against**

- lowest-common-denominator contracts;
- provider-specific schema leakage;
- silent semantic drift;
- inability to compare results across providers.

### 2.8 More Providers Must Reduce User Burden, Not Increase It

**Principle**

One provider should remain useful; multiple providers should make the system more capable without requiring the user to become the router.

**Meaning**

With one connected provider, AI Company OS should use it for everything it can validly satisfy, without artificially requiring a multi-provider setup.

With multiple providers, complexity should increase inside the runtime and decrease for the user:

~~~text
USER INTENT
↓
AUTOMATIC ELIGIBLE RESOURCE SELECTION
~~~

The system must not pretend that a connected provider can satisfy work that violates required contracts.

**Protects Against**

- artificial multi-provider requirements;
- user micromanagement of every task;
- routing complexity leaking into the primary product experience;
- false capability assumptions.

---

## 3. Runtime and Lifecycle Principles

### 3.1 Runtime Is the Product Core

**Principle**

Core lifecycle, policy, evidence, cost, and authorization logic belongs to the application/runtime layer.

**Meaning**

TUI, CLI, Web UI, headless operation, and future interfaces are clients of the same product runtime.

Conceptually:

~~~text
CLIENTS
   ↓
APPLICATION / RUNTIME
   ↓
CANONICAL STATE + POLICIES
~~~

Interfaces may present different workflows, but they must not become independent owners of core business rules.

**Protects Against**

- UI-owned business logic;
- inconsistent behavior between interfaces;
- duplicate implementation of policy;
- a future interface becoming a second product engine.

### 3.2 One Canonical Lifecycle

**Principle**

AI Company OS may have many interfaces, but only one lifecycle semantics.

**Meaning**

There must not be separate TUI, Web, CLI, or Headless lifecycle engines with diverging transition rules.

Every interface must operate on the same canonical lifecycle and authority model.

**Protects Against**

- state divergence by surface;
- feature-specific transition rules;
- bugs fixed in one interface but not another;
- incompatible interpretations of DONE, BLOCKED, Review, QA, or Security.

---

## 4. Execution and Safety Principles

### 4.1 Fail Closed on Safety, Authorization, and Material Ambiguity

**Principle**

When the system lacks required authority or evidence, it blocks and explains rather than inventing permission or success.

**Meaning**

Missing authorization, material evidence, an eligible provider, permitted cost, required security disposition, or verifiable ownership must not be guessed around.

The correct behavior is to preserve the truthful state and explain what is missing.

**Protects Against**

- implicit authorization;
- unsafe defaults;
- invented evidence;
- execution through unresolved ambiguity.

### 4.2 Automation Does Not Grant Unbounded Authority

**Principle**

~~~text
AUTOMATION
≠
UNBOUNDED AUTHORITY
~~~

**Meaning**

The product can automate substantial work, but actions with irreversible, destructive, economic, secret-bearing, or externally consequential impact must respect explicit authority boundaries.

Paid spend, merge, push, deployment, release, destructive operations, and secret access are examples of this class, not an exhaustive technical list.

**Protects Against**

- agents expanding their own authority;
- accidental external side effects;
- automation that bypasses user control;
- treating convenience as authorization.

### 4.3 Isolation Before Mutation

**Principle**

Concurrent writable work must be isolated before it is parallelized.

**Meaning**

Filesystem and repository safety take priority over maximizing agent concurrency.

Multiple writable agents must not mutate an undifferentiated shared workspace. The implementation mechanism may evolve, but the isolation property must remain.

**Protects Against**

- conflicting writes;
- cross-task contamination;
- unverifiable candidate state;
- concurrency-induced repository corruption.

### 4.4 Gates Inspect the Candidate Being Approved

**Principle**

Review, QA, and Security must evaluate the exact candidate that could advance.

**Meaning**

Approval evidence must be bound to the identity and provenance of the implementation candidate under consideration, not to an obsolete copy, unrelated main checkout, stale context, or different artifact.

Conceptually:

~~~text
IMPLEMENTATION CANDIDATE
        ↓
IDENTITY / PROVENANCE
        ↓
REVIEW
        ↓
QA
        ↓
SECURITY
~~~

The exact provenance mechanism is an implementation concern. Candidate identity is a product integrity requirement.

**Protects Against**

- approving code that was not actually reviewed;
- stale-checkout validation;
- evidence attached to the wrong candidate;
- gates that exist procedurally but do not protect the proposed change.

---

## 5. User Experience and Operability Principles

### 5.1 Observable Systems Are Operable Systems

**Principle**

A meaningful failure must not look like a no-op.

**Meaning**

When work fails, blocks, or stalls, the product should make it possible to understand:

- what failed;
- where in the lifecycle it failed;
- which provider/model or execution resource was involved when relevant;
- what was attempted;
- what state remains;
- what the user can do next.

Observability is part of the product experience, not only developer telemetry.

**Protects Against**

- silent failures;
- users repeating actions blindly;
- inability to recover;
- support dependent on reading internal logs manually.

### 5.2 Simple for Users, Explicit Internally

**Principle**

The primary product experience should reduce coordination burden without hiding critical decisions.

**Meaning**

Provider onboarding should be able to evolve toward a simple experience such as:

~~~text
CONNECT
→ VERIFY
→ DISCOVER
→ READY
~~~

But simple UI must not collapse or obscure distinctions involving cost, permission, capability, safety, lifecycle state, or evidence.

Ease of use means the system manages complexity responsibly. It does not mean the system pretends the complexity does not exist.

**Protects Against**

- easy-looking but unsafe flows;
- hidden cost and authorization semantics;
- UI convenience that weakens product truth;
- exposing unnecessary orchestration detail to normal users.

---

## 6. Learning and Enforcement Principles

### 6.1 Important Learning Must Become Durable Enforcement

**Principle**

Conversation memory and institutional knowledge are useful, but important reliability lessons should become enforceable product knowledge when technically possible.

**Meaning**

Prefer:

~~~text
INCIDENT
→ LESSON
→ RULE
→ REGRESSION TEST / ENFORCEMENT
~~~

An incident is not truly learned from if the only protection against recurrence is that a human or agent remembers the story.

**Protects Against**

- repeating known failures;
- organizational memory loss;
- lessons that disappear with a chat or collaborator;
- reliance on prompt folklore for critical safety.

### 6.2 Evidence Is Part of the Learning System

**Principle**

The product should preserve enough structured history to distinguish isolated failure from recurring product weakness.

**Meaning**

Provider failures, semantic failures, retries, Review/QA/Security outcomes, regressions, and acceptance results should remain usable as inputs to future reliability improvements.

This principle does not authorize self-modifying routing, automatic policy changes, or a specific learning architecture.

**Protects Against**

- anecdotal product decisions;
- losing the context behind reliability changes;
- confusing experimentation with proven policy.

---

## 7. Product Sequencing Principles

### 7.1 Reliability Before Surface Expansion

**Principle**

A new interface or ecosystem surface does not compensate for an unreliable engine.

**Meaning**

While the core runtime remains the current product priority, Web UI expansion, marketplaces, decorative polish, and broad surface growth must not outrank lifecycle correctness, provider reliability, writable execution, gates, recovery, evidence, and regression protection.

This principle governs sequencing, not permanent scope. Richer product surfaces remain valid after the engine earns that foundation.

**Protects Against**

- optimizing presentation before trust;
- expanding maintenance surface faster than runtime reliability;
- roadmap drift caused by visible but low-leverage features;
- treating UI progress as engine maturity.

**Decision Test**

Does this initiative strengthen the current reliability priority, or does it consume focus while leaving fundamental runtime trust unresolved?

---

## Product Decision Test

Any significant feature, architecture choice, provider integration, interface change, automation, or technical shortcut should be evaluated against these questions:

1. **Truth:** Does this weaken truthful failure or make false success easier?
2. **Evidence:** Does this bypass, erase, detach, or dilute required evidence?
3. **Lifecycle:** Does this create a second lifecycle or a second owner of canonical state?
4. **Candidate Integrity:** Could a gate approve something other than the candidate that would advance?
5. **Cost:** Could this introduce hidden spending or treat unknown cost as free?
6. **Consent:** Could credentials, availability, or configuration be mistaken for permission?
7. **Provider Independence:** Does this bind product semantics or a permanent role to one provider or model?
8. **Capability:** Does this confuse configured, available, responsive, and capable?
9. **Contracts:** Does a provider limitation silently weaken the canonical product contract?
10. **Authority:** Does this move irreversible or externally consequential authority away from the user/product-defined boundary?
11. **Isolation:** Could concurrent writable work interfere through a shared mutable workspace?
12. **Operability:** Would a meaningful failure become difficult for the user to understand or recover from?
13. **Complexity:** Does this expose orchestration complexity the product should manage internally?
14. **Learning:** If this fixes a known serious failure, does it create durable protection against recurrence where practical?
15. **Sequencing:** Does this advance the current product priority, or distract from it before the foundation is reliable?

A "yes" to a risk question does not automatically forbid all possible future change. It means the proposal requires explicit Product consideration against the relevant principle.

A technical implementation must not silently amend the product constitution.

---

## Relationship to the Product North Star

The Product North Star remains the higher authority.

It defines the mission, target users, problem, product promise, provider-agnostic and free-first direction, paid-spend consent invariant, runtime-first identity, trust model, observability direction, maturity progression, and success vision.

These Product Principles convert that direction into durable decision constraints.

They do not:

- replace the North Star;
- define a roadmap;
- define Provider Strategy;
- specify provider abstraction architecture;
- choose implementation languages, classes, database tables, APIs, schemas, scoring formulas, or UI structure;
- authorize automatic paid spend, merge, push, deployment, release, destructive operations, or secret access;
- promise permanent free access from any third party.

If a future decision cannot satisfy these principles, Product must explicitly decide whether the constitution itself should change. That change must be deliberate, reviewable, and visible rather than emerging accidentally from implementation.
