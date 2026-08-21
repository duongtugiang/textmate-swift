# Next versions — prioritized backlog

Derived from [feature-comparison.md](feature-comparison.md). Every item is a
GitHub issue (linked below); this file is the index with acceptance criteria
and the original-TextMate reference (see `../textmate`). Order within a version
is the recommended dependency order. Legend as in ROADMAP: effort **S** < 1 day,
**M** 1–3 days, **L** 3–7 days; story = user-visible feature.

## v0.4 — Editing essentials (Text menu + core commands)

The Text menu is the biggest visible gap. Engine prerequisites (case
transforms, indentation) already exist in `TextCore`.

| # | Story | Effort | Depends | AC (user-visible) | Original reference |
|---|---|---|---|---|---|
| 38 | Text ▸ Shift Left/Right (⌘[/⌘]) + indent line/selection | M | — | ⌘[ outdents, ⌘] indents the caret line (or every selected line) by one level; caret/selection preserved | `OakTextView shiftLeft:/shiftRight:`, `editor.cc::shift` |
| 39 | Comment/uncomment (⌘/) | M | 38 | ⌘/ toggles line comment for the grammar's comment scope (falls back to `#`); block comment for line-based toggling where defined | Default bundle "Comment Line / Selection" command; grammar `comment` scope |
| 40 | Text ▸ Move Selection Up/Down (⌃⌘↑/↓) incl. duplicate line (⌃⇧⌘D) | M | — | moving a selection (or caret line) up/down swaps it with its neighbor; ⌃⇧⌘D duplicates; undo-able | `OakTextView moveSelectionUp:/moveSelectionDown:`, `editor.cc` |
| 41 | Text ▸ Uppercase/Lowercase/Titlecase + Toggle Case | S | — | ⌥⌘U / ⌥⌘L / ⌥⌘T on the selection (or word at caret); Titlecase uses the ported `capitalize` | `changeCaseOfWord:` etc.; `TextFormatString.capitalize` already ported |
| 42 | Auto-indent on Return (indent-aware newline) | M | — | pressing Return indents the new line to the current line's indent (trimmed of trailing ws); blank lines inherit the previous indent | `editor.cc::insert_newline_with_indent`, `text::indent_t` (indent.cc dispositioned) |
| 43 | Auto-pairing (brackets/quotes) + Backspace-undoes-pair | M | 42 | typing `(`, `[`, `{`, `"`, `'` inserts the pair and places the caret between; Backspace inside an empty pair deletes both | `OakTextView` smart typing / pairing; `editor.cc` |
| 44 | Text ▸ Re-indent selection (⌃I) + transpose | S | 38 | ⌃I re-indents the selection using the grammar's indent patterns; transpose swaps adjacent chars | `editor.cc::reindent`, Default bundle |
| 45 | Edit ▸ Select ▸ Line / Paragraph / Enclosing Typing Pairs (⌘B) / Current Scope | M | 43 | the remaining Select submenu items select the logical unit; ⌘B grows/shrinks to enclosing pairs | `selectHardLine:/selectParagraph:/selectBlock:/selectCurrentScope:` |

## v0.5 — View & Navigate

| # | Story | Effort | Depends | AC (user-visible) | Original reference |
|---|---|---|---|---|---|
| 46 | View ▸ Font (⌘+/⌘−/⌘0, Show Fonts) | S | — | font size persists per window; ⌘0 resets to default | View ▸ Font menu |
| 47 | View ▸ Show Line Numbers toggle (⌥⌘L) + Show Invisibles (⌥⌘I) | M | — | gutter can be hidden; space/tab/EOL glyphs render when invisibles on | `toggleLineNumbers:/toggleShowInvisibles:` |
| 48 | View ▸ Enable Soft Wrap (⌥⌘W) + wrap column presets + Show Wrap Column | L | — | lines wrap at the wrap column (default 0 = window width); folding/find/selection stay correct across wrapped rows | `toggleSoftWrap:`, `wrapColumnMenu` |
| 49 | View ▸ Tab Size (2–8, Other…) + soft tabs + Show Indent Guides | M | — | tab size and soft-tab (spaces) settings apply to rendering and indentation; indent guides drawn at each level | `takeTabSizeFrom:`, `toggleShowIndentGuides:` |
| 50 | Preferences… (⌘,) with theme (light/dark/other) + settings editor | L | 49 | a preferences panel editing the same settings the engine already resolves (tab size, soft tabs, wrap, font, theme, shellVariables); theme colors drive `Syntax.swift` | `showPreferences:`; `settings` engine (4.S6) |
| 51 | Navigate ▸ Jump to Line… (⌘L) + Jump to Selection (⌘J) | S | — | ⌘L panel moves the caret to a line number; ⌘J centers the caret | `orderFrontGoToLinePanel:/centerSelectionInVisibleArea:` |
| 52 | Navigate ▸ Bookmarks (F2 set/next/prev) | S | — | F2 toggles a bookmark on the caret line; F2/⇧F2 jump; bookmarks survive scrolling and folds | `toggleCurrentBookmark:` etc.; `marks` engine (dispositioned `t_marks`) |
| 53 | File ▸ Open Quickly… (⌘T) — go to file | L | — | ⌘T fuzzy-finds files in the open folder (or recent), multi-select opens tabs; `.ext` filters, `/` full-path, line suffix `:N` | `goToFile:`; `t_glob` suites become the matcher (deferred since 4.T1) |

## v0.6 — Power editing

| # | Story | Effort | Depends | AC (user-visible) | Original reference |
|---|---|---|---|---|---|
| 54 | Multiple carets + column selection | XL | 45 | ⌘-click adds a caret; ⌥-drag selects a column; typing/deleting/arrowing affects all carets; Escape collapses to the primary | `OakTextView` mouse gestures; discontinuous selection; `t_selection` GUI suites |
| 55 | Select Next Occurrence / Find All → selection | M | 54 | ⌃⌘W adds the next occurrence of the current word to the selection; Find All adds all matches | `findAllInSelection:`, Find All |
| 56 | Autocomplete (⎋) with suffix preservation | M | — | ⎋ completes from the buffer's word index; the current-word suffix is preserved (TextMate help "Completion") | `OakTextView` completion; `TextMate.md` Completion |
| 57 | Macros (⌥⌘M record, ⇧⌘M replay, Save Macro…) | M | — | record/replay edits; save/load as bundle items | `toggleMacroRecording:`; `t_macro` (3) suites dispositioned for this |
| 58 | Shell command runner + filter (⌘\|) + run (⌥⌘R) + tab-trigger snippets | XL | 50, 56 | bundle commands run with the full environment (`TextFormatString`/`scope_variables` already ported); stdin/stdout round-trip into the buffer; typing a snippet's tabTrigger + Tab inserts it | `orderFrontRunCommandWindow:`; `editor::filter`; `snippets` + `bundles` engines |
| 59 | Find upgrades: Regular Expression, Wrap Around, Find All, Use Selection for Find (⌘E)/Replace, Replace All in Selection | L | — | find bar gains the Find Options; ⌘E seeds the find field from the selection | Find Options submenu; `find::options_t` |
| 60 | File Browser / project navigator + find in project | XL | 53 | the File Browser menu (new file/folder, back/forward, favorites, SCM status, go-to-folder) plus ⌘⇧F find in project | File Browser menu; `Favorites`/`SCM` |

## Lower priority / deferred (tracked here, not yet issued)

- Print/Page Setup; View Source; Full Screen; Scroll Past End; Touch Bar.
- Spelling (⌘:, ⌘;, check-while-typing) — AppKit `NSSpellChecker` integration.
- Clipboard history (Paste Next/Previous/Show History).
- Go to Related File (⌥⌘↑), Jump to Symbol (⇧⌘T — needs a symbol index).
- Save All/Close Tabs to Left/Right/Sticky/New Tab menu items (tab session mgmt).
- Find history (⌃⌥⌘F) + incremental search (⌃S).
- Terminal integration (mate/rmate, txmt://) + AppleScript suite.
- Bundle editor UI (Edit Bundles… ⌃⌥⌘B) and per-bundle dynamic menus.

## Definition of done (every item)

1. Acceptance criteria above are met and **pixel/keyboard-verified** in the app.
2. Ported C++ suites (where listed in docs/test-matrix.md) are green.
3. ROADMAP status + docs/test-matrix.md updated; progress.html appended.
4. Issue closed with an evidence comment; CI green; commit pushed.
