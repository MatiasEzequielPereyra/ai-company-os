from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass
class ApproachOption:
    id: str
    title: str
    description: str
    agents: list[str]
    approval: str
    recommended: bool = False


@dataclass
class CommandProposal:
    request: str
    intent: str
    options: list[ApproachOption]


class CommandService:
    def propose(
        self,
        request: str,
    ) -> CommandProposal:
        request = request.strip()

        if not request:
            raise ValueError(
                "Request cannot be empty."
            )

        lower = request.casefold()

        explicit_intent = None

        leading_patterns = (
            (
                "AUDIT",
                (
                    r"^(?:(?:please|por favor)\s+)?"
                    r"(?:audit|review|inspect|assess|"
                    r"auditar|revisar|inspeccionar|evaluar)\b"
                ),
            ),
            (
                "FIX",
                (
                    r"^(?:(?:please|por favor)\s+)?"
                    r"(?:fix|repair|resolve|correct|debug|"
                    r"corregir|arreglar|solucionar|reparar)\b"
                ),
            ),
            (
                "FEATURE",
                (
                    r"^(?:(?:please|por favor)\s+)?"
                    r"(?:add|adding|create|creating|"
                    r"implement|implementing|build|building|"
                    r"extend|extending|enhance|enhancing|"
                    r"introduce|introducing|support|supporting|"
                    r"enable|enabling|agregar|crear|implementar|"
                    r"añadir|extender|mejorar|incorporar|"
                    r"soportar|habilitar)\b"
                ),
            ),
        )

        for candidate_intent, pattern in leading_patterns:
            if re.search(pattern, lower):
                explicit_intent = candidate_intent
                break

        feature_signal = bool(
            re.search(
                (
                    r"\b(?:add|adding|create|creating|"
                    r"implement|implementing|build|building|"
                    r"extend|extending|enhance|enhancing|"
                    r"introduce|introducing|support|supporting|"
                    r"enable|enabling|agregar|crear|implementar|"
                    r"añadir|extender|mejorar|incorporar|"
                    r"soportar|habilitar)\b"
                ),
                lower,
            )
            or any(
                word in lower
                for word in (
                    "feature",
                    "nuevo",
                    "nueva funcionalidad",
                )
            )
        )

        fix_signal = bool(
            re.search(
                (
                    r"\b(?:regression|broken|breaks|crash|crashes|"
                    r"crashed|failing|fails|bug)\b"
                    r"(?!\s+(?:report|reports|reporting|tracker|tracking))"
                ),
                lower,
            )
            or re.search(
                (
                    r"\b(?:throws?|returns?|shows?|produces?|causes?)"
                    r"\s+(?:an?\s+)?error\b"
                    r"|\berror\s+(?:when|while|during|after|on)\b"
                    r"|\b(?:falla|fallo)\s+(?:al|cuando|durante)\b"
                    r"|\brompe\b"
                ),
                lower,
            )
        )

        audit_signal = any(
            word in lower
            for word in (
                "audit",
                "auditar",
                "review",
                "revisar",
                "producción",
                "produccion",
            )
        )

        if (
            explicit_intent == "AUDIT"
            or (
                explicit_intent is None
                and audit_signal
                and not feature_signal
                and not fix_signal
            )
        ):
            intent = "AUDIT"

            options = [
                ApproachOption(
                    id="focused",
                    title="Focused audit",
                    description=(
                        "Inspect the requested area only "
                        "and produce findings."
                    ),
                    agents=[
                        "engineering-manager",
                    ],
                    approval="Review findings",
                ),
                ApproachOption(
                    id="balanced",
                    title="Parallel specialist audit",
                    description=(
                        "Delegate independent technical, "
                        "QA and security analysis in parallel."
                    ),
                    agents=[
                        "cto",
                        "engineering-manager",
                        "qa",
                        "security",
                    ],
                    approval="Approve remediation plan",
                    recommended=True,
                ),
                ApproachOption(
                    id="thorough",
                    title="Production readiness",
                    description=(
                        "Run product, architecture, "
                        "engineering, QA, security and "
                        "deployment readiness analysis."
                    ),
                    agents=[
                        "pm",
                        "cto",
                        "engineering-manager",
                        "qa",
                        "security",
                        "devops",
                    ],
                    approval="Multiple quality gates",
                ),
            ]

        elif (
            explicit_intent == "FIX"
            or (
                explicit_intent is None
                and fix_signal
                and not feature_signal
            )
        ):
            intent = "FIX"

            options = [
                ApproachOption(
                    id="focused",
                    title="Fast fix",
                    description=(
                        "Diagnose the specific failure "
                        "and prepare the smallest fix."
                    ),
                    agents=[
                        "engineering-manager",
                    ],
                    approval="Approve change",
                ),
                ApproachOption(
                    id="balanced",
                    title="Root cause + fix",
                    description=(
                        "Find root cause, implement the fix "
                        "and validate regression coverage."
                    ),
                    agents=[
                        "engineering-manager",
                        "backend",
                        "frontend",
                        "qa",
                    ],
                    approval="Review + QA",
                    recommended=True,
                ),
                ApproachOption(
                    id="thorough",
                    title="Fix + hardening",
                    description=(
                        "Fix the issue and inspect related "
                        "architecture, security and "
                        "regression risks."
                    ),
                    agents=[
                        "cto",
                        "engineering-manager",
                        "backend",
                        "frontend",
                        "qa",
                        "security",
                    ],
                    approval="Full gates",
                ),
            ]

        elif (
            explicit_intent == "FEATURE"
            or (
                explicit_intent is None
                and feature_signal
            )
        ):
            intent = "FEATURE"

            options = [
                ApproachOption(
                    id="focused",
                    title="Direct implementation",
                    description=(
                        "Turn the request into a small "
                        "implementation ticket."
                    ),
                    agents=[
                        "engineering-manager",
                    ],
                    approval="Approve implementation",
                ),
                ApproachOption(
                    id="balanced",
                    title="Design then implement",
                    description=(
                        "Clarify scope, design the change, "
                        "implement and test it."
                    ),
                    agents=[
                        "pm",
                        "engineering-manager",
                        "backend",
                        "frontend",
                        "qa",
                    ],
                    approval="Plan + QA",
                    recommended=True,
                ),
                ApproachOption(
                    id="thorough",
                    title="Full delivery flow",
                    description=(
                        "Run product, architecture, "
                        "implementation, QA, security "
                        "and release planning."
                    ),
                    agents=[
                        "pm",
                        "cto",
                        "engineering-manager",
                        "backend",
                        "frontend",
                        "qa",
                        "security",
                        "devops",
                    ],
                    approval="Full workflow",
                ),
            ]

        else:
            intent = "GENERAL"

            options = [
                ApproachOption(
                    id="focused",
                    title="Focused",
                    description=(
                        "Use the minimum number of agents "
                        "needed to answer the request."
                    ),
                    agents=[
                        "engineering-manager",
                    ],
                    approval="Review result",
                ),
                ApproachOption(
                    id="balanced",
                    title="Balanced",
                    description=(
                        "Let the CEO decompose the request "
                        "and delegate where useful."
                    ),
                    agents=[
                        "ceo",
                        "engineering-manager",
                    ],
                    approval="Review plan",
                    recommended=True,
                ),
                ApproachOption(
                    id="thorough",
                    title="Full multi-agent",
                    description=(
                        "Create a complete cross-functional "
                        "plan before execution."
                    ),
                    agents=[
                        "ceo",
                        "pm",
                        "cto",
                        "engineering-manager",
                        "qa",
                        "security",
                        "devops",
                    ],
                    approval="Approve full plan",
                ),
            ]

        return CommandProposal(
            request=request,
            intent=intent,
            options=options,
        )