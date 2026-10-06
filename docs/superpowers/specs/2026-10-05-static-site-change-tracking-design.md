# Static site change tracking

**Status:** design, 2026-10-05. Follows the site builder queue
(`docs/superpowers/specs/2026-10-03-site-builder-queue-design.md`).

## Why

A play published to the static site is a snapshot. When its text, cast, metadata or
relatives change afterwards, nothing says so: the site stays stale until someone remembers to
republish that play, or presses Generate. Generate wipes `_site/` and rebuilds every
published play from the database, changed or not. That takes about 13 s for 83 plays on a
12-core machine, and minutes at the expected 300 plays on the 1-vCPU Fly machine.

## Goals

1. **A live "changed" flag.** Each published play shows when it has changed since it was
   published, as soon as it does, with a Refresh action.
2. **Site-wide change detection.** When the export's own code, assets or settings change,
   every play must be rebuilt, and the admin page says so.
3. **Generate rebuilds only what changed.** Otherwise it refreshes just the changed plays.
4. **Stability.** Change detection does not need touching when a field is added to any
   table.

## Why existing signals cannot serve

- **`plays.updated_at`** changes only when a column on the play's own row changes. Most of
  what a published play shows comes from other tables:
  - `play_divisions`, `play_elements`, `characters`, `element_characters`;
  - `play_editors`, `play_sources`, `play_editorial_notes`, `play_places`;
  - the gazetteer (`places`, `place_names`), whose ancestors appear in breadcrumbs and the
    TEI;
  - the relatives' titles, codes and languages.
- **`Catalogue.update_verse_count/1`** writes only when the count changes, so a typo fix in
  a verse leaves no trace.
- **Several writers record nothing at all**: the Word import, character reordering,
  play-place moves, the `is_complete` toggle and the TEI mix task.
- **The activity log** has gaps, records updates that changed nothing, includes exports, and
  stores place edits without a play.
- **PubSub `play_content:<id>`** is sent only by the content editor.

## Design

### 1. `plays.content_version`, kept by Postgres

**Columns.** `plays.content_version` (bigint, not null) is taken from the sequence
`play_content_version`; `plays.content_txid` (bigint) is the transaction that last bumped it.
Both are written only by the database. The `Play` schema reads `content_version` and never
casts it.

**Functions.** One migration defines five functions. None of them names a data column:
- **`touch_play(play_id)`** runs `UPDATE plays SET content_version =
  nextval('play_content_version'), content_txid = txid_current() WHERE id = play_id AND
  content_txid IS DISTINCT FROM txid_current()`, then `pg_notify('play_changed',
  play_id::text)`.
  - It bumps the play once per transaction, so a TEI import writing thousands of rows updates
    the play row once.
  - Postgres delivers the notification on commit and folds duplicate notifications from one
    transaction into one.
- **The generic row trigger** runs AFTER INSERT, UPDATE and DELETE on `play_divisions`,
  `play_elements`, `characters`, `play_editors`, `play_sources`, `play_editorial_notes` and
  `play_places`. It calls `touch_play(NEW.play_id)` and `touch_play(OLD.play_id)`; both are
  needed when a row moves between plays.
- **On `element_characters`,** the trigger touches the play of the row's element, old and
  new.
- **On `plays`,** two triggers fire on UPDATE, sharing one function, both `WHEN (to_jsonb(OLD) -
  '{content_version,content_txid,updated_at}'::text[] IS DISTINCT FROM to_jsonb(NEW) -
  '{content_version,content_txid,updated_at}'::text[])`:
  - BEFORE: sets the row's own new `content_version` and `content_txid`;
  - AFTER: notifies, then touches the old parent, the new parent and the children,
    because their title pages show this play.

  A bump that only moves `content_version` passes neither `WHEN`, so fan-out never repeats:
  a text edit moves only its own play. New plays start at `nextval`. Inserting or purging a
  play touches nobody: its relatives' pages list only published plays, and publishing or
  unpublishing one already re-exports them (`StaticSite.apply_changes/2`).
- **On `places` (UPDATE) and `place_names` (INSERT, UPDATE, DELETE),** one function,
  given the column naming the place, touches every play linked through `play_places` to
  that place or to any place beneath it (a recursive CTE over `places.parent_place_id`). A
  new place has no plays yet, and a linked place cannot be deleted.

**Deliberately over-inclusive.**
- Any change to a play's row flags its relatives, even when it is a field their pages don't
  show.
- Any statement touching a play's rows flags it, even when the values end up the same.

A needless flag costs a click; a missed one publishes a stale page.

**Measured** on Postgres 16, rolled back: rewriting the 8,341 elements of the largest dev
play costs about 0.25 s more with the triggers than without.

**Excluded.**
- `play_statistics`: derived from the content, and written during the export itself, so it
  would flag every play just exported.
- `activity_logs`: not page data.

**The maintenance rule.**
- A new table whose rows appear on a play's pages gets the generic trigger, which is one
  line in its migration.
- A guard test lists every table with a `play_id` column from `information_schema`. It fails
  unless each one has the trigger or is on the exclusion list.
- Adding columns needs nothing.

### 2. `build.json`

`StaticSite.generate/1` and `StaticSite.apply_changes/2` write `build.json` at the site
root:

```json
{"site": "<fingerprint>", "plays": {"<CODE>": <content_version>, …}}
```

**Each play's version** is the one on the play row loaded for that build.
`StaticSite.Edition.load/1` reads the play row before its content, so content read after it
can only be newer: a play edited during the build stays flagged, never published stale and
recorded as current.

**When it is written:**
- `generate/1` writes the whole file.
- `apply_changes/2` updates it: the entries of the plays it wrote, removed entries for the
  plays it took out, and the fingerprint left as it was.
- **When there is no `build.json` yet** (a site built before this feature), `apply_changes/2`
  writes the entries of the plays it wrote and `"site": null`. The other plays then count
  as changed, and the next Generate is a full rebuild, because a site written by unknown code
  cannot be trusted.
- **A batch that starts from an empty site** (no play on disk) writes every page there is,
  so it records the current fingerprint. A site begun with the switches alone shows no
  "design changed" banner.

**Where it lives.** The record sits next to the files it describes. Wiping the directory,
including an app deploy on a machine without a volume, wipes it too, so the two cannot
disagree. A missing or unreadable `build.json` means there is no trustworthy build. It ships
with the site, and holds only codes and numbers.

**Public functions in `StaticSite`:**
- `changed_plays(dir) :: [code]`: the published plays whose current `content_version` is
  newer than recorded, or that have no record. One query: code and `content_version` for the
  codes on disk.
- `site_changed?(dir, opts) :: boolean`: whether there is no `build.json`, or its fingerprint
  differs from `Fingerprint.current(opts)`.
- `outdated(dir) :: [{:add, play_id} | {:remove, code}]`: the batch that brings the site up
  to date, for section 5.

### 3. The site fingerprint

`StaticSite.Fingerprint.current(opts)` is a hex SHA-256 over:
- `module_info(:md5)` of the export code:
  - every loaded module whose name starts with `Playcode.Export.StaticSite`, plus
    `Playcode.Export.TeiXml`;
  - `Playcode.Statistics`, `Playcode.Statistics.Metrics`;
  - `Playcode.Catalogue.Play`, `Playcode.PlayContent.InlineMarkup`,
    `Playcode.PlayContent.Element`;
  - `Playcode.Places`;
  - `PlaycodeWeb.PlayLabels`, `PlaycodeWeb.Gettext`;
- the contents of every file under `priv/static_site`;
- the versions of the `phoenix_live_view`, `phoenix_html`, `jason` and `xml_builder`
  applications;
- the `:version` option.

**`build_date` is not in it.** The footer's date means "this page was built on", which is
already true of pages written by `apply_changes/2`. **`base_url`** is not in it either:
nothing reads it.

**The module list** comes from the application's own module list
(`Application.spec(:playcode, :modules)`), not from what happens to be loaded: in dev,
modules load on first use, and a list of loaded modules would differ before and after the
first build.

**A guard test** collects the remote calls of every `Playcode.Export.StaticSite*` module from
the `:imports` chunk of its BEAM file (`:beam_lib.chunks/2`), following them transitively
through `Playcode*` and `PlaycodeWeb*` modules. It fails if a reached module is neither
fingerprinted nor on the explicit data-access list, whose changes the triggers already
cover: `Playcode.Catalogue`, `Playcode.PlayContent`, `Playcode.Repo` and their schemas. A new
helper module cannot slip past unnoticed.

### 4. The live flag

**The listener.** `Playcode.Export.PlayChangeListener` runs under the application
supervisor. It holds a `Postgrex.Notifications` connection that uses the repo's
configuration, listens on `play_changed`, and rebroadcasts `{:play_changed, play_id}` on the
`"static_site"` topic.

**The play's own topic.** The listener also sends `{:play_content_changed, play_id}` on
`play_content:<id>`, through `PlayContent.notify_changed/1`. The content editor and the
admin play list already listen there, but until now only the content editor broadcast on
it, so an import, the metadata form or another admin's edit left both pages stale. A
content editor open on a play that is re-imported showed rows that no longer existed, and
deleting one crashed the page.
- `PlayContent.broadcast_content_changed/1` stops broadcasting, since Postgres now does it
  for every writer, and becomes `refresh_derived/1`: the verse count and the cached
  statistics.
- The editing session loses nothing: every editor handler reloads its own assigns
  directly. The hand broadcast only reached other sessions, and made the editing session
  reload a second time.

**The export page:**
- **On mount,** it computes the changed plays and whether the site changed.
- **On `{:play_changed, id}`,** it recomputes that play's state if the play is published.
- **After every builder `:done`,** it recomputes everything.

**What the page shows:**
- **Per changed play:** a "Changed" badge and a **Refresh** button. Refresh calls
  `SiteBuilder.add/2` for a play already in the site, which re-exports it in a batch like
  any other add.
- **When any play changed:** a line, "%{count} published plays have changed. Generate
  refreshes them." Generate is the "refresh all" action (section 5), and runs as one batch.
- **When the site changed:** a banner, "The site's design or settings changed since the last
  build. Generate will rebuild every play."

### 5. Generate

When `SiteBuilder` runs `:generate`:
- **If `site_changed?/2`:** a full rebuild, as today.
- **Otherwise,** one `StaticSite.apply_changes/2` batch:
  - adds: `changed_plays/1`;
  - removes: the codes on disk whose play is archived, deleted or no longer complete.

  This is `StaticSite.outdated/1`. The catalogue is rewritten. With nothing to do, nothing
  is written. The result is `{:ok, %{changed: count, skipped: [play_id]}}`,
  where `count` is the number of plays added or removed. The page says either
  "%{count} plays refreshed." or, for zero, "Nothing has changed since the last build."
- **A new request, `:rebuild`** ("Rebuild everything" on the page), always takes the full
  path. Like `:generate`, it runs alone in its turn and is not queued twice.

### 6. Fixes found on the way

- **A TEI re-import now deletes the play's cached statistics,** as the content editor and
  the Word import already do. Until now the statistics page kept the old numbers.
- **Stable ordering, so unchanged inputs render the same:**
  - `Catalogue.get_play_with_all!/1` orders `derived_plays` by `title_sort, title`;
  - it orders editorial notes by `position`, as the TEI export already does;
  - it orders `place.names` by `position`.

## Optional: a Fly volume

Production has no volume, so every app deploy wipes `_site/` and its `build.json`. The design
handles that: the first Generate after a deploy is a full rebuild. A 1 GB volume (about
$0.15 a month) mounted at `/data`, with `:static_site_dir` pointed there, would make
incremental builds survive deploys. The project owner decides; `CLAUDE.md` records it. The
Postgres volume belongs to the separate database app and cannot be shared.

## Out of scope

- The search index improvements (adaptive shards, tombstone removals, a bigram phrase index,
  a delta segment): a separate project.
- Automatic republishing: a changed play is flagged, never republished by itself.
- Change tracking for the site-wide pages beyond what each build already rewrites.

## Testing

TDD per CLAUDE.md, through the outermost API.
- **The sandbox is one transaction per test,** and a play is bumped once per transaction.
  The trigger tests stand in for the commit between two edits with
  `UPDATE plays SET content_txid = NULL WHERE content_txid = txid_current()`. Tests
  elsewhere edit the play's own row, whose BEFORE trigger always bumps.
- **Triggers:**
  - edit through the context functions, then read `Catalogue.get_play!/1`'s
    `content_version`;
  - each table, and a relative's change;
  - a place rename reaching a play under a child place;
  - several writes in one transaction bumping once;
  - a statistics write not bumping.
- **Guard tests:** trigger coverage and fingerprint coverage.
- **`build.json`:** through `generate/1` and `apply_changes/2`, then `changed_plays/1` and
  `site_changed?/2`.
- **Generate:** through `SiteBuilder`, checking which plays were rewritten by a sentinel
  file planted in each play's folder: rewriting a play deletes its folder first. File
  times have one-second resolution in Erlang, too coarse for a build that takes
  milliseconds.
- **The page:** through `live/2`.
- **The listener:** `pg_notify` is delivered only on commit, which the SQL sandbox never
  does. One test runs inside `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, commits a real edit,
  asserts the PubSub message, and deletes what it created.
