# File Name: test_repository_security_configuration.py
# Role: Guards security-sensitive repository and development defaults.

from pathlib import Path


_REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


# Function Name: test_local_generated_and_secret_files_are_ignored
# Description:
# - Prevents Kotlin session markers, generated Firebase platform files, local
#   environment variants, signing material, and Flutter plugin registrants from
#   appearing in commits.
# - Keeps shareable example environment files explicitly available to Git.
# Returns:
# - None; pytest reports a failure when repository hygiene rules regress.
def test_local_generated_and_secret_files_are_ignored() -> None:
    ignore_source = (_REPOSITORY_ROOT / ".gitignore").read_text(encoding="utf-8")

    for required_pattern in (
        "**/.env.*",
        "!**/.env.example",
        "*.salive",
        "**/.gradle/",
        "**/.kotlin/",
        "**/google-services.json",
        "**/GoogleService-Info.plist",
        "*.jks",
        "*.keystore",
        "frontend/ios/Runner/GeneratedPluginRegistrant.*",
    ):
        assert required_pattern in ignore_source


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
#   protected-main deployment policy.
# Returns:
# - None; pytest reports a failure when broad signing refs are reintroduced.
def test_android_signing_secrets_are_limited_to_main() -> None:
    workflow = (
        _REPOSITORY_ROOT / ".github" / "workflows" / "release-android.yml"
    ).read_text(encoding="utf-8")

    assert "test \"${GITHUB_REF}\" = \"refs/heads/main\"" in workflow
    assert "github.ref == 'refs/heads/main'" in workflow
    assert "refs/heads/beta/v0.1.0" not in workflow
    assert "refs/heads/beta/*" not in workflow
    assert "refs/tags/v*" not in workflow
    assert "environment: beta-android" in workflow


# Function Name: test_android_artifact_signature_checks_are_strict
# Description:
# - Prevents certificate-subject text from spoofing the APK digest parser.
# - Requires jarsigner warnings, including unsigned entries, to fail AAB checks.
# Returns:
# - None; pytest reports a failure when artifact verification is weakened.
def test_android_artifact_signature_checks_are_strict() -> None:
    workflow = (
        _REPOSITORY_ROOT / ".github" / "workflows" / "release-android.yml"
    ).read_text(encoding="utf-8")

    assert (
        "/^Signer #[0-9]+ certificate SHA-256 digest: "
        "[[:xdigit:]:]+$/" in workflow
    )
    assert "jarsigner -verify -strict \"${AAB}\"" in workflow
    assert '[[ ! "${APK_CERT}" =~ ^[0-9A-F]{64}$ ]]' in workflow
    assert '[[ ! "${AAB_CERT}" =~ ^[0-9A-F]{64}$ ]]' in workflow


# Function Name: test_dormant_cloud_deploy_rejects_anonymous_identities
# Description:
# - Keeps the retained managed-cloud deployment fail-closed if it is enabled
#   after the self-hosted beta period.
# - Prevents anonymous Firebase identities from reaching cost-bearing routes in
#   a future public Cloud Run deployment while leaving self-hosted guest policy
#   under its separate runtime configuration.
# Returns:
# - None; pytest reports a failure when anonymous Cloud Run access returns.
def test_dormant_cloud_deploy_rejects_anonymous_identities() -> None:
    workflow = (
        _REPOSITORY_ROOT / ".github" / "workflows" / "deploy-backend.yml"
    ).read_text(encoding="utf-8")

    assert "if: ${{ false }}" in workflow
    assert "FIREBASE_ALLOW_ANONYMOUS_AUTH=false" in workflow
    assert "FIREBASE_ALLOW_ANONYMOUS_AUTH=true" not in workflow


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


# Function Name: test_self_hosted_database_url_uses_structured_credentials
# Description:
# - Prevents Compose from interpolating an unescaped raw PostgreSQL password
#   directly into a SQLAlchemy URL.
# - Ensures every application service uses the same structured connection
#   fields while PostgreSQL receives the original raw password.
# Returns:
# - None; pytest reports a failure when raw URL interpolation returns.
def test_self_hosted_database_url_uses_structured_credentials() -> None:
    compose_source = (_REPOSITORY_ROOT / "compose.self-hosted.yml").read_text(
        encoding="utf-8"
    )

    assert "${POSTGRES_PASSWORD}@postgres" not in compose_source
    assert "DATABASE_URL:" not in compose_source
    assert compose_source.count("DATABASE_PASSWORD: ${POSTGRES_PASSWORD") == 3
    assert compose_source.count("DATABASE_HOST: postgres") == 3
