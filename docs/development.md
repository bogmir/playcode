# Loading data, and other development recipes

## The TEI corpus

Load the corpus: the 385 production files under `doc/tei_corpus/` (git-ignored; copy them there first; 13 of them from the project's GitHub copy since 2026-10-21) plus the fixtures under `test/fixtures/`, 407 plays, one per code, a `doc/tei_corpus` file winning over a fixture with the same code:

```bash
mix playcode.import.tei             # skip codes already imported
mix playcode.import.tei --dry-run   # report what would happen, write nothing
mix playcode.import.tei --force     # re-import every file, updating in place
mix playcode.import.tei --force --resume  # ...except plays imported since their file was written
mix playcode.import.tei --force --overwrite-edits  # ...and plays edited by hand too
```

`--force` skips a play with rows from its file edited by hand since their import, and names
it; the dry run says which it would skip. `--overwrite-edits` replaces those rows as well,
once someone has looked at them. The admin import page asks for the same thing as a tick.

Write Playcode's own TEI back to a corpus directory, each play as its download, named
`CODE.xml` as the corpus files are (archived plays left out); on Fly,
`Playcode.Release.export_tei/2`:

```bash
mix playcode.export.tei --dir DIR              # every play
mix playcode.export.tei --dir DIR --code CODE  # one play
```

On Fly, `mix playcode.fly.reimport prepare`, `run` (`run --overwrite-edits` to replace
plays edited by hand), `generate` and, after the preview,
`deploy`, from this directory (`docs/production-reimport.md`).

## FileMaker

Correct `language`, `relationship_type`, `parent_play_id` and `author_sort` from the FileMaker
published index,
and bootstrap `historical_time`/`historical_time_note` from the version records
(`doc/w3emothe_T01_tituloEM.ndjson`, git-ignored):

```bash
mix playcode.import.filemaker --dry-run   # print the changes, write nothing
mix playcode.import.filemaker             # apply them
mix playcode.import.filemaker --force     # also overwrite curated conflicts
```

The derived fields (`language`, `relationship_type`, `parent_play_id`, `author_sort`) overwrite
unconditionally —
the index is authoritative — but for what it cannot say: it knows only originals and translations, so
an adaptation, refundición or version keeps its kind and its original (filled when it has none), and
the families question 15 corrected stay so (`FilemakerSync`'s `@corrected_originals`).
`author_sort` is the work's author as emothe.uv.es's list gave it (`bus_autor`: "Vega y Carpio,
Félix Lope de"), one form for every play of the work, where the files' `<author key="orden">`
disagreed (2026-11-23); the TEI export writes it back to the file, so a TEI re-import from files
exported before the sync undoes it. The curated fields (`historical_time`, `historical_time_note`) are
fill-only: written when blank, reported as a conflict when they differ, overwritten only under
`--force`.

Create FileMaker's records Playcode does not hold as draft plays without a text, once, before the
four imports below, which then fill them too (`T01_ObraTitulo.xml` and `T00_ObraIndice.xml`, the
2026-11-17 export, under `doc/ctce_dades/`). A record whose code Playcode holds, archived plays
included, is left alone; FileMaker's tests and records with no title, no work or no language are
skipped and named. Each play gets its kind and, when Playcode holds it or the run creates it, its
original. A re-run creates nothing. FileMaker's own TEI for these plays goes through the TEI import,
which keeps the kind and original; a file that does not read is left for later:

```bash
mix playcode.import.filemaker.plays --texts tmp/fm-texts   # FileMaker's texts, nothing created
mix playcode.import.filemaker.plays --dry-run              # the plan: each play, each skip
mix playcode.import.filemaker.plays                        # create them
mix playcode.import.tei --dir tmp/fm-texts --force         # fill in the texts that read
```

On Fly, `Playcode.Release.import_filemaker_plays/2`, `dry_run: true` first, then the texts with
`mix playcode.fly.reimport files --dir tmp/fm-texts` (keep only the files the local import read).

Bring FileMaker's bibliography into the plays we hold, once (S4; the six tables of the
`ctce_dades` dump under `doc/ctce_dades/`, git-ignored). A re-run skips plays already imported,
so a curator's edits stay; on Fly, `Playcode.Release.import_bibliography/2`:

```bash
mix playcode.import.bibliography --dry-run   # the plan, per play and per skip reason
mix playcode.import.bibliography             # write it
```

Its witnesses likewise (S3; `T03` and `T03.2` under `doc/ctce_dades/`); on Fly,
`Playcode.Release.import_witnesses/2`:

```bash
mix playcode.import.witnesses --dry-run   # the plan, per play and per skip reason
mix playcode.import.witnesses             # write it
```

Its places of action likewise, each link with the historical state its place belonged to (S9b; the
`T10*` tables, read from `doc/ctce_dades/` or `--path DIR`). A re-run skips plays already imported, so a
curator's deletions stay, and the links (origin `filemaker`) survive a TEI re-import; on Fly,
`Playcode.Release.import_places/2`, `dry_run: true` first:

```bash
mix playcode.import.places --dry-run   # the plan, per play and per skip reason
mix playcode.import.places             # write it
```

The TEI header is not authoritative for language — every EMOTHE file carries `xml:lang="es"` for
the editorial platform. The index's `[EN]`/`[FR]` tag is.

Its performances likewise, each with its company, cast, place and source (S5; the `T11*`, `T13*`
and `T10*` tables, from `doc/ctce_dades/` or `--path DIR`). The sources of one work (Wiggins's
*British Drama*, the CATCOM catalogue) become one entry, the hand list at the top of
`Import.Performances`; FileMaker's twin companies and actors become one. A re-run skips plays
already imported, so a curator's deletions stay; on Fly, `Playcode.Release.import_performances/2`,
`dry_run: true` first:

```bash
mix playcode.import.performances --dry-run   # the plan, per play and per skip reason
mix playcode.import.performances             # write it
```

## Gettext

`mix gettext.extract --merge` works in this repo; note that it fuzzy-matches new strings onto unrelated existing translations. Check every entry it marks fuzzy before trusting it.

When `mix gettext.extract --merge` is not runnable, find missing translations manually:

```bash
# Strings in code but not in PO file:
grep -rho 'gettext("[^"]*")' lib/ | sed 's/.*gettext("\(.*\)")/\1/' | sort -u > /tmp/code_strings.txt
grep '^msgid ' priv/gettext/es/LC_MESSAGES/default.po | sed 's/msgid "\(.*\)"/\1/' | sort -u > /tmp/po_strings.txt
comm -23 /tmp/code_strings.txt /tmp/po_strings.txt
```
