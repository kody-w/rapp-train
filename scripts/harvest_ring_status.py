#!/usr/bin/env python3
"""harvest_ring_status.py — Static Data Covenant harvester for index.html.

index.html used to make two kinds of unauthenticated calls from the
visitor's browser:
  - https://api.github.com/repos/kody-w/<ring-repo>/commits/main   (per ring)
  - https://api.github.com/repos/kody-w/rapp-canary/branches?per_page=100

Both now read committed snapshots instead:
  - data/commits/<ring-repo>.json   (identical "get a commit" API shape)
  - data/canary-branches.json       (identical "list branches" API shape)

Deliberately uses `git` (smart HTTP / git protocol) rather than the REST
API to build these: git ls-remote / a shallow clone isn't subject to the
unauthenticated api.github.com rate limit, so this stays reliable in CI even
after other jobs have spent the shared 60/hr budget.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RING_REPOS = ["rapp-canary", "rapp-nightly", "rapp-alpha", "rapp-beta", "rapp-installer"]
CANARY_REPO = "rapp-canary"
OWNER = "kody-w"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, check=True, **kw)


def harvest_commit(repo: str, tmp: Path) -> dict:
    dest = tmp / repo
    run(["git", "clone", "--depth", "1", "--branch", "main", "--single-branch",
         f"https://github.com/{OWNER}/{repo}.git", str(dest)])
    sha = run(["git", "-C", str(dest), "rev-parse", "HEAD"]).stdout.strip()
    date_iso = run(["git", "-C", str(dest), "log", "-1", "--format=%cI"]).stdout.strip()
    author_name = run(["git", "-C", str(dest), "log", "-1", "--format=%an"]).stdout.strip()
    author_email = run(["git", "-C", str(dest), "log", "-1", "--format=%ae"]).stdout.strip()
    message = run(["git", "-C", str(dest), "log", "-1", "--format=%B"]).stdout.strip()
    # Shape matches GitHub's "get a commit" response closely enough for the
    # fields index.html actually reads (sha, commit.committer.date).
    return {
        "sha": sha,
        "html_url": f"https://github.com/{OWNER}/{repo}/commit/{sha}",
        "commit": {
            "message": message,
            "author": {"name": author_name, "email": author_email, "date": date_iso},
            "committer": {"name": author_name, "email": author_email, "date": date_iso},
        },
    }


def harvest_branches(repo: str) -> list:
    out = run(["git", "ls-remote", "--heads", f"https://github.com/{OWNER}/{repo}.git"]).stdout
    branches = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        sha, ref = line.split("\t")
        name = ref.removeprefix("refs/heads/")
        branches.append({
            "name": name,
            "commit": {"sha": sha, "url": f"https://api.github.com/repos/{OWNER}/{repo}/commits/{sha}"},
            "protected": name == "main",
        })
    return branches


def main():
    ok = True
    with tempfile.TemporaryDirectory() as tmpd:
        tmp = Path(tmpd)
        out_dir = ROOT / "data" / "commits"
        out_dir.mkdir(parents=True, exist_ok=True)
        for repo in RING_REPOS:
            try:
                data = harvest_commit(repo, tmp)
                (out_dir / f"{repo}.json").write_text(json.dumps(data, indent=1) + "\n")
                print(f"✓ data/commits/{repo}.json — {data['sha'][:7]}")
            except Exception as e:
                print(f"✗ failed to harvest {repo}: {e}", file=sys.stderr)
                ok = False

    try:
        branches = harvest_branches(CANARY_REPO)
        out = ROOT / "data" / "canary-branches.json"
        out.write_text(json.dumps(branches, indent=1) + "\n")
        print(f"✓ data/canary-branches.json — {len(branches)} branches")
    except Exception as e:
        print(f"✗ failed to harvest {CANARY_REPO} branches: {e}", file=sys.stderr)
        ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
