# The Kind of an Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A play its TEI file calls an adaptation (or a refundición) is one in Playcode, in its exported file and on the public site, instead of an original (10 plays) or a translation (The Shy Courtier). A play its file calls a version (3 plays) keeps the word, as a fourth kind, until question 40 is answered.

**Architecture:** `plays.relationship_type` already allows `traduccion`, `adaptacion` and `refundicion`, and the admin, the play page and the Phoenix catalogue already label all three; `version` joins them. What is missing is the TEI import and export (only `traduccion` is read and written), the FileMaker sync (which overwrites the kind), the static site (which calls every non-original a translation), the comparison (which pairs only a translation with its original), and the data on dev and production.

**Tech Stack:** Elixir/Phoenix, Saxy/XmlBuilder, the static site's HEEx components and `search.js`.

**Spec:** question 15 in `docs/stakeholder/preguntas.html` (decided 2026-10-16: "each by its own name, as the files call them: adaptation, and refundición when one comes", and the three links to correct), with the technical detail in `docs/backlog.md`, *Round trip*, "The kind of an adaptation". Question 40 (added 2026-10-18) asks what a version is; until it is answered, `version` is kept as a kind (decided by the user 2026-10-18: easy to change in each play's form afterwards).

## Global Constraints

- TDD: failing test first, watch it fail, smallest change, green, refactor while green, `mix test` whole suite; `mix format`; `mix compile --warnings-as-errors` before each commit.
- Test through the outermost API: round trips (`roundtrip/1`, `xml_elements/3`), the generated site's HTML, `live/2`; read back through context functions, never `Repo`.
- `relationship_type` stays `@platform_owned` in `TeiImport`: a re-import never changes it, so the plays already imported are corrected by the migration in Task 5.
- The site is in English and hard-codes its words (no gettext). Its kinds: `original`, `translation`, `adaptation`, `refundicion`, `version`; plural labels "Originals", "Translations", "Adaptations", "Refundiciones", "Versions"; singular "translation", "adaptation", "refundición", "version". The admin's word for `version` is "Version" ("Versión" in Spanish).
- `search.js` stays under its 15 KB budget (13.1 KB now), asserted in `static_site_test.exs`; `node --test test/js/*.test.mjs` after any JS change.
- Out of scope: what the downloads print (question 24).

## Review Focus

1. A play with both `<title type="traduccion">` and another typed title: the kind comes from the first typed title of the three kinds, and that title is the play's title, as today for translations.
2. An adaptation with no original in Playcode (EMOTHE0317 before the migration): the site says "adaptation" with no "Adaptation of" link; nothing crashes on a nil parent.
3. A FileMaker sync after the migration must not turn the 11 back into originals or a translation, nor unlink them (Task 2).
4. The comparison of a translation still opens beside its original (the existing test stays green).
5. The migration on a database that lacks a play it names (the test database, a fresh dev) changes nothing and fails nothing.

---

### Task 1: Read and write the kind in the TEI file

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex:406-429` (title selection)
- Modify: `lib/playcode/export/tei_xml.ex:105-110` (`build_title_stmt/1`)
- Modify: `lib/playcode/catalogue/play.ex:9-10, 213` (moduledoc, `validate_inclusion` gains `version`)
- Modify: the admin's labels, each gaining `version` → `gettext("Version")`: `play_form_live.ex:275` (`relationship_type_options/0`), `play_show_live.ex:655`, `play_detail_live.ex:132`, `play_catalogue_live.ex:61` (lower case there); `mix gettext.extract --merge`, Spanish "Versión"/"versión", and check every entry it marks fuzzy
- Test: `test/playcode/tei_roundtrip_test.exs`

- [ ] **Step 1: Write the failing test** (beside the translation tests that use `title_stmt:`, `tei_roundtrip_test.exs:344`; `tei/1` always writes a plain `<title>Test Play</title>` before `:title_stmt`, so this also checks the typed title wins)

```elixir
for kind <- ~w(adaptacion refundicion version) do
  test "a #{kind} is read from its title and written back there" do
    play = import_tei!(tei(title_stmt: ~s(<title type="#{unquote(kind)}">Le Menteur</title>)))

    assert %{relationship_type: unquote(kind), title: "Le Menteur"} = Catalogue.get_play!(play.id)
    assert {%{"type" => unquote(kind)}, "Le Menteur"} in xml_elements(export_tei(play), "title")
  end
end
```

- [ ] **Step 2: Run it, watch it fail** (`relationship_type` nil; no `type` written back)

- [ ] **Step 3: Implement**

```elixir
# tei_parser.ex
@kinds ~w(traduccion adaptacion refundicion version)

# The main title: the one that says what kind of play this is, else the first with no
# key or type, else the first with no key.
kind_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") in @kinds end)
main_title = kind_title || plain_title || Enum.find(titles, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)
relationship_type = kind_title && attr_value(elem(kind_title, 1), "type")
```

```elixir
# tei_xml.ex: the kind is the main title's type (Play.changeset allows only the four)
main_title_attrs = if play.relationship_type, do: %{type: play.relationship_type}, else: %{}
```

- [ ] **Step 4: Run it, green; then `mix test test/playcode/tei_roundtrip_test.exs test/playcode/import`**
- [ ] **Step 5: Commit** `feat(tei): an adaptation, refundición or version is read from its title and written back`

### Task 2: The FileMaker sync keeps an adaptation and its original

FileMaker's index knows only an editor (an original) and a translator (a translation), so `FilemakerSync.relationship_for/1` turned the 10 adaptations into originals and The Shy Courtier into a translation, and `parent_for/2` links each by FileMaker's family. The files' word wins (question 15).

**Files:**
- Modify: `lib/playcode/import/filemaker_sync.ex:173-180` (`changes_for/3`)
- Test: `test/playcode/import/filemaker_sync_test.exs:71-80`

- [ ] **Step 1: Write the failing test; change the one that asserts the opposite**

The test "a wrong relationship on an original is cleared" sets `adaptacion` on EMOTHE0038 and expects FileMaker to clear it. Make it `traduccion` (FileMaker still corrects a wrong translation), renamed "a wrong translation on an original is cleared", with a comment that an adaptation is kept since question 15. Add, with the file's `play/2`, `dated/0` and `index/0` (EMOTHE0038 an original, EMOTHE0052 its translation in FileMaker):

```elixir
# Question 15: the file's kind wins; FileMaker's index knows only originals and translations.
test "an adaptation stays one, with the original it has" do
  original = play("EMOTHE0038_AntonyAndCleopatra", Map.put(dated(), "language", "en"))
  adaptation = play("EMOTHE0052_AntonioYCleopatra", %{"relationship_type" => "adaptacion"})

  for change <- FilemakerSync.plan(index(), [original, adaptation]).changes,
      change.code == "EMOTHE0052" do
    refute Map.has_key?(change.sets, :relationship_type)
    refute Map.has_key?(change.sets, :parent_play_id)
  end
end
```

With no parent stored, FileMaker would otherwise link it (as in "a translation is marked and linked"), so the test also bites on the parent.

- [ ] **Step 2: Run, watch it fail**
- [ ] **Step 3: Implement**: in `changes_for/3`, a play whose `relationship_type` is `adaptacion`, `refundicion` or `version` gets `@keep` for both `relationship_type` and `parent_play_id`.
- [ ] **Step 4: Green; `mix test test/playcode/import/filemaker_sync_test.exs test/playcode_web/live/admin/filemaker_sync_live_test.exs`**
- [ ] **Step 5: Commit** `fix(filemaker): the sync keeps an adaptation and its original`

### Task 3: The site names each kind

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex:993-994` (`kind/1`), `:1022` (the catalogue tag), `:218-240` (`family/1`, "Translation of")
- Modify: `lib/playcode/export/static_site.ex:615-619` (the Kind facet's labels)
- Modify: `priv/static_site/search.js:107` and `:270` (facet label, result meta)
- Test: `test/playcode/export/static_site_catalogue_test.exs`, `test/playcode/export/static_site_test.exs`, `test/js/search.test.mjs`

- [ ] **Step 1: Write the failing tests**

In `static_site_catalogue_test.exs` (an adaptation of a published original, both complete): its entry has `data-kind="adaptation"` and the tag "adaptation"; the facets include "Adaptations 1". In `static_site_test.exs`: the adaptation's title page says "Adaptation of" and links the original; a translation's still says "Translation of". In `search.test.mjs`: `S.kindLabel('adaptation')` is `'Adaptations'`, `S.kindLabel('original')` is `'Originals'`.

- [ ] **Step 2: Run, watch them fail**

- [ ] **Step 3: Implement**

```elixir
# components.ex
@kinds %{"traduccion" => "translation", "adaptacion" => "adaptation", "refundicion" => "refundicion", "version" => "version"}
@doc "The site's word for a play's kind: original, translation, adaptation, refundicion or version."
def kind(%{relationship_type: type}), do: Map.get(@kinds, type, "original")

@doc "A kind in a sentence: \"adaptation\", \"refundición\"."
def kind_name("refundicion"), do: "refundición"
def kind_name(kind), do: kind
```

The tag: `<span :if={@lead and kind(@play) != "original"} class="tag">{kind_name(kind(@play))}</span>`. `family/1`: `{String.capitalize(kind_name(kind(@play)))} of <a …>` in place of "Translation of". The facet map in `static_site.ex` gains `"adaptation" => "Adaptations", "refundicion" => "Refundiciones", "version" => "Versions"`.

```js
// search.js, above `if (!root.document) return;`, so node can test it
var KINDS = { original: 'Originals', translation: 'Translations', adaptation: 'Adaptations', refundicion: 'Refundiciones', version: 'Versions' };
S.kindLabel = function (kind) { return KINDS[kind] || kind; };
// FACETS: ['kind', 'Kind', function (play) { return S.kindLabel(play.kind); }]
// group(): play.kind === 'original' ? null : (play.kind === 'refundicion' ? 'refundición' : play.kind)
```

- [ ] **Step 4: Green; `mix test test/playcode/export` and `node --test test/js/*.test.mjs`**
- [ ] **Step 5: Commit** `feat(site): each kind of play by its own name, in the catalogue, the search and the title page`

### Task 4: The comparison opens any derived play beside its original

`PlayComparison.build_initial_panels/2` prepends the original only for a `traduccion`, so after Task 5 The Shy Courtier would stop opening beside *El vergonzoso en palacio*.

**Files:**
- Modify: `lib/playcode_web/live/play_comparison.ex:43`
- Test: `test/playcode_web/live/play_compare_live_test.exs` (beside "auto-includes the parent panel when viewing a translation")

- [ ] **Step 1: Failing test**: the same as that test with a play of `relationship_type: "adaptacion"` and the original as parent: two panels, the original's title shown.
- [ ] **Step 2: Run, watch it fail**
- [ ] **Step 3: Implement**: `if play.relationship_type && play.parent_play_id do` (drop the `== "traduccion"`; update the `@doc` to say "a translation, adaptation or refundición").
- [ ] **Step 4: Green; `mix test test/playcode_web/live/play_compare_live_test.exs`**
- [ ] **Step 5: Commit** `feat(compare): an adaptation opens beside its original too`

### Task 5: Correct the stored plays, the file, and the docs

**Files:**
- Create: `priv/repo/migrations/20261018100000_name_the_adaptations.exs`
- Modify (git-ignored, outside the commit): `doc/tei_corpus/EMOTHE0141_LasMocedadesDelCid.xml`
- Modify: `docs/backlog.md`, `docs/history.md`, `docs/stakeholder/ida-y-vuelta.html`, `docs/stakeholder/preguntas.html` (question 15's "Built" line)

- [ ] **Step 1: The migration**, after the precedent `20261013140000_spell_delivery_as_tei_does.exs` (raw SQL, not reversible, the content triggers move each play's `content_version` so Generate refreshes them). Codes are matched on their prefix (`split_part(code, '_', 1)`), as production's codes carry the title. A play the database lacks matches nothing.

```elixir
def up do
  execute("""
  UPDATE plays SET relationship_type = 'adaptacion'
  WHERE split_part(code, '_', 1) IN ('EMOTHE0030', 'EMOTHE0049', 'EMOTHE0090', 'EMOTHE0120',
    'EMOTHE0121', 'EMOTHE0192', 'EMOTHE0298', 'EMOTHE0317', 'EMOTHE0653', 'EMOTHE0687')
    AND relationship_type IS DISTINCT FROM 'adaptacion'
  """)

  # Question 40 asks what a version is; until then the word the files give is kept.
  execute("""
  UPDATE plays SET relationship_type = 'version'
  WHERE split_part(code, '_', 1) IN ('EMOTHE0503', 'EMOTHE0715', 'EMOTHE0750')
    AND relationship_type IS NULL
  """)

  # Annabella adapts Ford's play; El pastor fido, Guarini's, not Calderón's auto.
  for {play, original} <- [{"EMOTHE0317", "EMOTHE0283"}, {"EMOTHE0298", "EMOTHE0006"}] do
    execute("""
    UPDATE plays p SET parent_play_id = o.id FROM plays o
    WHERE split_part(p.code, '_', 1) = '#{play}' AND split_part(o.code, '_', 1) = '#{original}'
      AND o.deleted_at IS NULL
    """)
  end

  # Las mocedades del Cid (c. 1618) is the original; Corneille's Le Cid (1637) adapts it.
  execute("UPDATE plays SET relationship_type = NULL, parent_play_id = NULL WHERE split_part(code, '_', 1) = 'EMOTHE0141'")
end

def down, do: :ok
```

- [ ] **Step 2: Run it on dev and check**: `mix ecto.migrate`, then with `mix run -e` through `Catalogue` print each of the 14 codes' `relationship_type` and parent's code: 10 `adaptacion`, 3 `version`, 0317 under 0283, 0298 under 0006, 0141 nil and unlinked. `mix test` (the test database runs the migration over no plays).

- [ ] **Step 3: Correct our copy of EMOTHE0141's file** (git-ignored, so a first import reads it as an original): `<title type="adaptacion">` becomes `<title>`; remove `<title type="original">Le Cid</title>` and `<author key="original">Pierre Corneille</author>`; the `edicion` title's "de Pierre Corneille" becomes "de Guillén de Castro". Re-save as UTF-16 like the rest (`iconv -t UTF-16`), then `mix playcode.import.tei --dry-run` reads it with no error. The project gets this change for its own file, as with Mariamne.

- [ ] **Step 4: Docs**: move the backlog item to `docs/history.md` (what was built, the tests, the migration, the 0141 file); question 40 is already on the questions page (added 2026-10-18); in `ida-y-vuelta.html` and question 15 of `preguntas.html`, say it is built. The stakeholder artifacts are republished only when the user says so (memory: *Stakeholder artifacts account*).

- [ ] **Step 5: Whole suite** (`mix test`, `node --test test/js/*.test.mjs`, `mix test --include slow test/playcode/roundtrip_test.exs`), **commit** `fix(data): the eleven adaptations named, and three links corrected`.

## After the merge (production)

The deploy runs the migration. The site's code changed (`Components`), so `mix playcode.fly.reimport generate` rebuilds every play on performance-1x; check the catalogue's Kind facet and The Shy Courtier's title page on the preview, then `deploy`.
