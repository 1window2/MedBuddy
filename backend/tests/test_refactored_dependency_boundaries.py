# File Name: test_refactored_dependency_boundaries.py
# Role: Keeps extracted prescription, account-lock and release-policy components independent of higher application layers.

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
