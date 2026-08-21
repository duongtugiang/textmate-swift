# Feature comparison — textmate-swift vs original TextMate

Status of every menu and editing feature of TextMate 2 (from the original
source, `Applications/TextMate/src/AppController.mm -mainMenu`) against this
port, as of **v0.3.0**. Legend: ✅ shipped · 🔶 partial · ❌ missing (planned —
see [next-versions.md](next-versions.md) for the issue numbers).

## Menus

### App menu (TextMate)

| Item | Status | Notes |
|---|---|---|
| About | ❌ | app-menu About panel |
| Preferences… (⌘,) | ❌ | settings editor UI — the engine-level `scope_variables`/settings resolution exists (4.S6) |
| Check for Update | ❌ | needs a Sparkle-style update path |
| Services / Hide / Quit | ✅ | standard app menu |

### File

| Item | Status | Notes |
|---|---|---|
| New (⌘N) / Open… (⌘O) / Close (⌘W) / Save (⌘S) / Save As… (⇧⌘S) | ✅ | NSDocument-based; encodings; dirty sheets |
| New Tab (⌥⌘N) | 🔶 | tabs exist (automatic window tabbing); explicit New Tab item missing |
| Open Quickly… (⌘T) | ❌ | fuzzy file finder (also the File Browser dependency) |
| Open Recent / Open Recent Project… | 🔶 | system Open Recent works; project (folder) support missing |
| Close Window / Close All Tabs / Close Other Tabs / Close Tabs to Left/Right | ❌ | tab-session management |
| Sticky | ❌ | pinned tab |
| Save All (⌥⌘S) / Revert | ❌ | |
| Page Setup… / Print… (⌘P) | ❌ | |

### Edit

| Item | Status | Notes |
|---|---|---|
| Undo/Redo (⌘Z/⇧⌘Z), Cut/Copy/Paste (⌘X/⌘C/⌘V), Select All (⌘A), Delete | ✅ | engine-backed undo with typing coalescing |
| Paste Without Indenting / Paste Next / Paste Previous / Show History | ❌ | clipboard history stack |
| Macros (⌥⌘M record, ⇧⌘M replay, Save Macro…) | ❌ | macro engine — the `t_macro` (3) C++ suites are dispositioned for it |
| Select ▸ Word / Line / Paragraph / Current Scope / Enclosing Pairs (⌘B) / All / Toggle Column Selection (⌥) | 🔶 | Word + All done; Line/Paragraph/Scope/Block + **column selection** missing |
| Find ▸ Find and Replace… (⌘F), Find Next/Prev (⌘G/⇧⌘G), Find All, Replace/Replace & Find/Replace All/Replace All in Selection, Use Selection for Find (⌘E)/Replace (⇧⌘E) | 🔶 | find bar with live highlights + replace/replace-all done; **regex option, Find All, Use Selection, find-in-project, find history, incremental search (⌃S)** missing |
| Find Options ▸ Ignore Case / Regular Expression / Ignore Whitespace / Wrap Around | 🔶 | case toggle done; regex/whitespace/wrap missing |
| Spelling (⌘: panel, ⌘; check, check-while-typing) | ❌ | |

### View

| Item | Status | Notes |
|---|---|---|
| Font ▸ Show Fonts / Bigger (⌘+) / Smaller (⌘−) / Default Size (⌘0) | ❌ | font size fixed at 13pt |
| Show File Browser / Show HTML Output | ❌ | project browser is a whole feature (File Browser menu) |
| Show Line Numbers (⌥⌘L) | 🔶 | gutter always on; toggle missing |
| Show Invisibles (⌥⌘I) | ❌ | |
| Enable Soft Wrap (⌥⌘W) / Show Wrap Column / Show Indent Guides / Wrap Column presets | ❌ | no wrap at all |
| Tab Size (2–8, Other…) | ❌ | tab width hard-coded |
| Theme (Light/Dark/Other…) | ❌ | theme colors hard-coded in `Syntax.swift` |
| Fold Current Block (F1) / Toggle Foldings at Level | 🔶 | ⌘⌥[/⌘⌥] fold/unfold done; F1 + level folding missing |
| Toggle Scroll Past End | ❌ | |
| View Source (⌥⌘U) | ❌ | |
| Enter Full Screen (⌃⌘F) | ❌ | |
| Customize Touch Bar… | ❌ | |

### Navigate

| Item | Status | Notes |
|---|---|---|
| Jump to Line… (⌘L) | ❌ | |
| Jump to Symbol… (⇧⌘T) | ❌ | needs symbol index from the grammar engine |
| Jump to Selection (⌘J) | ❌ | center caret |
| Bookmarks (F2 set/next/prev, Jump to Bookmark) | ❌ | |
| Next/Previous Mark (F3) | ❌ | |
| Scroll ▸ Line/Column (⌃⌥⌘ arrows) | ❌ | |
| Go to Related File (⌥⌘↑) | ❌ | header/source switching |
| Move Focus to File Browser (⌥⌘Tab) | ❌ | |

### Text

| Item | Status | Notes |
|---|---|---|
| Transpose | ❌ | |
| Move Selection ▸ Up/Down/Left/Right (⌃⌘ arrows) | ❌ | line move/duplicate is a core editing command |
| Toggle Case of Character/Word, Uppercase/Lowercase/Titlecase | ❌ | case engine exists in TextFormatString; not wired to editing |
| Shift Left/Right (⌘[/⌘]) | ❌ | **indent/outdent — highest-priority Text-menu item** |
| Indent Line/Selection | ❌ | |
| Reformat Text / Reformat & Justify / Unwrap Paragraph | ❌ | |
| Filter Through Command… (⌘\|) | ❌ | needs the command runner |

### Find (submenu of Edit — see above)

### File Browser (project navigator)

| Item | Status | Notes |
|---|---|---|
| New File / New Folder | ❌ | |
| Back/Forward/Enclosing Folder/Project Folder/Computer/Home/Desktop/Favorites | ❌ | |
| SCM Status (⌘Y) | ❌ | git integration |
| Go to Folder… / Reload | ❌ | |

### Bundles

| Item | Status | Notes |
|---|---|---|
| Load Grammar… | ✅ | `.tmLanguage` / `.tmBundle` → highlighting |
| Insert Snippet… | ✅ | full snippet engine behind it |
| Select Bundle Item… (⌃⌘T) | ❌ | |
| Edit Bundles… (⌃⌥⌘B) | ❌ | bundle editor UI |
| Dynamic bundle menus (all installed bundles' items) | ❌ | the query engine exists (`TextBundles`); menu population + item execution missing |
| Tab-trigger expansion (type trigger + Tab) | ❌ | `TextBundles` query ready; EditorView Tab handler is the hook |
| Commands (shell-based, ⌥⌘R run, ⌘\| filter) | ❌ | needs the command runner + `TextFormatString` env expansion (engine exists) |

### Window

| Item | Status | Notes |
|---|---|---|
| Minimize (⌘M) / Zoom / Bring All to Front | ✅ | |
| Show Previous/Next Tab (⇧⌃Tab / ⌃Tab, ⌥⌘←/→, ⌘{/}) | 🔶 | automatic tabbing + ⌘` cycling; explicit items missing |
| Show Tab / Move Tab to New Window | ❌ | |
| Merge All Windows | ✅ | |

### Help

| Item | Status | Notes |
|---|---|---|
| TextMate Help | ❌ | Help menu absent |

## Editing features (beyond menus)

| Feature | Original | Ours | Notes |
|---|---|---|---|
| Multiple carets (⌘-click) | ✅ | ❌ | |
| Column / rectangular selection (⌥-drag, Toggle Column Selection) | ✅ | ❌ | |
| Select Next Occurrence (⌃⌘W / Find All) | ✅ | ❌ | find highlights exist; selection accumulation missing |
| Autocomplete (⎋) with current-word suffix | ✅ | ❌ | |
| Auto-pairing (brackets/quotes) + auto-indent on Return | ✅ | ❌ | |
| Comment/uncomment (⌘/) | ✅ | ❌ | Default-bundle command in original |
| Re-indent selection (⌃I) | ✅ | ❌ | |
| Duplicate line/selection (⌃⇧⌘D) | ✅ | ❌ | part of Move Selection in original |
| Word wrap + wrap column | ✅ | ❌ | |
| Soft tabs / tab size / indent guides | ✅ | ❌ | |
| Syntax highlighting + gutter | ✅ | ✅ | |
| Code folding (F1, level folding) | ✅ | 🔶 | ⌘⌥[/⌘⌥] + gutter done |
| Find & replace (regex, wrap, find all) | ✅ | 🔶 | plain-text only |
| Snippets (tab triggers, mirrors, transforms, choices) | ✅ | ✅ | engine complete; menu-only insertion |
| Macros | ✅ | ❌ | |
| Shell commands / filters | ✅ | ❌ | |
| Go to file/symbol/line | ✅ | ❌ | |
| Bookmark lines | ✅ | ❌ | |
| Spelling | ✅ | ❌ | |
| Show invisibles | ✅ | ❌ | |
| Terminal integration (mate / rmate / txmt://) | ✅ | ❌ | |
| Scriptability (AppleScript suite, `TextMate.scriptSuite`) | ✅ | ❌ | |

## What the port already exceeds

- **Engine fidelity**: the piece-tree buffer, undo, scope rank formula,
  grammar anchor semantics, format strings, and snippet machinery are ported
  and verified against the original C++ test suites (126 green).
- **Perf**: 0.063 ms visible-window render on 11.5 MB (2.T3) — two orders of
  magnitude under the C++ baseline.
- **Modern delivery**: SwiftPM + XcodeGen + CI + tag-to-release CD (unsigned
  leg live; notarization awaits secrets).

## Bottom line

The **engine is complete**; the **editing surface is ~40%**. The biggest
gaps are (1) the Text menu (indent, case, line move), (2) the View menu
(wrap, tab size, theme, invisibles), (3) multi-caret/column selection,
(4) autocomplete + auto-pairing, (5) the command runner + tab-trigger
snippets, (6) the File Browser/project, and (7) Navigate (go to line/file/
symbol, bookmarks). See [next-versions.md](next-versions.md) for the
prioritized plan with acceptance criteria and issue numbers.
