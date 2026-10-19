# S5 — Historical performances — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring FileMaker's historical performances into the plays we hold, print them on the play page and the site (layout B), let researchers add and correct them and their casts, and carry them in the TEI file.

**Architecture:** A context `Playcode.Performances` over four tables: `play_performances` and `performance_cast` per play, `performance_companies` and `performance_actors` corpus-wide. A performance's place is a gazetteer link with a historical state, as S9b's play links are; its source is a bibliography entry with the performance's own volume and pages (question 11), never linked to the play's bibliography (question 12). One presenter, `Performances.listing/4`, feeds the play page and the site. `Playcode.Import.Performances` is S9b's shape (`load/1`, `plan/2`, `apply_plan/2`, `report/1`) and reuses S9b's place rules through two functions `Import.Places` exposes.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Ecto + PostgreSQL triggers, Saxy, xml_builder.

**Spec:** `docs/superpowers/specs/2026-10-19-s5-performances-design.md` — read it first; this plan argues from it and does not repeat its reasons.

## Global Constraints

- TDD, CLAUDE.md's loop: failing test, see it fail, smallest code, see it pass, **refactor while green** (Saša Jurić's clear code: names, no duplication, the helper the code already has, the surrounding idiom), then `mix test` (whole suite), `mix format`, `mix compile --warnings-as-errors`, commit.
- Test through the outermost API: LiveViews with `live/2`, the mix task with `Mix.Task.rerun/2`, the importer's rules through `plan/2` (as `test/playcode/import/places_test.exs` does), TEI as round trips (`roundtrip/1`, `xml_elements/3`), read back through `Playcode.Performances`, never `Repo`.
- **Prove a new test bites** where it covers code that already works: break the line, watch red, restore, say so in the commit.
- Places in async tests: `place_fixture/1` derives a unique slug; pass `"slug"` only when asserting on it, with a per-file prefix (`perf-…`, `rt-perf-…`).
- An id from the browser is resolved with a scoped getter (`Performances.get_performance/2`, `Places.get_place/1`, `Bibliography.get_entry/1`); nil → reload and `LiveHelpers.put_gone_flash/1`.
- New gettext strings: `mix gettext.extract --merge`, check every entry it marks fuzzy, give the Spanish: Performances → Representaciones, Cast → Reparto, Add performance → Añadir representación, No performances yet. → Aún no hay representaciones., Venue → Lugar de la representación, Venue type → Circunstancia escénica, Company → Compañía, Date → Fecha, Year from → Desde el año, Year to → Hasta el año, Cast as in the cast list → Reparto como en el elenco, Rename → Renombrar, Edit source → Editar la fuente, Surname → Apellidos, Forename → Nombre, Nickname → Apodo, Sex → Sexo, Man → Hombre, Woman → Mujer, Role → Papel, Volume → Volumen, Pages → Páginas.
- Venue types (`Performance.venue_types/0`, FileMaker's ids 1–8 in this order) and their labels, verbatim from `T11.2`: `public_theatre` teatro público / public theatre; `palace` palacio / palace / court; `street` calle, plaza / street, square; `other` otro / other; `private_theatre` teatro privado / private theatre; `unknown` desconocido / unknown; `university` universidad / “inns of court” / university, inns of court; `commercial_theatre` teatro comercial / commercial theatre.
- Activity log: `resource_type: "play_performance"`; the import's row `action: "import"`, `metadata: %{"source" => "filemaker"}`; renames `action: "update"`, `resource_type: "performance_company"` / `"performance_actor"`.
- A TEI file names no database or FileMaker id; `filemaker_id` never reaches it.
- No new dependencies. FileMaker never creates plays.
- Work on branch `s5-performances`. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01TjzxRhzNSTuMrNZf3uZLXx`.
- Before staging `docs/backlog.md` or `docs/stakeholder/*.html`, `git diff` them; edits that are not yours mean asking the owner first.

## Review Focus

1. **A rename onto a name another company or actor already has** ("The Duke's Company" twice) → refused with a message on the field, nothing merged, the page usable. Test in Task 6.
2. **A TEI file with no performances** (every production file today) re-imported on a play holding FileMaker's → they stay; only `tei` performances are replaced. Test in Task 8.
3. **A second performance switched to "Cast as in the cast list"** on the same play → refused with a message, not a crash from the unique index. Test in Task 5.
4. **A date with no year, or only an end year** ("desconocida", "Before 1642") → printed as written, sorted by the year it has or last, never a crash; a year a curator typed survives a later edit of the date. Test in Task 1.
5. **The cast-list switch on a play whose characters have no actor** → no "Cast:" line at all, never an empty "Cast: ". Test in Task 4.

---

### Task 1: The tables, the triggers, the performance itself

**Files:**
- Create: `priv/repo/migrations/20261020100000_create_performances.exs`, `lib/playcode/performances.ex`, `lib/playcode/performances/performance.ex`, `lib/playcode/performances/company.ex`, `lib/playcode/performances/actor.ex`, `lib/playcode/performances/cast_member.ex`, `test/playcode/performances_test.exs`
- Modify: `lib/playcode/catalogue/play.ex` (`has_many :performances`), `test/support/fixtures.ex` (`performance_fixture/2`), `test/playcode/content_version_test.exs`

**Interfaces:**
- Produces:

```elixir
# Performance fields: play_id, date_text, year_from, year_to, venue, venue_type, company_id,
#   place_id, historical_state_id, note, source_entry_id, source_volume, source_pages,
#   cast_from_cast_list (default false), position, origin (default "manual"), filemaker_id
#   belongs_to :company, :place, :historical_state (Place), :source (Entry, foreign_key: :source_entry_id)
#   has_many :cast, CastMember, preload_order: [asc: :position]
# CastMember: performance_id, actor_id, role, position;  belongs_to :actor
# Company: name.   Actor: surname, forename, nickname, sex ("man" | "woman" | nil)
Performance.venue_types() :: [String.t()]
Performance.venue_type_label(type, locale :: "es" | "en") :: String.t()
Performance.years(date_text :: String.t() | nil) :: {integer | nil, integer | nil}
Performances.list_for_play(play_id) :: [Performance.t()]   # preloaded: company, place: :names, source, cast: :actor
Performances.get_performance(play_id, id) :: Performance.t() | nil
Performances.change_performance(performance, attrs \\ %{}) :: Ecto.Changeset.t()
Performances.create_performance(attrs, base \\ %Performance{}) :: {:ok, Performance.t()} | {:error, Ecto.Changeset.t()}
Performances.update_performance(performance, attrs) :: {:ok, Performance.t()} | {:error, Ecto.Changeset.t()}
Performances.delete_performance(performance) :: {:ok, Performance.t()}
performance_fixture(play, attrs \\ %{}) :: Performance.t()   # test/support/fixtures.ex
```

- [ ] **Step 1: Write the failing tests**

`performances_test.exs` (`use Playcode.DataCase, async: true`):

```elixir
describe "years/1" do
  test "reads FileMaker's dates" do
    for {date, years} <- [
          {"1610", {1610, 1610}}, {"1597-9", {1597, 1599}}, {"1610-11", {1610, 1611}},
          {"1612 - 1613", {1612, 1613}}, {"c. 1622-5", {1622, 1625}}, {"1590s", {1590, 1599}},
          {"c. 1620", {1620, 1620}}, {"Before 1642", {nil, 1642}}, {"04/05//1674", {1674, 1674}},
          {"1603, 1609-1642", {1603, 1642}}, {"30 y 31 de marzo de 1682", {1682, 1682}},
          {"1701-1702: 1 Oct, 21 Oct", {1701, 1702}}, {"¿1683?¿1684?", {1683, 1684}},
          {"desconocida", {nil, nil}}, {nil, {nil, nil}}
        ],
        do: assert(Performance.years(date) == years, date)
  end
end

test "a play's performances come in order of year, the undated last, then as entered"
  # create "1623", "Before 1610", "", "1610" (in that order) → date_text order
  # ["Before 1610", "1610", "1623", ""]
test "the years are filled from the date when left blank, and a curator's are kept"
  # create %{"date_text" => "1597-9"} → {1597, 1599}; update %{"date_text" => "c. 1598",
  # "year_from" => "1590"} → year_from 1590, year_to 1598
test "a venue type is one of FileMaker's eight"  # "theatre" → errors_on(...).venue_type
test "a performance needs something to say"      # all blank → error on :date_text
test "only one performance of a play takes its cast from the cast list"
  # second {:error, cs}; errors_on(cs).cast_from_cast_list == ["is already set on another performance of this play"]
test "a performance of another play, a deleted one or a malformed id is nil"
```

`content_version_test.exs`, copying the shape of `"every edit to the text, cast, credits, notes or places moves the play"`: one test per trigger — `"a performance moves its play"` (insert, update, delete), `"a cast row moves the performance's play"`, `"renaming a company or an actor moves every play whose performances name it"`, `"an edit to a source entry moves the plays whose performances cite it"`, `"an edit to a place moves the plays performed there or anywhere inside it, or in a state it names"`. Each also asserts an unrelated play does not move. Write the company, actor and entry updates through `Repo` with an alias and a comment (the contexts for them come in Tasks 2 and 3).

- [ ] **Step 2: Run them, watch them fail**

Run: `mix test test/playcode/performances_test.exs test/playcode/content_version_test.exs`
Expected: FAIL (`Playcode.Performances.Performance` undefined).

- [ ] **Step 3: Implement**

- Migration `up`: the four tables of the spec's *The model* (UUID keys, `timestamps(type: :utc_datetime)`); `performance_companies` unique index on `lower(name)`; indexes on every foreign key; partial unique index `play_performances (play_id) WHERE cast_from_cast_list`, named `play_performances_one_cast_list_index`. Triggers: `play_performances_touch_play` → `play_row_changed()`; `performance_cast` → new `performance_cast_changed()` (`touch_play(play_id) FROM play_performances WHERE id IN (OLD.performance_id, NEW.performance_id)`); `performance_companies` and `performance_actors` AFTER UPDATE → new `performance_name_changed()` with `TG_ARGV[0]` the column (`company_id`; for actors, through `performance_cast`); `CREATE OR REPLACE FUNCTION bibliography_entry_changed()` adding the plays whose `play_performances.source_entry_id` is the entry; `CREATE OR REPLACE FUNCTION place_changed()` (S9b's body, `20261019120000_add_historical_state_to_play_places.exs:21-44`) adding `play_performances` whose `place_id` or `historical_state_id` is in the tree. `down` restores both functions and drops the tables. Moduledoc: the line `20261005120000_track_play_content_version`'s moduledoc asks for.
- `Performance.changeset/2`: cast every field but `position` and `filemaker_id`; `Playcode.Text.squeeze/1` the text fields as `Witness` does; `validate_inclusion(:venue_type, @venue_types)`, `:origin` in `Catalogue.origins()`; error `"needs a date, a venue, a company or a note"` on `:date_text` when all of date_text, venue, venue_type, company_id, note are blank; fill a blank `year_from`/`year_to` from `years(date_text)`; `unique_constraint(:cast_from_cast_list, name: :play_performances_one_cast_list_index, message: "is already set on another performance of this play")`.
- `years/1`: every four-digit year in the text is a year; a `-` followed by one or two digits right after a year completes it (`1597-9` → 1599); `NNN0s` gives `NNN9` as the last; `before` (any case) before the only year → `{nil, year}`; from the smallest, to the largest; no year → `{nil, nil}`.
- `Performances`: `create_performance/2` sets `position` after the play's last (as `Witnesses.create_witness/2`); `list_for_play/1` orders by `fragment("coalesce(?, ?)", p.year_from, p.year_to) ASC NULLS LAST`, then `position`, `inserted_at`.

- [ ] **Step 4: Run them, watch them pass.** Same command. Prove one trigger test bites: drop the `play_performances` line from `place_changed()`, `MIX_ENV=test mix ecto.rollback`, run, red, restore.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit**

`mix test` also runs `complete_copy_test.exs`, whose table check fails on the new `play_id` table: add `play_performances` to its `kept_out` with the comment `# until the TEI export carries performances (Task 8)`.
```bash
git add priv/repo/migrations lib/playcode/performances.ex lib/playcode/performances lib/playcode/catalogue/play.ex test
git commit -m "feat(performances): a play's historical performances, kept in their own tables"
```

---

### Task 2: Companies and actors

**Files:**
- Modify: `lib/playcode/performances.ex`, `lib/playcode/performances/company.ex`, `lib/playcode/performances/actor.ex`
- Test: `test/playcode/performances_test.exs`

**Interfaces:**
- Consumes: Task 1.
- Produces:

```elixir
Performances.list_companies() :: [Company.t()]            # by name, for the datalist
Performances.list_actors() :: [Actor.t()]                 # by surname, forename, nickname
Performances.find_or_create_company(name :: String.t()) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
Performances.find_or_create_actor(%{"surname", "forename", "nickname", "sex"}) :: {:ok, Actor.t()} | {:error, Ecto.Changeset.t()}
Performances.update_company(company, attrs) :: {:ok, Company.t()} | {:error, Ecto.Changeset.t()}
Performances.update_actor(actor, attrs) :: {:ok, Actor.t()} | {:error, Ecto.Changeset.t()}
Performances.usage(%Company{} | %Actor{}) :: %{performances: non_neg_integer, plays: non_neg_integer}
Performances.put_cast(performance, [%{"actor_id" => id, "role" => role}]) :: {:ok, Performance.t()} | {:error, Ecto.Changeset.t()}
Performances.get_company(id) :: Company.t() | nil   # nil for a malformed or missing id
Performances.get_actor(id) :: Actor.t() | nil
Actor.display_name(actor) :: String.t()
```

- [ ] **Step 1: Write the failing tests**

```elixir
test "a company is found by its name whatever the case, else created"
  # find_or_create_company("The Duke’s Company") twice and "the duke’s company" → one id
test "an actor is found by all four fields, else created"
  # %{"surname" => "Burbage", "forename" => "Richard"} twice → one; with "nickname" → another
test "an actor needs a surname or a nickname"   # %{"forename" => "Jean"} → error on :surname
test "an actor reads as forename, surname, then the nickname in quotes"
  # Poquelin / Jean François / Molière → "Jean François Poquelin, “Molière”"; nickname only
  # "Rosimond" → "Rosimond"; surname only "Lowin" → "Lowin"
test "renaming a company renames it for every performance that names it"
  # two plays' performances name it; update_company(c, %{"name" => "The King’s Men"});
  # both list_for_play/1 show the new name; usage(c) == %{performances: 2, plays: 2}
test "a rename onto a name another company has is refused"
  # errors_on(cs).name == ["is already the name of another company"]; same for an actor
  # onto another actor's four fields: errors_on(cs).surname == ["is already another actor"]
test "a company or actor no performance names is deleted with its last use"
  # deleting the only performance naming a company: list_companies() == [];
  # pointing a performance at another company deletes the first; put_cast/2 dropping the
  # only row of an actor deletes the actor; a company still used elsewhere stays
test "the cast keeps the order it is given"
```

- [ ] **Step 2: Run, watch them fail.** `mix test test/playcode/performances_test.exs`

- [ ] **Step 3: Implement.** `Company.changeset/2`: required name, squeezed, `unique_constraint(:name, name: :performance_companies_lower_name_index, message: "is already the name of another company")`. `Actor.changeset/2`: squeezed fields, sex in `~w(man woman)`, the surname-or-nickname rule; "is already another actor" checked by a query on the four fields, case-insensitive, excluding itself. Deletion of unused companies and actors: one private `delete_unused/1` in `Performances` called inside the transaction of `update_performance/2`, `delete_performance/1` and `put_cast/2` with the company and actor ids the change let go of. `put_cast/2` replaces the performance's rows, `position` from the list's order.

- [ ] **Step 4: Run, watch them pass.**

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit** — `feat(performances): companies and actors, shared by every performance, renamed in place`

---

### Task 3: A performance's source

**Files:**
- Modify: `lib/playcode/bibliography/entry.ex` (kind `catalogue`), `lib/playcode/bibliography.ex` (`unlink/1`, `plays_for_entry/1`, `link_counts/1`, `search_entries/3`, new `get_entry/1`, new `delete_if_unused/1`), `lib/playcode/performances.ex`
- Test: `test/playcode/bibliography_test.exs`, `test/playcode/performances_test.exs`

**Interfaces:**
- Produces: `Entry.kinds/0` unchanged (the four the bibliography groups and the Bibliography tab offers); the changeset accepts `"catalogue"` too. `Bibliography.get_entry(id) :: Entry.t() | nil` (nil for a malformed or missing id). `Bibliography.delete_if_unused(entry_id) :: :deleted | :kept`. `plays_for_entry/1` and `link_counts/1` count a play whose performances cite the entry once, beside one that links it. `Bibliography.search_entries(term, play_id, limit \\ 10, opts \\ [])` with `kinds: :all` — the default leaves out `catalogue`; `kinds: :all` (the Performances tab) finds every kind and does not leave out the play's own entries.

- [ ] **Step 1: Write the failing tests**

`bibliography_test.exs`:
- `"a catalogue is an entry the play's bibliography never shows or finds"` — an entry `kind: "catalogue"` cited by a performance: `list_for_play/1` has no group for it; `search_entries("Wiggins", play.id)` is `[]`; with `kinds: :all` it is found.
- `"an entry a performance cites outlives the play's last link to it"` — the entry linked to the play and cited by another play's performance: `unlink/1` gives `{:ok, :unlinked}`, the entry stays.
- `"the plays an entry is shared with include those whose performances cite it"` — `plays_for_entry/1` lists both plays; `link_counts([id]) == %{id => 2}`.

`performances_test.exs`:
- `"a source nothing else cites goes with its performance"` — delete the only performance citing an entry: `Bibliography.get_entry(id) == nil`; change a performance's source: the old entry is gone; an entry a play's bibliography links stays.
- `"a performance's own volume and pages are kept beside its source"`.

- [ ] **Step 2: Run, watch them fail.** `mix test test/playcode/bibliography_test.exs test/playcode/performances_test.exs`

- [ ] **Step 3: Implement.** `delete_if_unused/1` holds the existence check `unlink/1` has now, over links and performances; `unlink/1` calls it; `Performances` calls it in the transactions of Task 2 with the entry the change let go of.

- [ ] **Step 4: Run, watch them pass.**

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit** — `feat(bibliography): an entry a performance cites, and catalogues that stay out of the bibliography`

---

### Task 4: What readers see

**Files:**
- Modify: `lib/playcode/performances.ex` (`listing/4`), `lib/playcode/places.ex` (`place_line/3` takes any struct with `place` and `historical_state_id`), `lib/playcode_web/live/play_show_live.ex` (section `meta-performances` between `meta-witnesses` and `meta-bibliography`; the section index), `lib/playcode/export/static_site/edition.ex` (`performances` field), `lib/playcode/export/static_site/components.ex` (`performances/1`, the rail link `index.html#performances`), `lib/playcode/export/static_site/pages/title.html.heex:42`, `priv/static_site/style.css`, `lib/playcode/export/static_site/fingerprint.ex` (`Playcode.Performances`, `Playcode.Performances.Performance`, `Playcode.Performances.Actor`)
- Test: `test/playcode/performances_test.exs`, `test/playcode_web/live/play_show_live_test.exs`, `test/playcode/export/static_site_test.exs`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:

```elixir
Performances.listing(performances :: [Performance.t()], characters :: [Character.t()],
                     gazetteer :: map, locale :: String.t()) ::
  %{lines: [%{id: binary, date: String.t() | nil, parts: [String.t()],
              source: pos_integer | nil, range: String.t() | nil,
              cast: [String.t()], note: String.t() | nil}],
    sources: [{pos_integer, Entry.t()}]}
```

`parts`: the venue, `Places.place_line/3`, the company's name, `venue_type_label/2`, those present. `range`: `"vol. 6, p. 83"`, either half alone, or nil. `cast`: each `"#{Actor.display_name(a)} (#{role})"`, the role's brackets left out when blank; with `cast_from_cast_list`, first each character with an `actor`, in cast-list order, `"Mr. Betterton (Fainall)"`. `sources`: each distinct source, numbered by first citation in `lines`.

- [ ] **Step 1: Write the failing tests**

`performances_test.exs`, describe `"listing/4"`:
- `"a line is the date, then venue, place, company and venue type, the source's number and the performance's pages"` — The Alchemist's 1610 row: `date == "1610"`, `parts == ["Globe or Blackfriars", "The King’s Men", "commercial theatre"]` (locale `"en"`), `source == 1`, `range == "vol. 6, p. 83"`; locale `"es"` gives `"teatro comercial"`.
- `"one source cited by several performances is numbered once"` — two Wiggins rows, one Chambers: `sources` has two entries, `[1, 1, 2]`.
- `"the cast reads actor (role)"` — `["Jean François Poquelin, “Molière” (Argan)", "Rosimond"]`.
- `"the cast-list switch prints the characters' actors"` — `["Mr. Betterton (Fainall)", "Mr. Verbruggen (Mirabell)"]`; **Review Focus 5:** with no character holding an actor, `cast == []`.
- `"a performance with only a venue type prints that"` — `parts == ["street, square"]`, `date == nil`.

`play_show_live_test.exs`, describe `"the performances panel"`: `render(element(view, "#meta-performances"))` holds the line, `"[1] vol. 6, p. 83"`, the cast line, the note, and the source's citation once with its `public_note` (CATCOM's credit); the section index links `#meta-performances`; a play with none has no section.

`static_site_test.exs`, beside the witnesses' test: the title page holds `id="performances"`, the line, the citation once, and the rail links `index.html#performances`; no FileMaker placeholder (`refute html =~ "{Falta"`) for an entry with no year.

- [ ] **Step 2: Run, watch them fail.**

Run: `mix test test/playcode/performances_test.exs test/playcode_web/live/play_show_live_test.exs test/playcode/export/static_site_test.exs`

- [ ] **Step 3: Implement.** Layout B, as the spec's *What readers see* and its mockup: on the play page a `<dl>` like the witnesses' (label `gettext("Performances")`), a `<ul>` of lines with the date in `font-semibold`, the parts joined by `" · "`, the source and range in `text-xs text-base-content/70`; cast (`gettext("Cast")` + `": "` + the list joined by `"; "`) and note below in `text-xs`; then a `<ul class="font-serif">` of `"[n] "` and `Citation.html(entry)`. The site: `Components.performances/1` the same, English labels as the site's other sections, place names `"es"`; its CSS inside the 25 KB budget `static_site_test.exs` asserts. The play page loads `Performances.list_for_play/1` in `mount` as it loads the bibliography; the site's `Edition.load/1` likewise.

- [ ] **Step 4: Run, watch them pass.** Then `mix test test/playcode/export/fingerprint_test.exs`.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Gettext, whole suite, format, compile, commit** — `feat(performances): the play page and the site print a play's performances`

---

### Task 5: The Performances tab

**Files:**
- Create: `lib/playcode_web/live/admin/play_performances_live.ex`, `test/playcode_web/live/admin/play_performances_live_test.exs`
- Modify: `lib/playcode_web/router.ex:164` (`live "/plays/:id/performances", PlayPerformancesLive, :index`), `lib/playcode_web/components/layouts.ex` (the tab after Witnesses; `:performances` in the `active_tab` doc at line 106), `test/playcode_web/authorization_test.exs:26` (`{"/admin/plays/:id/performances", :active}`), `test/playcode_web/accessibility_test.exs:90` and `:127` (`{"/admin/plays/:id/performances", [{"button", t("Add performance")}]}`)

**Interfaces:**
- Consumes: Tasks 1, 4 (`listing/4` for the list shown).
- Produces: the form `performance[date_text|year_from|year_to|venue|venue_type|company_name|place_id|historical_state_id|note|source_volume|source_pages|cast_from_cast_list]`; events `new`, `edit` (`%{"id"}`), `validate`, `save`, `delete` (`%{"id"}`), `cancel`. Tasks 6 and 7 add to this form.

- [ ] **Step 1: Write the failing tests**, in the shape of `play_witnesses_live_test.exs`:
- `"a researcher adds a performance and sees it as readers will"` — fill date "1610", venue, venue type, company name "The King’s Men" (new); the list shows the line; `Performances.list_for_play/1` has it, origin `"manual"`, the company created.
- `"a company is picked from those that exist"` — an existing company's name typed: no second company.
- `"the place is found by name, and a state chosen"` — the Places tab's search component; `place_line` in the list.
- `"a performance is edited and deleted"` — the activity log has `create`, `update`, `delete` rows with `resource_type: "play_performance"`.
- **Review Focus 3:** `"a second cast-list switch is refused with a message"` — the form shows `"is already set on another performance of this play"`.
- `"a performance that is gone says so"` — `edit` with another play's id, then `"not-a-uuid"`: the gone flash.

- [ ] **Step 2: Run, watch them fail.** `mix test test/playcode_web/live/admin/play_performances_live_test.exs test/playcode_web/authorization_test.exs`

- [ ] **Step 3: Implement**, shaped like `PlayWitnessesLive`: the list (`listing/4` lines, each with Edit and Delete buttons labelled for the performance), the form below. `company_name` through `Performances.find_or_create_company/1` on save (blank → nil), the companies as a `<datalist>`. The place: the search the Places tab uses (`Places.search_names/2`) and the state select of countries and regions (`play_places_live.ex`'s `@states`); ids through `Places.get_place/1`.

- [ ] **Step 4: Run, watch them pass**; then `mix test test/playcode_web/accessibility_test.exs`.

- [ ] **Step 5: Refactor while green.** If the place search and state select can be one function component shared with `PlayPlacesLive`, extract it.

- [ ] **Step 6: Gettext, whole suite, format, compile, commit** — `feat(admin): the Performances tab adds, edits and deletes a play's performances`

---

### Task 6: The cast, and renaming in the form

**Files:**
- Modify: `lib/playcode_web/live/admin/play_performances_live.ex`
- Test: `test/playcode_web/live/admin/play_performances_live_test.exs`

**Interfaces:**
- Consumes: Task 2's `put_cast/2`, `find_or_create_actor/1`, `update_company/2`, `update_actor/2`, `usage/1`.
- Produces: form fields `performance[cast][N][actor_name|surname|forename|nickname|sex|role]`; events `add_cast`, `remove_cast` (`%{"index"}`), `rename_company`, `rename_actor` (`%{"id"}`), `save_rename`.

- [ ] **Step 1: Write the failing tests**
- `"the cast is added, ordered and removed in the form"` — two rows, one an existing actor by name, one new (surname, forename, nickname, sex); saved in order; one removed.
- `"Rename corrects a company for every performance, and says how many"` — the rename form shows `"40 performances in 12 plays"`-shaped text from `usage/1` (here `"2 performances in 2 plays"`); after saving, the other play's performance shows the new name.
- `"Rename corrects an actor's four fields"` — "Hart, Charles Hart" → forename "Charles"; the line shows "Charles Hart".
- **Review Focus 1:** `"a rename onto a taken name is refused"` — the message on the field, both companies unchanged, the page still answers events.

- [ ] **Step 2: Run, watch them fail.**

- [ ] **Step 3: Implement.** The cast rows as `inputs_for`-style indexed fields held in the form params (no DB writes until save); save runs `update_performance/2` and `put_cast/2` in one `Repo.transaction`. "Rename" opens a small form beside the chosen company or actor; its ids from the browser are re-read (`Performances.get_company/1` and `get_actor/1`, nil → gone flash). Help text under the company field: `gettext("Rename corrects the company for every performance that names it.")`.

- [ ] **Step 4: Run, watch them pass**, accessibility included.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Gettext, whole suite, format, compile, commit** — `feat(admin): a performance's cast, and renaming a company or actor for every performance`

---

### Task 7: The source in the form

**Files:**
- Create: `lib/playcode_web/live/admin/entry_fields.ex` (`entry_fields/1`, the entry inputs now inline in `play_bibliography_live.ex:390-470`)
- Modify: `lib/playcode_web/live/admin/play_bibliography_live.ex` (uses the component), `lib/playcode_web/live/admin/play_performances_live.ex`
- Test: `test/playcode_web/live/admin/play_performances_live_test.exs`, `test/playcode_web/live/admin/play_bibliography_live_test.exs` (stays green, unchanged)

**Interfaces:**
- Consumes: Task 3's `search_entries(…, kinds: :all)`, `get_entry/1`, `plays_for_entry/1`.
- Produces: `PlaycodeWeb.Admin.EntryFields.entry_fields(assigns)` with `attr :form, Phoenix.HTML.Form, required: true` and `attr :kinds, :list, default: Entry.kinds()`; events `search_source` (`%{"term"}`), `pick_source` (`%{"entry"}`), `new_source`, `edit_source`, `save_source`, `clear_source`.

- [ ] **Step 1: Write the failing tests**
- `"a source is found among every entry, catalogues included, and cited with its own pages"` — a catalogue entry "British Drama 1533–1642"; search "Wiggins", pick, volume 6, pages 83; the line shows `"[1] vol. 6, p. 83"`.
- `"a new source is entered in the form"` — `new_source`, the entry fields (kind select offering `catalogue` here), save: the entry exists and is cited, and is in no play's bibliography (`Bibliography.list_for_play/1 == []`).
- `"Edit source corrects the entry for every play, after the warning"` — a source cited by two plays' performances: the warning names both codes; after saving, the other play's page prints the new title.
- `"a source that is gone says so"` — `pick_source` with a malformed id: the gone flash.

- [ ] **Step 2: Run, watch them fail.**

- [ ] **Step 3: Implement.** Extract the entry inputs into `entry_fields/1` first, with `play_bibliography_live_test.exs` green before and after (a refactor under its own tests). The Performances tab's source picker: the search list, "New source", and beside a chosen one "Edit source"; the warning is the Bibliography tab's `role="alert"` block, fed by `plays_for_entry/1` minus this play. A new or edited source passes `kinds: Entry.kinds() ++ ["catalogue"]`.

- [ ] **Step 4: Run, watch them pass**, accessibility included.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Gettext, whole suite, format, compile, commit** — `feat(admin): a performance's source, picked, entered or corrected in the form`

---

### Task 8: The TEI file carries the performances

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`build_front/4`, `build_places/1`, the elenco `castList`; `build_bibl_struct/1` reused), `lib/playcode/import/tei_parser.ex` (`performances:` in the parsed map and the doc at line 15; `front/1`), `lib/playcode/import/tei_import.ex` (`write_performances/2`; `:performances` in the replaced and preserved counts at lines 118–162)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/complete_copy_test.exs`, `test/playcode/export/tei_validator_test.exs`, `test/playcode/import/tei_import_test.exs`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: the encoding, after the cast list and the scene, in the list's order:

```xml
<performance xml:id="performance-1" corresp="#castlist">          <!-- corresp only with the switch -->
  <p>
    <date when="1610">1610</date>                                <!-- or notBefore/notAfter; text as written -->
    <rs type="venue" subtype="commercial_theatre">Globe or Blackfriars</rs>  <!-- empty rs when only a type -->
    <placeName ref="#londres"><country ref="#reino-de-inglaterra"/></placeName>  <!-- as S9b's setting -->
    <orgName>The King’s Men</orgName>
  </p>
  <castList>
    <castItem><role>Argan</role><actor sex="M"><persName><forename>Jean François</forename>
      <surname>Poquelin</surname><addName type="nickname">Molière</addName></persName></actor></castItem>
  </castList>
  <note>The play was reportedly hissed occasionally.</note>
  <biblStruct>… as the bibliography writes it, with
    <citedRange unit="volume">6</citedRange><citedRange unit="page">83</citedRange></biblStruct>
</performance>
```

The elenco's `<castList>` gets `xml:id="castlist"` only when a performance points at it. `sex`: `"M"` man, `"F"` woman, absent otherwise. If the slow schema check refuses any of this, change the encoding here, in both halves, and say so in the commit.

- [ ] **Step 1: Write the failing tests**

`tei_roundtrip_test.exs`, describe `"performances"` (slugs `rt-perf-…`):
- `"a performance comes back with every field"` — import a file with the XML above; `Performances.list_for_play/1` has the date as written and its years, the venue and its type, the company, the place and its state, the note, the cast row with its four actor fields and role, the source entry with volume 6 and page 83; `roundtrip/1` gives the same XML elements (`xml_elements(xml, "performance")`, `xml_texts(xml, "orgName", within: "performance")`).
- `"a company, an actor and a source already in Playcode are reused, not copied"`.
- `"the cast-list switch comes back"` — `corresp="#castlist"`; the play's `castList` has `xml:id="castlist"`.
- `"a source cited by a performance stays out of the play's bibliography"` — after import, `Bibliography.list_for_play/1 == []`.
- **Review Focus 2:** `"a re-import replaces the file's performances and keeps the others"` — a play with a `filemaker` and a `manual` performance; import a file with one performance identical to the `manual` one and another new: three performances after, the identical one skipped, origins `filemaker`, `manual`, `tei`; import a file with none: the `tei` one is gone, the other two stay.

`tei_import_test.exs`: `preview_import/1` reports `performances` among replaced and preserved, as it does for witnesses.

`complete_copy_test.exs`: take `play_performances` out of `kept_out`; the ordinary play gets one performance; the rarer one every column (a place with a state, a source with volume and pages, a company, a cast row with nickname and sex, the switch on a character with an actor). `snapshot/1` reads `Performances.list_for_play/1` with cast, company and actor fields, the source as its `Entry.description/1`; `filemaker_id` and `source_entry_id`, `company_id`, `actor_id`, `performance_id` join `@dropped` with the reason (ids the file does not carry; the rows they name are compared by value).

`tei_validator_test.exs`: a shape `{"performances", &performances/0}` exporting the rarer play's performances.

- [ ] **Step 2: Run, watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/complete_copy_test.exs test/playcode/import/tei_import_test.exs` and `mix test --include slow test/playcode/export/tei_validator_test.exs`

- [ ] **Step 3: Implement.** `TeiXml.generate/2` loads `Performances.list_for_play/1`; `build_places/1` takes the performances' places and states into the `listPlace`; the source through `build_bibl_struct(%{entry: source, volume: source_volume, pages: source_pages})`. `TeiParser` reads each `front/performance` into `%{date_text, year_from, year_to, venue, venue_type, place, state, company, note, cast: [%{role, surname, forename, nickname, sex}], source: description | nil, source_volume, source_pages, cast_from_cast_list}`, the `biblStruct` through the bibliography reader's own function. `TeiImport.write_performances/2` runs after places and characters: delete the play's `tei` performances, then for each parsed one skip it when identical to one the play keeps (every field the listing prints), else resolve place and state by slug as `write_settings/2` does, company and actor by `find_or_create_*`, source through `Bibliography.identical_entries/2` or a new entry, and create it with origin `"tei"`. The `tei` performances are deleted through `Performances.delete_performance/1`, so the companies, actors and entries they leave unused go too.

- [ ] **Step 4: Run, watch them pass**, the slow validator included.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit** — `feat(tei): a play's performances are written in the file and read back`

---

### Task 9: S9b's place rules, for any FileMaker link

A refactor under `test/playcode/import/places_test.exs` and the `playcode.import.places` tests, which must stay green unchanged.

**Files:**
- Modify: `lib/playcode/import/places.ex`

**Interfaces:**
- Produces:

```elixir
# rows: T10_ObraAccionLugar rows of any owner (a version's or a performance's)
Import.Places.place_plan(data, rows) ::
  %{places: [planned_place], resolved: %{ref => {place_key, state_key | nil}},
    skipped: %{no_place: [label], empty: [label], nameless: [label]}}
#   ref: "T10:<_kp_IdObraAccionLugar>"; planned_place as plan/2's plan.places today
Import.Places.apply_places(places :: [planned_place]) :: %{key => place_id :: binary}
```

`plan/2` calls `place_plan/2` with the version links; `apply_plan/2` calls `apply_places/1`. `Import.Places.load/1` already reads every T10 table.

- [ ] **Step 1:** Run `mix test test/playcode/import/places_test.exs test/mix/tasks_test.exs` — green, the baseline.
- [ ] **Step 2: Write the failing test** — `"the place rules resolve a performance's link like a play's"`: the fixture's rows reduced to one version link; `place_plan(data, rows)` resolves its ref to the same `{place, state}` keys `plan/2` gives that link.
- [ ] **Step 3: Implement** by moving code, not copying it.
- [ ] **Step 4:** Both commands green.
- [ ] **Step 5: Refactor while green.**
- [ ] **Step 6: Whole suite, format, compile, commit** — `refactor(import): S9b's place rules serve any FileMaker link`

---

### Task 10: The import plan

**Files:**
- Create: `lib/playcode/import/performances.ex`, `test/fixtures/filemaker/performances/regenerate.exs` and the cut tables beside it, `test/playcode/import/performances_test.exs`

**Interfaces:**
- Consumes: `FilemakerXml.read/1`, `Import.Places.place_plan/2`, `Import.Bibliography.lookups/1` and the `T13` record reading (move S4's `record_attrs/2` pieces into a shared function if `T13`'s field names differ only by prefix: `FueInf_` against `BibSel_`), `Bibliography.identical_entries/2`.
- Produces:

```elixir
@spec load(dir) :: {:ok, data} | {:error, {file, reason}}
# files: performances "T11_ObraRepresentacion.xml", cast "T11.1_ActorRepresentacion.xml",
#   actors "T11.11_ActorNombre.xml", sexes "T11.12_ActorSexo.tab", roles "T11.22_ActorRol.xml",
#   companies "T11.3_CompaniaNombre.xml", sources "T13_FuenteInformacion.xml",
#   cities "T13.1_Ciudad.xml", publishers "T13.2_Editorial.xml", source_types "T13.3_FuenteInfoTipo.xml",
#   and Import.Places's T10 files
@spec plan(data, plays) :: plan
# plan.performances: [%{play_id, code, ref: "T11:<id>", attrs: %{"date_text" ...}, company: name | nil,
#   cast: [%{actor: %{"surname", "forename", "nickname", "sex"}, role}], place: key | nil,
#   state: key | nil, source: work_key | nil, source_volume, source_pages, cast_from_cast_list}]
# plan.places (from place_plan/2); plan.works: %{work_key => %{attrs: entry attrs, existing: "T04:116" | nil,
#   records: [id]}}; plan.skipped: %{undated: [label], cast: [label], source: [label]};
#   plan.not_held, plan.already_imported, plan.merged_companies, plan.merged_actors
@spec report(plan) :: [String.t()]
```

- [ ] **Step 1: Cut the fixture** — `regenerate.exs` in the style of `test/fixtures/filemaker/places/regenerate.exs`: keep the `T11` rows of versions `10 304 313 379 491 671 675 714` plus one version we hold citing record `105`, one with a performance of company 52 (the Duke's Company twin) and one we do not hold; then the cast, actors, roles, companies, sources (with `81 97 98`), cities, publishers and the T10 rows (`_k_IdObraRepresentacion` among the kept) with the toponym tables they reach, closed over parents as S9b's cut does. Run: `mix run --no-start test/fixtures/filemaker/performances/regenerate.exs`. Its header comment names the row behind each test below.

- [ ] **Step 2: Write the failing tests** (`use Playcode.DataCase, async: true`, plays created for each kept version, `T04:116`, `T04:385`, `T04:418` entries created with `entry_fixture`):

```elixir
test "a performance's fields, as FileMaker wrote them"
  # EMOTHE0304's 1610 row: date "1610", venue "Globe or Blackfriars", venue_type
  # "commercial_theatre", company "The King’s Men", note "The play was reportedly hissed occasionally."
test "Wiggins's records are one work, each performance with its volume and page"
  # every 0304 performance's source is the same work key; one has volume "6" pages "83";
  # a record with "Volume 5: 1603-1608" in its title gives volume "5"
test "CATCOM's two records are one work, and its credit leaves the venue for the citation"
  # 0379 (performance 164): venue == "Casa de comedias de Toledo"; the CATCOM work's attrs
  # public_note == "Copyright © DICAT Grupo de investigación teatral bajo Licencia Creative Commons BY-NC-ND."
test "a source that is an edition S4 brought in cites that entry"  # record 97 → existing "T04:116"
test "a record that is its own work keeps its pages"  # Child's chapter (39): pages "lxix-xcvii", kind "criticism"
test "record 479 is named, record 105 is reported"
test "FileMaker's twin companies and actors are one"  # plan.merged_companies has "The Duke’s Company"
test "the cast, its actors and roles, the picker leftovers skipped"
  # 0714's 1673 row: [{"Poquelin", "Jean François", "Molière", "man", "Argan"}, …];
  # skipped.cast has performance 358's leftover
test "a performance's place comes from T10, with its state"  # 0671's Nápoles: state Reino de Nápoles
test "The Way of the World's 1700 performance takes its cast from the cast list"  # ref "T11:145"
test "a version we do not hold is counted; a play already imported is skipped whole"
test "the report says what it would write and what it left out"
  # report(plan) contains "EMOTHE0304", "Globe or Blackfriars · The King’s Men · commercial theatre [Wiggins 6, 83]"
```

- [ ] **Step 3: Implement** the spec's *The import*, *From FileMaker rows to performances* and *From FileMaker source records to entries*. The hand list as module attributes at the top, one comment each, in `Import.Places`'s style:

```elixir
# T13 records of one work, by work; the work's entry as the project cites it.
@works %{
  wiggins: %{records: ~w(…every Wiggins record, from the dry run…), kind: "catalogue", attrs: %{…}},
  catcom: %{records: ~w(119 468), kind: "catalogue", attrs: %{…, public_note: "Copyright © DICAT …"}},
  restoration_comedy_1671: %{records: ~w(…the 7…), kind: "catalogue", attrs: %{…}}
}
@catalogues ~w(…London Stage Database, Harbage's Annals, Gómez-Lara…)   # lone records of kind catalogue
@existing %{"97" => "T04:116", "98" => "T04:385", "81" => "T04:418"}
@named %{"479" => %{monogr_title: "data.bnf.fr", kind: "catalogue"}}
@cast_list_performance "145"
```

The Wiggins and Mora Sena record lists start with the fixture's ids; Task 12 completes them from the dry run.

- [ ] **Step 4: Run, watch them pass.** `mix test test/playcode/import/performances_test.exs`

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git add lib/playcode/import/performances.ex test/fixtures/filemaker/performances test/playcode/import/performances_test.exs
git commit -m "feat(import): FileMaker's performances, casts and sources planned for the plays we hold"
```

---

### Task 11: Writing the plan: `apply_plan/2`, the mix task, the release

**Files:**
- Modify: `lib/playcode/import/performances.ex` (`apply_plan/2`), `lib/playcode/release.ex` (`import_performances/2`)
- Create: `lib/mix/tasks/playcode.import.performances.ex`
- Test: `test/mix/tasks_test.exs` (describe `"playcode.import.performances"`, beside `"playcode.import.places"` at line 517)

**Interfaces:**
- Produces: `apply_plan(plan, opts \\ []) :: {:ok, %{performances: n, companies: n, actors: n, entries: n, places: n}}`; `mix playcode.import.performances [--dry-run] [--path DIR]`; `Playcode.Release.import_performances(dir, opts \\ [])`.

- [ ] **Step 1: Write the failing tests**, in the style of the places tests, with `@performances "test/fixtures/filemaker/performances"`:

```elixir
test "a dry run prints the plan and writes nothing"
test "writes the performances as readers will see them"
  # The Alchemist's listing/4 (locale "en"): first line parts ["Globe or Blackfriars", "The King’s Men",
  # "commercial theatre"], range "vol. 6, p. 83"; every origin "filemaker"; one "import" log row per play
test "a second run changes nothing"            # out =~ "already imported"
test "performances a curator deleted stay deleted"
test "a play's own performances stay, FileMaker's go after them"
```

- [ ] **Step 2: Run, watch them fail.** `mix test test/mix/tasks_test.exs`

- [ ] **Step 3: Implement.** One `Repo.transaction(…, timeout: :infinity)`: `Import.Places.apply_places/1`; the works' entries (an `existing` one looked up by `filemaker_id`; else `identical_entries/2`; else inserted with `filemaker_id` `"T13:<first record>"`); companies and actors by `find_or_create_*`; each performance by `create_performance/2` on a `%Performance{filemaker_id: ref, origin: "filemaker"}` base, then `put_cast/2`; the activity-log row per play. The task and the release copy `playcode.import.places` and `import_places/2`.

- [ ] **Step 4: Run, watch them pass.**

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit** — `feat(import): mix playcode.import.performances writes FileMaker's performances`

---

### Task 12: The paperwork, and the real tables

- [ ] **Step 1: Paperwork.** `CLAUDE.md` (*Database Schema*: the four tables; *TEI-XML Format*: a `front/performance` line; *Getting Started*: the import beside S9b's), `CONTEXT.md` (*Performance*, *Company*, *Venue*, the spec's wording), `docs/stakeholder/ida-y-vuelta.html` (the row: admin, TEI export, TEI import, play page, site yes; HTML/PDF/EPUB no), `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md` (S5 points at the spec), `docs/backlog.md` (the "New FileMaker slices go into the TEI from the start" item loses S5; new items: the performance search with pages for companies and actors and merging; venues as gazetteer places; the witnesses' `T13` sources). `git diff` the docs first (Global Constraints). Commit — `docs: S5's tables, mapping, command, glossary words and round-trip row`.
- [ ] **Step 2:** `mix playcode.import.performances --dry-run > <scratchpad>/s5-dry-run.txt` against `playcode_dev` (S9b's places already imported there), and read it: every T13 record on a held play must be in a work, a lone record, `@existing` or `@named`; the twins merged must be the same company or actor; the undated list and the skipped lists must hold only what the spec expects; the counts must match the spec's (244 performances on 60 plays, 188 sourced, 49 placed, 41 cast rows less the 2 leftovers).
- [ ] **Step 3:** For each correction: the FileMaker rows into the fixture (`regenerate.exs`), a failing test, the hand-list entry, green, refactor, commit (`fix(import): …`).
- [ ] **Step 4:** Run it: `mix playcode.import.performances`; open `/plays/EMOTHE0304`, `/plays/EMOTHE0313` and `/admin/plays/:id/performances` for one of them; Generate one play on `/admin/export` and read its Performances section.
- [ ] **Step 5:** Report to the owner: the dry run's summary and anything accepted rather than fixed. Production waits for the owner: deploy, `Playcode.Release.import_performances/2` with `dry_run: true`, then without, then Generate. Once production has it, S5 moves from `docs/backlog.md` to `docs/history.md`.
