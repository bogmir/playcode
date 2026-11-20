---
name: delete-comment
description: Sweep code comments in a directory (default lib/), sort each block as tautology, stale, excuse or decision record, delete the first three, file excuses in docs/backlog.md, and tighten the comment ratchet. Use when invoked as /delete-comment [PATH].
disable-model-invocation: true
---

# Delete comments

`test/comment_ratchet_test.exs` holds lib/ to `test/comment_baseline.txt`: a file's comments only go down. This sweep is how they go down.

Work in a worktree of your own on a branch `chore/delete-comments-<date>`: other sessions switch branches in the main checkout. Link `deps` from the main checkout (`ln -s ../playcode/deps deps`).

## 1. List

```sh
git ls-files 'PATH/*.ex' | xargs elixir .claude/skills/delete-comment/list_comments.exs > SCRATCH/comments.txt
git grep -n '<%!--' -- 'PATH/*.ex' 'PATH/*.heex'
```

Each block prints as `path:start_line`, its lines, and `=>` the code line after it. Read every block; for a big listing, read it in pages. Done when every block has a category.

## 2. Categorise

- **Tautology**: says what the names and the code already say. `# Extract code from idno` above `extract_idno`, `# --- Editors ---` dividers, phx generator boilerplate (`# See https://hexdocs.pm…`, `## Session`), HEEx labels (`<%!-- Toolbar --%>`). A divider that carries content (`# --- Modern editions: Editors, ed. <<Title>>. Author. ---`) is not one.
- **Stale**: names a file, function, step or behaviour that is gone, or is commented-out code. Check a named path with `git ls-files`, a function with `git grep "def[p]\? name"`. Only the stale clause goes when the rest of the comment holds.
- **Excuse**: lets a hacky implementation stand ("regex since Saxy would need namespaces", a stubbed `x = []` under commented-out code).
- **Decision record**: the why the code cannot show: a question number or date it follows, a corpus fact, a constraint, a measured number, a `ponytail:` ceiling. The house style is full of these; most blocks are one. They stay in the code.

When unsure between tautology and decision record, read the code it sits on: if deleting it loses a fact the code does not hold, it is a decision record.

## 3. Act

- Tautology and stale blocks: list `path start_line …` per file in SCRATCH/targets.txt, then `elixir .claude/skills/delete-comment/delete_blocks.exs SCRATCH/targets.txt`. It refuses a line that is no comment. Trim partial ones and HEEx labels by hand.
- Excuse: delete it and add an item to `docs/backlog.md`, *Medium Priority*: what the code does, why that is wrong, the fix, "(comment sweep, DATE)". Verify every claim in the item against the code.
- Decision record: leave it.

## 4. Check

```sh
mix format
UPDATE_COMMENT_BASELINE=1 mix test test/comment_ratchet_test.exs
mix test 2>&1 | tail -5
```

The baseline diff should show only lower numbers. Sweeping outside lib/ means widening the wildcard in `counts/0` of the ratchet test first, then writing its baseline.

## 5. Report

Per category: blocks and lines deleted, the backlog items filed, and what remains (`awk '{s+=$2} END {print s}' test/comment_baseline.txt`).
