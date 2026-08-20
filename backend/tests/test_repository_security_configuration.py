# File Name: test_repository_security_configuration.py
# Role: Guards security-sensitive repository and development defaults.

from pathlib import Path


_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


# Function Name: test_direct_backend_entrypoint_binds_to_loopback
# Description:
# - Prevents the convenience Python entrypoint from exposing the alpha API on
#   every network interface by default.
# Returns:
# - None; pytest reports a failure when the safe default regresses.
def test_direct_backend_entrypoint_binds_to_loopback() -> None:
    main_source = (_REPOSITORY_ROOT / "backend" / "main.py").read_text(
        encoding="utf-8"
    )

    assert 'host="127.0.0.1"' in main_source


# Function Name: test_pull_request_ci_does_not_inject_repository_api_secrets
# Description:
# - Ensures pull-request-controlled code receives deterministic fake keys, not
#   repository API secrets.
# Returns:
# - None; pytest reports a failure when a secret expression is reintroduced.
def test_pull_request_ci_does_not_inject_repository_api_secrets() -> None:
    workflow = (
        _REPOSITORY_ROOT / ".github" / "workflows" / "backend-ci.yml"
    ).read_text(encoding="utf-8")

    assert "secrets.GEMINI_API_KEY" not in workflow
    assert "secrets.PUBLIC_DATA_API_KEY" not in workflow
    assert workflow.count("test-key-for-ci") >= 4


# Function Name: test_android_signing_secrets_are_limited_to_release_branches
# Description:
# - Prevents arbitrary beta branches or version-like tags from selecting
#   repository-controlled build code that receives Android signing secrets.
# - Keeps the repository gate aligned with the beta-android environment's
#   exact custom deployment branch policies.
# Returns:
# - None; pytest reports a failure when broad signing refs are reintroduced.
def test_android_signing_secrets_are_limited_to_release_branches() -> None:
    workflow = (
        _REPOSITORY_ROOT / ".github" / "workflows" / "release-android.yml"
    ).read_text(encoding="utf-8")

    assert "refs/heads/main|refs/heads/beta/v0.1.0" in workflow
    assert "refs/heads/beta/*" not in workflow
    assert "refs/tags/v*" not in workflow
    assert "environment: beta-android" in workflow


# Function Name: test_issue_templates_forbid_real_medical_data
# Description:
# - Keeps public bug intake from soliciting prescription images, personal
#   medical text, identifiers, credentials, or raw logs.
# Returns:
# - None; pytest reports a failure when the privacy warning is absent.
def test_issue_templates_forbid_real_medical_data() -> None:
    template_directory = _REPOSITORY_ROOT / ".github" / "ISSUE_TEMPLATE"
    for filename in ("ai---ocr-data-issue.md", "bug-report.md"):
        template = (template_directory / filename).read_text(encoding="utf-8")
        assert "Do not attach real medical or personal data" in template
        assert "SECURITY.md" in template


# Function Name: test_self_hosted_catalog_has_periodic_atomic_refresh
# Description:
# - Ensures production keeps refreshing MFDS catalogs after the first seed.
# - Guards the periodic writer against accidentally inheriting the
#   bootstrap-only empty-catalog shortcut.
# Returns:
# - None; pytest reports a failure when the maintenance service regresses.
def test_self_hosted_catalog_has_periodic_atomic_refresh() -> None:
    compose_source = (_REPOSITORY_ROOT / "compose.self-hosted.yml").read_text(
        encoding="utf-8"
    )
    refresh_service = compose_source.split("  catalog-refresh:", maxsplit=1)[1]
    refresh_service = refresh_service.split("\n  backend:", maxsplit=1)[0]

    assert "restart: unless-stopped" in refresh_service
    assert "CATALOG_REFRESH_INTERVAL_SECONDS" in refresh_service
    assert "CATALOG_REFRESH_RETRY_SECONDS" in refresh_service
    assert "sync_drug_catalog.py --dataset all" in refresh_service
    assert "--only-if-empty" not in refresh_service
