from company_os.application.command_service import (
    CommandService,
)


def test_english_implementation_requests_are_features():
    service = CommandService()

    for request in (
        "Implement sample.txt so it contains the approved value.",
        "Add payments to the application.",
        "Create a customer portal.",
        "Build a reporting dashboard.",
        "Adding audit history to the UI.",
        "Please add audit history to the UI.",
    ):
        proposal = service.propose(request)

        assert proposal.intent == "FEATURE"
        assert any(
            option.recommended
            and option.id == "balanced"
            for option in proposal.options
        )


def test_feature_keyword_does_not_match_inside_another_word():
    proposal = CommandService().propose(
        "Investigate the address issue."
    )

    assert proposal.intent == "GENERAL"


def test_explicit_fix_and_audit_requests_keep_their_intent():
    service = CommandService()

    assert (
        service.propose(
            "Fix the add button regression."
        ).intent
        == "FIX"
    )

    assert (
        service.propose(
            "Audit the new feature before release."
        ).intent
        == "AUDIT"
    )
