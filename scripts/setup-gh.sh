#!/usr/bin/env bash
# One-time GitHub setup: labels, milestones, issues, and a kanban project.
# Requires `gh` authenticated as duongtugiang with repo write access.
set -euo pipefail

REPO="duongtugiang/textmate-swift"
cd "$(dirname "$0")/.."

echo "== Labels (source of truth: .github/labels.yml — keep in sync) =="
# name:color:description
labels=(
  "kind/story:0e8a16:User-visible feature (has acceptance criteria)"
  "kind/task:5319e7:Engineering work with no direct end-user value"
  "kind/bug:d73a4a:Something is broken or behaves incorrectly"
  "kind/spike:fbca04:Time-boxed research or experiment"
  "effort/S:c2e0c6:Less than 1 day"
  "effort/M:bfd4f2:1-3 days"
  "effort/L:fef2c0:3-7 days"
  "effort/XL:f9d0c4:More than 1 week"
  "epic/phase-0:d4c5f9:Phase 0 - Scaffold & build"
  "epic/phase-1:d4c5f9:Phase 1 - Text model"
  "epic/phase-2:d4c5f9:Phase 2 - Editing, rendering & delivery"
  "epic/phase-3:d4c5f9:Phase 3 - Document layer"
  "epic/phase-4:d4c5f9:Phase 4+ - Signature features"
  "gate/tests:0075ca:Blocked until the ported original-TextMate suites are green"
  "ci/cd:0075ca:Touches the CI or release pipelines"
  "status/blocked:b60205:Blocked by an external dependency or open decision"
)
for entry in "${labels[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  color="${rest%%:*}"
  desc="${rest#*:}"
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null 2>&1 \
    || echo "[warn] could not create label '$name'"
done
echo "Labels done."

echo "== Milestones + issues =="
./scripts/create-issues.sh

echo "== Kanban project (best-effort) =="
if gh project list --owner duongtugiang --format json >/dev/null 2>&1; then
  gh project create --owner duongtugiang --title "textmate-swift" 2>/dev/null \
    && echo "Project created — add columns and cards at https://github.com/duongtugiang/textmate-swift/projects" \
    || echo "Project creation skipped/failed — create it at https://github.com/duongtugiang/textmate-swift/projects"
else
  echo "gh project unavailable — create the board at https://github.com/duongtugiang/textmate-swift/projects"
fi

cat <<'EOF'

== Manual follow-ups (repo admin) ==
1. Branch protection on main: Settings → Branches → require PR review + status checks (CI).
2. Release secrets for signed/notarized .dmg (Settings → Secrets and variables → Actions):
   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
   (or App Store Connect API key: APPLE_API_KEY, APPLE_API_KEY_ID, APPLE_API_ISSUER)
   plus signing cert: MACOS_CERTIFICATE (base64 .p12), MACOS_CERTIFICATE_PWD, MACOS_CERTIFICATE_NAME.
3. Backfill the Issue column in ROADMAP.md from docs/issues/issue-map.json.
EOF
