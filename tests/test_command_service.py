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


def test_extend_feature_with_error_language_stays_feature():
    request = (
        "Extend the existing Python task CLI with persistent JSON-backed "
        "task management. Required behavior: add a task with text; list "
        "all tasks; complete a task by ID; remove a task by ID; keep "
        "stable numeric task IDs; persist tasks across independent CLI "
        "process executions; represent completed and pending tasks "
        "clearly; unknown task IDs must return a non-zero exit status "
        "with a useful error message; invalid operations must not corrupt "
        "the stored task data; use `.taskcli/tasks.json` as the default "
        "project-local data location; support a `TASKCLI_DATA_FILE` "
        "environment variable so automated tests can isolate storage; "
        "add `.taskcli/` to `.gitignore`; preserve the existing "
        "empty-list behavior; add automated tests for the new behavior; "
        "update README usage documentation. The existing application "
        "must remain functional."
    )

    proposal = CommandService().propose(request)

    assert proposal.intent == "FEATURE"
    assert any(
        option.recommended
        and option.id == "balanced"
        for option in proposal.options
    )


def test_feature_requirements_can_describe_failures_without_becoming_fix():
    service = CommandService()

    for request in (
        "Add error handling and useful failure messages to imports.",
        "Create bug reporting for failed background jobs.",
        "Implement invalid input handling for the account form.",
        "Support failure messages when an external API is unavailable.",
        "Extend the CLI so invalid input returns a useful error message.",
    ):
        assert service.propose(request).intent == "FEATURE"


def test_contextual_defect_reports_still_classify_as_fix():
    service = CommandService()

    for request in (
        "The dashboard shows an error when loading.",
        "The login flow crashes after authentication.",
        "There is a regression in task deletion.",
        "The save operation fails when the file already exists.",
        "Dashboard bug on login.",
    ):
        assert service.propose(request).intent == "FIX"


def test_explicit_intent_takes_precedence_over_incidental_vocabulary():
    service = CommandService()

    assert (
        service.propose(
            "Extend the dashboard with bug reporting and error messages."
        ).intent
        == "FEATURE"
    )
    assert (
        service.propose(
            "Fix the add-task feature regression."
        ).intent
        == "FIX"
    )
    assert (
        service.propose(
            "Audit the new error-handling feature before release."
        ).intent
        == "AUDIT"
    )
