# Playcode - Digital Theatre Play Management System

The backend behind the EMOTHE and ARTELOPE public sites. It manages, catalogues and presents digitized early modern European theatre plays (16th-17th century): humanities researchers input play data, export to TEI-XML/PDF/HTML, and it generates the static pages those sites publish, with statistics.

EMOTHE and ARTELOPE stay the public brands; Playcode is the internal platform they both run on. Reference site: https://emothe.uv.es

## Where Things Are Written Down

This file holds the rules every session needs. The rest is in `docs/`:

- `docs/architecture.md` - the file map and the routes
- `docs/static-site.md` - the static site export in full: architecture, measurements, output, publishing on emothe.uv.es
- `docs/backlog.md` - open work, the TEI corpus gaps among it
- `docs/history.md` - what has been built, and what each audit found and fixed
- `docs/static-site-improvements.md` - deferred static-site and exporter work, written up at length
- `docs/superpowers/specs/` and `docs/superpowers/plans/` - one design and one plan per project

Finishing a project moves its item from `docs/backlog.md` to `docs/history.md`. This file
changes only when a rule, an invariant or a command changes.

## How To Work In This Repo

**Naming.** The application was renamed `Emothe` -> `Playcode` on 2026-09-21, because a
backend serving both EMOTHE and ARTELOPE should not be named after one of them. Upper-case
`EMOTHE` is *never* the application: it is a play code (`EMOTHE0010`), the corpus, or the
public brand. Four lower-case tokens are also not the application and must survive any future
search-and-replace - `emothe.uv.es`, `plays.emothe_id`, `w3emothe` (the FileMaker export's
database, including the real path `doc/w3emothe_T01_tituloEM.ndjson`) and `emothe-static` (the
published site's repo and .zip). `test/rename_guard_test.exs` enforces all of this; read it
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
- **An existing test that contradicts a deliberate behaviour change gets updated, with a comment saying why.** See `test/playcode/import/tei_parser_test.exs`, "the play it returns is the play as stored": it used to assert the stale value `import_file/1` returned.
- **Bugfixes get a regression test** that fails before the fix.
- **`mix format` after every task.** The repo is formatted; a noisy diff hides the real change.
- **`mix compile --warnings-as-errors` before committing.**

**Test behaviour through the outermost API** (Saša Jurić's rule). A user journey is
tested through its route: a LiveView with `live/2`, `form/3` and `render_submit/1`, a
controller with `get`/`post`, a mix task with `Mix.Task.rerun/2`. Test an internal only
where the outer path is much slower or clumsier to set up: the TEI and Word importers
through `TeiParser.import_file/1` / `WordParser.import_content/2`, the FileMaker sync
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
- OpenTelemetry (Phoenix, Ecto, Bandit auto-instrumented; stdout exporter in dev)
- Saxy for TEI-XML parsing, xml_builder for TEI-XML generation
- ChromicPDF (headless Chrome) for PDF generation
- Deployed on Fly.io (see *Production*)

## Database Schema

All tables use UUID primary keys. Key relationships:

- `users` - email/password auth with role (`:admin`, `:researcher`), `confirmed_at`, `deactivated_at`; `hashed_password` is nullable because an invited account has no password yet
- `users_tokens` - session tokens (with `ip_address`/`user_agent`), invite and password-reset tokens. There is no self-service email change, so no `change:` context
- `plays` has_many `play_editors`, `play_sources`, `play_editorial_notes`, `characters`, `play_divisions`, `play_elements`; `composition_date_from`, `composition_date_to`, `composition_date_note` hold when the play was written, as a year range plus the competing datings verbatim; `form` is nil (automatic, from `is_verse`) or a curator's `verse`/`prose`/`mixed`, read only through `Play.form/1`
- `plays.content_version` - moved by Postgres triggers (migration `20261005120000_track_play_content_version`) whenever anything a play's static pages show changes: its own row, its divisions, elements, speakers, characters, editors, sources, notes, places and bibliography links, the gazetteer entries of those places and their ancestors, the bibliography entries it links to, and the rows of its original and translations. Once per transaction, with a `pg_notify('play_changed', id)`. Never written by the app (`writable: :never`). **A new table with a `play_id` whose rows appear on a play's pages needs the `play_row_changed()` trigger in its migration** (the migration's moduledoc has the line); `test/playcode/content_version_test.exs` fails until it has it. Adding a column needs nothing. Over-flagging is deliberate: any statement touching a play's rows flags it, even when the values end up the same
- `play_divisions` self-references via `parent_id` (acts contain scenes)
- `play_elements` self-references via `parent_id` (speeches contain line_groups contain verse_lines)
- `play_elements.content` holds an inline stage direction as `<stage type="…">…</stage>` next to the `<<…>>` italics, written by the TEI importer from a `<stage>` child of an `<l>`, `<p>` or `<seg>` and written back by the export; `Element.changeset` refuses a malformed marker, and any marker in an element that is not a verse line or a paragraph (a stage direction or trailer is a stage already). `/api/v1` returns `content` raw, markers included
- `element_characters` join table links `play_elements` to `characters` (many-to-many, supports multi-speaker speeches like `who="#ALB #COR"`)
- `play_notes` - in-text notes (TEI `<note>` in the body): on one element (a line, paragraph, stage direction, trailer, or a speech's speaker label) or one division's heading, at `offset` graphemes into that text's plain form (`PlayContent.anchor_text/1`); `position` orders notes at one offset (set by `PlayContent.create_note/1` and `update_note/2`, never passed by a caller); `n`, `type`, `term`, `body` (paragraphs split by a blank line). `update_element/2` and `update_division/2` carry offsets through an edit. Numbered in reading order (`Note.reading_order/1`) by `load_play_content/1`. A re-import replaces them with the file's notes. **Not rolled out to every play yet:** a play imported before 2026-10-08 keeps its notes and inline stages pasted into its lines until its TEI file is re-imported (`docs/backlog.md`, *Production rollout*). **A re-import replaces the play's elements, divisions and notes: hand edits to its lines and hand-added notes are lost** (`play_notes` has no `origin` column, unlike editors, sources and editorial notes, so nothing marks a note as hand-entered)
- `play_statistics` stores computed JSONB data per play
- `bibliography_entries` - corpus-wide, one row per work cited, shared by every play that cites it, so one correction reaches them all (S4). Two levels, `analytic_*` (article, chapter) and `monogr_*` (book, journal); `kind` (`modern_edition`/`criticism`/`translation`/`adaptation`), `pub_type`, `language`, imprint text columns, `filemaker_id` (`"T12:<id>"`/`"T04:<id>"`, unique). `public_note` is printed with the citation; `note` is for researchers only and never leaves the admin pages, not even into the TEI file. An update moves every linked play's `content_version` (`bibliography_entry_changed()`)
- `play_bibliography` - a play's link to an entry: `volume` and `pages` (where the play sits in a modern edition; they win over the entry's when printed), an internal `note`, `origin` (`manual`/`filemaker`). Unique per play and entry. `Bibliography.unlink/1` deletes the entry with its last link, so there are no orphan entries
- `activity_logs` tracks admin actions with user_id, play_id, action, resource_type, resource_id, changes (JSONB), metadata (JSONB)

Element types: `speech`, `stage_direction`, `verse_line`, `prose`, `line_group`, `trailer` (a division's closing formula, "FIN DEL PRIMER ACTO"; exported last in its division). A `prose` or `line_group` with no parent is text nobody speaks: a dumb show, a stanza opening a prologue
Division types: `acto`, `escena`, `prologo`, `argumento`, `dedicatoria`, `elenco`, `front`

### Archiving and provenance

- `plays.deleted_at` — archiving, not deletion. `Catalogue.delete_play/1` sets it, `restore_play/1` clears it, `purge_play/1` is the destructive path (wired to no button). Every Catalogue read hides archived plays; pass `include_deleted: true` for both or `archived: true` for only the archived ones. The unique index on `plays.code` is deliberately global, so an archived play keeps its code reserved.
- `play_editors.origin`, `play_sources.origin`, `play_editorial_notes.origin` — `"tei" | "manual" | "filemaker"`, default `"manual"`. A TEI re-import deletes only its own `"tei"` rows, so hand-entered records survive.
- **Re-importing a TEI file whose code exists updates that play in place** (same `id`, same history, un-archived). It does *not* write `language`, `relationship_type`, `parent_play_id`, `is_complete`, `historical_time`, `historical_time_note`, `composition_date_from`, `composition_date_to`, `composition_date_note` or `form` — those are `@platform_owned` in `lib/playcode/import/tei_parser.ex`. Any new curated column must be added to that list: for a column the TEI parser emits, the list is what stops the re-import overwriting it; for one it does not emit, the list is what makes the import preview report it as preserved.
- `TeiParser.preview_import/1` reports what an import would replace and keep, without writing. Used by the admin import page and `mix playcode.import.tei --dry-run`.

### Access control

- **Accounts are invite-only.** There is no registration page. `Accounts.invite_user/3`
  creates a password-less row plus a 7-day `"invite"` token; accepting sets the password
  and `confirmed_at` in one transaction, because clicking the emailed link already proves
  the mailbox. Re-inviting invalidates the previous link.
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
  deploy, the dashboard and the FileMaker sync (`:import_filemaker`).
- **A draft (`is_complete: false`) is for staff only.** `/plays/:code`, its compare page and
  `/export/:id/*` pass `complete: not can?(user, :view_drafts)` to the Catalogue read, so a
  visitor gets a 404 and staff keep the preview the admin pages link to. Related plays
  (`parent_play`, `derived_plays`) are preloaded under the same option, so no page links
  to a relative its reader cannot open. `/api/v1` has no session and reads `complete: true`.
- **An id in a LiveView event came from the browser.** On a play's tabs, resolve it with a
  getter scoped to the play (`Catalogue.get_play_editor/2`, `get_play_source/2`,
  `get_play_editorial_note/2`, `Places.get_play_place/2`, `Bibliography.get_link/2`,
  `PlayContent.get_character/2`, `get_division/2`, `get_element/2`, `get_note/2`), never `Repo.get!(id)`.
  Each returns nil for another play's row, a deleted one or a malformed id; the tab then
  reloads its list and calls `PlaycodeWeb.Admin.LiveHelpers.put_gone_flash/1`. A selection
  or a list of character ids from the browser is filtered to the play's own rows before a
  bulk action. This is what keeps per-play scoping below a one-clause change. The
  gazetteer and the place picker resolve a place the same way, with `Places.get_place/1`.
- **Per-play scoping is a planned extension**, not a rewrite: `can?/3` already takes the
  resource, so restricting researchers to assigned plays is one new clause plus a
  `play_assignments` table. See the `@moduledoc` in `lib/playcode/authz.ex`.
- **A password reset confirms an unconfirmed account.** The link was mailed to that
  address, so following it proves the mailbox — the same argument as accepting an invite.
  Without this, an invited user who reaches for "forgot password" instead of their invite
  link ends up with a working password on an account every gate refuses, which is a lockout
  with no UI escape. A reset never clears `deactivated_at`.
- **Accounts are deactivated, never deleted** — `activity_logs.user_id` references them.
  Deactivating destroys every token and disconnects open LiveViews.
- Sessions last 30 days and are listed and revocable at `/users/settings`; admins can force
  logout from `/admin/users`. Login throttling has two ETS keys: 20/minute per IP and
  10/15 minutes per email address, and a successful login clears the email counter.

## TEI-XML Format

The importer handles the TEI P5 format used by EMOTHE/Artelope. Key mappings:
- `teiHeader/fileDesc` -> play metadata, editors, sources
- `teiHeader/profileDesc/creation/date` -> composition date (`@when` or `@notBefore`/`@notAfter`, text as the note); read on first import only, since the columns are `@platform_owned`
- `text/front/div[@type="elenco"]/castList` -> characters
- `text/front/div[@type="dedicatoria|introduccion_editor"]` -> editorial notes
- `text/body/div1[@type="acto"]` -> act divisions
- `text/body/div1/div2[@type="escena"]` -> scene subdivisions
- `sp` -> speech elements with `who` -> character reference
- `lg` -> line groups with verse type (redondilla, romance_tirada, etc.)
- `l` -> verse lines with line numbering, split line markers (part I/M/F)
- `stage` -> stage directions
- `stage` inside `l`, `p` or `seg` -> a `<stage>` marker in the line's text (aside lines and paragraphs drop theirs)
- `note` in the play text -> `play_notes`, at its offset in the line, speaker label or heading it sits in (not part of the text)

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

### Finding missing gettext translations without mix

When `mix gettext.extract --merge` is not runnable, find missing translations manually:

```bash
# Strings in code but not in PO file:
grep -rho 'gettext("[^"]*")' lib/ | sed 's/.*gettext("\(.*\)")/\1/' | sort -u > /tmp/code_strings.txt
grep '^msgid ' priv/gettext/es/LC_MESSAGES/default.po | sed 's/msgid "\(.*\)"/\1/' | sort -u > /tmp/po_strings.txt
comm -23 /tmp/code_strings.txt /tmp/po_strings.txt
```

## Getting Started

```bash
cd ~/Projects/playcode
mix deps.get
mix ecto.create
mix ecto.migrate
mix test
mix phx.server
```

Load the corpus: the 370 production files under `doc/tei_corpus/` (git-ignored; copy them there first) plus the fixtures under `test/fixtures/`, 392 plays, one per code, a `doc/tei_corpus` file winning over a fixture with the same code:

```bash
mix playcode.import.tei             # skip codes already imported
mix playcode.import.tei --dry-run   # report what would happen, write nothing
mix playcode.import.tei --force     # re-import every file, updating in place
```

Correct `language`, `relationship_type` and `parent_play_id` from the FileMaker published index,
and bootstrap `historical_time`/`historical_time_note` from the version records
(`doc/w3emothe_T01_tituloEM.ndjson`, git-ignored):

```bash
mix playcode.import.filemaker --dry-run   # print the changes, write nothing
mix playcode.import.filemaker             # apply them
mix playcode.import.filemaker --force     # also overwrite curated conflicts
```

The derived fields (`language`, `relationship_type`, `parent_play_id`) overwrite unconditionally —
the index is authoritative. The curated fields (`historical_time`, `historical_time_note`) are
fill-only: written when blank, reported as a conflict when they differ, overwritten only under
`--force`.

Bring FileMaker's bibliography into the plays we hold, once (S4; the six tables of the
`ctce_dades` dump under `doc/ctce_dades/`, git-ignored). A re-run skips plays already imported,
so a curator's edits stay; on Fly, `Playcode.Release.import_bibliography/2`:

```bash
mix playcode.import.bibliography --dry-run   # the plan, per play and per skip reason
mix playcode.import.bibliography             # write it
```

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

## Key Decisions

- **TEI Import first**: Primary data entry via XML import, not manual forms
- **ChromicPDF for PDF**: Reuses the HTML export via headless Chrome, so PDF looks identical to the website
- **Saxy for XML**: SAX-style streaming parser; uses `Saxy.SimpleForm` to parse into tree
- **UUID primary keys**: All tables use `binary_id` for eventual distributed deployment
- **JSONB statistics**: Cached stats stored as a JSON blob, recomputed on demand
- **Self-referencing trees**: Both divisions and elements use `parent_id` for hierarchy
- **bcrypt authentication**: Standard Phoenix auth pattern with session tokens and password reset; accounts arrive by invitation, so accepting the invite replaces a separate confirmation step
- **One authorization seam**: two roles (`:admin`, `:researcher`) but every access decision goes through `Playcode.Authz.can?/3`, which already takes the resource — per-play scoping becomes one extra clause instead of a rewrite
- **Admin identity in config, not the UI**: `ADMIN_EMAILS` is reconciled at boot, so a compromised admin session cannot strip its co-admins or lock the owner out
