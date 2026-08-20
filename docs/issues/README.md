# Backlog manifest

The GitHub backlog is generated from **`backlog.json`** — the single source for
issue titles, bodies, labels, and milestones.

- `backlog.json` — the 37 issues (18 stories + 19 tasks) from [ROADMAP.md](../../ROADMAP.md).
- `issue-map.json` — written by the script; maps roadmap IDs → GitHub issue numbers
  (e.g. `"0.S1": 12`), used to backfill the ROADMAP and to skip already-created issues
  on re-runs.

## Creating issues

```bash
./scripts/create-issues.sh
```

Creates the milestones, then every issue that isn't already in `issue-map.json`.
Safe to re-run — already-created issues are skipped. Requires `gh` authenticated as
`duongtugiang`.

## After creation

1. Backfill the `Issue` column in [ROADMAP.md](../../ROADMAP.md) from `issue-map.json`.
2. Add the issues to the kanban board (see `scripts/setup-gh.sh`).

## Editing the backlog

Edit `backlog.json`, then re-run `scripts/create-issues.sh`. New issues are created;
titles/bodies of existing issues are **not** auto-updated (update those in GitHub).

## Label/milestone source

- Labels: [.github/labels.yml](../../.github/labels.yml) (reference) + `scripts/setup-gh.sh` (application).
- Milestones: defined in `backlog.json`.
