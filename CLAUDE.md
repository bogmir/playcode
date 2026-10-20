# Playcode - Digital Theatre Play Management System

The backend behind the EMOTHE and ARTELOPE public sites. It manages, catalogues and presents digitized early modern European theatre plays (16th-17th century): humanities researchers input play data, export to TEI-XML/PDF/HTML, and it generates the static pages those sites publish, with statistics.

EMOTHE and ARTELOPE stay the public brands; Playcode is the internal platform they both run on. Reference site: https://emothe.uv.es

## Where Things Are Written Down

This file holds the rules every session needs. The rest is in `docs/`:

- `CONTEXT.md` - the glossary: the project's words for its concepts (paratext, editorial text, kind…) and the words to avoid
- `docs/architecture.md` - the file map, the routes and the key decisions
- `docs/schema.md` - every table and column, and the rules behind them; the account lifecycle
- `docs/tei-mapping.md` - how each element of a TEI file reaches Playcode and back
- `docs/development.md` - loading the corpus and FileMaker's data, and what each re-run keeps; gettext recipes
- `docs/static-site.md` - the static site export in full: architecture, measurements, output, publishing on emothe.uv.es
- `docs/production-reimport.md` - re-importing the TEI corpus on Fly: the machines, the steps, and what broke each time
- `docs/backlog.md` - open work, the TEI corpus gaps among it
- `docs/history.md` - what has been built, and what each audit found and fixed
- `docs/static-site-improvements.md` - deferred static-site and exporter work, written up at length
- `docs/stakeholder/ida-y-vuelta.html` - which part of a play reaches which output (admin, TEI export, TEI import, HTML/PDF/EPUB, the play page, the static site), and every gap: the one table, written for the project
- `docs/stakeholder/preguntas.html` - the project's open questions, one running list (numbers never change; new ones go at the end), plus the FileMaker tables still to ask for. A question for the stakeholders goes here, with its background in a page of its own beside it
- `docs/superpowers/specs/` and `docs/superpowers/plans/` - one design and one plan per project

Finishing a project moves its item from `docs/backlog.md` to `docs/history.md`. This file
changes only when a rule, an invariant or a command changes.

## How To Work In This Repo

**Naming.** The application was renamed `Emothe` -> `Playcode` on 2026-09-21, because a
backend serving both EMOTHE and ARTELOPE should not be named after one of them. Upper-case
`EMOTHE` is *never* the application: it is a play code (`EMOTHE0010`), the corpus, or the
public brand. Five lower-case tokens are also not the application and must survive any future
search-and-replace - `emothe.uv.es`, `plays.emothe_id`, `w3emothe` (the FileMaker export's
database, including the real path `doc/w3emothe_T01_tituloEM.ndjson`), `emothe-static` (the
published site's repo and .zip) and `emothe-db-1g` (production's database, a Fly app). `test/rename_guard_test.exs` enforces all of this; read it
before running any bulk rename. Plans and specs under `docs/superpowers/` written before that
date use the old namespace and are left as written - they record work done, not instructions.
The one exception is the FileMaker roadmap, `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`:
its slices are still to be built, so it uses the new names.

**Test-driven development is required.** Every feature and every bugfix follows the same loop, in this order:

1. **Write the failing test first.** Before touching implementation code, write a test that expresses the behaviour you want.
2. **Run it and watch it fail.** Paste-worthy proof that the test exercises the thing you are about to build. A test that passes before the implementation exists is testing nothing.
3. **Write the smallest implementation that passes.**
4. **Run the test again.** It must pass.
5. **Refactor while green.** Clean what you just wrote and what it touches: clear names, no duplication, a helper the code already has instead of a new one, the surrounding idiom (Saša Jurić's clear code). Behaviour stays the same; run the test after each change.
6. **Run `mix test`** — the whole suite, not just the new file — before claiming anything works.

Rules that follow from this:

- **Never claim "done", "fixed" or "working" without the command output that proves it.** Evidence first, assertion second.
- **A failing test is information, not an obstacle.** If a test fails, read the failure before changing anything. If the failure means the *test's* expectation was wrong, fix the test and say so — but check the implementation first.
- **An existing test that contradicts a deliberate behaviour change gets updated, with a comment saying why.** See `test/playcode/import/tei_import_test.exs`, "the play it returns is the play as stored": it used to assert the stale value `import_file/1` returned.
- **Bugfixes get a regression test** that fails before the fix.
- **`mix format` after every task.** The repo is formatted; a noisy diff hides the real change.
- **`mix compile --warnings-as-errors` before committing.**

**Test behaviour through the outermost API** (Saša Jurić's rule). A user journey is
tested through its route: a LiveView with `live/2`, `form/3` and `render_submit/1`, a
controller with `get`/`post`, a mix task with `Mix.Task.rerun/2`. Test an internal only
where the outer path is much slower or clumsier to set up: the TEI and Word importers
through `TeiImport.import_file/1` / `WordParser.import_content/2`, the FileMaker sync
rules through `FilemakerSync.plan/3`, the account token rules through `Accounts`. Even
then, assert on what someone outside can observe, never on how rows are stored:

- **Import and export are asserted as round trips.** Import a TEI snippet, export it,
  query the XML: `roundtrip/1`, `xml_elements/3`, `xml_texts/3`, `outline/1` and
  `docx/1` in `test/support/import_helpers.ex`. Not `parent_id`, `position` or element
  types.
- **Read back through a context's public functions**, not `Repo`. `DataCase` does not
  import `Repo` or `Ecto.Query`; the rare test that must reach past the contexts (ageing
  a token, say) aliases them in place and says why.
- **Select by what the user sees or by a stable id**: `element(lv, "#user-#{id} button",
  t("Reactivate"))`, an `aria-label` on an icon-only button, `aria-current` in the
  sidebar. Not `phx-click` attributes, CSS classes or regexes over markup. `t/2` in
  ConnCase gives the Spanish text the page renders.
- **Prove a new test bites.** A test written for code that already works passes at
  once, which proves nothing. Break the line it covers, watch it go red, put it back,
  and say so in the commit.
- **Delete a test only when you can name what still covers its behaviour.**
- **Who may open which page** is `test/playcode_web/authorization_test.exs`, a
  route-by-persona table written by hand. Add a row for every new gated route: a test
  reading the router fails until you do.

Where the tests live: `test/playcode/` for contexts, importers and exporters
(`tei_roundtrip_test.exs` for everything a TEI file carries); `test/playcode_web/` for
routes, LiveViews and controllers; `test/mix/tasks_test.exs` for the mix tasks;
`test/support/fixtures.ex` for `play_fixture/1` and friends (users are made through the
invite flow); `test/fixtures/` for TEI, Word and FileMaker sample files.

**The TEI file is a complete copy of a play.** Export a play, import the file into an empty
database, and every row comes back: the text and notes, the bibliography and witnesses, the curated
columns. An export the import does not read back is a bug, not a deferral. **If TEI has an element
or attribute for a piece of data, the export writes it there, wherever the data came from**: the
file, a form, or FileMaker. FileMaker is imported once and not gone back to, so FileMaker data
held only in the database cannot be recovered from the TEI files (`FilemakerSync` and the S3/S4
imports write rows, not files); a new slice writes its data to the TEI from the start. The
reverse holds too: what TEI can say and Playcode cannot store (which cast list a character is
in) is a gap in Playcode.
`docs/stakeholder/ida-y-vuelta.html` tables each part of a play against the admin, the TEI export,
the TEI import, HTML/PDF/EPUB, the play page and the static site, in words the project reads; it is
the only copy. A change that adds data to a play fills its row, and a cell short of "yes" is an
item in `docs/backlog.md`, *Round trip*, with the technical detail, or an exception the page
explains (a researcher's note never leaves Playcode: the file is published with the static site).
**Whether a play is complete, and whether its variants are shown (`show_variants`), are the two
curated columns kept out of the file on purpose**: they are Playcode's switches for what visitors
see, not part of the edition, so a play imported from a file arrives as a draft (decided
2026-10-13) with its variants shown (2026-10-18). `test/playcode/complete_copy_test.exs` holds
the rule: it builds an ordinary play and one with the rarer encodings, every column filled,
exports them, imports the files into an empty Playcode and compares every column of every row.
A new column joins that comparison by itself; it is written to the file, dropped there with the
reason, or listed among the test's known gaps with its item in `docs/backlog.md`. A new table with a
`play_id` fails the test's table check until its snapshot reads the table, or lists it as kept out. **A TEI file names no FileMaker or Playcode identifier**:
no record numbers, no database ids. The only identifiers it gives are play codes (a translation's
original, `EMOTHE0530`) and the ones TEI defines (sigla, the text's `xml:id`s); a FileMaker number
stays in the installation FileMaker was imported into (decided 2026-10-13).

**Accessibility** is held by `test/playcode_web/accessibility_test.exs`, which renders
every page, the content editor's tabs and the modal forms, and fails on an unnamed control,
link or button, an `aria-label` on a role-less element, content outside a landmark, or a
scrolling box with nothing focusable (give it `tabindex="0" role="region" aria-label`); add
a new page's path to its list. Contrast is not testable without a browser: both daisyUI
themes' colours in `app.css` are tuned to 4.5:1 (regenerating a theme undoes that), muted
text is never lighter than `text-base-content/70`, and a `<label>` names
its control through `for={@form[:x].id}` or by wrapping it.

`mix test --include slow` adds the TEI schema validation and the full corpus sweep in
`test/playcode/roundtrip_test.exs`: every tracked `test/fixtures/*.xml` plus the
git-ignored `test/fixtures/tei_files/`, a few minutes. The default run covers two of those
files.

**Two async tests creating the same place deadlock.** `places.slug` is unique across the whole
corpus, so two async tests creating a place with the same name take the same index lock inside
their own transactions — a pair of those acquired in opposite order deadlocks Postgres.
`place_fixture/1` therefore derives a *unique* slug unless you pass `"slug"`. Pass one only when
the test asserts on the literal value, and then give it a per-file prefix (`tx-roma`, `sch-roma`).
A test about slug derivation itself should call `Places.create_place/1` directly and use a
toponym no other test uses.

## Tech Stack

- Elixir 1.19.5 / Erlang/OTP 28.1 (via asdf, see `.tool-versions`)
- Phoenix 1.8.3, LiveView 1.1.22, Tailwind 4.x
- PostgreSQL with UUID primary keys
- OpenTelemetry (Phoenix, Ecto, Bandit), instrumented only when `:opentelemetry, :traces_exporter` is not `:none`: every environment has `:none` today (production reads `OTEL_TRACES_EXPORTER`), and OpentelemetryEcto alone costs every query about 55 µs
- Saxy for TEI-XML parsing, xml_builder for TEI-XML generation
- ChromicPDF (headless Chrome) for PDF generation
- Deployed on Fly.io (see *Production*)

## Database Schema

The tables, their columns and the rules behind each: `docs/schema.md`. What bites when you change them:

- All tables use UUID primary keys. A play has its divisions (a `parent_id` tree: acts contain scenes), its elements (speeches contain line groups contain verse lines), characters, editors, sources, paratexts, notes and variants (`play_notes`), witnesses, place links, bibliography links and performances. Bibliography entries, places, companies and actors are corpus-wide, shared by every play that names them, so one correction reaches them all
- `plays.content_version` is moved by Postgres triggers whenever anything a play's static pages show changes, and never written by the app. **A new table with a `play_id` whose rows appear on a play's pages needs the `play_row_changed()` trigger in its migration**; `test/playcode/content_version_test.exs` fails until it has it
- **Every text the TEI importer reads holds `<emph>` as `<<…>>`**, not only a line: a source's note, a front-matter section, a character's name and description, a heading. Print such text through the text's renderers (`PlayText.inline_content`, `Components.inline`, `NoteMarkup.inline`), export it through `TeiXml`'s `build_inline_content`, and where markup cannot go (a link, a title attribute, a `<title>`) use `InlineMarkup.plain/1`. Printing it with `{text}` or `escape/1` shows the markers to readers
- `play_elements.content` holds inline markers beside the italics (`<stage>`, `<aside>`, `<folio>`, `<lb n="…"/>`); `Element.changeset` refuses a malformed one. `/api/v1` returns `content` raw, markers included
- **A re-import replaces the play's elements, divisions and notes: hand edits to its lines and hand-added notes are lost** (`play_notes` has no `origin` column)

### Archiving and provenance

- `plays.deleted_at` is archiving, not deletion: every Catalogue read hides archived plays (`include_deleted: true` for both, `archived: true` for only those); `purge_play/1` is the destructive path, wired to no button. The unique index on `plays.code` is global, so an archived play keeps its code reserved.
- Editors, sources, paratexts, witnesses, place links, bibliography links and performances carry an `origin` (`"tei" | "manual" | "filemaker"`, a paratext also `"word"`). A TEI re-import replaces only its own `"tei"` rows (bibliography links it only adds) and a Word import only its `"word"` ones, so hand-entered records survive.
- **Re-importing a TEI file whose code exists updates that play in place** (same `id`, same history, un-archived). It does *not* write `language`, `relationship_type`, `parent_play_id`, `is_complete`, `historical_time`, `historical_time_note`, `composition_date_from`, `composition_date_to`, `composition_date_note`, `form` or `show_variants` — those are `@platform_owned` in `lib/playcode/import/tei_import.ex`. Any new curated column must be added to that list: for a column the TEI parser emits, the list is what stops the re-import overwriting it; for one it does not emit, the list is what makes the import preview report it as preserved.
- `TeiImport.preview_import/1` reports what an import would replace and keep, without writing. Used by the admin import page and `mix playcode.import.tei --dry-run`.

### Access control

- **Accounts are invite-only, and deactivated, never deleted** (`activity_logs.user_id` references them); the account lifecycle (invites, resets, sessions, throttling) is in `docs/schema.md`, *Accounts*.
- **`ADMIN_EMAILS`** is the source of truth for who is an admin. `Playcode.Accounts.AdminBootstrap`
  reconciles it at boot: unknown addresses get an invited admin plus mail, non-admins get
  promoted, deactivated ones get reactivated. Those accounts cannot be demoted, deactivated
  or deleted from `/admin/users` — `Accounts.protected_admin?/1` refuses in the handler.
  **Unset in production means zero admins.** Break-glass: `mix playcode.invite EMAIL --admin --print-url`,
  or `Playcode.Release.invite_url/1` from `fly ssh console`, both of which bypass SMTP.
- **`Playcode.Authz.can?(user, action, resource \\ nil)` is the only authorization predicate.**
  The router, the LiveView mount hooks and the admin sidebar all call it, which is what keeps
  the nav and the routes from drifting — `/admin/users` was previously reachable but unlinked.
  Never write `role == :admin` outside that module for an access decision. Because
  `pipe_through` cannot pass options to a plug, each permission gets a one-line pipeline
  (`:require_admin_area`, `:require_deploy`, `:require_dashboard`) wrapping
  `UserAuth.require_permission/2`.
- **Researchers** get every content action (plays, content, editors, sources, import, export
  download, archive). **Admins** additionally get purge, user management, activity log, site
  deploy and the dashboard. The FileMaker imports run from the backend (mix tasks, and
  `Playcode.Release` on Fly); the `/admin/filemaker` upload page was removed on 2026-10-18,
  its S1/S2 sync done.
- **A draft (`is_complete: false`) is for staff only.** `/plays/:code`, its compare page and
  `/export/:id/*` pass `complete: not can?(user, :view_drafts)` to the Catalogue read, so a
  visitor gets a 404 and staff keep the preview the admin pages link to. Related plays
  (`parent_play`, `derived_plays`) are preloaded under the same option, so no page links
  to a relative its reader cannot open. `/api/v1` has no session and reads `complete: true`.
- **An id in a LiveView event came from the browser.** On a play's tabs, resolve it with a
  getter scoped to the play (`Catalogue.get_play_editor/2`, `get_play_source/2`,
  `get_paratext/2`, `Places.get_play_place/2`, `Bibliography.get_link/2`,
  `PlayContent.get_character/2`, `get_division/2`, `get_element/2`, `get_note/2`), never `Repo.get!(id)`.
  Each returns nil for another play's row, a deleted one or a malformed id; the tab then
  reloads its list and calls `PlaycodeWeb.Admin.LiveHelpers.put_gone_flash/1`. A selection
  or a list of character ids from the browser is filtered to the play's own rows before a
  bulk action. This is what keeps per-play scoping below a one-clause change. The
  gazetteer and the place picker resolve a place the same way, with `Places.get_place/1`.
- **Per-play scoping is a planned extension**, not a rewrite: `can?/3` already takes the
  resource, so restricting researchers to assigned plays is one new clause plus a
  `play_assignments` table. See the `@moduledoc` in `lib/playcode/authz.ex`.

## TEI-XML Format

The importer reads the TEI P5 of EMOTHE/Artelope. Every element's mapping, both ways, is
`docs/tei-mapping.md`; a change to the import or the export changes its line there.

TEI fixture files are at `test/fixtures/tei_files/` (UTF-16 encoded, ~37 files covering Spanish/Italian/English/French plays). The whole production corpus, the 370 files the live site was loaded from, is at `doc/tei_corpus/` (git-ignored, like the FileMaker exports beside it); 17 of its plays are newer than their copies under `test/fixtures/`.

## Static Site Export

An Endings-compliant static archive of the complete plays (`is_complete: true`): pure
HTML/CSS/JS, no third-party requests, and everything, search included, works from the unzipped
archive opened as `file://`. Built and shipped from `/admin/export` or `mix playcode.export.site`.
The full write-up is `docs/static-site.md`; the rules that bite when you change it:

- **Every path built from a play code goes through `StaticSite.safe_code!/1`.** Play codes have no format validation, and `apply_changes/2` takes a removed play's code from a socket event.
- **Every build and deploy goes through `Playcode.Export.SiteBuilder`, one job at a time.** Two builds at once drop a play from the incremental index; a deploy during a build pushes half a site. `mix playcode.export.site` runs in its own VM, unserialised: pass `-o` while a server is building.
- **The search normaliser has two halves that must agree**: `StaticSite.Search` and `EMOTHE.normalise` in `site.js`, both run against `test/fixtures/search_normalisation.json`. `node --test test/js/*.test.mjs` runs the browser halves; CI runs it after `mix test`.
- **Generate rebuilds only what changed** (`build.json`, `StaticSite.Fingerprint`). There is no forced full rebuild: a play Generate misses is a tracking bug. `fingerprint_test.exs` fails when the export calls a module of the app that is neither fingerprinted nor data access.
- **A page links a style or script as `assets/…?v=` and `@site.assets`**, the assets' stamp, which an asset change moves in every page in place; an unstamped link lets a returning reader's browser pair new pages with an old stylesheet. The font preload is the exception (it must match `style.css`'s `url()`).
- **Size budgets** for `style.css` (25 KB), `site.js` and `search.js` (15 KB each) and the fonts (300 KB) are asserted in `static_site_test.exs`.
- **`assets/js/sync_scroll.mjs` is the comparison's one scroll-sync implementation**: the compare pages' hook imports it and `Export.CompareHtml` inlines it at compile time.

## Running Commands

Run mix plainly — no PATH export:

```bash
mix test
mix compile
mix phx.server
mix test 2>&1 | tail -10
```

`.claude/settings.json` sets `env.PATH` to the Erlang and Elixir `bin` directories, so every Bash tool call inherits them. The asdf shims are *not* on that PATH and do not work in the sandbox anyway (they are bash scripts needing `/bin/bash`).

Prefixing commands with `export PATH=...` is what the repo used to require, and it is now actively harmful: a compound `export ... && mix test` starts with `export`, so the `Bash(mix test:*)` permission rule no longer matches and every run asks for approval.

**If `mix: command not found`**, `env.PATH` did not reach the Bash tool. Fall back for that session only, and say so rather than editing this file:

```bash
export PATH="/home/bogdan/.asdf/installs/erlang/28.1/bin:/home/bogdan/.asdf/installs/elixir/1.19.5-otp-28/bin:/usr/local/bin:/usr/bin:/bin"
```

The version numbers are pinned in both places. An asdf upgrade means editing `env.PATH` in `.claude/settings.json` and the line above; `.tool-versions` stays the source of truth for which versions those are.

## Getting Started

```bash
cd ~/Projects/playcode
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix phx.server
```

Load the data. Every command takes `--dry-run`; what each reads, and what a re-run keeps, is in
`docs/development.md`:

```bash
mix playcode.import.tei            # the TEI corpus: doc/tei_corpus/ and test/fixtures/ (--force, --resume)
mix playcode.import.filemaker      # language, kind and original from FileMaker's index, historical time
mix playcode.import.bibliography   # S4, FileMaker's bibliography
mix playcode.import.witnesses      # S3, its witnesses
mix playcode.import.places         # S9b, its places of action
mix playcode.import.performances   # S5, its historical performances
```

On Fly: `mix playcode.fly.reimport prepare`, `run`, `generate` and `deploy` (`docs/production-reimport.md`),
and the `Playcode.Release.import_*` functions, `dry_run: true` first.

The TEI header is not authoritative for language — every EMOTHE file carries `xml:lang="es"` for
the editorial platform. The index's `[EN]`/`[FR]` tag is.

`mix gettext.extract --merge` works in this repo; note that it fuzzy-matches new strings onto unrelated existing translations. Check every entry it marks fuzzy before trusting it.

Then visit:
- http://localhost:4000/admin/plays/import to import TEI files
- http://localhost:4000/plays to browse the catalogue

## Production

Fly.io, app `playcode` (`playcode.fly.dev`), deployed by `.github/workflows/deploy-fly.yml` on
every green CI run on `main`. The pre-rename app (`fly.emothe.toml`, `emothe.fly.dev`) is
hand-deployed only and scaled to zero. History and numbers: `docs/history.md` (Fly.io
deployment, Fly volume, PDF downloads); publishing the site: `docs/static-site.md`.

- **One machine.** `_site` (`STATIC_SITE_DIR=/data/site`) and the PDF cache (`/data/pdf`) live on the `playcode_site` volume, which belongs to one machine; with two, each built and deployed a site of its own.
- **`ADMIN_EMAILS` unset means zero admins** (see *Access control*), and **`SMTP_HOST` unset silently drops every invitation**: use `bin/playcode rpc 'Playcode.Release.invite_url("...")'`.
- **`DATABASE_URL` must be a direct or session-mode connection.** `PlayChangeListener` holds a LISTEN connection that a transaction-mode pooler silently breaks; pages then update only on reload.
- Secrets: `DATABASE_URL`, `SECRET_KEY_BASE`, `ADMIN_EMAILS`, `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and the four deploy secrets in `docs/static-site.md`. `fly secrets list` shows names only.
