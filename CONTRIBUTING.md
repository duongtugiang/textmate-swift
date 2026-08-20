# Contributing

Welcome! This file is the workflow contract for `textmate-swift`. It defines how we
branch, commit, review, and — most importantly — what "done" means.

## Getting started

- Backlog & status: [GitHub Issues](https://github.com/duongtugiang/textmate-swift/issues)
  (board: see README). Phase index: [ROADMAP.md](ROADMAP.md).
- Test-compatibility tracking: [docs/test-matrix.md](docs/test-matrix.md).
- Architecture decisions: [docs/decisions/](docs/decisions/) (ADRs).

## Branching & pull requests

- **One issue per PR.** Branch name references the issue, e.g. `feat/2-S1-render-text`,
  `fix/1-T1-position-map`, `test/0-T3-port-storage`.
- Open a PR that says **`Closes #N`** in the description so the issue auto-closes on merge.
- Keep PRs small and reviewable (< ~400 lines unless it is a ported test suite — those
  are expected to be large and are reviewed as a batch).
- A PR is mergeable only when the **Definition of Done** below is met and CI is green.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new user-facing feature
- `fix:` — bug fix
- `test:` — tests (including ported TextMate suites)
- `docs:` — documentation (ROADMAP, ADRs, matrix, README)
- `refactor:` — behavior-preserving restructuring
- `chore:` — tooling, CI, build, dependencies

## Definition of Done (applies to every issue)

- [ ] Code merged to `main` via a reviewed PR
- [ ] `swift build` is clean
- [ ] `swift test` is green — **including that phase's ported original-TextMate suites**
- [ ] All acceptance criteria on the issue are met
- [ ] ROADMAP status + issue number updated; board card moved
- [ ] `docs/test-matrix.md` updated (suite counts/status) if the issue touches a gate
- [ ] ADR filed in `docs/decisions/` for any non-obvious design choice
- [ ] CI green; release path exercised at least once per milestone

## Test compatibility gate

The project's core contract: **the Swift implementation must pass the original
TextMate test suites** (ported to Swift XCTest). Rules:

- Port tests *with* the code they specify — never after.
- Translate cases verbatim where possible. Where macOS API drift forces adaptation
  (AppKit-bound `.mm` suites), record the adaptation in the matrix.
- Never silently drop a test. Out-of-scope suites are listed in the matrix with
  rationale and reviewed as part of the change.
- A red ported suite fails CI.

## Review checklist

- Acceptance criteria covered by tests?
- Ported suites: are all original cases present (count matches the matrix)?
- Any skipped/adapted case — is it documented in the matrix?
- ADR needed? ROADMAP/README/matrix updated?
- Conventional commit message? PR links `Closes #N`?
