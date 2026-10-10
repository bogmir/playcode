# Static Site Export

Generates an Endings Project-compliant static website — pure HTML/CSS/JS, no server required. Only plays marked as **complete** (`is_complete: true`) are included by default.

Spec: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`. No third-party requests, and everything, search included, works from the unzipped archive opened as `file://`.

## Architecture

- `Playcode.Export.StaticSite` — orchestrator: loads plays, writes pages, copies `priv/static_site/` to `assets/`, builds the search index. `generate/1` builds into `<dir>.new` beside the site and swaps it in only when done, so a build cut short (out of memory, a restart) leaves the previous site whole; the next build clears what it left (`<dir>.new`, `<dir>.old`). Switches (`apply_changes/2`) still write in place. Every path built from a play code goes through `StaticSite.safe_code!/1` (an allow-list `[A-Za-z0-9_-]+`), because `apply_changes/2` takes a removed play's code from a socket event (through `SiteBuilder.remove/2`) and play codes have no format validation
- `StaticSite.Edition` — one play prepared once: pages (`act-N`, or the division type), line anchors (`#l<n>`; `#l<act>-<scene>-<n>` when numbering restarts per scene; `#p<n>` otherwise), citation refs, split-verse ghost text, passage starts
- A division with more than 120,000 bytes of text and two or more scenes with text also gets a page per scene (`act-1-s3.html`); `generate/1` builds plays concurrently (`Task.async_stream`, at most the number of cores or the pool size minus two, whichever is smaller)
- `StaticSite.Pages` (`pages/*.html.heex`) and `StaticSite.Components` — HEEx rendered to strings with `Phoenix.HTML.Safe.to_iodata/1`; dev's HEEx annotations are stripped
- `StaticSite.Search` — the normaliser (must agree with `EMOTHE.normalise` in `site.js`: `test/fixtures/search_normalisation.json` runs against both) and the index: `search/plays.js`, `search/index/<shard>.js` (per play `[play, n, deltas…]`, `delta = (line − previous) × 2 + stage flag`) and `search/lines/<CODE>/<k>.js` (100 lines each), all calling `EMOTHE.search.load`. A play's notes are entries of their own after its lines, note `i` numbered `Search.note_base() + i` (1,000,000, the same in `search.js`, both pinned by `search_normalisation.json`), so the search page tells a note hit, and counts the Text facet's Notes, from the shard alone; their rows are in `search/lines/<CODE>/n<k>.js`, kind `"n"`, linking to the note's marker on the first page that shows it. `write_index/3` carries every play's postings over from the shards on disk, so adding or removing a play reloads no other; an index older than chunked lines is rebuilt in full. It writes one shard at a time, reading each old one only in its turn, and `write_play/2` hands back a play's postings as one string per shard (`"sueño 2,6,9"` lines), so a build never holds more than the index's own size: as tuples and lists, the 371 plays' 6.3 million postings took 455 MB and their index peaked at 1.7 GB
- In-text notes: a `<button id="nref-<n>" popovertarget>` after the word, each page's notes as a `doc-endnotes` list of `popover` items (endnotes in print). `Playcode.PlayContent.Note` is in the fingerprint. `Edition.notes` decides once, for the search index and `notes.html`, each note's first page, citation, speakers and glossed word (`Note.glossed/2`: the `<term>`, else the word before the note). `notes.html` lists them, filterable by type (`PlayLabels.note_type_key/1`: a type with no label is filed under one plain Note) with a few lines of `site.js`
- `Playcode.Statistics.Metrics` — metrical passages, characters, presence, divisions; cached by `Playcode.Statistics` (bump `@version` when what it stores changes)
- `priv/static_site/` — `style.css`, `site.js` (reading tools, catalogue filter, normaliser), `search.js`, `fonts/` (Source Serif 4 and Inter, OFL)
- `StaticSite.Deployer` — pushes `_site/` to the `gh-pages` branch of the repository in `:static_site_deploy` (the GitHub token reaches git as an HTTP header for that repository only, through `GIT_CONFIG_*` environment variables, so it is never in a command line or URL, and is scrubbed from errors), then, when a publish URL is set, POSTs to it with the key in `X-Deploy-Token` and answers the published site's address. See *Publishing on emothe.uv.es* below
- `Playcode.Export.SiteBuilder` — the one process that writes and ships the admin's site (`StaticSite.output_dir/0`): generate, add a play, remove one, deploy. It runs one job at a time under `SiteBuilder.Tasks`, because two builds at once drop a play from the incremental index and a deploy during a build pushes half a site. A request that arrives meanwhile is queued (`:queued`), not refused. When the job ends, the adds and removes at the front of the queue run as one batch through `StaticSite.apply_changes/2`: pages and catalogue first, then one search-index write. Generate brings the plays on disk up to date when it runs. It broadcasts `:queued`, `:started`, `:progress`, `:published`, `:done` and `:failed` on `"static_site"`, so every admin's export page shows the same state. `mix playcode.export.site` runs in its own VM and calls `StaticSite.generate/1` directly, unserialised: its default `_site` is also the admin page's directory in dev, so pass `-o` while a server is building
- **Change tracking.** Every build writes `build.json` at the site root: the site fingerprint (`StaticSite.Fingerprint`: the export's code by `module_info(:md5)`, the English translations, the rendering libraries' versions and the `:version` option; not `PlaycodeWeb.Gettext`'s code, which every Spanish edit of the admin pages changes, though the site is in English), the `:version` that went into it, and each published play's `content_version`; the export page prefills its Version field from it (`StaticSite.built_version/1`), so a site is current for the version it was built with. `priv/static_site` (styles, scripts, fonts) has its own hash in `build.json` (`Fingerprint.assets/0`): no page embeds anything of those files but their paths, so when only they changed Generate copies them and rebuilds no play, and the export page says so (`StaticSite.assets_changed?/1`, `update_assets/1`). `StaticSite.changed_plays/1` lists the published plays whose version moved since, `site_changed?/2` says whether the fingerprint did (or there is no `build.json`), and `outdated/1` is the batch that brings the site up to date. `Playcode.Export.PlayChangeListener` relays Postgres's `play_changed` notifications, coalesced per play over 200 ms, to `"static_site"`, so the export page flags a changed play (an amber dot, and an icon-only Refresh) as soon as the edit commits, and to the play's own topic (`PlayContent.notify_changed/1`), so the content editor and the play list reload whoever made the change. Generate (`SiteBuilder.generate/1`) rebuilds every play only when the site changed or holds no play; otherwise it writes the changed plays and takes out the archived or incomplete ones in one batch, and writes nothing when nothing changed. There is no forced full rebuild: tracking covers everything the pages show, so a play Generate misses is a tracking bug. `test/playcode/export/static_site/fingerprint_test.exs` fails when the export calls a module of the app that is neither fingerprinted nor data access

`generate/1` returns `{:ok, %{plays, size, output_dir, largest_page_gzip, index_bytes, largest_shard_bytes}}` and the mix task prints the last three. Size budgets: `style.css` 25 KB, `site.js` and `search.js` 15 KB each, and the fonts 300 KB are asserted in `static_site_test.exs`; an act page at most 80 KB gzipped and a first search at most 300 KB gzipped are only reported by the build (`generate/1`'s return and the mix task's printed line), not asserted. On the full dev corpus (83 plays, `--all`) the largest act page is 43.1 KB gzipped (EMOTHE0084, 0254 and 0648 are split into scene pages). A first single-word search costs at most ~166 KB gzipped (*sueño* 148 KB, *honneur* 166 KB, *de* 137 KB), under the 300 KB budget; a phrase over common words does not (*"vida es"* 954 KB, *"la vida es"* 691 KB), because the postings hold no word positions and every candidate line's chunk must load (`docs/static-site-improvements.md`, item 5). Builds, measured on the 83 plays at `9b37335`: 45.2 s sequential, 17.0 s parallel; removing one play 2.8 s, adding one 4.3 s. On the dev corpus's 371 complete plays with one scheduler, as on Fly's shared-cpu-1x (2026-10-08): a full build takes about 200-225 s of CPU on a laptop core and peaks at 217 MB (1.7 GB before the index was written shard by shard); switching one play on in the full site takes 9.4 s and peaks at 151 MB (733 MB before).

## Output structure

```
_site/
├── index.html  search.html  about.html
├── build.json                 the fingerprint and version it was built with, and each play's content_version
├── assets/                    style.css, site.js, search.js, fonts/
├── search/                    plays.js, index/<shard>.js, lines/<CODE>/<k>.js and n<k>.js (its notes)
└── plays/
    ├── <CODE>.html            redirect stub to the old address
    └── <CODE>/
        ├── index.html         title page
        ├── act-1.html …       one per act (act-1-s3.html … per scene for a very long act); prologue.html etc.
        ├── text.html          full text
        ├── statistics.html
        ├── notes.html         every note, filterable by type; only for a play with notes
        └── <CODE>.xml         TEI-XML
```

`node --test test/js/*.test.mjs` runs the browser halves of search and of the comparison's scroll sync; CI runs it after `mix test`.

**Comparison scroll sync.** `assets/js/sync_scroll.mjs` is the one implementation: the compare pages' `SyncScroll` hook imports it and `Export.CompareHtml` inlines it at compile time with its `export` keywords stripped (the downloaded page opens from disk). Speeches carry `data-sync-act`, their act's key from `Division.sync_keys/1` (kind and place among siblings, so `acto n="1"` and `act` with no `n` pair up); a speech pairs with the one as far through the same act in the other panel, or through the whole play when the other edition has no such act. Keys from each file's own `type`/`number` left 40 of the 152 original/translation pairs with no speech in common.

## Publishing on emothe.uv.es

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

## Usage

**Admin UI**: `GET /admin/export` (`PlaycodeWeb.Admin.ExportSiteLive`) — configure the version; Generate, the one build button, brings the site up to date (only the changed plays, unless the site's code or settings changed); the play count and size above Preview, Deploy and Download are read from `_site/` (`StaticSite.dir_size/1`, which skips the `.git` Deploy leaves), so a switch changes them too; each play in the site shows a green dot when up to date and an amber dot plus an icon-only Refresh button when changed, except while the whole site changed, when only the banner shows; a play still in the site but now a draft or archived keeps a muted row with a hollow dot until its switch takes it out (or Generate does), and the switch can only add published plays; the list follows `play_changed`, so a play set to draft or marked complete moves at once; download as .zip, or Deploy: the target is server config (`STATIC_SITE_REPO`), named under the button, never typed in, because the GitHub token goes to it; with no repository configured there is no Deploy button.

**Mix task**:
```bash
mix playcode.export.site                              # complete plays → _site/
mix playcode.export.site -o /tmp/archive              # custom output dir
mix playcode.export.site --plays AL0001,AL0002        # specific plays only
mix playcode.export.site --all                        # include incomplete plays
mix playcode.export.site --version 2.0
```

## Completeness gate

The `plays.is_complete` boolean (default `false`) controls which plays are exported. Toggle it in the play edit form. The export site page shows "X of Y plays marked as complete". Pass `--all` to the mix task or `all: true` to `StaticSite.generate/1` to override.
