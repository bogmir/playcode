# S9b — Places from FileMaker, and historical states — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the plays we hold FileMaker's places of action, once, and let a play–place link name the historical state the place belonged to in that play.

**Architecture:** One nullable column, `play_places.historical_state_id`, carries the historical state on the link; the gazetteer stays today's geography. `Places.place_line/3` prints a link for readers ("Roma, República romana, Europa (hoy Italia)"); the TEI export nests the state in the link's `<placeName>` and the import reads it back. `Playcode.Import.Places` is S3's shape (`load/1`, `plan/2`, `apply_plan/2`, `report/1`) over the `T10*` tables, resolving FileMaker's per-context copies into one place per real place.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Ecto + PostgreSQL triggers, Saxy, xml_builder.

**Spec:** `docs/superpowers/specs/2026-10-19-s9b-places-import-design.md` — read it first; this plan argues from it and does not repeat its reasons.

## Global Constraints

- TDD, CLAUDE.md's loop: failing test, see it fail, smallest code, see it pass, **refactor while green** (Saša Jurić's clear code: names, no duplication, the helper the code already has, the surrounding idiom), then `mix test` (whole suite), `mix format`, `mix compile --warnings-as-errors`, commit.
- Test through the outermost API (CLAUDE.md, *Test behaviour through the outermost API*): LiveViews with `live/2`, the mix task with `Mix.Task.rerun/2`, the importer's rules through `plan/2` (as `witnesses_test.exs` does), read back through `Playcode.Places`, never `Repo`.
- **Prove a new test bites** where it covers code that already works: break the line, watch red, restore, say so in the commit.
- Places in async tests: `place_fixture/1` derives a unique slug; pass `"slug"` only when asserting on it, with a per-file prefix (`rt-hs-…`). Two async tests creating the same slug deadlock.
- An id from the browser is resolved with a scoped getter (`Places.get_play_place/2`, `Places.get_place/1`); nil → reload and `LiveHelpers.put_gone_flash/1`.
- New gettext strings: `mix gettext.extract --merge`, then check every entry it marks fuzzy; give the Spanish.
- No new dependencies. FileMaker never creates plays and never touches `AL####`.
- Activity log: `action: "import"`, `resource_type: "play_place"`, `metadata: %{"source" => "filemaker"}` (the allowed actions are `create update delete import export role_change`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work on branch `s9b-places-import`.
- `docs/backlog.md` and `docs/stakeholder/preguntas.html` carried the owner's own uncommitted edits when this plan was written. Before staging either, run `git diff` on it; if edits that are not yours are there, ask the owner before committing them.

## Review Focus

1. **A curator deletes a place some link names as its historical state** → refused with a message on `/admin/places`, never a crash. Test in Task 1.
2. **A TEI re-import of a file without the state** (every production file) on a play whose `tei` link had one → the state is cleared, because the file is the truth for `tei` links; a `filemaker` link is left untouched. Test in Task 4.
3. **A historical state with no name in the page's locale** (Illyria has English only; the site asks for `"es"`) → the line prints the name it has, never an empty slot or a stray comma. Test in Task 2.
4. **A curator removes FileMaker's links from a play, then the import runs again** → the play is skipped; nothing comes back. Test in Task 7.
5. **A state id from the browser that is malformed or deleted** → the row is not saved and the gone flash shows. Test in Task 3.

---

### Task 1: The historical state on the link

**Files:**
- Create: `priv/repo/migrations/20261019120000_add_historical_state_to_play_places.exs`
- Modify: `lib/playcode/places/play_place.ex`, `lib/playcode/places/place.ex`, `lib/playcode/places.ex` (`delete_place/1`, `with_play_counts/1`), `lib/playcode_web/live/admin/place_list_live.ex:71` (the delete error)
- Test: `test/playcode/places_test.exs`, `test/playcode/content_version_test.exs`, `test/playcode_web/live/admin/place_list_live_test.exs`

**Interfaces:**
- Produces: `PlayPlace` field `historical_state_id` (`belongs_to :historical_state, Place`), cast by `PlayPlace.changeset/2` and so by `Places.link_place/3` and `Places.update_play_place/2` under the string key `"historical_state_id"`; `Place` gets `has_many :state_links, PlayPlace, foreign_key: :historical_state_id`.

- [ ] **Step 1: Write the failing tests**

In `places_test.exs`, describe `"historical state"`:
- `"a link may name the historical state its place belonged to"` — `link_place(play.id, roma.id, %{"historical_state_id" => republica.id})`, then `[link] = Places.list_play_places(play.id)` and `link.historical_state_id == republica.id`.
- `"a place cannot be its own historical state"` — `{:error, changeset}`; `errors_on(changeset).historical_state_id == ["cannot be the place itself"]`.
- `"a state in use cannot be deleted"` — `{:error, changeset} = Places.delete_place(republica)`; `errors_on(changeset).state_links == ["is the historical state of a play's place"]`.
- `"the play count counts the links naming a place as their state"` — one play links Roma with state República romana, another links Castilla itself; `Places.list_places()` gives República romana `play_count: 1`.

In `content_version_test.exs`, beside `"an edit to a place moves every play set there or anywhere inside it"` (line 142), `"an edit to a historical state moves every play whose places it names"`: rename the state's name through `Places.update_place/2`; the play linking Roma with that state moves, a play elsewhere does not. Copy that test's shape.

In `place_list_live_test.exs`, `"deleting a place a link names as its state says why"`: the page shows the message, the place stays.

- [ ] **Step 2: Run them, watch them fail**

Run: `mix test test/playcode/places_test.exs test/playcode/content_version_test.exs test/playcode_web/live/admin/place_list_live_test.exs`
Expected: FAIL (unknown field `historical_state_id`).

- [ ] **Step 3: Implement**

- Migration `up`: `alter table(:play_places)` add `historical_state_id` `references(:places, type: :binary_id, on_delete: :restrict)`, nullable; `create index(:play_places, [:historical_state_id])`; `CREATE OR REPLACE FUNCTION place_changed()` with the body of `20261005120000_track_play_content_version.exs:108-125`, its `WHERE place_id IN (tree)` becoming `WHERE place_id IN (tree) OR historical_state_id IN (tree)` (one CTE, both columns). `down`: the original function, then remove the column. The moduledoc says why: a state's names are printed in the play's line.
- `PlayPlace.changeset/2`: cast `:historical_state_id`; `foreign_key_constraint(:historical_state_id)`; error `"cannot be the place itself"` when it equals `place_id`.
- `Places.delete_place/1`: `no_assoc_constraint(:state_links, message: "is the historical state of a play's place")`.
- `with_play_counts/1`: a link counts for its place and for its state.
- `PlaceListLive`: the delete error reads `changeset.errors[:state_links]` beside `[:play_places]`.

- [ ] **Step 4: Run them, watch them pass**

Run: `mix test test/playcode/places_test.exs test/playcode/content_version_test.exs test/playcode_web/live/admin/place_list_live_test.exs` (the `test` alias migrates the test database).
Expected: PASS. Prove the trigger test bites: take `OR historical_state_id IN (tree)` out of the migration, `MIX_ENV=test mix ecto.rollback`, run the content-version test, see red, restore, roll back and run again.

- [ ] **Step 5: Refactor while green**, re-running the three files after each change.

- [ ] **Step 6: Whole suite, format, compile, commit**

Run: `mix test 2>&1 | tail -5 && mix format && mix compile --warnings-as-errors`
```bash
git add priv/repo/migrations/20261019120000_add_historical_state_to_play_places.exs lib/playcode/places lib/playcode/places.ex lib/playcode_web/live/admin/place_list_live.ex test
git commit -m "feat(places): a play's link names the historical state of its place"
```

---

### Task 2: The line readers see

**Files:**
- Modify: `lib/playcode/places.ex` (new `place_line/3`), `lib/playcode_web/live/play_show_live.ex:445`, `lib/playcode/export/static_site/components.ex:302-310`, `lib/playcode_web/live/admin/play_places_live.ex:330` (the row's breadcrumb)
- Test: `test/playcode/places_test.exs`, `test/playcode_web/live/play_show_live_test.exs` (describe `"the places panel"`), `test/playcode/export/static_site_test.exs`

**Interfaces:**
- Consumes: Task 1's `historical_state_id`.
- Produces: `Places.place_line(%PlayPlace{} = link, gazetteer :: %{binary => Place.t()}, locale :: String.t()) :: String.t()`. `link.place` is preloaded (as every caller has it); the state is read from the gazetteer by `link.historical_state_id`, so no caller preloads it.

- [ ] **Step 1: Write the failing tests**

`places_test.exs`, describe `"place_line/3"`, each building its gazetteer with `place_fixture/1` and `Places.gazetteer()`:

```elixir
test "a link with no state prints the breadcrumb" # "Ardenas, Francia, Europa"
test "the place's historical name, the state, the state's ancestors, then today's names that differ"
  # Helsingør: es "Elsinor" preferred; en "Helsingør" preferred, en "Elsinore" historical;
  # parent Dinamarca (en Denmark) under Europa (en Europe); state Reino de Dinamarca
  # (en Kingdom of Denmark) under Europa.
  assert Places.place_line(link, g, "es") == "Elsinor, Reino de Dinamarca, Europa (hoy Dinamarca)"
  assert Places.place_line(link, g, "en") ==
           "Elsinore, Kingdom of Denmark, Europe (today Helsingør, Denmark)"
test "no brackets when today's names are all printed already"
  # "Chipre, República de Venecia, Europa": Chipre's parent is Europa
test "a state with no continent leaves today's continent in the brackets"
  # "Jerusalén, República romana (hoy Israel, Asia)"
test "a state with no name in the locale prints the name it has"
  # state Illyria (en only), place under Europa: Places.place_line(link, g, "es") ==
  # "Ragusa, Illyria, Europa (hoy Croacia)" — no empty slot, no ", ,"
```

`play_show_live_test.exs`, describe `"the places panel"`: `"a place's historical state is printed, today's names in brackets"` — Roma under Italia under Europa, state República romana under Europa; `render(element(view, "#meta-places")) =~ "Roma, República romana, Europa (hoy Italia)"`.

`static_site_test.exs`, beside `"a play page carries its places…"` (line 337): `"a place's historical state is printed in the names' language, whatever the page's"` — generate under `Gettext.with_locale(PlaycodeWeb.Gettext, "en", …)`; the page holds `"Madrid, Castilla, Europa (hoy España)"` and not `"today"`.

- [ ] **Step 2: Run them, watch them fail**

Run: `mix test test/playcode/places_test.exs test/playcode_web/live/play_show_live_test.exs test/playcode/export/static_site_test.exs`
Expected: FAIL (`place_line/3` undefined; the pages print the breadcrumb).

- [ ] **Step 3: Implement `Places.place_line/3`, and call it from the three pages**

The spec's *What readers see* is the rule: no state → `breadcrumb/3`; else the place's historical name in `locale` (first `is_historical` name of that language, by position) or `display_name/2`, then the state and its ancestors (`ancestors/2`, outermost last) by `display_name/2`; brackets hold the place's breadcrumb names minus every name already printed, joined by `", "`, after `@today[locale]` (`%{"es" => "hoy", "en" => "today"}`, falling back to `"hoy"`). Replace the breadcrumb call in `PlayShowLive` (`@locale`), `StaticSite.Components.place_links/1` (`"es"`) and the admin row (`"es"`). `Playcode.Places` is already in `StaticSite.Fingerprint`.

- [ ] **Step 4: Run them, watch them pass**

Same command. Expected: PASS.

- [ ] **Step 5: Refactor while green** — `breadcrumb/3` and the brackets share the place's chain of names; one private helper, not two walks.

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git commit -am "feat(places): readers see a place's historical state, today's names in brackets"
```

---

### Task 3: The Places tab sets a link's historical state

**Files:**
- Modify: `lib/playcode_web/live/admin/play_places_live.ex` (`update_link` handler, the row's form, `load_links/1`), `priv/gettext/default.pot`, `priv/gettext/{es,en}/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_places_live_test.exs`

**Interfaces:**
- Consumes: Task 1's column; Task 2's `Places.place_line/3` for the row.
- Produces: the row's form field `play_place[historical_state_id]` (`""` clears it).

- [ ] **Step 1: Write the failing tests**

- `"a link's historical state is chosen, then cleared, on its row"` — a country `"Castilla"` exists; submit `#link-form-#{link.id}` with `%{"play_place" => %{"role" => "setting", "historical_state_id" => castilla.id}}`; the row shows `"Madrid, Castilla, Europa"`; `hd(Places.list_play_places(play.id)).historical_state_id == castilla.id`; submit `""`; it is nil.
- `"only countries and regions are offered as a state"` — the select (labelled `t("Historical state")`) offers Castilla (country) and Península itálica (region), not Madrid (city).
- `"a state that is gone says so instead of saving"` — submit a deleted place's id, then `"not-a-uuid"`: the gone flash (`LiveHelpers.put_gone_flash/1`'s text), the link unchanged.

- [ ] **Step 2: Run, watch them fail**

Run: `mix test test/playcode_web/live/admin/play_places_live_test.exs`

- [ ] **Step 3: Implement**

The row's form gains a `<select name="play_place[historical_state_id]">` labelled "Historical state" (`aria-label` or a `<label for>`; `accessibility_test.exs` renders this tab), a blank option first, then `Places.list_places()` filtered to types `country` and `region`, by `display_name(&1, "es")`, assigned once in `load_links/1` as `@states`. In `update_link`: `""` → `nil`; any other value through `Places.get_place/1` → nil means `load_links |> LiveHelpers.put_gone_flash()` and no save.

- [ ] **Step 4: Run, watch them pass**; then `mix test test/playcode_web/accessibility_test.exs`.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Gettext, whole suite, format, compile, commit**

`mix gettext.extract --merge`; Spanish "Historical state" → "Estado histórico"; check every fuzzy entry. Then the suite, format, compile.
```bash
git commit -am "feat(admin): the Places tab sets a link's historical state"
```

---

### Task 4: The TEI file carries the historical state

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`build_places/1`, `build_setting_ref/1`), `lib/playcode/import/tei_parser.ex` (`setting_links/1`, the `settings:` doc at line 15), `lib/playcode/import/tei_import.ex` (`write_settings/2`)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/complete_copy_test.exs`, `test/playcode/export/tei_validator_test.exs`

**Interfaces:**
- Consumes: Task 1's column.
- Produces: `TeiParser`'s settings entries gain `state: String.t() | nil` (the slug of the `<country ref>` or nested `<placeName ref>`).

- [ ] **Step 1: Write the failing tests**

`tei_roundtrip_test.exs`, describe `"the historical state of a place"` (slugs prefixed `rt-hs-`):
- `"a country comes back inside the link's placeName, and the state in listPlace"` — a `listPlace` with `rt-hs-europa` > `rt-hs-italia` > `rt-hs-roma` and `rt-hs-republica-romana` (type `country`) under `rt-hs-europa`; `<setting><placeName ref="#rt-hs-roma" ana="setting"><country ref="#rt-hs-republica-romana"/><note>Acto I.</note></placeName></setting>`. After `roundtrip/1`: `xml_elements(xml, "country", within: "setting") == [{%{"ref" => "#rt-hs-republica-romana"}, ""}]`, the note still there, and `rt-hs-republica-romana` a `place` in `listPlace`.
- `"a state that is not a country is a nested placeName"` — a `region` state comes back as `<placeName ref="#…"/>` inside the link's.
- `"a file without the state clears it from the file's own links, never from a curator's"` — import the file above; import it again without the `<country>`: the `tei` link's state is nil. A `manual` link with a state on another play keeps it through that play's import.

`complete_copy_test.exs`: in `places!/1` give the link `"historical_state_id"` of a new `place_fixture(%{"name" => "República de Venecia", "type" => "country"})`; add `historical_state_id` to `@dropped`; in `snapshot/1`, `Map.put(:historical_state, …)` with the state's `place/1` and ancestors, as the link's place has. It fails until export and import carry it.

`tei_validator_test.exs`: a shape `{"places with a historical state", &historical_state/0}` — a play with Roma (state República romana, a country) and Verona (state Península itálica, a region), exported.

- [ ] **Step 2: Run, watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/complete_copy_test.exs` (and `mix test --include slow test/playcode/export/tei_validator_test.exs`, about a minute)

- [ ] **Step 3: Implement**

- `build_places/1`: the places the play needs are each link's place **and** its state (from the gazetteer), with their ancestors.
- `build_setting_ref/2` (gazetteer passed in): children are the state, then the note; the state is `element(:country, %{ref: "#" <> slug})` for type `country`, else `element(:placeName, %{ref: "#" <> slug})`.
- `setting_links/1`: `state:` the `ref` of the first `country` or `placeName` child, `#` trimmed, else nil.
- `write_settings/2`: resolve `setting.state` by slug like the place (unknown → `Logger.warning` and nil); always pass `"historical_state_id"`, nil included, so a `tei` link is refreshed.

- [ ] **Step 4: Run, watch them pass**, the slow validator included.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git commit -am "feat(tei): a place's historical state is written in the file and read back"
```

---

### Task 5: The import plan — from FileMaker's records to places

**Files:**
- Create: `lib/playcode/import/places.ex`, `test/fixtures/filemaker/places/regenerate.exs`, the eight cut tables beside it, `test/playcode/import/places_test.exs`

**Interfaces:**
- Consumes: `Playcode.Import.FilemakerXml.read/1`, `Playcode.Catalogue.Play.short_code/1`, `Places.find_by_name/1`.
- Produces (Tasks 6 and 7 rely on these):

```elixir
@spec default_dir() :: String.t()                       # "doc/ctce_dades"
@spec load(dir) :: {:ok, data} | {:error, {file :: String.t(), reason :: term}}
# data: %{links:, names:, pairs:, continents:, countries:, regions:, cities:, vague:}, each [row]
@spec plan(data, plays :: [Play.t()]) :: plan
# key: {level :: 1..5, id :: String.t()}, FileMaker's record; 1 continent … 5 vague place
# plan.places: [%{key: key,
#                 attrs: %{"type" => String.t(), "is_fictional" => boolean,
#                          "names" => [%{"name", "language", "is_preferred", "is_historical", "position"}]},
#                 parent: key | nil,
#                 existing: Place.t() | nil}]   # parents before children
# plan.merged, plan.twinless, plan.no_country, plan.reused: [String.t()]  (report lines)
```

Files read by `load/1`: `links: "T10_ObraAccionLugar.xml"`, `names: "T10.11_NombreToponimo.xml"`, `pairs: "T10.X_TopoRelacion.xml"`, `continents: "T10.1_Continente.xml"`, `countries: "T10.2_Pais.xml"`, `regions: "T10.3_Region.xml"`, `cities: "T10.4_Ciudad.xml"`, `vague: "T10.5_Locvaga.xml"`.

- [ ] **Step 1: Cut the fixture**

`regenerate.exs` in the style of `test/fixtures/filemaker/witnesses/regenerate.exs` (rows copied byte for byte, `FOUND` rewritten): keep the `T10` links whose `_k_IdObraTitulo` is one of `5 6 7 10 38 151 153 262 337 354 367 394 545 653 697 418`; then the toponym rows, names and pairs they reach, closed over parents (a city's `_k_IdPais`, `_k_IdRegion`, `_k_IdContinente`; a region's and a country's likewise), both sides of every pair, and the hand lists' targets (Step 3). Run: `mix run --no-start test/fixtures/filemaker/places/regenerate.exs`. The header comment names one play per rule (below).

- [ ] **Step 2: Write the failing tests**

`places_test.exs`, `use Playcode.DataCase, async: true`, setup as `witnesses_test.exs` (plays `EMOTHE0005_Aminta`, `0006_PastorFido`, `0007_Calandria`, `0010_Hamlet`, `0038_AntonyAndCleopatra`, `0151_AsYouLikeIt`, `0153_RomeoAndJuliet`, `0262_ShoemakersHoliday`, `0337_Mariam`, `0354_Lacedaemon`, `0367_Endymion`, `0394_…`, `0545_LaTraicionEnLaAmistad`, `0653_…`, `0697_Othello`; 0418 has no play). A helper `es(plan, key)` gives a planned place's Spanish preferred name; `place(plan, es_name)` finds one; `parent(plan, es_name)` its parent's Spanish name.

```elixir
test "one Rome, whatever state FileMaker filed it under" # exactly one planned place named "Roma"
test "a renamed place keeps its old names as historical ones"
  # "Elsinor" (Helsingør, record 92): en "Helsingør" preferred, en "Elsinore" historical,
  # es "Elsinor" preferred and not historical; parent "Dinamarca"
test "a place inside another is not merged into it" # "Old Ford": type "district", parent "Londres"
test "a historical state is a place under its continent; one named like today's country is that country"
  # "Reino de Dinamarca" type "country" parent "Europa"; no planned place "Francia" twice;
  # "Ardenas" parent "Francia"
test "a state filed on two continents has none"  # "República romana": parent nil, planned once
test "today's geography wins over FileMaker's missing country"
  # "Verona" and "Mantua" parent "Italia"; "Esparta" parent "Grecia", historical es name "Lacedemonia"
test "vague places are typed, the generic ones fictional and shared"
  # "Ardenas" "forest"; one "bosque pastoril", "forest", is_fictional
test "a place the gazetteer has under any of its names is reused, never changed"
  # place_fixture(%{"name" => "Rome"} with language "en") before plan: the "Roma" entry has existing set
```

- [ ] **Step 3: Implement `load/1`, `plan/2`'s places half, and the hand lists**

The spec's *From FileMaker records to places* is the rule, in this order: referent (hand list, then `T10.X`; a country record merges with a twin sharing a name in any language, else it is a state, states sharing a name are one); names (languages `%{"1" => "es", "2" => "fr", "3" => "en", "4" => "it", "5" => "pt"}`, trimmed; the referent's names preferred, Spanish first, then en, fr, it, pt, alternates (`esAlternativo`) not preferred; merged records add each name whose language lacks that text, `is_historical`); parent (rule 5, a state parent replaced by its one modern twin); type (by level `continent country region city other`, then `@types`); reuse (`Places.find_by_name/1` on each name). Report lines for merges whose names differ in any language, as `"<from> → <to>"` in English or the first name there is (`"Elsinore → Helsingør"`), twinless historical records (a record is historical when its names carry `esHistorico == "1"`; continents and states are not reported) and places left with no country between them and their continent.

The hand lists, exact (the spec's values; Task 9 completes them against the real tables):

```elixir
# A historical record's modern twin where T10.X has none.
@twins %{
  {4, "113"} => {4, "92"},  # Elsinore → Helsingør
  {4, "110"} => {4, "111"}, # Santarén → Santarém
  {4, "198"} => {4, "202"}, {4, "200"} => {4, "202"}, {4, "201"} => {4, "202"}, {4, "203"} => {4, "202"} # Faversham
}

# Records that are a place of their own whatever T10.X says, with their parent.
@own %{
  {4, "152"} => {4, "70"},       # Old Ford, inside London
  {4, "132"} => :continent,      # Sardis: no modern country
  {4, "219"} => :continent,      # Carthage: no modern country
  {5, "82"} => {2, "1177"}       # Costa de Tarragona, in Spain
}

# Today's parent where FileMaker's modern record lacks the country.
@parents %{
  {4, "92"} => {2, "1168"},  # Helsingør → Dinamarca
  {4, "183"} => {2, "1198"}, # Esparta → Grecia
  {4, "159"} => {2, "1219"}, {4, "161"} => {2, "1219"}, {4, "163"} => {2, "1219"},
  {4, "170"} => {2, "1219"}, {4, "172"} => {2, "1219"}, {4, "181"} => {2, "1219"}
  # Mantua, Verona, Palermo, Florencia, Génova, Sicilia → Italia
}

@types %{
  {4, "152"} => "district", {4, "181"} => "region",
  {5, "85"} => "forest", {5, "89"} => "forest", {5, "82"} => "other", {5, "102"} => "other",
  {5, "87"} => "town", {5, "104"} => "city", {5, "91"} => "island"
}

@fictional MapSet.new([{5, "85"}, {5, "91"}]) # bosque pastoril, Una isla

@no_place MapSet.new([{5, "98"}]) # sin especificar

# A link naming only this state is a link to that place, in that state.
@state_links %{{2, "1385"} => {2, "1164"}} # Othello: Cyprus, then Venetian
```

The modern twins of 158, 160, 162, 169, 171 and 180 are assumed to be the next id (as 158 → 159 is); check each in the fixture or the dry run and correct `@parents` if not.

- [ ] **Step 4: Run, watch them pass.** `mix test test/playcode/import/places_test.exs`

- [ ] **Step 5: Refactor while green** — the referent, names and parent rules each a small named function; the hand lists at the top with one comment each, as `Witnesses`' `@types`.

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git add lib/playcode/import/places.ex test/fixtures/filemaker/places test/playcode/import/places_test.exs
git commit -m "feat(import): FileMaker's place records become one place per real place"
```

---

### Task 6: The import plan — from FileMaker's links to play links

**Files:**
- Modify: `lib/playcode/import/places.ex` (`plan/2`'s links half, `report/1`)
- Test: `test/playcode/import/places_test.exs`

**Interfaces:**
- Consumes: Task 5's `plan.places` and keys.
- Produces:

```elixir
# plan.links: [%{play_id: binary, code: String.t(), place: key, state: key | nil,
#                note: String.t() | nil, ref: String.t()}]   # ref "T10:<_kp_IdObraAccionLugar>"
# plan.skipped: %{no_place: [label], empty: [label], duplicate: [label], nameless: [label]}
#   label "EMOTHE0367 T10:1083: <FileMaker's denominacionAntigua and espacio>"
# plan.not_held: non_neg_integer
# plan.already_imported: [code]
@spec report(plan) :: [String.t()]
```

- [ ] **Step 1: Write the failing tests**

A helper `links(plan, code)` gives `[{place_es, state_es | nil}]` in plan order.

```elixir
test "each link names its place and, where FileMaker gives one, its state, in FileMaker's order" do
  assert links(plan, "EMOTHE0038_AntonyAndCleopatra") == [
           {"Roma", "República romana"}, {"Alejandría", "Egipto ptolemaico"},
           {"Atenas", "República romana"}, {"Miseno", "República romana"}]
  assert links(plan, "EMOTHE0007_Calandria") == [{"Roma", "Estados Pontificios"}]
  assert links(plan, "EMOTHE0010_Hamlet") == [{"Elsinor", "Reino de Dinamarca"}]
  assert links(plan, "EMOTHE0262_ShoemakersHoliday") ==
           [{"Old Ford", "Reino de Inglaterra"}, {"Londres", "Reino de Inglaterra"}]
end
test "a link to a whole state is a link to the state" # 0394: [{"Madrid", "Castilla"}, {"Castilla", nil}]
test "a country that is today's has no state"        # 0151: [{"Ardenas", nil}]
test "the editors' area stands in for a state"
  # 0153: [{"Mantua", "Península itálica"}, {"Verona", "Península itálica"}]
  # 0354: [{"Esparta", "Antigua Grecia"}]
test "FileMaker's free text is the note, as written"
  # 0545's note starts "Madrid, escenarios urbanos y ambiente cortesano;"
test "Othello's Venetian Cyprus is one link" # 0697: [{"Europa", nil}, {"Chipre", "República de Venecia"}, {"Venecia", "República de Venecia"}]; skipped.duplicate has "EMOTHE0697…T10:1200"
test "no place, no link" # skipped.no_place has 0367's (its Wiggins citation in the label); skipped.empty has 0653's
test "a version we do not hold is counted, not planned" # not_held == 1
test "a play the import has written to is skipped whole"
  # a filemaker play_place_fixture on Hamlet → already_imported == ["EMOTHE0010_Hamlet"], no Hamlet links
test "the report says what it would write and what it left out"
  # report(plan) contains "EMOTHE0038_AntonyAndCleopatra  Roma — República romana",
  # "Elsinore → Helsingør", and a "skipped, no_place:" line
```

- [ ] **Step 2: Run, watch them fail.**

- [ ] **Step 3: Implement** the spec's *From FileMaker links to play links*: plays by `version_code/1` against `Play.short_code/1` (copy `Witnesses`' private helper; one per importer is the codebase's idiom); place = referent of the deepest record (`@no_place` → skipped `:no_place`; none → `:empty`; a record with no names → `:nameless`); state = `@state_links`, else the link's country when it is a state and the place lies below it, else a countryless region the place's record (or the link) sits under; duplicates within a play skipped, the later note joining the first after `"\n\n"`; order by `_kp_IdObraAccionLugar`; already-imported plays as `Witnesses.imported_play_ids/0` does, `resource_type: "play_place"` and `origin == "filemaker"`. `report/1` in `Witnesses.report/1`'s style and the spec's *The report* order.

- [ ] **Step 4: Run, watch them pass.**

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git commit -am "feat(import): FileMaker's place links become the plays' links, with their states"
```

---

### Task 7: Writing the plan: `apply_plan/2`, the mix task, the release

**Files:**
- Modify: `lib/playcode/import/places.ex` (`apply_plan/2`), `lib/playcode/release.ex` (`import_places/2`)
- Create: `lib/mix/tasks/playcode.import.places.ex`
- Test: `test/mix/tasks_test.exs` (describe `"playcode.import.places"`)

**Interfaces:**
- Consumes: Tasks 5 and 6's plan.
- Produces: `apply_plan(plan, opts \\ []) :: {:ok, %{places: non_neg_integer, links: non_neg_integer}}`; `mix playcode.import.places [--dry-run] [--path DIR]`; `Playcode.Release.import_places(dir, opts \\ [])`.

- [ ] **Step 1: Write the failing tests**, in the style of `describe "playcode.import.witnesses"` (`tasks_test.exs:432`), with `@places "test/fixtures/filemaker/places"`:

```elixir
test "a dry run prints the plan and writes nothing" # out =~ "Roma — República romana"; Places.list_places() == []
test "writes the places and the links, as readers will see them"
  # run without --dry-run; out =~ "created"; Hamlet's links through Places.list_play_places/1
  # and Places.place_line/3 ("es") == ["Elsinor, Reino de Dinamarca, Europa (hoy Dinamarca)"];
  # every link origin "filemaker"; one activity-log "import" row per play
test "a second run changes nothing" # same counts before and after; out =~ "already imported"
test "links a curator removed stay removed" # Places.unlink_place/1 on all of Hamlet's, run again, none back
test "a play's own links stay, FileMaker's go after them"
  # a manual link on Othello first: it keeps position 0, FileMaker's follow
```

- [ ] **Step 2: Run, watch them fail.** `mix test test/mix/tasks_test.exs`

- [ ] **Step 3: Implement**

`apply_plan/2`, one `Repo.transaction(…, timeout: :infinity)`: create `plan.places` in order with `Places.create_place/1` (`attrs` plus `"parent_place_id"` from the map built so far; an `existing` place is mapped, not created), then `Places.link_place(play_id, place_id, %{"historical_state_id" => …, "note" => …, "role" => "setting", "origin" => "filemaker"})` (it appends after the play's highest position), then one `ActivityLog.log!/1` per play. The mix task and `Release.import_places/2` copy `playcode.import.witnesses` and `import_witnesses/2`, printing `"created N places and M links"`.

- [ ] **Step 4: Run, watch them pass.**

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Whole suite, format, compile, commit**

```bash
git add lib/mix/tasks/playcode.import.places.ex lib/playcode/import/places.ex lib/playcode/release.ex test/mix/tasks_test.exs
git commit -m "feat(import): mix playcode.import.places writes FileMaker's places of action"
```

---

### Task 8: The paperwork

**Files:**
- Modify: `CLAUDE.md` (*Getting Started*: the import command beside the witnesses'; *TEI-XML Format*: a `setting/placeName/country` line), `CONTEXT.md` (*Historical state*, the spec's wording), `docs/stakeholder/ida-y-vuelta.html` (the row: admin, TEI export, TEI import, play page, site yes; HTML/PDF/EPUB no), `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md` (S9b points at the spec; the "( Miseno ) = mentioned" paragraph corrected; open question 4's `T10*` and genre items received 2026-10-19; S5's place table found), `docs/stakeholder/preguntas.html` (the tables still to ask for), `docs/backlog.md` (Wikidata matching for imported places)

- [ ] **Step 1:** Make the edits. Each says what changed in the file's own voice; no file but these.
- [ ] **Step 2:** `git diff docs/backlog.md docs/stakeholder/preguntas.html` — if lines that are not yours are there, ask the owner before staging (Global Constraints).
- [ ] **Step 3: Commit** — `docs: S9b's command, glossary word, round-trip row and roadmap`

---

### Task 9: Against the real tables

Dev has no database. Nothing here is committed but hand-list corrections, each with its fixture row and test.

- [ ] **Step 1:** `mix ecto.create && mix ecto.migrate && mix playcode.import.tei` (the corpus, a few minutes).
- [ ] **Step 2:** `mix playcode.import.places --dry-run`, its output saved to a scratch file, and read it: every *twinless* and *no country* line must be settled by a hand-list entry or accepted as the spec says (Moldavia, Palestina); every *merged* line must be the same place; the plays and link counts must match the spec's numbers (150 links on 106 plays, less the skipped).
- [ ] **Step 3:** For each correction: add the FileMaker rows to the fixture (`regenerate.exs`), a test in `places_test.exs` that fails, the hand-list entry, green, refactor, commit (`fix(import): …`).
- [ ] **Step 4:** Run it for real: `mix playcode.import.places`; open `/plays/EMOTHE0010` and `/admin/places`; Generate one play on `/admin/export` and read its Places line.
- [ ] **Step 5:** Report to the owner: the dry run's summary and anything accepted rather than fixed. Production waits for the owner: deploy, then `Playcode.Release.import_places/2` with `dry_run: true`, then without, then Generate. Once production has it, S9b moves from `docs/backlog.md` to `docs/history.md`.
