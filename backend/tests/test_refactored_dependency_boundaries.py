# File Name: test_refactored_dependency_boundaries.py
# Role: Keeps extracted medication, prescription, account-lock and release-policy components independent of higher application layers.

import ast
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


# Function Name: _imported_modules
# Description:
# - Reads imports without executing a component or initializing external services.
# - Retains imported members so "from core import config" cannot bypass a module guard.
# Parameters:
# - source_path (Path): Source module whose declared dependency edges are inspected.
# Returns:
# - Module and member paths, with leading dots retained for relative imports.
def _imported_modules(source_path: Path) -> set[str]:
    tree = ast.parse(source_path.read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            module = "." * node.level + (node.module or "")
            if module:
                imported.add(module)
            separator = "" if module.endswith(".") or not module else "."
            imported.update(
                f"{module}{separator}{alias.name}" for alias in node.names
            )
    return imported


# Function Name: _assert_standard_library_only
# Description:
# - Rejects local/relative imports and external packages in runtime-independent utilities.
# Parameters:
# - source_path (Path): Extracted utility module expected to use only Python's standard library.
# Returns:
# - None; an assertion identifies a forbidden dependency without importing it.
def _assert_standard_library_only(source_path: Path) -> None:
    imported = _imported_modules(source_path)
    forbidden = {
        module
        for module in imported
        if module.startswith(".")
        or module.split(".", 1)[0] not in sys.stdlib_module_names
    }
    assert not forbidden, (
        f"{source_path.name} acquired runtime dependencies: {sorted(forbidden)}"
    )


# Function Name: test_prescription_verifier_does_not_depend_on_orchestration
# Description:
# - Keeps catalog name verification independently reusable without API/control composition or application settings.
# Parameters:
# - None.
# Returns:
# - None; an assertion reports a forbidden higher-layer dependency.
def test_prescription_verifier_does_not_depend_on_orchestration() -> None:
    imported = _imported_modules(
        ROOT / "backend/services/prescription_medication_name_verifier.py"
    )
    forbidden = {
        module
        for module in imported
        if module.lstrip(".").split(".", 1)[0] in {"api", "controls"}
        or module.lstrip(".") == "core.config"
        or module.lstrip(".").startswith("core.config.")
    }
    assert not forbidden, (
        "Prescription verifier acquired orchestration dependencies: "
        f"{sorted(forbidden)}"
    )


# Function Name: test_android_release_configuration_uses_only_the_standard_library
# Description:
# - Keeps local release policy validation separate from backend startup, SDKs and network clients.
# Parameters:
# - None.
# Returns:
# - None; an assertion reports an external or application dependency.
def test_android_release_configuration_uses_only_the_standard_library() -> None:
    _assert_standard_library_only(
        ROOT / "scripts/check_android_release_configuration.py"
    )


# Function Name: test_account_operation_locks_uses_only_the_standard_library
# Description:
# - Keeps process-local account serialization independent of request adapters, database sessions and auth settings.
# Parameters:
# - None.
# Returns:
# - None; an assertion reports an external or application dependency.
def test_account_operation_locks_uses_only_the_standard_library() -> None:
    _assert_standard_library_only(ROOT / "backend/core/account_operation_locks.py")


# Function Name: test_medication_detail_collaborators_do_not_depend_on_orchestration
# Description:
# - Prevents extracted catalog/cache/summary/matching components from importing their control or API composition.
# Parameters:
# - None.
# Returns:
# - None; an assertion identifies an upward dependency in any collaborator.
def test_medication_detail_collaborators_do_not_depend_on_orchestration() -> None:
    for relative_path in (
        "services/local_medication_catalog.py",
        "services/medication_name_matching.py",
        "boundaries/medication_detail_cache_boundary.py",
        "boundaries/medication_summary_boundary.py",
    ):
        imported = _imported_modules(ROOT / "backend" / relative_path)
        forbidden = {
            module
            for module in imported
            if module.lstrip(".").split(".", 1)[0] in {"api", "controls"}
        }
        assert not forbidden, f"{relative_path} acquired orchestration dependencies: {sorted(forbidden)}"


# Function Name: test_medication_name_matching_stays_runtime_independent
# Description:
# - Allows only standard-library dependencies and the existing pure medication safety policy.
# - Also checks that policy remains standard-library-only so the allowed edge cannot acquire runtime coupling.
# Parameters:
# - None.
# Returns:
# - None; imports requiring application startup, persistence or external clients are rejected.
def test_medication_name_matching_stays_runtime_independent() -> None:
    imported = _imported_modules(ROOT / "backend/services/medication_name_matching.py")
    forbidden = {
        module
        for module in imported
        if module.split(".", 1)[0] not in sys.stdlib_module_names
        and module != "services.medication_match_safety"
        and not module.startswith("services.medication_match_safety.")
    }
    assert not forbidden, f"Medication name matching acquired runtime dependencies: {sorted(forbidden)}"
    _assert_standard_library_only(ROOT / "backend/services/medication_match_safety.py")


# Function Name: test_medication_detail_control_contains_only_orchestration_class
# Description:
# - Keeps storage/client implementation classes out of the medication-detail use-case control.
# Parameters:
# - None.
# Returns:
# - None; helpers must remain public collaborators rather than be embedded again.
def test_medication_detail_control_contains_only_orchestration_class() -> None:
    source = ROOT / "backend/controls/check_medication_detail_control.py"
    classes = [node.name for node in ast.parse(source.read_text()).body if isinstance(node, ast.ClassDef)]
    assert classes == ["CheckMedicationDetail"]


# Function Name: test_catalog_workers_never_consult_borrowed_request_sessions
# Description:
# - Guards worker setup/read/write methods against reacquiring or sharing their owner's request Session.
# - Keeps captured Engine-bound factories as the only worker-session composition port.
# Parameters:
# - None.
# Returns:
# - None; a direct self.db access identifies the lifecycle regression before runtime.
def test_catalog_workers_never_consult_borrowed_request_sessions() -> None:
    for relative_path, method_names in (
        ("services/prescription_medication_name_verifier.py", {
            "_requires_current_thread_session",
            "_prepare_verifications_with_isolated_session",
        }),
        ("services/local_medication_catalog.py", {
            "_search_catalog_with_isolated_session",
            "_save_approval_summary_with_isolated_session",
        }),
    ):
        tree = ast.parse((ROOT / "backend" / relative_path).read_text())
        methods = {
            node.name: node
            for node in ast.walk(tree)
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name in method_names
        }
        assert set(methods) == method_names
        for name, method in methods.items():
            forbidden = [
                node
                for node in ast.walk(method)
                if isinstance(node, ast.Attribute)
                and isinstance(node.value, ast.Name)
                and node.value.id == "self"
                and node.attr == "db"
            ]
            assert not forbidden, f"{relative_path}:{name} acquired borrowed request-session access"
