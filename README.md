# TextMate (Swift)

A from-scratch, simplified modernization of [TextMate](https://github.com/textmate/textmate),
rewritten in Swift. The goal is a clean, maintainable editor that starts with a bare
editor core and grows feature-by-feature.

## Decisions (v0)

| Topic | Decision |
|---|---|
| Strategy | Greenfield Swift rewrite |
| Text engine | Bridge the proven C++ core (`buffer`/`text`/`layout`) via a bridging layer |
| UI layer | AppKit (`NSView`) for the text area |
| MVP scope | Bare editor: open, edit, select, undo/redo, save |

See [docs/decisions/](docs/decisions/) for rationale.

## Status

Planning — no buildable app yet. See [ROADMAP.md](ROADMAP.md).

## Layout

```
Core/            Swift code (app, UI, document layer)
Native/          bridged C++ (buffer/text/layout + bridge headers)
docs/decisions/  architecture decision records
ROADMAP.md       phases, milestones, and complexity tracking
```

## License

Derived from TextMate (GPL-3.0-or-later); this project inherits GPL-3.0-or-later.
