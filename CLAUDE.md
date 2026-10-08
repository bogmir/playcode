# Playcode - Digital Theatre Play Management System

The backend behind the EMOTHE and ARTELOPE public sites. It manages, catalogues and presents digitized early modern European theatre plays (16th-17th century): humanities researchers input play data, export to TEI-XML/PDF/HTML, and it generates the static pages those sites publish, with statistics.

EMOTHE and ARTELOPE stay the public brands; Playcode is the internal platform they both run on. Reference site: https://emothe.uv.es

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
5. **Run `mix test`** — the whole suite, not just the new file — before claiming anything works.

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
  route-by-persona table written by hand. Add a row for every new gated route.

Where the tests live: `test/playcode/` for contexts, importers and exporters
(`tei_roundtrip_test.exs` for everything a TEI file carries); `test/playcode_web/` for
routes, LiveViews and controllers; `test/mix/tasks_test.exs` for the mix tasks;
`test/support/fixtures.ex` for `play_fixture/1` and friends (users are made through the
invite flow); `test/fixtures/` for TEI, Word and FileMaker sample files.

`mix test --include slow` adds the TEI schema validation and the full corpus sweep in
`test/playcode/roundtrip_test.exs`: every tracked `test/fixtures/*.xml` plus the
git-ignored `test/fixtures/tei_files/`, a few minutes. The default run covers two of those
files.

## Tech Stack

- Elixir 1.19.5 / Erlang/OTP 28.1 (via asdf, see `.tool-versions`)
- Phoenix 1.8.3, LiveView 1.1.22, Tailwind 4.x
- PostgreSQL with UUID primary keys
- OpenTelemetry (Phoenix, Ecto, Bandit auto-instrumented; stdout exporter in dev)
- Saxy for TEI-XML parsing, xml_builder for TEI-XML generation
- ChromicPDF (headless Chrome) for PDF generation
- Deployment target: Fly.io (later)

## Project Structure

```
lib/
├── playcode/
│   ├── catalogue.ex                  # Play CRUD, search, listing context
│   ├── catalogue/
│   │   ├── play.ex                   # Core play schema (UUID PK)
│   │   ├── play_editor.ex            # Editors/reviewers
│   │   ├── play_source.ex            # Bibliographic sources
│   │   └── play_editorial_note.ex    # Front matter notes (dedications, editorial notes)
│   ├── play_content.ex               # Content management context (divisions, elements, characters)
│   ├── play_content/
│   │   ├── character.ex              # Dramatis personae
│   │   ├── division.ex               # Acts, scenes, prologues (self-referencing tree)
│   │   ├── element.ex                # Speeches, verse lines, stage directions, prose (self-referencing tree)
│   │   ├── element_character.ex      # Join table: element ↔ character (multi-speaker support)
│   │   └── inline_markup.ex          # The <<…>> italics markers
│   ├── statistics.ex                 # Compute & cache play statistics
│   ├── bibliography.ex               # Corpus-wide bibliography: entries, links, grouping and order
│   ├── bibliography/
│   │   ├── entry.ex                  # One work cited, shared by every play that cites it
│   │   ├── link.ex                   # A play's link to an entry (its volume, pages, note)
│   │   └── citation.ex               # The one renderer: segments, plain text, safe HTML
│   ├── activity_log.ex                   # Activity log context (log, list, count)
│   ├── activity_log/
│   │   └── entry.ex                  # Activity log entry schema
│   ├── statistics/
│   │   ├── metrics.ex                # Passages, characters, presence, divisions (pure)
│   │   └── play_statistic.ex         # Cached JSONB statistics per play
│   ├── accounts.ex                   # Invitations, login, sessions, deactivation
│   ├── accounts/
│   │   ├── user.ex                   # User schema (email, hashed_password, role, deactivated_at)
│   │   ├── user_token.ex             # Session and email tokens (session, invite, reset, change)
│   │   ├── admin_bootstrap.ex        # Reconciles ADMIN_EMAILS at boot
│   │   └── user_notifier.ex          # Email notification templates
│   ├── authz.ex                      # The only place that answers "may this user do that?"
│   ├── import/
│   │   ├── tei_parser.ex             # TEI-XML importer (handles UTF-16 files)
│   │   ├── filemaker_xml.ex          # FMPXMLRESULT reader (one FileMaker table)
│   │   └── bibliography.ex           # S4's one-time FileMaker bibliography import
│   └── export/
│       ├── tei_xml.ex                # Generate TEI-XML from DB
│       ├── html.ex                   # Standalone HTML document export
│       ├── pdf.ex                    # PDF via ChromicPDF (headless Chrome)
│       ├── epub.ex                   # EPUB 3 generation via BUPE
│       ├── compare_html.ex           # Standalone comparison HTML with sync scroll
│       ├── site_builder.ex           # The one process that writes and ships the admin's site
│       ├── play_change_listener.ex   # Relays Postgres's play_changed notifications to the export page and the play's topic
│       └── static_site.ex            # Static site orchestrator
│           ├── edition.ex            # One play prepared: pages, anchors, refs, split-verse ghosts
│           ├── pages.ex              # embed_templates "pages/*" → HTML strings
│           ├── components.ex         # Shell, rail, play text, charts, catalogue entry
│           ├── search.ex             # Normaliser + full-text index writer
│           ├── fingerprint.ex        # One hash of the code, assets and settings the pages are built with
│           └── deployer.ex           # Pushes the site to a git branch, then tells the publish server to fetch it
└── playcode_web/
    ├── router.ex
    ├── user_auth.ex                  # Auth plugs & LiveView on_mount hooks (delegates to Authz)
    ├── play_labels.ex                # Translated play metadata vocabularies (historical_time, …)
    ├── live/
    │   ├── play_catalogue_live.ex    # Public: /plays - searchable catalogue
    │   ├── play_show_live.ex         # Public: /plays/:code - play text, characters, stats
    │   ├── current_path_hook.ex      # Assigns :current_path for sidebar highlighting
    │   ├── user_accept_invite_live.ex # /users/accept-invite/:token
    │   ├── user_login_live.ex        # /users/log-in
    │   ├── user_settings_live.ex     # /users/settings (email, password, active sessions)
    │   ├── user_forgot_password_live.ex
    │   ├── user_reset_password_live.ex
    │   └── admin/
    │       ├── play_list_live.ex     # Admin: /admin/plays - manage plays
    │       ├── play_form_live.ex     # Admin: /admin/plays/new|:id/edit
    │       ├── play_detail_live.ex   # Admin: /admin/plays/:id - detail + exports
    │       ├── import_live.ex        # Admin: /admin/plays/import - TEI file import
    │       ├── activity_log_live.ex  # Admin: /admin/activity-log - activity audit log
    │       ├── export_site_live.ex   # Admin: /admin/export - static site generation UI
    │       ├── play_compare_live.ex  # Admin: /admin/plays/:id/compare - side-by-side comparison
    │       ├── play_bibliography_live.ex # Admin: /admin/plays/:id/bibliography - a play's bibliography
    │       └── user_list_live.ex     # Admin: /admin/users - user management
    ├── controllers/
    │   ├── user_session_controller.ex # Login/logout session handling
    │   └── admin/
    │       └── export_controller.ex  # Download endpoints for TEI/HTML/PDF/EPUB
    └── components/
        ├── play_text.ex              # Play text rendering (speeches, verses, stage dirs)
        └── statistics_panel.ex       # Modern stats visualization (cards, bar charts)
```

## Database Schema

All tables use UUID primary keys. Key relationships:

- `users` - email/password auth with role (`:admin`, `:researcher`), `confirmed_at`, `deactivated_at`; `hashed_password` is nullable because an invited account has no password yet
- `users_tokens` - session tokens (with `ip_address`/`user_agent`), invite and password-reset tokens. There is no self-service email change, so no `change:` context
- `plays` has_many `play_editors`, `play_sources`, `play_editorial_notes`, `characters`, `play_divisions`, `play_elements`; `composition_date_from`, `composition_date_to`, `composition_date_note` hold when the play was written, as a year range plus the competing datings verbatim; `form` is nil (automatic, from `is_verse`) or a curator's `verse`/`prose`/`mixed`, read only through `Play.form/1`
- `plays.content_version` - moved by Postgres triggers (migration `20261005120000_track_play_content_version`) whenever anything a play's static pages show changes: its own row, its divisions, elements, speakers, characters, editors, sources, notes, places and bibliography links, the gazetteer entries of those places and their ancestors, the bibliography entries it links to, and the rows of its original and translations. Once per transaction, with a `pg_notify('play_changed', id)`. Never written by the app (`writable: :never`). **A new table with a `play_id` whose rows appear on a play's pages needs the `play_row_changed()` trigger in its migration** (the migration's moduledoc has the line); `test/playcode/content_version_test.exs` fails until it has it. Adding a column needs nothing. Over-flagging is deliberate: any statement touching a play's rows flags it, even when the values end up the same
- `play_divisions` self-references via `parent_id` (acts contain scenes)
- `play_elements` self-references via `parent_id` (speeches contain line_groups contain verse_lines)
- `element_characters` join table links `play_elements` to `characters` (many-to-many, supports multi-speaker speeches like `who="#ALB #COR"`)
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
  `PlayContent.get_character/2`, `get_division/2`, `get_element/2`), never `Repo.get!(id)`.
  Each returns nil for another play's row, a deleted one or a malformed id; the tab then
  reloads its list and calls `PlaycodeWeb.Admin.LiveHelpers.put_gone_flash/1`. A selection
  or a list of character ids from the browser is filtered to the play's own rows before a
  bulk action. This is what keeps per-play scoping below a one-clause change.
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

## Routes

### Public
- `GET /` - Home page
- `GET /plays` - Public play catalogue with search
- `GET /plays/:code` - Public play presentation (text, characters, statistics tabs); a draft is a 404 except for staff

### Authentication
- `GET /users/accept-invite/:token` - Set a password on an invited account, then log in
- `GET /users/log-in` - Login (redirects if already logged in)
- `POST /users/log-in` - Create session
- `DELETE /users/log-out` - Destroy session
- `GET /users/settings` - Password and active sessions (requires an active account). The email address is shown read-only: only an admin can change it
- `GET /users/reset-password` - Forgot password
- `GET /users/reset-password/:token` - Reset password form

### Admin (requires `:view_admin`, i.e. any active researcher or admin)
- `GET /admin/plays` - Play management list
- `GET /admin/plays/new` - Create play
- `GET /admin/plays/:id/edit` - Edit play metadata
- `GET /admin/plays/:id` - Play detail (structure, stats, export buttons)
- `GET /admin/plays/import` - Import TEI-XML files (file upload; bulk server-side import is `mix playcode.import.tei`)
- `GET /admin/activity-log` - Activity audit log with filters (`:view_activity_log`)
- `GET /admin/users` - Invite, deactivate, reactivate, force logout, change role (`:manage_users`)
- `GET /admin/export` - Static site generation UI (`:deploy_site`)
- `GET /admin/export/download-zip` - Download generated static site as .zip (`:deploy_site`)
- `GET /admin/export/preview/*path` - Browse the built `_site/` before downloading or deploying; redirects to `/admin/export` when nothing is built (`:deploy_site`)
- `GET /admin/dashboard` - LiveDashboard (`:view_dashboard`)
- `GET /admin/filemaker` - Sync the FileMaker export: upload, preview the diff, apply (`:import_filemaker`)
- `GET /admin/places` - Corpus-global gazetteer: places, their names, hierarchy and authority links (`:manage_places`)
- `GET /admin/plays/:id/places` - The play's place index: role, order, notes (`:manage_places`)
- `GET /admin/plays/:id/bibliography` - A play's bibliography: new, edit (with a warning on a shared entry), add an existing entry, remove, filter (`:manage_bibliography`)
- `GET /admin/plays/compare/export/html` - Comparison HTML export
- `GET /admin/plays/:id/export/tei` - Download TEI-XML
- `GET /admin/plays/:id/export/html` - Download HTML
- `GET /admin/plays/:id/export/pdf` - Download PDF
- `GET /admin/plays/:id/export/epub` - Download EPUB

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

TEI fixture files are at `test/fixtures/tei_files/` (UTF-16 encoded, ~37 files covering Spanish/Italian/English/French plays).

## Static Site Export

Generates an Endings Project-compliant static website — pure HTML/CSS/JS, no server required. Only plays marked as **complete** (`is_complete: true`) are included by default.

Spec: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`. No third-party requests, and everything, search included, works from the unzipped archive opened as `file://`.

### Architecture

- `Playcode.Export.StaticSite` — orchestrator: loads plays, writes pages, copies `priv/static_site/` to `assets/`, builds the search index. Every path built from a play code goes through `StaticSite.safe_code!/1` (an allow-list `[A-Za-z0-9_-]+`), because `apply_changes/2` takes a removed play's code from a socket event (through `SiteBuilder.remove/2`) and play codes have no format validation
- `StaticSite.Edition` — one play prepared once: pages (`act-N`, or the division type), line anchors (`#l<n>`; `#l<act>-<scene>-<n>` when numbering restarts per scene; `#p<n>` otherwise), citation refs, split-verse ghost text, passage starts
- A division with more than 120,000 bytes of text and two or more scenes with text also gets a page per scene (`act-1-s3.html`); `generate/1` builds plays concurrently (`Task.async_stream`, at most the number of cores or the pool size minus two, whichever is smaller)
- `StaticSite.Pages` (`pages/*.html.heex`) and `StaticSite.Components` — HEEx rendered to strings with `Phoenix.HTML.Safe.to_iodata/1`; dev's HEEx annotations are stripped
- `StaticSite.Search` — the normaliser (must agree with `EMOTHE.normalise` in `site.js`: `test/fixtures/search_normalisation.json` runs against both) and the index: `search/plays.js`, `search/index/<shard>.js` (per play `[play, n, deltas…]`, `delta = (line − previous) × 2 + stage flag`) and `search/lines/<CODE>/<k>.js` (100 lines each), all calling `EMOTHE.search.load`. `write_index/3` carries every play's postings over from the shards on disk, so adding or removing a play reloads no other; an index older than chunked lines is rebuilt in full
- `Playcode.Statistics.Metrics` — metrical passages, characters, presence, divisions; cached by `Playcode.Statistics` (bump `@version` when what it stores changes)
- `priv/static_site/` — `style.css`, `site.js` (reading tools, catalogue filter, normaliser), `search.js`, `fonts/` (Source Serif 4 and Inter, OFL)
- `StaticSite.Deployer` — pushes `_site/` to the `gh-pages` branch of the repository in `:static_site_deploy` (the GitHub token reaches git as an HTTP header for that repository only, through `GIT_CONFIG_*` environment variables, so it is never in a command line or URL, and is scrubbed from errors), then, when a publish URL is set, POSTs to it with the key in `X-Deploy-Token` and answers the published site's address. See *Publishing on emothe.uv.es* below
- `Playcode.Export.SiteBuilder` — the one process that writes and ships the admin's site (`StaticSite.output_dir/0`): generate, add a play, remove one, deploy. It runs one job at a time under `SiteBuilder.Tasks`, because two builds at once drop a play from the incremental index and a deploy during a build pushes half a site. A request that arrives meanwhile is queued (`:queued`), not refused. When the job ends, the adds and removes at the front of the queue run as one batch through `StaticSite.apply_changes/2`: pages and catalogue first, then one search-index write. Generate brings the plays on disk up to date when it runs. It broadcasts `:queued`, `:started`, `:progress`, `:published`, `:done` and `:failed` on `"static_site"`, so every admin's export page shows the same state. `mix playcode.export.site` runs in its own VM and calls `StaticSite.generate/1` directly, unserialised: its default `_site` is also the admin page's directory in dev, so pass `-o` while a server is building
- **Change tracking.** Every build writes `build.json` at the site root: the site fingerprint (`StaticSite.Fingerprint`: the export's code by `module_info(:md5)`, `priv/static_site`, the English translations, the rendering libraries' versions and the `:version` option; not `PlaycodeWeb.Gettext`'s code, which every Spanish edit of the admin pages changes, though the site is in English), the `:version` that went into it, and each published play's `content_version`; the export page prefills its Version field from it (`StaticSite.built_version/1`), so a site is current for the version it was built with. `StaticSite.changed_plays/1` lists the published plays whose version moved since, `site_changed?/2` says whether the fingerprint did (or there is no `build.json`), and `outdated/1` is the batch that brings the site up to date. `Playcode.Export.PlayChangeListener` relays Postgres's `play_changed` notifications, coalesced per play over 200 ms, to `"static_site"`, so the export page flags a changed play (an amber dot, and an icon-only Refresh) as soon as the edit commits, and to the play's own topic (`PlayContent.notify_changed/1`), so the content editor and the play list reload whoever made the change. Generate (`SiteBuilder.generate/1`) rebuilds every play only when the site changed or holds no play; otherwise it writes the changed plays and takes out the archived or incomplete ones in one batch, and writes nothing when nothing changed. There is no forced full rebuild: tracking covers everything the pages show, so a play Generate misses is a tracking bug. `test/playcode/export/static_site/fingerprint_test.exs` fails when the export calls a module of the app that is neither fingerprinted nor data access

`generate/1` returns `{:ok, %{plays, size, output_dir, largest_page_gzip, index_bytes, largest_shard_bytes}}` and the mix task prints the last three. Size budgets: `style.css` 25 KB, `site.js` and `search.js` 15 KB each, and the fonts 300 KB are asserted in `static_site_test.exs`; an act page at most 80 KB gzipped and a first search at most 300 KB gzipped are only reported by the build (`generate/1`'s return and the mix task's printed line), not asserted. On the full dev corpus (83 plays, `--all`) the largest act page is 43.1 KB gzipped (EMOTHE0084, 0254 and 0648 are split into scene pages). A first single-word search costs at most ~166 KB gzipped (*sueño* 148 KB, *honneur* 166 KB, *de* 137 KB), under the 300 KB budget; a phrase over common words does not (*"vida es"* 954 KB, *"la vida es"* 691 KB), because the postings hold no word positions and every candidate line's chunk must load (`docs/static-site-improvements.md`, item 5). Builds, measured on the 83 plays at `9b37335`: 45.2 s sequential, 17.0 s parallel; removing one play 2.8 s, adding one 4.3 s.

### Output structure

```
_site/
├── index.html  search.html  about.html
├── build.json                 the fingerprint and version it was built with, and each play's content_version
├── assets/                    style.css, site.js, search.js, fonts/
├── search/                    plays.js, index/<shard>.js, lines/<CODE>/<k>.js
└── plays/
    ├── <CODE>.html            redirect stub to the old address
    └── <CODE>/
        ├── index.html         title page
        ├── act-1.html …       one per act (act-1-s3.html … per scene for a very long act); prologue.html etc.
        ├── text.html          full text
        ├── statistics.html
        └── <CODE>.xml         TEI-XML
```

`node --test test/js/*.test.mjs` runs the browser halves of search and of the comparison's scroll sync; CI runs it after `mix test`.

**Comparison scroll sync.** `assets/js/sync_scroll.mjs` is the one implementation: the compare pages' `SyncScroll` hook imports it and `Export.CompareHtml` inlines it at compile time with its `export` keywords stripped (the downloaded page opens from disk). Speeches carry `data-sync-act`, their act's key from `Division.sync_keys/1` (kind and place among siblings, so `acto n="1"` and `act` with no `n` pair up); a speech pairs with the one as far through the same act in the other panel, or through the whole play when the other edition has no such act. Keys from each file's own `type`/`number` left 40 of the 152 original/translation pairs with no speech in common.

### Publishing on emothe.uv.es

Deploy pushes the site to `bogmir/emothe-static` (branch `gh-pages`), then POSTs to
`https://emothe.uv.es/playcode-deploy.php`, which downloads that branch from GitHub and
swaps it into `emothe.uv.es/edicion_estatica/` (https://emothe.uv.es/edicion_estatica/). The script lives in
`deploy/`: `playcode-deploy.php`, its settings template `playcode-deploy.config.example.php`
(the live `playcode-deploy.config.php` holds the key's SHA-256 and is git-ignored), and
`test.sh`, which runs it under PHP 7.2, the server's version, against a mock of the site's
folder (docker and python3; `PHP_IMAGE=wordpress:cli-php7.4 deploy/test.sh` for another).

- **It never touches WordPress or the older sections** in the same folder: it writes only
  into its target folder, refuses to replace a folder without its `.playcode-site` marker,
  and refuses a download holding PHP, `.htaccess` or a path leaving the folder.
- **`POST …/playcode-deploy.php?check=1`** with the key reports PHP, zip, curl, write access
  and whether GitHub is reachable, and changes nothing.
- **Updating the script** needs the UV VPN (eduVPN) and the SMB share
  `smb://entresiglosvm.uv.es/html/emothe.uv.es/`; the server itself needs neither, since
  Playcode reaches it over HTTPS.
- **The four Fly secrets**: `STATIC_SITE_REPO` (`bogmir/emothe-static`),
  `GITHUB_DEPLOY_TOKEN` (fine-grained, that repository only, Contents read and write),
  `STATIC_SITE_PUBLISH_URL` (`https://emothe.uv.es/playcode-deploy.php`) and
  `STATIC_SITE_PUBLISH_TOKEN` (the key whose hash the server's config holds). In dev, the
  same environment variables apply; without `GITHUB_DEPLOY_TOKEN`, git pushes with your own
  login.

### Usage

**Admin UI**: `GET /admin/export` (`PlaycodeWeb.Admin.ExportSiteLive`) — configure the version; Generate, the one build button, brings the site up to date (only the changed plays, unless the site's code or settings changed); the play count and size above Preview, Deploy and Download are read from `_site/` (`StaticSite.dir_size/1`, which skips the `.git` Deploy leaves), so a switch changes them too; each play in the site shows a green dot when up to date and an amber dot plus an icon-only Refresh button when changed, except while the whole site changed, when only the banner shows; a play still in the site but now a draft or archived keeps a muted row with a hollow dot until its switch takes it out (or Generate does), and the switch can only add published plays; the list follows `play_changed`, so a play set to draft or marked complete moves at once; download as .zip, or Deploy: the target is server config (`STATIC_SITE_REPO`), named under the button, never typed in, because the GitHub token goes to it; with no repository configured there is no Deploy button.

**Mix task**:
```bash
mix playcode.export.site                              # complete plays → _site/
mix playcode.export.site -o /tmp/archive              # custom output dir
mix playcode.export.site --plays AL0001,AL0002        # specific plays only
mix playcode.export.site --all                        # include incomplete plays
mix playcode.export.site --version 2.0
```

### Completeness gate

The `plays.is_complete` boolean (default `false`) controls which plays are exported. Toggle it in the play edit form. The export site page shows "X of Y plays marked as complete". Pass `--all` to the mix task or `all: true` to `StaticSite.generate/1` to override.

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

Load the corpus (82 TEI files under `test/fixtures/`):

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

## What Has Been Implemented

- [x] Phoenix 1.8.3 project scaffold with all dependencies
- [x] OpenTelemetry configuration (Phoenix, Ecto, Bandit auto-instrumentation)
- [x] 7 database migrations (plays, editors, sources, notes, characters, divisions, elements, statistics)
- [x] All Ecto schemas with changesets and associations
- [x] `Playcode.Catalogue` context - play CRUD with search (title, author, code)
- [x] `Playcode.PlayContent` context - characters, divisions, elements; full content tree loading
- [x] `Playcode.Statistics` context - computes acts, scenes, verse distribution, split verses, prose fragments, stage directions, asides, character appearances; caches as JSONB
- [x] `Playcode.Import.TeiParser` - parses UTF-16 TEI-XML files into DB (handles BOM, encoding detection, full TEI structure mapping)
- [x] `Playcode.Export.TeiXml` - reconstructs TEI-XML from DB using xml_builder
- [x] `Playcode.Export.Html` - standalone HTML document with CSS styling
- [x] `Playcode.Export.Pdf` - PDF generation via ChromicPDF (reuses HTML export)
- [x] `Playcode.Export.Epub` - EPUB 3 generation via BUPE (chapters per division, embedded CSS)
- [x] `Playcode.Export.CompareHtml` - standalone comparison HTML with synchronized scrolling between panels
- [x] `Playcode.Export.StaticSite` - static archive on HEEx: title page, one page per act, full text, statistics page (metrical synopsis, characters, who shares the stage), catalogue of works with facets, full-text search that works from `file://`, reading tools. Spec: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`; deferred work: `docs/static-site-improvements.md`
- [x] `Playcode.Export.StaticSite.Deployer` - pushes the site to a git branch with a GitHub token, then has emothe.uv.es publish it (`deploy/playcode-deploy.php`)
- [x] Public catalogue page (`/plays`) with search
- [x] Public play presentation page (`/plays/:code`) with Text/Characters/Statistics tabs, line number and stage direction toggles
- [x] Statistics panel with modern cards and CSS bar charts
- [x] Admin play list with search and delete
- [x] Admin play create/edit form
- [x] Admin play detail page with structure overview and export buttons
- [x] Admin TEI import page (file upload)
- [x] Export controller (TEI-XML, HTML, PDF download endpoints)
- [x] Authentication with bcrypt (invite-only accounts, login, password reset). Public registration and the account-confirmation flow are deleted; accepting an invitation is what sets `confirmed_at`
- [x] `Playcode.Authz.can?/3` - single authorization predicate consulted by the router, the LiveView mount hooks and the admin sidebar
- [x] Account state enforced - the three auth gates require `confirmed_at` set and `deactivated_at` nil. This is the claim that was previously false in this file
- [x] `ADMIN_EMAILS` reconciled at boot by `Playcode.Accounts.AdminBootstrap`; those admins are protected from UI demotion/deactivation
- [x] Visible, revocable sessions - `/users/settings` lists IP and browser per session, revokes one or all others; 30-day tokens; admins force logout from `/admin/users`
- [x] Self-service email change removed - the address identifies the invited account, so `/users/settings` shows it read-only. `change_user_email/2`, `apply_user_email/3`, `update_user_email/2`, `User.email_changeset/3`, `User.confirm_changeset/1` and the `change:` token context are all deleted
- [x] Admin sidebar shell - three permission-filtered groups, collapsible at every breakpoint, hidden by default on play pages; breadcrumbs removed from the admin layout
- [x] Compile & fix errors (all modules compile cleanly)
- [x] TEI round-trip test suite (`tei_roundtrip_test.exs`) - every feature a TEI file carries, imported and exported: header fields, language, composition date, cast list, front-matter notes, divisions, speeches (including multi-character `who`), split verses, asides, emphasis, stage directions and their types, extent, and an export → import → export fixpoint. `tei_parser_test.exs` keeps what the export cannot show: failure modes, encodings, the gazetteer rules
- [x] TEI XML export test suite (`tei_xml_test.exs`) - exports of data no TEI import produces: gazetteer-built places and a dating note with no years
- [x] Real-fixture roundtrip test (`RoundtripTest`) - imports real TEI files, exports, and verifies: 12 structural count fields (acts, scenes, characters, speeches, verses, line_groups, stage_dirs, asides, split_parts, verse_type_attrs, hidden_chars, heads), ordering preservation (characters, sources, verse line attrs), metadata fidelity (title, author, code, original_title, pub_place, publication_date, licence_url, edition_title, author_attribution, editors, principals, sponsor, funder, sources), derived fields (verse_count, is_verse, extent), and warn-only speaker_refs (multi-character `who` limitation) Two tracked fixtures (`EMOTHE0746`, verse; `EMOTHE0776`, prose) run on every `mix test`; `mix test --include slow` sweeps every tracked `test/fixtures/*.xml` plus the git-ignored `test/fixtures/tei_files/` (a few minutes). The sweep is green: 83 fixtures, 0 failures
- [x] Duplicate character xml_id handling in TEI importer (`create_character_unless_exists`)
- [x] Manual play content editor at `/admin/plays/:id/content` - characters, divisions, elements with modal forms
- [x] Navigation overhaul: two layouts (public app + admin sidebar shell), play context bar for admin play pages; breadcrumbs remain on public pages only
- [x] Collapsible sidebar with scroll spy (IntersectionObserver) on public play page
- [x] Theme toggle (system/light/dark) in navbar
- [x] EMOTHE home page with catalogue CTA
- [x] "Edit in Admin" link on public play page for logged-in users
- [x] DaisyUI component migration (catalogue, play show, admin pages)
- [x] Bibliographic sources admin page (`/admin/plays/:id/sources`) - add/edit/delete sources with modal forms
- [x] Play text visual markers in sidebar: line numbers, stage directions, asides, split verses, verse type toggles
- [x] i18n: full Spanish translations for all UI strings (public + admin); `mix gettext.extract/merge` workflow established
- [x] Statistics panel act label i18n fix - stores raw division type (`"acto"`, `"jornada"`) and translates at display time
- [x] `Playcode.Places` — corpus-global gazetteer on a three-layer model: `places` (referent, self-referencing containment, coordinates, one authority link), `place_names` (surface forms, one preferred per language), `play_places` (per-play index with `role`, `position`, `note`, `origin`). `/admin/places` for the gazetteer, `/admin/plays/:id/places` as a peer context-bar tab, `#meta-places` on `/plays/:code`, and TEI `<settingDesc>` with nested `<listPlace>` plus `<setting>` in both directions. Wikidata behind a swappable `Places.Authority` behaviour, stubbed in test so no test touches the network. Spec: `docs/superpowers/specs/2026-08-04-s9-places-design.md`

  **Testing gotcha:** `places.slug` is unique across the whole corpus, so two async tests
  creating a place with the same name take the same index lock inside their own
  transactions — a pair of those acquired in opposite order deadlocks Postgres.
  `place_fixture/1` therefore derives a *unique* slug unless you pass `"slug"`. Pass one
  only when the test asserts on the literal value, and then give it a per-file prefix
  (`tx-roma`, `sch-roma`). A test about slug derivation itself should call
  `Places.create_place/1` directly and use a toponym no other test uses.

## What Still Needs To Be Done

### High Priority
- [x] **Create initial admin user** - set `ADMIN_EMAILS` (comma-separated); `Playcode.Accounts.AdminBootstrap` reconciles it at boot and mails each address an invitation. Break-glass with SMTP down: `mix playcode.invite EMAIL --admin --print-url`
- [x] **Fly.io deployment** — live. `fly.toml` deploys the `playcode` app (`playcode.fly.dev`) and `.github/workflows/deploy-fly.yml` deploys it on every green CI run on `main`. The pre-rename app survives as `fly.emothe.toml` (`emothe.fly.dev`), hand-deployed only (`fly deploy --config fly.emothe.toml`) and switched off with `fly scale count 0 -a emothe`. Both configs run `/app/bin/playcode` — the release binary follows the code, not the app name. Secrets required per app: `DATABASE_URL`, `SECRET_KEY_BASE`, `ADMIN_EMAILS` (**unset means zero admins**), `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`. With `SMTP_HOST` unset the mailer falls back to the Local adapter and **every invitation is silently dropped** — use `bin/playcode rpc 'Playcode.Release.invite_url("...")'` to get the link instead. Fly secrets cannot be read back: `fly secrets list` shows names only. Deploy needs four more, `STATIC_SITE_REPO`, `GITHUB_DEPLOY_TOKEN`, `STATIC_SITE_PUBLISH_URL` and `STATIC_SITE_PUBLISH_TOKEN` (see *Publishing on emothe.uv.es*); the runtime image carries `git` for it. `Playcode.Export.PlayChangeListener` holds one extra Postgres connection for LISTEN, so `DATABASE_URL` must be a direct or session-mode connection — a transaction-mode pooler silently drops the notifications (pages then update only on reload)
- [ ] **Render** — `render.yaml` and `Dockerfile.render` exist but the blueprint has never been applied
- [x] **Email delivery** - SMTP adapter via `gen_smtp`; configure `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD` (+ optional `SMTP_PORT`, `MAIL_FROM`) as Fly.io secrets
- [x] **Account state enforced** - `require_authenticated_user`, `require_permission` and the `{:ensure_can, action}` LiveView hook all require `Accounts.active?/1` (confirmed and not deactivated); an inactive session is destroyed with an explanatory flash rather than looping
- [x] **Login rate limiting** - 20/minute per IP plus 10/15 minutes per email address via ETS-backed `PlaycodeWeb.RateLimit`; a successful login calls `RateLimit.reset/1` so only failures consume the email budget
- [x] **User management admin UI** - `/admin/users` invites by email with a role, resends invitations, deactivates, reactivates, forces logout and changes roles; state badges are Protected/Deactivated/Invited/Active

### Medium Priority
- [x] **Aside detection** in TEI importer (detects `<stage type="delivery">[Aparte.]</stage>` and `<seg type="aside">` patterns)
- [x] **Verse type statistics** - distribution of verse types (redondilla, romance, etc.) in statistics panel
- [x] **Pagination** on catalogue pages (25/page public, 50/page admin) with URL-based navigation (`?page=N&search=query`); parent play field is now an autocomplete combobox
- [x] ~~Install Typst~~ PDF export now uses ChromicPDF (requires Chrome/Chromium on the system)
- [ ] **Stage direction navigator** (`« N / M »`) - client-side JS hook to scroll between stage directions in play text
- [x] **Recompute statistics** - a cached `play_statistics` row stores the play's `content_version` it was computed at, and `Statistics.get_statistics/1` recomputes when the play's version has moved, so every edit invalidates it with nothing to call (lazy recompute on next access); one-time refresh: `Playcode.Repo.all(Playcode.Catalogue.Play) |> Enum.each(&Playcode.Statistics.recompute(&1.id))`

### Known Roundtrip Gaps
- [x] **`Play.language` imported** from `<profileDesc><langUsage><language ident="xx-XX">` (e.g. "it-IT" → "it"); exported back as `<profileDesc><langUsage><language ident="...">` with label. Note: `xml:lang` on the root `<TEI>` element is always "es" in EMOTHE files (editorial platform language), NOT the play language — the play language lives in `profileDesc/langUsage`.
- [x] **`PlaySource.publisher/pub_place/pub_date`** — now imported from `<publisher>`, `<pubPlace>`, `<date>` inside `<bibl>`; exported back to same elements; editable in admin UI. Fields are optional — most EMOTHE corpus `<bibl>` elements use a freeform `<note>` citation instead.
- [x] **PlayEditors admin UI** — `/admin/plays/:id/editors` (new tab in context bar between Metadata and Sources); full CRUD with role dropdown (principal/translator/researcher/editor/digital_editor/reviewer)
- [x] **PlayEditorialNotes admin UI** — first tab ("Editorial Notes") inside `/admin/plays/:id/content`; full CRUD with section_type dropdown (introduccion_editor/dedicatoria/argumento/prologo/nota); uses same modal pattern as characters/divisions/elements. NOTE: plays imported with older parser versions will have empty notes — delete and re-import to populate from TEI.
- [x] **`front_notes` roundtrip check** — roundtrip test now verifies that front-matter `<div>` elements (prologo/dedicatoria/introduccion_editor/argumento/nota with non-empty `<p>` content) survive import→export
- [ ] **`project_description`/`editorial_declaration`** — imported and exported but no admin UI to edit
- [x] **Multi-character `who` attrs** (`who="#ALB #COR"`) — replaced single `character_id` FK with `element_characters` join table (many-to-many). Parser splits space-separated `who` refs and resolves each independently. Export reconstructs multi-character `who` attribute. Character Review UI supports multi-select assignment. `speaker_refs` promoted to strict roundtrip assertion.

### Found by the test rework (2026-09-26)
Each is pinned by a test as it behaves today, not endorsed.
- [x] **`ImportLive` `import_directory`** - any researcher's socket could push it and make the server import every `.xml` under any path. Handler deleted; `import_live_test.exs` asserts the pushed event imports nothing
- [x] **Drafts are public** - an incomplete play was hidden from `/plays` but served by `/plays/:code`, `/api/v1` (whose index listed every draft) and `/export/:id/*`. Now a 404 for visitors and visible to staff (`:view_drafts`); see *Access control*. The comparison page also stopped adding a panel for any id the browser sent: only the family it offers
- [ ] **Inline `<stage>` is flattened** - a plain `<stage>` inside a verse line or prose paragraph (~2,500 in the corpus) becomes part of the line's text on import; the corpus sweep does not count these
- [ ] **In-text `<note>` is pasted into the line** - `text_content/1` takes a note's text (every `<p>`) into the `<l>` or `<stage>` it sits in; 333 body notes in 13 tracked fixtures. Same root cause as the inline `<stage>` gap above. Next project after the static site redesign: `docs/static-site-improvements.md`
- [x] **Activity-log order was unstable within one second** - `activity_logs.inserted_at` is now microsecond precision (migration `20260926120000`), so a burst of entries lists newest first; the `to:` date filter ends at `23:59:59.999999`
- [x] **`ExportSiteLive` hardcoded `_site`** and a shared temporary zip path - the output directory now comes from `StaticSite.output_dir/0` (`:static_site_dir`, a temporary directory under test), so `export_site_live_test.exs` drives Generate. The zip still goes to one shared temporary path, so that test file is `async: false`
- [x] **Custom changeset messages had no Spanish translation** - all 15, not just "must be given together with the end year". `gettext.extract` cannot see a plain string in `add_error`/`message:`, so they are hand-added to `errors.pot` and the PO files; `test/playcode_web/error_translations_test.exs` finds them in `lib/` and fails on any without Spanish
- [x] **`mix playcode.import.filemaker` included archived plays** (and crashed applying to one: `Catalogue.get_play!/1` hides them); `/admin/filemaker` excluded them. Both now skip archived plays, through `FilemakerSync.all_plays/0`
- [x] **`Places.Authority.Stub` shipped in `lib/`** - now `test/support/place_authority_stub.ex`, compiled only in test

### Awaiting the project (static site)
Questions only the stakeholders can answer, recorded in `docs/static-site-improvements.md`, "Awaiting the project":
- [ ] **Adaptations are labelled "translation"** - `Components.kind/1` calls every `relationship_type` a translation, `adaptacion` and `refundicion` included
- [ ] **Verse-form families** - the romance / Spanish stanzas / Italianate grouping in `Metrics` `@families` needs the philologists' confirmation

### Low Priority / Future
- [ ] **"Review character in text" UI** — admin page to review and assign/reassign `character_id` (the `who` attribute) on speeches across an entire play. Researchers need to: (1) define character identifiers (`xml_id`, the "acrónimo" e.g. `don_diego`) in the dramatis personae, (2) associate each `<speaker>` with a character to generate `<sp who="#don_diego">`, and (3) bulk-review all speech-character associations throughout the play. Character CRUD and import-time `who` resolution already exist; what's missing is the review/bulk-assign UI.
- [x] **Soft delete & re-importable plays (S0b)** — `plays.deleted_at`, `origin` on the three mixed-ownership child tables, re-import updates in place, import preview + `--dry-run`, admin archive filter and restore. Archived plan: `docs/superpowers/plans/archive/README.md`
- [ ] **Places Phase 2** — in-text mentions (`<placeName ref>` in the body, an `element_places` table and the tagging UI), map rendering from the stored coordinates, catalogue browse-by-place, multiple authority links per place, and the FileMaker `pub_LugAccion` import
- [ ] **FileMaker version metadata (S2)** — taken one field at a time, each its own migration + import + admin control + row in the public panel. **S2a `historical_time` and S2c `composition_date` are done** (see below). One sub-slice is left, **blocked on a question to the project**: S2d `collection` (needs to know whether the field is still wanted and what separates its codes `1` and `3`). S2b `place_of_action` was split out as **S9** — it is a toponym gazetteer, not a text column; Phase 1 is done, see `Playcode.Places` above. S2e `legacy_url` and S2f `original_title`/`title_sort` are **dropped**: the first is derivable from code + filename, and the second is already imported from TEI on 82/82 plays. Anything drawing on `T01` is capped at the 22 plays with such a record; S2c is the exception, since its from/to come from the published index instead. The admin sync page at `/admin/filemaker` renders whatever `sets` and `conflicts` contain, so each of these slices needs no change to it
- [x] **FileMaker historical time (S2a)** — `plays.historical_time` (nine-term vocabulary, `Play.historical_times/0`) and `plays.historical_time_note`. `Filemaker.load_versions/1` reads the `T01_tituloEM` layout keyed by the code in the `pub_edicionWeb` href; `FilemakerSync` writes curated fields **fill-only** — blank columns filled, disagreements reported under `:conflicts` and left alone, overwritten only with `mix playcode.import.filemaker --force` or, per conflict, from `/admin/filemaker`. Edited in the admin form's Research Metadata fieldset, shown in the `#meta-study` section on `/plays/:code`. Labels live in `PlaycodeWeb.PlayLabels`. Applied to `playcode_dev`: 11 plays, 4 with a note. Archived plan: `docs/superpowers/plans/archive/README.md`
- [x] **FileMaker composition date (S2c)** — `plays.composition_date_from`/`_to`/`_note`. From/to come from `T00_indiceEM`'s index header (the *accepted* dating), the note from `pub_datacion`'s competing datings joined with `"; "`, falling back to the header verbatim when blank. Written only to the family head (`relationship_type` nil) — a translation does not inherit the original's composition date. Round-trips through TEI's `<profileDesc><creation><date>` (`when` or `notBefore`/`notAfter`), fill-only sync, same Research Metadata fieldset and `#meta-study` section as S2a. Spec: `docs/superpowers/specs/2026-08-05-s2c-composition-date-design.md`. Applied to `playcode_dev`: `updated 7, failed 0` — EMOTHE0010, 0038, 0281, 0337, 0346, 0777 from the index plus EMOTHE0341 note-only (no index entry, so from/to stayed nil); zero conflicts; a second run reports `0 to change`.
- [x] **FileMaker bibliography (S4)** — `Playcode.Bibliography`: corpus-wide entries linked to plays, grouped by kind (modern editions, criticism, translations by language, adaptations) and sorted alphabetically by the printed citation. One renderer, `Bibliography.Citation`, prints FileMaker's form on the admin tab (`/admin/plays/:id/bibliography`, live preview, shared-entry warning, accent-blind filter), on `/plays/:code` (`#meta-bibliography`), on the static site's title page (with a rail entry) and in TEI `<back><div type="bibliografia">`. Imported once by `mix playcode.import.bibliography`: on `playcode_dev`, 2,723 entries and 2,795 links on 114 plays. `test/playcode/bibliography/oracle_test.exs` checks every word FileMaker printed is in ours (a committed sample; the whole dump under `--include slow`). Spec: `docs/superpowers/specs/2026-10-07-s4-bibliography-design.md`
- [ ] **FileMaker import (S3, S5-S8)** — witnesses, historical performances, character reconciliation, credits, genre. Roadmap: `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`. Governing rule: the export is a bootstrap, not a dependency — every field it carries gets a permanent column *and* an admin form. As with S2, `/admin/filemaker` needs no change for these — it already renders whatever `sets` and `conflicts` contain
- [x] **FileMaker work families and language (S1)** — `Playcode.Import.Filemaker` parses the published index out of the NDJSON export; `Playcode.Import.FilemakerSync` diffs it against the database and writes `language`, `relationship_type` and `parent_play_id`. `mix playcode.import.filemaker [--dry-run] [--path ...]`. Creates nothing; codes absent from the index (every `AL####`) are reported, not failed. Applied to `playcode_dev`: 15 plays corrected, 11 work families linked. Archived plan: `docs/superpowers/plans/archive/README.md`
- [ ] **TEI import improvements** - handle more TEI variants, better error reporting
- [ ] **Full-text search** with PostgreSQL tsvector
- [x] **Activity log** - `activity_logs` table tracks all admin actions (create/update/delete/import/export/role_change) with user, play, resource type, changes, and metadata; admin UI at `/admin/activity-log` with filters (action, resource, user, date range) and pagination
- [ ] **TEI validation** - validate exported XML against TEI schema
**- [ ] **Responsive mobile design** refinements**
- [ ] **API endpoints** for programmatic access
- [ ] **Batch export** - export multiple plays at once
- [ ] **Custom OTel spans** for TEI import, export, statistics computation
- [ ] **Line number frequency control** - "show every N lines" option (original Artelope had "Mostrar cada 5")
- [ ] **HTML email templates** - replace plain-text bodies in `user_notifier.ex` with `html_body/1` using `Phoenix.Swoosh` for branded transactional emails
- [ ] **Login audit log** - store failed/successful login attempts in a DB table for security review
- [ ] **Session activity tracking** - add `last_active_at` to users table, update on each request
- [x] **Fly volume for the static site** - `_site` lives on the `playcode_site` volume (3 GB since 2026-10-07, `cdg`, mounted at `/data`), through `STATIC_SITE_DIR=/data/site` in `fly.toml` (read in the prod block of `config/runtime.exs`), so the site and its `build.json` survive a stopped machine and a deploy. A volume belongs to one machine, so the app runs **one** machine: with two, each built and deployed a site of its own, and the export page showed every switch off whenever it landed on the other. The volume root is owned by `nobody`, the image's user, as Fly mounts it. Extend it with `fly vol extend` before the site outgrows it (371 plays measured 465 MB on 2026-10-07, plus the deploy's `.git`); a volume cannot shrink

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
