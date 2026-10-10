# Architecture: files and routes

Where the code lives and which route does what. Moved from `CLAUDE.md` on 2026-10-10; the rules
for working in the code stay there. `mix phx.routes` lists the routes from the router itself.

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
│   │   ├── inline_markup.ex          # The <<…>> italics and <stage> markers
│   │   └── note.ex                   # In-text notes: a gloss anchored at an offset in a line, speaker or heading
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
│       ├── pdf_cache.ex              # Each play's PDF rendered once per version, kept on the volume
│       ├── epub.ex                   # EPUB 3 generation via BUPE
│       ├── note_markup.ex            # Italics and note references for the HTML/PDF and EPUB downloads
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
    │   ├── play_show_live.ex         # Public: /plays/:code - play text, stats, notes
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
    │       ├── notes_component.ex        # The note editor inside the content editor's modals
    │       ├── play_notes_live.ex        # Admin: /admin/plays/:id/notes - a play's notes, edited in place
    │       └── user_list_live.ex     # Admin: /admin/users - user management
    ├── controllers/
    │   ├── user_session_controller.ex # Login/logout session handling
    │   └── admin/
    │       └── export_controller.ex  # Download endpoints for TEI/HTML/PDF/EPUB
    └── components/
        ├── play_text.ex              # Play text rendering (speeches, verses, stage dirs)
        └── statistics_panel.ex       # Modern stats visualization (cards, bar charts)
```

## Routes

### Public
- `GET /` - Home page
- `GET /plays` - Public play catalogue with search
- `GET /plays/:code` - Public play presentation (text, statistics and, for a play with notes, notes views); a draft is a 404 except for staff

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
- `GET /admin/plays/:id/notes` - A play's in-text notes in reading order: filter by type, words or no term; edit type, word, term and text in place; delete; open the line in Content (`?element=`/`?division=` opens its modal), where notes are added (`:edit_content`)
- `GET /admin/plays/:id/bibliography` - A play's bibliography: new, edit (with a warning on a shared entry), add an existing entry, remove, filter (`:manage_bibliography`)
- `GET /admin/plays/compare/export/html` - Comparison HTML export
- `GET /admin/plays/:id/export/tei` - Download TEI-XML
- `GET /admin/plays/:id/export/html` - Download HTML
- `GET /admin/plays/:id/export/pdf` - Download PDF
- `GET /admin/plays/:id/export/epub` - Download EPUB
