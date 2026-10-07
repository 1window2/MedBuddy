# File Name: check_release_ci.py
# Role: Fail closed unless both required push workflows passed for the signed source SHA.

import json
import os
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen

REQUIRED_WORKFLOWS = ("backend-ci.yml", "frontend-ci.yml")


# Function Name: validate_runs
# Description: Require the latest matching push run, including its latest attempt, to pass.
# Parameters: payload - GitHub workflow-run response; sha - exact source; workflow - diagnostic name.
# Returns: None; raises ValueError for absent, malformed, pending or unsuccessful evidence.
def validate_runs(payload: dict, sha: str, workflow: str) -> None:
    runs = [
        run for run in payload["workflow_runs"]
        if run["head_sha"] == sha and run["event"] == "push"
    ]
    if not runs:
        raise ValueError(f"{workflow}: no push CI run for the exact source commit")
    latest = max(runs, key=lambda run: (run["run_number"], run["run_attempt"]))
    if latest["status"] != "completed" or latest["conclusion"] != "success":
        raise ValueError(f"{workflow}: latest run has not completed successfully")


# Function Name: main
# Description: Query only the repository's named CI workflows before allowing signing.
# Parameters: None; uses GitHub runner identity and a read-only Actions token from the environment.
# Returns: Zero on success, one on missing evidence or API/response failure; never prints credentials.
def main() -> int:
    try:
        repository = os.environ["GITHUB_REPOSITORY"]
        sha = os.environ["GITHUB_SHA"]
        token = os.environ["GH_TOKEN"]
        api = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
        query = urlencode({"head_sha": sha, "event": "push", "per_page": 100})
        for workflow in REQUIRED_WORKFLOWS:
            request = Request(
                f"{api}/repos/{repository}/actions/workflows/{workflow}/runs?{query}",
                headers={"Authorization": f"Bearer {token}",
                         "Accept": "application/vnd.github+json"},
            )
            with urlopen(request, timeout=30) as response:
                validate_runs(json.load(response), sha, workflow)
            print(f"{workflow}: exact-commit CI passed")
        return 0
    except Exception as exc:
        print(f"Release CI gate rejected: {type(exc).__name__}. "
              "Both required push workflows must pass for this SHA; retry after CI completes.",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
