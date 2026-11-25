# Export page: one Publish button, the site's state on every play

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/admin/export` becomes one Publish button over a short list of what is waiting to go online, and every play, in the play list and on its own page, says where it stands on emothe.uv.es.

**Architecture:** Marking a play complete is the only decision: Generate brings the site in line with the catalogue (adds the complete plays it lacks, refreshes the changed ones, takes the rest out), and a new `:publish` job in `SiteBuilder` runs that and then the deploy, in one task. A new `Playcode.Export.SiteStatus` compares each play with the live site (the deploy record, or the built site where no deploy is configured) and gives one of five states; the export page groups by it, the play list shows and filters by it, the play page's state band says it. The per-play switches, Add every complete play, Refresh, and `SiteBuilder`'s add/remove batches go.

**Tech Stack:** Elixir 1.19, Phoenix LiveView 1.1, daisyUI, gettext (English msgids, Spanish `es` translations).

**Spec:** the conversation of 2026-11-24 and its mockup, option B + C with the details in the Publish card ("Export · details in the Publish card" and "Play list and play page" tabs): https://claude.ai/artifact/RP78S4DZZXpYXAjqg2z8Xi. The decisions it settled are listed below; the mockup is the layout.

## Decisions

- **Complete means it goes online.** No switch per play. Generate adds every complete play the site lacks, also when it rebuilds the whole site (today it rebuilds only the plays already in it, and on a non-empty site never adds a new one: the play page's "The next Generate and Deploy put it on the published site" is false).
- **One Publish button** queues `:publish`: generate, then deploy only when the generate succeeded. Progress reads "Step 1 of 2 · …" / "Step 2 of 2 · …". Without a deploy repository (dev) there is no Publish button, only Generate, and the hint says what to set, as today.
- **A preview without publishing stays:** a secondary "Generate preview" button (the `:generate` job) and an "Open preview ↗" link once a site exists. (The mockup's single "Vista previa ↗" could not both build and open a tab: a server push cannot open one.)
- **Groups are measured against the live site:** New (complete, not live), Changed (live, `content_version` moved since), Leaving (live, now a draft, archived or purged), Up to date (folded `<details>`, with a search box and 50 to a page). A play leaves New/Changed/Leaving after the next successful deploy. Where no deploy repository is configured, "live" is the built site.
- **The headline** is "%{count} plays to publish" (New + Changed + Leaving) with "%{live} on %{host} · last deploy %{date}" under it; "Everything is published." when the count is 0 and the site has not changed as a whole.
- **The whole-site banner** names the cause: "Playcode has changed since the last build. Publish rebuilds the %{count} plays of the site." plus today's sentence about `mix playcode.fly.reimport generate`. It is an `alert-info`, not `alert-warning`.
- **Details in the Publish card:** one line at its foot: "Edition %{version}" with a native `<details>` "change" that opens the version field and its warning; plays built and size; folder; destination host. No "Advanced" section, no "Built site" card, no "Deployed!" card (the flash names the address).
- **"About the static site"** keeps its name and becomes one folded `<details>` of plain text under everything, outside any card.
- **Five states** (`SiteStatus.state/2`), with the words a researcher reads:

  | atom | when | badge (msgid → es) |
  |---|---|---|
  | `:draft` | not complete, not live | "Not published" → "No publicada" |
  | `:waiting` | complete, not live | "Waiting to be published" → "Esperando publicación" |
  | `:changed` | complete, live, `content_version` differs | "Unpublished changes" → "Cambios sin publicar" |
  | `:leaving` | live, but a draft or archived | "Leaving the site" → "Saldrá de la web" |
  | `:live` | complete, live at its `content_version` | "On the site" → "En la web" |

## Global Constraints

- TDD, red then green then **refactor while green**, per CLAUDE.md; every new test proven to bite with `bin/bites FILE OLD NEW TEST_PATH`, said in the commit.
- Tests through the outermost API: `live/2` and `render_*` for pages, `SiteBuilder` for jobs; select by visible text (`t/2`) or stable ids, never `phx-click` or classes.
- `mix format` and `mix compile --warnings-as-errors` before each commit (the pre-commit hook runs them).
- Comments only go down: `test/comment_ratchet_test.exs`; a comment only for a why, the baseline raised in the same commit if one is truly needed.
- `mix gettext.extract --merge` after copy changes; check every entry it marks fuzzy; Spanish translations as in this plan.
- `test/playcode_web/accessibility_test.exs` must stay green (the export page and the play list are in it).
- No commit attribution lines. Commit messages in the repo's style (`feat:`, `fix:`, `refactor:`, `docs:`).
- **Shared machine:** other sessions run `mix test` in other worktrees against the same `playcode_test` database and the same `/tmp/playcode-test-site`. Before the full suite, check no other `mix test` runs (`pgrep -af "mix test"`); a failure in the export tests while another runs is that, not the change.

## Review Focus

1. **No deploy record yet** (production today: nothing was deployed since the record was introduced). Every complete play must read Waiting, not On the site, and the headline must count them all. Test in Task 2 ("with no deploy yet, every complete play is waiting").
2. **A purged play still live** has no row, only its code: Leaving must list it by code with "deleted", and nothing may crash on its missing title. Test in Task 4.
3. **Generate fails during Publish:** the deploy must not run, the old live site stays, the flash says the generate failed. Test in Task 3.
4. **A play set back to draft while a Publish runs:** after the job, the groups are read again from disk and database, so it shows as Leaving or Waiting as it truly is. Covered by reloading on `:done` (Task 4 test "the groups are read again when a job ends").
5. **Search in Up to date with a page number past the end** (search narrows 358 to 3 while on page 5): the page clamps to the last one. Test in Task 4.

---

### Task 0: The worktree

The worktree is `/home/bogdan/Projects/playcode-export-publish` on `feature/export-page-publish`, made from `main` at `d47ea18`, hooks set.

- [ ] **Step 1:** `cd /home/bogdan/Projects/playcode-export-publish && mix deps.get && mix compile` — Expected: compiles with no warnings.
- [ ] **Step 2:** `mix test test/playcode_web/live/admin/export_site_live_test.exs 2>&1 | tail -3` — Expected: `0 failures`. This is the baseline.

### Task 1: Generate adds the complete plays the site lacks

**Files:**
- Modify: `lib/playcode/export/static_site.ex` (`outdated/1`, its `@doc`)
- Modify: `lib/playcode/export/site_builder.ex` (`build_all/1`; delete `codes_in_site/0`; `@moduledoc` and `generate/1` `@doc`)
- Test: `test/playcode/export/site_builder_test.exs`
- Modify: `test/playcode_web/live/admin/export_site_live_test.exs` ("Generate rebuilds only the plays in the site, so a removed play stays out" now contradicts the behaviour: delete it, its removal half is covered by Task 1's second test)

**Interfaces:**
- Produces: `StaticSite.outdated(dir) :: [{:add, play_id} | {:remove, code}]` now also returns `{:add, id}` for each complete, unarchived play not on disk. `SiteBuilder.generate/1`'s full rebuild builds every complete play (`play_codes: nil`).

- [ ] **Step 1: Write the failing tests** in `site_builder_test.exs`, through `SiteBuilder.generate/1` and the site on disk (`StaticSite.list_exported_codes/1`):
  - `"Generate adds a play marked complete since the last build"`: build a site with play A; mark B complete; `generate(version: built_version)`; await `:done`; assert `list_exported_codes` == `[A.code, B.code]` (sorted).
  - `"a whole-site rebuild also adds the complete plays the site lacks and leaves out drafts"`: build with A and C; set C to draft, mark B complete; generate with a new `version:` (forces `site_changed?`); assert codes == `[A, B]`.
- [ ] **Step 2:** `mix test test/playcode/export/site_builder_test.exs` — Expected: both FAIL (B missing).
- [ ] **Step 3:** In `outdated/1` add an `{:add, id}` for each `published` play whose code is not in `list_exported_codes(dir)`. In `SiteBuilder.build_all/1` drop `:play_codes` (every complete play); delete `codes_in_site/0` and its comment. Update the two docs to say Generate adds the complete plays the site lacks.
- [ ] **Step 4:** Run the file — Expected: PASS. Then `bin/bites lib/playcode/export/static_site.ex` on the new add clause, and again on `build_all`, each against its test.
- [ ] **Step 5: Refactor while green.** `changed/2` and the new missing-plays clause read `list_exported_codes(dir)` and `read_build(dir)` once between them.
- [ ] **Step 6:** Delete the contradicted export page test named above. `mix test test/playcode/export test/playcode_web/live/admin/export_site_live_test.exs` — Expected: PASS.
- [ ] **Step 7: Commit** `fix: Generate adds the plays marked complete since the last build`

### Task 2: `SiteStatus`, and the play page says where the play stands

**Files:**
- Create: `lib/playcode/export/site_status.ex`
- Modify: `lib/playcode/export/static_site.ex` (add `built_plays/1`, `deployed_at/1`)
- Modify: `lib/playcode/export/static_site/deployer.ex` (add `target/0`, moved from `ExportSiteLive.deploy_target/0`)
- Modify: `lib/playcode_web/live/play_sections_hook.ex` (`:play_deployed` → `:play_site_state`)
- Modify: `lib/playcode_web/components/layouts.ex`, `layouts/admin.html.heex` (sidebar's public-page link when the state is `:live`, `:changed` or `:leaving`)
- Modify: `lib/playcode_web/components/admin_components.ex` (`state_band/1`: `site_state` attr replaces `deployed`; badge + sentence)
- Modify: `lib/playcode_web/live/admin/play_detail_live.ex:291`
- Test: `test/playcode_web/live/admin/play_detail_live_test.exs` (find the state band tests there with `grep -n "play-state"`)

**Interfaces:**
- Produces:
  - `StaticSite.built_plays(dir) :: %{code => content_version}` (`read_build(dir).plays`)
  - `StaticSite.deployed_at(dir) :: DateTime.t() | nil` (mtime of the deploy record)
  - `Deployer.target() :: %{repo: String.t(), host: String.t() | nil} | nil` (body of today's `ExportSiteLive.deploy_target/0`)
  - `SiteStatus.live(dir \\ StaticSite.output_dir()) :: %{code => content_version}`: `StaticSite.deployed_plays(dir)` when `Deployer.target()` is not nil, else `StaticSite.built_plays(dir)`
  - `SiteStatus.state(play, live) :: :draft | :waiting | :changed | :leaving | :live`, per the Decisions table; a play with `deleted_at` that is live is `:leaving`, one not live is `:draft`
  - `SiteStatus.label(state) :: String.t()` (the badge msgids) and `SiteStatus.badge_class(state) :: String.t()` (`badge-ghost`, `badge-info`, `badge-warning`, `badge-neutral`, `badge-success`)
  - `PlaycodeWeb.AdminComponents.site_badge(assigns)` with `attr :state` — the pill both pages use

- [ ] **Step 1: Write the failing tests** in `play_detail_live_test.exs`, each building a real site (`StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [...])`), deploying where needed with `StaticSite.record_deploy(StaticSite.output_dir())`, and a deploy target set with `Application.put_env(:playcode, :static_site_deploy, repo: "file:///nowhere")` (restored `on_exit`):
  - `"a complete play not yet deployed is waiting, and says the next Publish puts it online"`: band has `t("Waiting to be published")` and `t("It goes on the site with the next Publish.")`.
  - `"a deployed play edited since has unpublished changes"`: deploy, then edit a line through the context; band has `t("Unpublished changes")`.
  - `"a deployed play at its version is on the site"`: `t("On the site")`.
  - `"a deployed play set back to draft is leaving the site"`: `t("Leaving the site")` and `t("The next Publish takes it off the site.")`.
  - `"with no deploy yet, every complete play is waiting"`: site built with the play, no `record_deploy`, target set: `t("Waiting to be published")` (Review Focus 1).
  - `"without a deploy repository, the built site counts as the live one"`: target unset, site built: `t("On the site")`.
- [ ] **Step 2:** Run the file — Expected: the six FAIL (no such text).
- [ ] **Step 3:** Implement the interfaces above. Sentences (msgid → es):
  - `:draft` "Only the team sees it." → "Solo la ve el equipo."
  - `:waiting` "It goes on the site with the next Publish." → "Sale en la web con la próxima publicación."
  - `:changed` "On the site; your changes go online with the next Publish." → "En la web; los cambios salen con la próxima publicación."
  - `:leaving` "The next Publish takes it off the site." → "La próxima publicación la quita de la web."
  - `:live` "On the site as it is." → "En la web tal como está."
  The band keeps its Complete/Draft badge and its button; the site badge sits beside it. Delete the five old `state_sentence/2` clauses and their msgids.
- [ ] **Step 4:** Run the file — PASS; `bin/bites` on one clause of `SiteStatus.state/2` (e.g. swap `:changed`'s comparison) against its test.
- [ ] **Step 5: Refactor while green.** The export page still calls its own `deploy_target/0`: point it at `Deployer.target/0` now and delete the copy.
- [ ] **Step 6:** `mix test test/playcode_web` — Expected: PASS (sidebar's public link tests included).
- [ ] **Step 7: Commit** `feat: a play's page says whether it is on the site, waiting, changed or leaving`

### Task 3: `SiteBuilder.publish/2`

**Files:**
- Modify: `lib/playcode/export/site_builder.ex`
- Test: `test/playcode/export/site_builder_test.exs` (the bare-repo helper is in `test/playcode/export/deploy_test.exs`; move it to `test/support/static_site_helpers.ex` as `bare_repo/0` if both files need it)

**Interfaces:**
- Produces: `SiteBuilder.publish(opts, repo) :: :started | :queued`. Job `:publish`. Broadcasts `{:site_builder, :started, :publish}`, then the generate's `{:site_builder, :progress, :generate, info}` and the deploy's `{:site_builder, :progress, :deploy, status}`, then `{:site_builder, :done, :publish, {:ok, url}}` or `{:site_builder, :done, :publish, {:error, reason}}`. Queued like `:generate` and `:deploy` (runs on its own; a second ask while one waits takes its place with the latest args).

- [ ] **Step 1: Write the failing tests:**
  - `"Publish generates and then deploys, and records the deploy"`: bare repo; complete play A; `publish([version: "1.0"], "file://" <> repo)`; await `{:site_builder, :done, :publish, {:ok, _}}`; assert `git show gh-pages:plays/A/index.html` holds A's title and `StaticSite.deployed_plays(dir)` has A's code.
  - `"a Publish whose generate fails deploys nothing"` (Review Focus 3): no complete play (generate returns `{:error, _}`); assert `:done` carries `{:error, _}` and the bare repo has no `gh-pages` branch.
- [ ] **Step 2:** Run — FAIL (`publish/2` undefined).
- [ ] **Step 3:** `def publish(opts, repo), do: request(:publish, {opts, repo})`; `take/1` treats `:publish` like `:generate`; `run(:publish, {opts, repo})` is `with {:ok, _} <- run(:generate, opts), do: run(:deploy, repo)`.
- [ ] **Step 4:** Run — PASS; `bin/bites` the `with` into an unconditional deploy against the second test.
- [ ] **Step 5: Refactor while green**; update the `@moduledoc`'s job list.
- [ ] **Step 6: Commit** `feat: SiteBuilder.publish, generate then deploy in one job`

### Task 4: The export page

**Files:**
- Modify (most of it rewritten): `lib/playcode_web/live/admin/export_site_live.ex`
- Rewrite: `test/playcode_web/live/admin/export_site_live_test.exs`

**Interfaces:**
- Consumes: `SiteStatus.live/1`, `SiteStatus.state/2`, `site_badge/1`, `StaticSite.deployed_at/1`, `Deployer.target/0`, `SiteBuilder.publish/2`, `SiteBuilder.generate/1`.
- Events: `"publish"`, `"generate"` (preview), `"update_form"` (version), `"search_live"` (Up to date's search), `"live_page"` (`%{"page" => n}`).
- Ids for tests: `#publish-card`, `#group-new`, `#group-changed`, `#group-leaving`, `#group-live`, `#play-<code>` (by code: a purged play has no id), `#site-size`, `#edition-version`.

Layout, top to bottom (mockup tab 2):
1. Header as today.
2. `#publish-card`: headline + "%{live} on %{host} · last deploy %{date}" (no deploy yet: "Not published yet"); buttons "Generate preview", "Open preview ↗" (when a site exists), primary "Publish %{count} plays" (when `Deployer.target()`; "Publish" when the count is 0 but the site changed); the info banner when `site_changed`; progress while a job runs ("Step 1 of 2 · building play %{current} of %{total}: %{detail}", "Step 2 of 2 · %{status}"; a lone generate shows no step prefix); the facts line with `<details id="edition-version">` holding the version form and its warning ("Printed in every page's footer, in the citation and on the About page. Changing it rebuilds every play: change it only for a new edition."); the deploy hint when no repository.
3. Plays card: the three groups, each hidden when empty, rows with code, title, and a reason (Changed: "edited %{date}" from `content_changed_at`; Leaving: "back to draft" / "archived" / "deleted"); "Everything is published." when all three are empty. Then `<details id="group-live">` "Up to date (%{count})" with the search input and 50 to a page, prev/next buttons.
4. `<details>` "About the static site", plain paragraph, outside any card.

Gone: the switches, `toggle_play`, `add_all`, `refresh_play`, the status dots, `:indexing`, `:pending`, the "Built site" and "Deployed!" cards, the "Configuration" card, `generate_hint/5` and its helpers (the banner and the headline say it now).

- [ ] **Step 1: Write the failing tests** (keep the setup, `wait_for/2`, the `"the preview"` describe and the deploy repository tests' helpers; delete the rest, named in Step 6):
  - `"a complete play not on the live site is listed as new"`: A and B complete, nothing built → both in `#group-new`; the draft is in no group.
  - `"a deployed play edited since is listed as changed, with the day it was edited"`.
  - `"a deployed play set back to draft is listed as leaving"`, and `"a purged play still on the site is listed by its code as deleted"` (Review Focus 2: purge via `Catalogue.purge_play/1` after deploy).
  - `"the headline counts what is waiting and the deploy that is live"`: `t("%{count} plays to publish", count: 2)`.
  - `"Publish puts every waiting play online and empties the groups"`: bare repo target; click Publish; wait for `t("Published at %{url}", ...)`; `#group-new` gone, `#group-live` counts 2.
  - `"Generate preview builds without deploying"`: no deploy record after; the plays stay in `#group-new`; the preview link serves A.
  - `"without a repository there is no Publish, and the hint says what to set"` (today's last deploy test, kept).
  - `"Playcode changing since the build is named, and Publish rebuilds every play"`: set a new version; banner text; after Generate preview every play's page carries the new version.
  - `"Up to date is searchable and 50 to a page"`: 51 deployed plays; page 2 has one row; search for one title shows only it; searching while on page 2 clamps to page 1 (Review Focus 5).
  - `"the groups are read again when a job ends"` (Review Focus 4): set a play to draft while a Publish runs; after `:done` it is in `#group-leaving`.
  - `"a second admin's page follows a Publish started on the first"` (adapted from today's test of that name).
  - `"a failed Publish says why"`.
- [ ] **Step 2:** Run the file — FAIL.
- [ ] **Step 3:** Rewrite the LiveView as laid out above. Groups from `SiteStatus.state/2` over `Catalogue.list_plays(include_deleted: true)` plus the live codes with no row; recompute on mount, on `{:play_changed, _}` and on `:done`/`:failed`.
- [ ] **Step 4:** Run — PASS. `bin/bites` the group assignment (e.g. map `:changed` to `:live`) and the clamp.
- [ ] **Step 5: Refactor while green.** The page's module doc says what it is now in two sentences; delete helpers nothing calls.
- [ ] **Step 6:** Deleted tests and what covers each: the switch, Add every, Refresh, dot and "leaving row" tests test removed controls (behaviour gone); "Generate pressed while a play is being added" and "switches flipped during a build" covered by `SiteBuilder`'s queue tests; "the site's figures are the site on disk" by `"Publish puts every waiting play online"` reading `#site-size`. List them in the commit message.
- [ ] **Step 7:** `mix gettext.extract --merge`; Spanish for every new msgid (the mockup's tab 2 has the wording: "%{count} obras por publicar", "Publicar %{count} obras", "Generar vista previa", "Abrir vista previa", "Nuevas", "Con cambios", "Saldrán", "Al día", "Edición %{version}", "cambiar", "Sobre el sitio estático", "Todo está publicado.", "editada %{date}", "vuelta a borrador", "archivada", "eliminada", "Paso 1 de 2 · …", and the flash "Published at %{url}" → "Publicado en %{url}"); check every fuzzy entry. `mix test test/playcode_web/accessibility_test.exs` — PASS.
- [ ] **Step 8: Commit** `feat: the export page publishes in one step and lists only what is waiting`

### Task 5: The play list shows and filters by the site's state

**Files:**
- Modify: `lib/playcode/catalogue.ex` (`apply_status/2`: a `{:codes, [code]}` clause, `where p.code in ^codes`)
- Modify: `lib/playcode_web/live/admin/play_list_live.ex`
- Test: `test/playcode_web/live/admin/play_list_live_test.exs`

**Interfaces:**
- Consumes: `SiteStatus.live/1`, `SiteStatus.state/2`, `site_badge/1`.
- `?status=` takes `waiting | changed | leaving | live` besides today's values; the LiveView turns one into `{:codes, codes}` from `Catalogue.list_plays()` classified against `SiteStatus.live()`, read once per `reload/1`.

- [ ] **Step 1: Write the failing tests:**
  - `"each play shows where it stands on the site"`: one play per state (built and deployed as in Task 2); each row (`#play-<id>` or the row id the list uses) has its badge text.
  - `"the site filter lists only the plays waiting"`: click the "Waiting" chip (by its text); only that play listed; its count follows the search.
  - `"a translation waiting under an original on the site is listed under it"`: the family rule `list_families` applies to `:status` holds for the new filter.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** A "Site" column after Status (hidden on `max-sm:` like Verses); a second chip group, labelled "Site" (`aria-label`), with Waiting / Unpublished changes / Leaving / On the site and their counts (`count_plays(search:, status: {:codes, codes})`).
- [ ] **Step 4:** Run — PASS; `bin/bites` the `{:codes, _}` clause.
- [ ] **Step 5: Refactor while green.**
- [ ] **Step 6:** gettext as in Task 4; `mix test test/playcode_web` — PASS.
- [ ] **Step 7: Commit** `feat: the play list shows and filters by the site's state`

### Task 6: `SiteBuilder` loses add and remove

Nothing calls `SiteBuilder.add/2`, `remove/2` or the batch job after Task 4. `StaticSite.apply_changes/2` stays: Generate's refresh uses it.

**Files:**
- Modify: `lib/playcode/export/site_builder.ex` (delete `add/2`, `remove/2`, `change?/1`, the batch `take/1` clause, `run({:batch, _})`, the `:published` broadcast; the queue now holds `:generate`, `:deploy`, `:publish`)
- Modify: `test/playcode/export/site_builder_test.exs` (delete the batch tests; keep and adapt the queue tests: "a request already waiting keeps its place and takes the latest options" with `:generate`)
- Modify: `test/support/static_site_helpers.ex` if `await_idle_builder/0` matches batch messages

- [ ] **Step 1:** Delete the batch tests; name in the commit what covers the queue now.
- [ ] **Step 2:** Delete the code; `mix compile --warnings-as-errors` — clean.
- [ ] **Step 3:** `mix test test/playcode/export` — PASS.
- [ ] **Step 4: Commit** `refactor: SiteBuilder runs generate, deploy and publish; no per-play batches`

### Task 7: Docs, and the whole suite

**Files:**
- Modify: `docs/static-site.md` (the admin page's section: Publish, the groups, the states; the switches gone)
- Modify: `docs/architecture.md` if it names the switches or `SiteBuilder.add`
- Modify: `docs/history.md` (this work, one paragraph, 2026-11-24)
- Modify: `CLAUDE.md` only if a rule changed: *Static site export*'s "Every build and deploy goes through `SiteBuilder`, one job at a time" still holds; check `grep -n "switch\|Add every" CLAUDE.md docs/*.md`

- [ ] **Step 1:** Update the docs; `grep -rn "switch\|Add every\|refresh_play\|SiteBuilder.add" docs lib CLAUDE.md` — only historical entries left.
- [ ] **Step 2:** `pgrep -af "mix test"` shows no other run, then `mix test 2>&1 | tail -10` — Expected: `0 failures`. `node --test test/js/*.test.mjs` — PASS.
- [ ] **Step 3:** `mix test --include browser test/playcode/export/static_site_browser_test.exs` if Chrome is present — PASS.
- [ ] **Step 4: Commit** `docs: the export page publishes in one step`
