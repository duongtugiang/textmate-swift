#!/usr/bin/env python3
"""Create GitHub milestones and issues from docs/issues/backlog.json.

Safe to re-run: issues already present in docs/issues/issue-map.json are skipped.
Requires `gh` authenticated with write access to the repo.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "docs", "issues", "backlog.json")
MAP_FILE = os.path.join(ROOT, "docs", "issues", "issue-map.json")
BODY_TMPL = os.path.join(ROOT, "docs", "issues", ".issue-body.md")

DOD = "merged to main · build clean · tests green (incl. ported suites) · AC met · matrix/ROADMAP/ADR updated"


def run_gh(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["gh", *args], capture_output=True, text=True)


def render(item: dict) -> str:
    lines = []
    lines.append("## Summary")
    if item.get("story"):
        lines.append(item["story"])
    elif item.get("acceptance_criteria"):
        lines.append(item["title"])
    lines.append("")
    lines.append("## Acceptance criteria")
    for ac in item["acceptance_criteria"]:
        lines.append(f"- [ ] {ac}")
    lines.append("")
    lines.append("## Effort")
    lines.append(item["effort"])
    lines.append("")
    lines.append("## Depends on")
    deps = item.get("depends_on") or []
    lines.append(", ".join(deps) if deps else "none")
    lines.append("")
    lines.append("## Test gate")
    lines.append(item.get("gate") or "n/a")
    lines.append("")
    lines.append("## Definition of Done")
    lines.append(DOD)
    return "\n".join(lines)


def create_milestones(repo: str, names: list) -> None:
    for name in names:
        p = run_gh("api", "-X", "POST", f"repos/{repo}/milestones",
                   "-f", f"title={name}", "-f", "state=open")
        if p.returncode != 0:
            msg = p.stderr.strip()
            if "already_exists" in msg or "422" in msg:
                print(f"milestone '{name}' already exists")
            else:
                print(f"[warn] milestone '{name}' failed: {msg[:160]}", file=sys.stderr)


def main() -> int:
    data = json.load(open(MANIFEST))
    repo = data["repo"]

    print(f"== milestones ({repo}) ==")
    create_milestones(repo, data["milestones"])

    issue_map = {}
    if os.path.exists(MAP_FILE):
        issue_map = json.load(open(MAP_FILE))

    print(f"== issues ({len(data['issues'])} in manifest) ==")
    created = 0
    for item in data["issues"]:
        iid = item["id"]
        if iid in issue_map:
            print(f"skip {iid} (already #{issue_map[iid]})")
            continue
        labels = ",".join(item["labels"])
        args = ["issue", "create", "--repo", repo,
                "--title", item["title"], "--label", labels]
        if item.get("milestone"):
            args += ["--milestone", item["milestone"]]
        body = render(item)
        with open(BODY_TMPL, "w") as f:
            f.write(body)
        args += ["--body-file", BODY_TMPL]
        p = run_gh(*args)
        if p.returncode != 0:
            print(f"[error] {iid} failed: {p.stderr.strip()[:300]}", file=sys.stderr)
            continue
        url = p.stdout.strip()
        m = re.search(r"issues/(\d+)$", url)
        number = int(m.group(1)) if m else None
        issue_map[iid] = number
        created += 1
        print(f"created {iid} -> #{number} ({item['title']})")

    os.remove(BODY_TMPL)
    with open(MAP_FILE, "w") as f:
        json.dump(issue_map, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"\nDone. Created {created} new issues; total mapped: {len(issue_map)}")
    print(f"Map written to {os.path.relpath(MAP_FILE, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
