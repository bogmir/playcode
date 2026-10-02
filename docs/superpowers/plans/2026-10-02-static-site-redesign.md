# Static Site Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static site's look, structure and search: HEEx templates instead of string interpolation, one page per act, a metrical synopsis and per-character statistics, and full-text search that works from `file://`.

**Architecture:** `Playcode.Export.StaticSite` stays the orchestrator and keeps its public API. A play is first prepared by `StaticSite.Edition` (pages, anchors, refs, split-verse ghosts, passage starts), then rendered by `StaticSite.Pages` (`pages/*.html.heex`) and `StaticSite.Components`. Statistics are computed by a new pure module, `Playcode.Statistics.Metrics`, and cached by `Playcode.Statistics`. Search is an inverted index written as `.js` files by `StaticSite.Search` and read by `priv/static_site/search.js`.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22 (`Phoenix.Component`, `embed_templates`), Jason, LazyHTML (tests), plain CSS and ES2017 JS, `node --test` for the JS.

**Spec:** `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`. Read it before Task 1; this plan argues from it.

## Global Constraints

- No new Hex dependencies and no npm. Node is used only to run `test/js/search.test.mjs`.
- The generated site makes **no third-party requests**: no CDN, no remote fonts, no remote scripts.
- Everything works from the unzipped archive opened as `file://`, search included. Search data files are `.js` that call `EMOTHE.search.load(kind, key, data)`; never `fetch`.
- The archive is in English whatever the admin's locale: every `StaticSite` entry point runs inside `Gettext.with_locale(PlaycodeWeb.Gettext, "en", …)`.
- Lower-case `emothe` must never appear in a tracked file (`test/rename_guard_test.exs`). The wordmark is typed `EMOTHE` and set in `font-variant: all-small-caps`; the JS global is `EMOTHE`.
- Colours: paper `#fbfbf9`, ink `#1b2430`, accent `#1f3a5f`, hairline `#e3e6ea`. Metrical families, light `#2f66a8` / `#cf6a3a` / `#22a07a`; dark `#4f84cf` / `#d2703f` / `#24a07a` (both validated all-pairs, colour-blind safe, ≥ 3:1 against `#fbfbf9` and `#121519`). Other / unmarked is grey.
- Fonts: Source Serif 4 (text) and Inter (interface), woff2, Latin and Latin Extended subsets, OFL licence files shipped beside them.
- Size budget: `style.css` ≤ 25 KB, `site.js` ≤ 15 KB, `search.js` ≤ 15 KB, fonts ≤ 300 KB total, longest act page ≤ 80 KB gzipped, a first search ≤ 300 KB (largest shard plus the five largest lines files).
- CLAUDE.md testing rules apply to every task: failing test first, run it red, smallest implementation, run it green, then the whole `mix test`; test through the outermost API (`StaticSite.generate/1`, `Statistics.get_statistics/1`); select by stable id, `data-*` hook, ARIA or visible text, not CSS classes; `DataCase` tests do not use `Repo` except where a step says why. A test written for behaviour that already works must be shown to bite: break the line, watch it go red, restore it.
- After every task: `mix format`, `mix compile --warnings-as-errors`, `mix test`. Run mix plainly (no `export PATH=…`).
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

Inputs the spec implies that a reviewer should check by hand beyond each task's own tests, most likely first. Each has a pinning test in the task named.

1. **A play that restarts its line numbering in each scene** (EMOTHE0761, 0281, 0337, 0678 in dev). Every line must still get a unique `id`, on act pages and on the full text, or `#l12` links land on the wrong line. Task 4, "a play that numbers each scene from 1…".
2. **Text with `&`, `<`, quotes in titles, speakers and lines.** It must arrive escaped, never as markup. Task 4 ("…keeps its italics, escaped") and Task 6 ("titles and authors are escaped").
3. **A play without verse, or without `<extent>`.** `is_verse` comes from `<extent>` (`tei_parser.ex:406`), so any file without one imports as prose. The share-of-play unit and the "Form" line therefore read the computed verse count, not `is_verse`. Task 5, "a play in prose…".
4. **Translations whose original is not published, and translations of translations.** Neither may vanish from the catalogue. Task 6, two tests.
5. **An empty, punctuation-only or one-letter query.** None may throw or hang the search page. Task 9, node tests "a query of punctuation…" and "starts-with…except a one-letter word".

---

## File map

Create:

| File | Responsibility |
|---|---|
| `lib/playcode/play_content/inline_markup.ex` | The `<<…>>` italics markers: split into parts, or strip |
| `lib/playcode/statistics/metrics.ex` | Pure figures over the content tree: items, passages, families, characters, presence columns, divisions, word counts |
| `lib/playcode/export/static_site/edition.ex` | One play prepared for the site: pages, anchors, refs, ghosts, passage starts |
| `lib/playcode/export/static_site/pages.ex` | `embed_templates "pages/*"`; `render/2` to a string; strips dev annotations |
| `lib/playcode/export/static_site/pages/*.html.heex` | `title`, `division`, `text`, `statistics`, `catalogue`, `about`, `search`, `redirect` |
| `lib/playcode/export/static_site/components.ex` | Shell, rail, play text, charts, catalogue entry, small formatters |
| `priv/static_site/style.css`, `site.js`, `search.js`, `fonts/` | Static assets, copied to `_site/assets/` |
| `test/support/static_site_helpers.ex` | `generate!/2`, `read!/2`, `html!/2`, `texts/2`, `rows/2`, `squish/1`, `load_js!/2` |
| `test/playcode/export/static_site_play_test.exs` | Act, full-text and statistics pages |
| `test/playcode/export/static_site_catalogue_test.exs` | Catalogue page |
| `test/playcode/export/static_site_search_test.exs` | Normaliser parity, index files, search page |
| `test/fixtures/search_normalisation.json` | Cases run by both the Elixir and the JS test |
| `test/js/search.test.mjs` | `node --test` for `site.js` + `search.js` |

Modify: `lib/playcode_web/components/play_text.ex`, `lib/playcode_web/play_labels.ex`, `lib/playcode_web/components/statistics_panel.ex`, `lib/playcode/statistics.ex`, `lib/playcode/export/static_site.ex` (rewritten), `lib/playcode/export/static_site/search.ex` (rewritten), `lib/mix/tasks/playcode.export.site.ex`, `test/playcode/export/static_site_test.exs`, `test/playcode/statistics_test.exs`, `test/playcode_web/live/play_show_live_test.exs`, `test/mix/tasks_test.exs`, `.github/workflows/ci.yml`, `priv/gettext/**`, `CLAUDE.md`, the spec (one line, Task 5).

Delete: `lib/playcode/export/static_site/renderer.ex` (Task 6).

---

### Task 1: Shared inline markup and labels

**Files:**
- Create: `lib/playcode/play_content/inline_markup.ex`
- Modify: `lib/playcode_web/components/play_text.ex` (`inline_content/1`, delete `split_inline_markup/1`)
- Modify: `lib/playcode_web/play_labels.ex` (add verse-form, family and act labels)
- Modify: `lib/playcode_web/components/statistics_panel.ex` (delete its private label functions, call `PlayLabels`)
- Modify: `priv/gettext/default.pot`, `priv/gettext/*/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Produces: `Playcode.PlayContent.InlineMarkup.parts(text | nil) :: [%{text: String.t(), italic: boolean}]`; `InlineMarkup.plain(text | nil) :: String.t()`.
- Produces: `PlaycodeWeb.PlayLabels.verse_form_label(slug) :: String.t()`, `verse_family_label(family) :: String.t()`, `act_label(type) :: String.t()`, `act_label_plural(type) :: String.t()`.

- [ ] **Step 1: Write the test for italics on the live page**

Add `import Playcode.ImportHelpers` under `import Phoenix.LiveViewTest` in `test/playcode_web/live/play_show_live_test.exs`, then add:

```elixir
  test "italics in the text render as emphasis, without the storage markers", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp><speaker>ANA</speaker><lg><l n="1">Dulce <emph>sueño</emph> mío</l></lg></sp>
          </div1>
          """
        )
      )

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert "sueño" in (html |> LazyHTML.from_fragment() |> LazyHTML.query("em") |> Enum.map(&LazyHTML.text/1))
    refute html =~ "&lt;&lt;"
  end
```

- [ ] **Step 2: Run it, then prove it bites**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: PASS, because the live page already does this. Now in `play_text.ex` change `<em :if={part.italic}>{part.text}</em>` to `<span :if={part.italic}>{part.text}</span>`, run again, expect FAIL (`"sueño" in []`), and restore the line.

- [ ] **Step 3: Create `InlineMarkup` and use it in `PlayText`**

`lib/playcode/play_content/inline_markup.ex`:

```elixir
defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content. `parts/1` turns that back into pieces a renderer can mark up; `plain/1`
  gives the text without the markers, for search and word counts.
  """

  @doc "Splits `text` into `%{text: binary, italic: boolean}` parts, in order."
  def parts(nil), do: []

  def parts(text) do
    text
    |> String.replace("&lt;&lt;", "<<")
    |> String.replace("&gt;&gt;", ">>")
    |> then(&Regex.split(~r/<<(.*?)>>/s, &1, include_captures: true))
    |> Enum.map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> %{text: inner, italic: true}
        nil -> %{text: part, italic: false}
      end
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  @doc "`text` without the `<<` and `>>` markers."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)
end
```

In `lib/playcode_web/components/play_text.ex`, add `alias Playcode.PlayContent.InlineMarkup` under `use Phoenix.Component`, replace the first line of `inline_content/1` with

```elixir
    parts = InlineMarkup.parts(assigns.text)
```

and delete `split_inline_markup/1` entirely.

- [ ] **Step 4: Run the test**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Move the labels into `PlayLabels`**

Append to `lib/playcode_web/play_labels.ex` (before the final `end`):

```elixir
  @doc """
  The name of a verse form as stored on `play_elements.verse_type`, or `"unmarked"`
  for a passage with no form; an unknown slug as stored. A `_tirada` (a run with no
  stanzas) is named by its form alone, as metrical synopses do.
  """
  def verse_form_label("redondilla"), do: gettext("Redondilla")
  def verse_form_label("quintilla"), do: gettext("Quintilla")
  def verse_form_label("decima"), do: gettext("Décima")
  def verse_form_label("romance"), do: gettext("Romance")
  def verse_form_label("romance_tirada"), do: gettext("Romance")
  def verse_form_label("romancillo_o_endecha"), do: gettext("Romancillo o endecha")
  def verse_form_label("octava_real"), do: gettext("Octava real")
  def verse_form_label("soneto"), do: gettext("Soneto")
  def verse_form_label("terceto"), do: gettext("Terceto")
  def verse_form_label("silva"), do: gettext("Silva")
  def verse_form_label("silva_tirada"), do: gettext("Silva")
  def verse_form_label("lira"), do: gettext("Lira")
  def verse_form_label("sexteto_lira"), do: gettext("Sexteto-lira")
  def verse_form_label("cancion"), do: gettext("Canción")
  def verse_form_label("cancion_canzone"), do: gettext("Canción")
  def verse_form_label("endecasilabos_sueltos_tirada"), do: gettext("Endecasílabos sueltos")
  def verse_form_label("verso_suelto"), do: gettext("Verso suelto")
  def verse_form_label("pareados"), do: gettext("Pareados")
  def verse_form_label("pareados_endecasilabos"), do: gettext("Pareados endecasílabos")
  def verse_form_label("pareado_hexasilabo"), do: gettext("Pareado hexasílabo")
  def verse_form_label("cuarteto"), do: gettext("Cuarteto")
  def verse_form_label("copla_arte_mayor"), do: gettext("Copla de arte mayor")
  def verse_form_label("copla_estructura_abierta"), do: gettext("Copla de estructura abierta")
  def verse_form_label("otro"), do: gettext("Otro")
  def verse_form_label("unmarked"), do: gettext("Unmarked")
  def verse_form_label(other), do: other

  @doc "The name of a metrical family from `Playcode.Statistics.Metrics.family/1`."
  def verse_family_label("romance"), do: gettext("Romance")
  def verse_family_label("spanish"), do: gettext("Spanish stanzas")
  def verse_family_label("italianate"), do: gettext("Italianate")
  def verse_family_label(_other), do: gettext("Other")

  @doc "The singular name of an act division type; an unknown one as stored."
  def act_label("acto"), do: gettext("Acto")
  def act_label("jornada"), do: gettext("Jornada")
  def act_label("act"), do: gettext("Act")
  def act_label("acte"), do: gettext("Acte")
  def act_label("play"), do: gettext("Play")
  def act_label("Jornada"), do: gettext("Jornada")
  def act_label("Act"), do: gettext("Act")
  def act_label(other), do: other

  @doc "The plural name of an act division type."
  def act_label_plural("acto"), do: gettext("Actos")
  def act_label_plural("jornada"), do: gettext("Jornadas")
  def act_label_plural("act"), do: gettext("Acts")
  def act_label_plural("acte"), do: gettext("Actes")
  def act_label_plural("play"), do: gettext("Plays")
  def act_label_plural("Jornada"), do: gettext("Jornadas")
  def act_label_plural("Act"), do: gettext("Acts")
  def act_label_plural(other), do: other <> "s"
```

In `lib/playcode_web/components/statistics_panel.ex`: add `alias PlaycodeWeb.PlayLabels`; replace every `act_label_singular(` with `PlayLabels.act_label(`, every `act_label_plural(` with `PlayLabels.act_label_plural(`, every `verse_type_label(` with `PlayLabels.verse_form_label(`; delete the private `act_label_singular/1`, `act_label_plural/1` and `verse_type_label/1` clauses. The live panel now says "Romance" for `romance_tirada` instead of "Romance (tirada)", which is deliberate and matches the synopsis.

- [ ] **Step 6: Extract and translate the new strings**

Run: `mix gettext.extract --merge`
Then in `priv/gettext/es/LC_MESSAGES/default.po` give every new entry its Spanish text, and check every entry the merge marked `#, fuzzy` (it fuzzy-matches onto unrelated strings; remove the flag only when the text is right):

| msgid | Spanish msgstr |
|---|---|
| Romancillo o endecha | Romancillo o endecha |
| Sexteto-lira | Sexteto-lira |
| Endecasílabos sueltos | Endecasílabos sueltos |
| Verso suelto | Verso suelto |
| Pareados | Pareados |
| Pareados endecasílabos | Pareados endecasílabos |
| Pareado hexasílabo | Pareado hexasílabo |
| Cuarteto | Cuarteto |
| Copla de arte mayor | Copla de arte mayor |
| Copla de estructura abierta | Copla de estructura abierta |
| Unmarked | Sin marcar |
| Spanish stanzas | Estrofas castellanas |
| Italianate | Formas italianas |

If any other locale directory exists under `priv/gettext/`, give it the msgid as msgstr. "Other" already exists and is reused.

- [ ] **Step 7: Run everything**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: compile clean, all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/playcode/play_content/inline_markup.ex lib/playcode_web/components/play_text.ex lib/playcode_web/play_labels.ex lib/playcode_web/components/statistics_panel.ex priv/gettext test/playcode_web/live/play_show_live_test.exs
git commit -m "refactor: share the italics parser and the verse-form labels

InlineMarkup moves out of PlayText so the static site can use it; the act
and verse-form labels move from StatisticsPanel into PlayLabels and gain
the forms the corpus actually uses. romance_tirada is now labelled
\"Romance\", as metrical synopses name it. The new test proves the live
page's italics: it went red with <em> replaced by <span>.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Statistics — cache version, passages, characters, presence, divisions

**Files:**
- Create: `lib/playcode/statistics/metrics.ex`
- Modify: `lib/playcode/statistics.ex`
- Test: `test/playcode/statistics_test.exs`

**Interfaces:**
- Consumes: `PlayContent.load_play_content/1` (divisions with `:loaded_elements` and `:children`; elements with `:children` three levels deep and `element_characters` preloaded).
- Produces (used by Edition, Task 3, and the statistics page, Task 5):
  - `Metrics.act_types() :: [String.t()]` — `~w(acto act acte jornada)`
  - `Metrics.items(divisions) :: [item]`, item = `%{kind: :verse | :prose | :stage, element: %Element{}, line_group: %Element{} | nil, speech: %Element{} | nil, speakers: [{key, name}], number: integer | nil, act: pos_integer | nil, division: %Division{}, scene: %Division{} | nil}`
  - `Metrics.passages(items) :: [%{act, form, from, to, verses, element_ids}]` (form is a slug or `"unmarked"`; `[]` when all unmarked)
  - `Metrics.family(form) :: "romance" | "spanish" | "italianate" | "other"`
  - `Metrics.columns(items, passages) :: {basis, columns, column_of}`
  - `Metrics.characters(items, passages, column_of) :: [map]`, `Metrics.divisions(items) :: [map]`, `Metrics.words(text) :: integer`, `Metrics.whole_verse?(item) :: boolean`
  - New keys in `get_statistics/1` `.data`: `"version"`, `"verses"`, `"speeches"`, `"words"`, `"metrical_passages"`, `"characters"`, `"presence"`, `"divisions"`.

- [ ] **Step 1: Write the cache-version test**

Add to `test/playcode/statistics_test.exs`:

```elixir
  test "a row cached by an older version is recomputed on read" do
    %{play: play} = TestFixtures.play_with_structure_fixture()
    stat = Statistics.get_statistics(play.id)

    # No public function writes a stale row, by design, so the test ages it directly.
    alias Playcode.Repo
    stale = stat.data |> Map.delete("version") |> Map.put("total_verses", 999)
    stat |> Ecto.Changeset.change(data: stale) |> Repo.update!()

    assert Statistics.get_statistics(play.id).data["total_verses"] == 1
  end
```

- [ ] **Step 2: Run it**

Run: `mix test test/playcode/statistics_test.exs`
Expected: FAIL — `total_verses` is `999`, the stale row is returned as is.

- [ ] **Step 3: Version the cache**

In `lib/playcode/statistics.ex`, under the aliases:

```elixir
  # Bump when compute/1 changes what it stores: a cached row with another version is
  # recomputed on its next read, so no migration or manual recompute is needed.
  @version 2
```

Replace `get_statistics/1` with:

```elixir
  def get_statistics(play_id) do
    case Repo.get_by(PlayStatistic, play_id: play_id) do
      %PlayStatistic{data: %{"version" => @version}} = stat -> stat
      _missing_or_stale -> compute_and_store(play_id)
    end
  end
```

and add `"version" => @version,` as the first entry of the map `compute/1` returns.

- [ ] **Step 4: Run it**

Run: `mix test test/playcode/statistics_test.exs`
Expected: PASS. Commit:

```bash
git add lib/playcode/statistics.ex test/playcode/statistics_test.exs
git commit -m "feat: recompute cached statistics when their version is stale

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Write the metrical-passage tests**

Add `import Playcode.ImportHelpers` at the top of the test module, then:

```elixir
  describe "metrical passages" do
    test "fragments inherit the open passage's form, a new act closes it, same forms merge" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>A</speaker>
                <lg type="redondilla"><l n="1">uno</l><l n="2">dos</l><l n="3">tres</l><l n="4">cuatro</l></lg>
                <lg type="redondilla" part="I"><l n="5">cinco</l><l n="6" part="I">seis</l></lg>
              </sp>
              <sp><speaker>B</speaker>
                <lg type="free" part="M"><l part="F">y medio</l><l n="7">siete</l></lg>
              </sp>
              <sp><speaker>A</speaker>
                <lg type="free" part="F"><l n="8">ocho</l></lg>
                <lg type="romance_tirada"><l n="9">nueve</l><l n="10">diez</l></lg>
              </sp>
            </div1>
            <div1 type="jornada" n="2"><head>Jornada II</head>
              <sp><speaker>B</speaker>
                <lg type="romance_tirada"><l n="11">once</l></lg>
                <lg type="nil"><l n="12">doce</l></lg>
              </sp>
            </div1>
            """
          )
        )

      assert Statistics.get_statistics(play.id).data["metrical_passages"] == [
               %{"act" => 1, "form" => "redondilla", "family" => "spanish", "from" => 1, "to" => 8, "verses" => 8},
               %{"act" => 1, "form" => "romance_tirada", "family" => "romance", "from" => 9, "to" => 10, "verses" => 2},
               %{"act" => 2, "form" => "romance_tirada", "family" => "romance", "from" => 11, "to" => 11, "verses" => 1},
               %{"act" => 2, "form" => "unmarked", "family" => "other", "from" => 12, "to" => 12, "verses" => 1}
             ]
    end

    test "a play whose verse carries no form has no synopsis" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acte" n="1"><head>Acte I</head>
              <sp><speaker>A</speaker><lg type="free"><l n="1">un</l></lg><lg><l n="2">deux</l></lg></sp>
            </div1>
            """
          )
        )

      assert Statistics.get_statistics(play.id).data["metrical_passages"] == []
    end
  end
```

The first passage counts 8: lines 1–5, the `I` fragment of 6, 7 and 8; the `F` fragment "y medio" completes verse 6 and is not counted again.

- [ ] **Step 6: Run them**

Run: `mix test test/playcode/statistics_test.exs`
Expected: FAIL — `nil == [...]`, the key does not exist.

- [ ] **Step 7: Create `Metrics` with `items/1`, `passages/1`, `family/1`**

`lib/playcode/statistics/metrics.ex`:

```elixir
defmodule Playcode.Statistics.Metrics do
  @moduledoc """
  Dramatic and metrical figures computed from a play's content tree, as
  `Playcode.PlayContent.load_play_content/1` returns it.

  Pure functions. `Playcode.Statistics` stores what they return; the static site
  reads `items/1` and `passages/1` directly to place lines on pages and verse-form
  labels in the margin, so the pages and the statistics follow the same rules.
  """

  alias Playcode.PlayContent.Element

  @act_types ~w(acto act acte jornada)
  @unmarked [nil, "", "free", "nil"]
  @whole_verse [nil, "", "I"]

  # ponytail: the grouping awaits review by the project's philologists (spec, open
  # question 1). A form not listed here is "other".
  @families %{
    "romance" => ~w(romance romance_tirada romancillo_o_endecha),
    "spanish" => ~w(redondilla quintilla decima copla_arte_mayor copla_estructura_abierta),
    "italianate" => ~w(terceto octava_real soneto lira sexteto_lira silva silva_tirada
                       cancion cancion_canzone endecasilabos_sueltos_tirada
                       pareados_endecasilabos cuarteto verso_suelto)
  }

  @doc "Division types that are acts."
  def act_types, do: @act_types

  @doc ~S'The family of a verse form: "romance", "spanish", "italianate" or "other".'
  def family(form) do
    Enum.find_value(@families, "other", fn {family, forms} -> if form in forms, do: family end)
  end

  @doc """
  The play's text as a flat list in reading order: a division's own elements, then
  its scenes'. Each item is a map with

    * `:kind` — `:verse`, `:prose` or `:stage`
    * `:element`, `:line_group` (or nil), `:speech` (or nil)
    * `:speakers` — `{key, name}` per speaker: the character id, or
      `"label:" <> label` when the speech names no character
    * `:number` — the verse number; for a split verse's `M`/`F` fragment, the number
      of the verse it completes; nil for prose and stage directions
    * `:act` — 1-based ordinal among the act divisions, nil outside them
    * `:division` (top level) and `:scene` (child division or nil)
  """
  def items(divisions) do
    {items, _acts} =
      Enum.flat_map_reduce(divisions, 0, fn division, previous ->
        act = if division.type in @act_types, do: previous + 1
        context = %{act: act, division: division, scene: nil}

        own = Enum.flat_map(division.loaded_elements, &element_items(&1, context))

        scenes =
          Enum.flat_map(division.children, fn scene ->
            Enum.flat_map(scene.loaded_elements, &element_items(&1, %{context | scene: scene}))
          end)

        {own ++ scenes, act || previous}
      end)

    number_fragments(items)
  end

  defp element_items(%{type: "speech"} = speech, context) do
    context = Map.merge(context, %{speech: speech, speakers: speakers(speech)})

    Enum.flat_map(speech.children, fn
      %{type: "line_group"} = group ->
        Enum.flat_map(group.children, &leaf(&1, Map.put(context, :line_group, group)))

      child ->
        leaf(child, Map.put(context, :line_group, nil))
    end)
  end

  defp element_items(element, context),
    do: leaf(element, Map.merge(context, %{speech: nil, speakers: [], line_group: nil}))

  defp leaf(%{type: "verse_line"} = el, context),
    do: [Map.merge(context, %{kind: :verse, element: el})]

  defp leaf(%{type: "prose"} = el, context),
    do: [Map.merge(context, %{kind: :prose, element: el})]

  defp leaf(%{type: "stage_direction"} = el, context),
    do: [Map.merge(context, %{kind: :stage, element: el})]

  defp leaf(_element, _context), do: []

  defp speakers(speech) do
    label = speech.speaker_label

    case Element.characters(speech) do
      [] when label in [nil, ""] -> []
      [] -> [{"label:" <> label, label}]
      characters -> Enum.map(characters, &{&1.id, &1.name})
    end
  end

  # A fragment that continues a split verse has no number of its own; it belongs to
  # the verse its first fragment opened.
  defp number_fragments(items) do
    {items, _last} =
      Enum.map_reduce(items, nil, fn
        %{kind: :verse, element: %{line_number: n}} = item, _last when is_integer(n) ->
          {Map.put(item, :number, n), n}

        %{kind: :verse, element: %{part: part}} = item, last when part in ["M", "F"] ->
          {Map.put(item, :number, last), last}

        item, last ->
          {Map.put(item, :number, nil), last}
      end)

    items
  end

  @doc "True for a verse line that is a whole verse or a split verse's first fragment."
  def whole_verse?(%{kind: :verse, element: %{part: part}}), do: part in @whole_verse
  def whole_verse?(_item), do: false

  @doc """
  The metrical passages in order. Each is a map with `:act`, `:form` (a verse-type
  slug, or `"unmarked"`), `:from` and `:to` (first and last verse number), `:verses`
  (a split verse counts once) and `:element_ids` (its verse lines, in order).

  A line group with a real form and no `part`, or `part="I"`, opens a passage unless
  the open one has the same form. `M`/`F` fragments and lines outside any group
  continue the open passage. A new top-level division (an act, a prologue) closes it.
  Returns `[]` when every passage is unmarked.
  """
  def passages(items) do
    {passages, _seen} =
      items
      |> Enum.filter(&(&1.kind == :verse))
      |> Enum.reduce({[], nil}, fn item, {passages, seen} ->
        group = {item.division.id, item.line_group && item.line_group.id}
        passages = if group == seen, do: passages, else: place(item, passages, seen)
        {add_verse(passages, item), group}
      end)

    passages =
      passages
      |> Enum.reverse()
      |> Enum.map(&Map.update!(&1, :element_ids, fn ids -> Enum.reverse(ids) end))

    if Enum.all?(passages, &(&1.form == "unmarked")), do: [], else: passages
  end

  defp place(item, passages, seen) do
    group = item.line_group
    division = item.division.id

    open =
      case {passages, seen} do
        {[current | _], {^division, _}} -> current
        _ -> nil
      end

    cond do
      open == nil -> [new_passage(item, form(group)) | passages]
      group == nil or group.part in ["M", "F"] -> passages
      open.form == form(group) -> passages
      true -> [new_passage(item, form(group)) | passages]
    end
  end

  defp form(nil), do: "unmarked"
  defp form(%{verse_type: type}) when type in @unmarked, do: "unmarked"
  defp form(%{verse_type: type}), do: type

  defp new_passage(item, form),
    do: %{act: item.act, form: form, from: nil, to: nil, verses: 0, element_ids: []}

  defp add_verse([current | rest], %{element: element} = item) do
    n = element.line_number
    whole = if whole_verse?(item), do: 1, else: 0

    current = %{
      current
      | from: current.from || n,
        to: n || current.to,
        verses: current.verses + whole,
        element_ids: [element.id | current.element_ids]
    }

    [current | rest]
  end

  @doc "Number of words in element content; the `<<`/`>>` markers are not words."
  def words(nil), do: 0
  def words(text), do: length(Regex.scan(~r/[\p{L}\p{N}]+/u, text))
end
```

In `lib/playcode/statistics.ex` add `alias Playcode.PlayContent` and `alias Playcode.Statistics.Metrics` beside the existing aliases, and in `compute/1`, before the map:

```elixir
    items = play_id |> PlayContent.load_play_content() |> Metrics.items()
    passages = Metrics.passages(items)
```

then add to the returned map:

```elixir
      "metrical_passages" => Enum.map(passages, &passage_data/1),
```

and a private function:

```elixir
  defp passage_data(passage) do
    %{
      "act" => passage.act,
      "form" => passage.form,
      "family" => Metrics.family(passage.form),
      "from" => passage.from,
      "to" => passage.to,
      "verses" => passage.verses
    }
  end
```

- [ ] **Step 8: Run them**

Run: `mix test test/playcode/statistics_test.exs`
Expected: PASS. Commit:

```bash
git add lib/playcode/statistics lib/playcode/statistics.ex test/playcode/statistics_test.exs
git commit -m "feat: compute a play's metrical synopsis

Split-stanza fragments (lg part M/F, often typed \"free\") inherit the form
the open passage started with, so the synopsis counts verses where the old
verse_type_distribution counted fragments.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Write the character tests**

```elixir
  describe "characters" do
    test "speeches, lines, words, first words, asides, longest speech and forms" do
      play =
        import_tei!(
          tei(
            front: """
            <div type="elenco"><castList>
              <castItem><role xml:id="ANA">Ana</role></castItem>
              <castItem><role xml:id="JUAN">Juan</role></castItem>
            </castList></div>
            """,
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp who="#ANA"><speaker>ANA</speaker>
                <lg type="redondilla"><l n="1">Dulce <emph>sueño</emph> mío</l><l n="2">ven a mí</l><l n="3" part="I">ya</l></lg>
              </sp>
              <sp who="#JUAN"><speaker>JUAN</speaker>
                <lg type="free" part="F"><l part="F">no puedo</l><l n="4"><seg type="aside">qué haré</seg></l></lg>
              </sp>
              <sp who="#ANA #JUAN"><speaker>LOS DOS</speaker>
                <lg type="redondilla"><l n="5">juntos</l></lg>
              </sp>
              <sp><speaker>CRIADO</speaker><p>Señor, la cena.</p></sp>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data
      characters = Map.new(data["characters"], &{&1["name"], &1})

      assert Enum.map(data["characters"], & &1["name"]) == ["Ana", "Juan", "CRIADO"]

      assert %{
               "speeches" => 2,
               "lines" => 4,
               "words" => 8,
               "first" => %{"act" => 1, "line" => 1},
               "aside_verses" => 0,
               "longest_speech" => %{"lines" => 3, "words" => 7},
               "forms" => %{"redondilla" => 4}
             } = characters["Ana"]

      # Juan's first words complete verse 3; the shared verse 5 counts for both.
      assert %{"speeches" => 2, "lines" => 3, "words" => 5, "first" => %{"line" => 3}, "aside_verses" => 1} =
               characters["Juan"]

      assert %{"speeches" => 1, "lines" => 0, "words" => 3, "first" => %{"line" => nil}} =
               characters["CRIADO"]

      assert %{"verses" => 5, "speeches" => 4, "words" => 15} = data
    end
  end
```

- [ ] **Step 10: Run it**

Run: `mix test test/playcode/statistics_test.exs`
Expected: FAIL — `data["characters"]` is nil.

- [ ] **Step 11: Write the presence tests**

```elixir
  describe "presence" do
    test "columns are the scenes when the play has them" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>Acto I</head>
              <div2 type="escena" n="1"><head>Escena 1</head>
                <sp><speaker>A</speaker><l n="1">uno</l></sp>
              </div2>
              <div2 type="escena" n="2"><head>Escena 2</head>
                <sp><speaker>B</speaker><l n="2">dos</l></sp>
                <sp><speaker>A</speaker><l n="3">tres</l></sp>
              </div2>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data

      assert %{"basis" => "scene", "columns" => [%{"act" => 1, "label" => "Escena 1"}, %{"act" => 1, "label" => "Escena 2"}]} =
               data["presence"]

      assert %{"A" => [[0, 1], [1, 1]], "B" => [[1, 1]]} =
               Map.new(data["characters"], &{&1["name"], &1["columns"]})

      assert [
               %{"scene" => "Escena 1", "verses" => 1, "speeches" => 1, "speakers" => 1},
               %{"scene" => "Escena 2", "verses" => 2, "speeches" => 2, "speakers" => 2}
             ] = data["divisions"]
    end

    test "with no scenes, columns are the metrical passages" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>A</speaker><lg type="redondilla"><l n="1">uno</l></lg><lg type="decima"><l n="2">dos</l></lg></sp>
              <sp><speaker>B</speaker><lg type="decima"><l n="3">tres</l></lg></sp>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data

      assert %{
               "basis" => "passage",
               "columns" => [%{"form" => "redondilla", "from" => 1, "to" => 1}, %{"form" => "decima", "from" => 2, "to" => 3}]
             } = data["presence"]

      assert %{"A" => [[0, 1], [1, 1]], "B" => [[1, 1]]} =
               Map.new(data["characters"], &{&1["name"], &1["columns"]})
    end
  end
```

- [ ] **Step 12: Run them**

Run: `mix test test/playcode/statistics_test.exs`
Expected: FAIL — `data["presence"]` is nil.

- [ ] **Step 13: Add `columns/2`, `characters/3`, `divisions/1` and wire them in**

Append to `Metrics` (before the final `end`):

```elixir
  @doc """
  Presence columns: the play's scenes if it has any, else its metrical passages, else
  its top-level divisions. Returns `{basis, columns, column_of}`, where `column_of`
  maps an item to its column index, or nil.
  """
  def columns(items, passages) do
    cond do
      Enum.any?(items, & &1.scene) ->
        scenes = items |> Enum.filter(& &1.scene) |> Enum.uniq_by(& &1.scene.id)
        index = scenes |> Enum.with_index() |> Map.new(fn {item, i} -> {item.scene.id, i} end)

        columns =
          Enum.map(scenes, fn item ->
            %{"act" => item.act, "label" => item.scene.title || "#{item.act}.#{item.scene.position + 1}"}
          end)

        {"scene", columns, fn item -> item.scene && index[item.scene.id] end}

      passages != [] ->
        index =
          passages
          |> Enum.with_index()
          |> Enum.flat_map(fn {passage, i} -> Enum.map(passage.element_ids, &{&1, i}) end)
          |> Map.new()

        columns =
          Enum.map(passages, fn p ->
            %{"act" => p.act, "form" => p.form, "family" => family(p.form), "from" => p.from, "to" => p.to}
          end)

        {"passage", columns, fn item -> index[item.element.id] end}

      true ->
        divisions = Enum.uniq_by(items, & &1.division.id)
        index = divisions |> Enum.with_index() |> Map.new(fn {item, i} -> {item.division.id, i} end)
        columns = Enum.map(divisions, &%{"act" => &1.act, "label" => &1.division.title})
        {"division", columns, fn item -> index[item.division.id] end}
    end
  end

  @doc "Per-character figures, most lines first, then most words."
  def characters(items, passages, column_of) do
    form_of =
      passages
      |> Enum.flat_map(fn passage -> Enum.map(passage.element_ids, &{&1, passage.form}) end)
      |> Map.new()

    items
    |> Enum.filter(&(&1.kind in [:verse, :prose] and &1.speech != nil))
    |> Enum.flat_map(fn item -> Enum.map(item.speakers, &{&1, item}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {{key, name}, spoken} -> character(key, name, spoken, form_of, column_of) end)
    |> Enum.sort_by(&{-&1["lines"], -&1["words"], &1["name"]})
  end

  defp character(key, name, spoken, form_of, column_of) do
    verses = Enum.filter(spoken, &(&1.kind == :verse))
    speeches = spoken |> Enum.group_by(& &1.speech.id) |> Map.values()
    first = hd(spoken)

    %{
      "key" => key,
      "name" => name,
      "speeches" => length(speeches),
      "lines" => length(verses),
      "words" => sum_words(spoken),
      "first" => %{"act" => first.act, "line" => first.number},
      "aside_verses" => Enum.count(verses, & &1.element.is_aside),
      "longest_speech" => %{
        "lines" => speeches |> Enum.map(&Enum.count(&1, fn item -> item.kind == :verse end)) |> Enum.max(),
        "words" => speeches |> Enum.map(&sum_words/1) |> Enum.max()
      },
      "forms" => verses |> Enum.map(&form_of[&1.element.id]) |> Enum.reject(&is_nil/1) |> Enum.frequencies(),
      "columns" =>
        spoken
        |> Enum.map(column_of)
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies()
        |> Enum.sort()
        |> Enum.map(&Tuple.to_list/1)
    }
  end

  defp sum_words(items), do: items |> Enum.map(&words(&1.element.content)) |> Enum.sum()

  @doc "Verses, speeches and speakers per top-level division and per scene, in order."
  def divisions(items) do
    items
    |> Enum.chunk_by(&{&1.division.id, &1.scene && &1.scene.id})
    |> Enum.map(fn [first | _] = chunk ->
      spoken = Enum.filter(chunk, &(&1.kind in [:verse, :prose] and &1.speech != nil))

      %{
        "act" => first.act,
        "division" => first.division.title,
        "scene" => first.scene && first.scene.title,
        "verses" => Enum.count(chunk, &whole_verse?/1),
        "speeches" => spoken |> Enum.uniq_by(& &1.speech.id) |> length(),
        "speakers" => spoken |> Enum.flat_map(& &1.speakers) |> Enum.uniq() |> length()
      }
    end)
  end
```

In `Statistics.compute/1`, after `passages = …`:

```elixir
    {basis, columns, column_of} = Metrics.columns(items, passages)
    spoken = Enum.filter(items, &(&1.kind in [:verse, :prose]))
```

and add to the returned map:

```elixir
      "verses" => Enum.count(items, &Metrics.whole_verse?/1),
      "speeches" => count_by_type(all_elements, "speech"),
      "words" => spoken |> Enum.map(&Metrics.words(&1.element.content)) |> Enum.sum(),
      "characters" => Metrics.characters(items, passages, column_of),
      "presence" => %{"basis" => basis, "columns" => columns},
      "divisions" => Metrics.divisions(items),
```

- [ ] **Step 14: Run the whole suite**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all pass, including the two older statistics tests.

- [ ] **Step 15: Commit**

```bash
git add lib/playcode/statistics lib/playcode/statistics.ex test/playcode/statistics_test.exs
git commit -m "feat: per-character figures, presence and per-division counts

A split verse counts for each speaker's lines and once in the play's
verses; presence is by scene, or by metrical passage for the 32 plays that
encode no scenes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Edition, page shell, assets and the title page

**Files:**
- Create: `lib/playcode/export/static_site/edition.ex`, `pages.ex`, `components.ex`, `pages/title.html.heex`, `pages/redirect.html.heex`
- Create: `priv/static_site/style.css`, `priv/static_site/site.js`, `priv/static_site/fonts/*`
- Create: `test/support/static_site_helpers.ex`
- Modify: `lib/playcode/export/static_site.ex` (rewrite), `lib/playcode/export/static_site/renderer.ex` (two links only)
- Test: `test/playcode/export/static_site_test.exs` (rewrite), `test/mix/tasks_test.exs` (one path)

**Interfaces:**
- Consumes: `Metrics.items/1`, `Metrics.passages/1`, `Metrics.act_types/0` (Task 2); `InlineMarkup.plain/1`, `PlayLabels.*` (Task 1).
- Produces:
  - `%Edition{play, characters, divisions, stats, pages, items, anchors, refs, ghosts, passage_starts, page_of}` from `Edition.load(play_id)`. `pages` is a list of `%{slug, title, division}`; `anchors`, `refs`, `ghosts`, `passage_starts`, `page_of` are maps keyed by element id (anchors also by division id).
  - `Edition.neighbours(pages) :: [{page, previous | nil, next | nil}]`, `Edition.roman(pos_integer) :: String.t()`.
  - `Pages.render(name, assigns) :: String.t()`, `Pages.strip_annotations(html) :: String.t()`.
  - `Components.shell/1` (attrs `root`, `title`, `site`, `current`, `rail_label`; slots `rail`, `inner_block`), `Components.play_rail/1` (attrs `edition`, `current`), `Components.play_contents/1`, `Components.number/1`.
  - `site` assign: `%{version, build_date, published :: MapSet.t(code), play_count}`.
  - Output: `plays/<CODE>/index.html`, `plays/<CODE>/<CODE>.xml`, `plays/<CODE>.html` (redirect), `assets/…`.

- [ ] **Step 1: Write the test helpers**

`test/support/static_site_helpers.ex`:

```elixir
defmodule Playcode.StaticSiteHelpers do
  @moduledoc """
  Generate the static site into a temp directory and read it back as a visitor gets
  it: files, HTML documents, table rows and the search index's `.js` files.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Playcode.Export.StaticSite

  @doc "Generates the site for `plays` (by code) into a fresh temp dir and returns it."
  def generate!(plays, opts \\ []) do
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    opts = Keyword.merge([output_dir: dir, play_codes: Enum.map(plays, & &1.code)], opts)
    assert {:ok, %{output_dir: ^dir}} = StaticSite.generate(opts)
    dir
  end

  def read!(dir, path), do: File.read!(Path.join(dir, path))
  def html!(dir, path), do: dir |> read!(path) |> LazyHTML.from_document()

  @doc "The text of every node matching `selector`, whitespace collapsed."
  def texts(html, selector), do: html |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  @doc "Each row matching `selector` as the list of its cell texts."
  def rows(html, selector) do
    html
    |> LazyHTML.query(selector)
    |> Enum.map(fn row -> texts(row, "th, td") end)
  end

  def squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  @doc "Decodes a search file: `{kind, key, data}` from `EMOTHE.search.load(kind, key, data);`."
  def load_js!(dir, path) do
    [_, kind, key, json] =
      Regex.run(~r/\AEMOTHE\.search\.load\((".*?"),(".*?"),(.*)\);\n\z/s, read!(dir, path))

    {Jason.decode!(kind), Jason.decode!(key), Jason.decode!(json)}
  end
end
```

- [ ] **Step 2: Rewrite `test/playcode/export/static_site_test.exs` for the new layout**

```elixir
defmodule Playcode.Export.StaticSiteTest do
  @moduledoc """
  The published site as a whole: which plays it publishes, where each file goes, and
  each play's title page. Generated with `StaticSite.generate/1` into a temp
  directory and read back as the files a visitor gets.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Pages

  defp complete_play(attrs \\ %{}), do: play_fixture(Map.put(attrs, "is_complete", true))
  defp title_page(dir, play), do: html!(dir, "plays/#{play.code}/index.html")
  defp hrefs(html), do: html |> LazyHTML.query("a") |> LazyHTML.attribute("href")

  test "only complete plays are published, and only they are in the catalogue" do
    complete = complete_play(%{"title" => "Obra terminada"})
    draft = play_fixture(%{"title" => "Obra en curso"})

    dir = generate!([complete, draft])

    assert File.exists?(Path.join([dir, "plays", complete.code, "index.html"]))
    assert File.exists?(Path.join([dir, "plays", complete.code, "#{complete.code}.xml"]))
    refute File.exists?(Path.join([dir, "plays", draft.code]))

    index = read!(dir, "index.html")
    assert index =~ "Obra terminada"
    refute index =~ "Obra en curso"
  end

  test "with nothing complete to publish, nothing is generated" do
    assert {:error, _} =
             StaticSite.generate(output_dir: "/nonexistent", play_codes: [play_fixture().code])
  end

  test "the address of the previous layout redirects to the play's folder" do
    play = complete_play()
    stub = html!(generate!([play]), "plays/#{play.code}.html")

    assert stub |> LazyHTML.query(~s(meta[http-equiv="refresh"])) |> LazyHTML.attribute("content") ==
             ["0; url=#{play.code}/index.html"]

    assert hrefs(stub) == ["#{play.code}/index.html"]
  end

  test "the stylesheet, script and fonts are published under assets/, with the font licences" do
    dir = generate!([complete_play()])

    assert File.exists?(Path.join([dir, "assets", "style.css"]))
    assert File.exists?(Path.join([dir, "assets", "site.js"]))
    assert Path.wildcard(Path.join([dir, "assets", "fonts", "*.woff2"])) != []
    assert Path.wildcard(Path.join([dir, "assets", "fonts", "OFL-*.txt"])) != []
  end

  test "the title page carries the play's metadata, edition, sources and front notes" do
    {:ok, play} =
      Catalogue.update_play(play_with_metadata_fixture(), %{
        "is_complete" => true,
        "author_name" => "Pedro Calderón de la Barca"
      })

    page = title_page(generate!([play]), play)
    text = LazyHTML.text(page)

    assert texts(page, "h1") == [play.title]
    assert text =~ "Pedro Calderón de la Barca"
    assert text =~ "Editor One"
    assert text =~ "Source note"
    assert "Editorial heading" in texts(page, "h2")
    assert text =~ "Editorial content"
    assert text =~ "ed. Editor One"
    assert "#{play.code}.xml" in hrefs(page)
  end

  test "the title page lists the cast and the contents, linking each act's page" do
    %{play: play} = play_with_structure_fixture()
    page = title_page(generate!([play], all: true), play)

    assert "ALFA" in texts(page, "dt")
    assert "act-1.html" in hrefs(page)
    assert "text.html" in hrefs(page)
    assert "statistics.html" in hrefs(page)
  end

  test "an original's title page links its published translations, and only those" do
    %{original: original, translation: translation} = translation_family_fixture()
    unpublished = play_fixture(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"})

    page = title_page(generate!([original, translation]), original)

    assert "../#{translation.code}/index.html" in hrefs(page)
    refute "../#{unpublished.code}/index.html" in hrefs(page)
  end

  test "a play page carries its places and its historical time, in English whatever the locale" do
    play = complete_play(%{"historical_time" => "siglo_xvii"})
    play_place_fixture(play, place_fixture(%{"name" => "Roma"}))

    dir = Gettext.with_locale(PlaycodeWeb.Gettext, "es", fn -> generate!([play]) end)
    html = read!(dir, "plays/#{play.code}/index.html")

    assert html =~ "Roma"
    assert html =~ "17th century"
    refute html =~ "Siglo XVII"
  end

  test "a play with no places has no places section" do
    play = complete_play()

    refute "Places" in texts(title_page(generate!([play]), play), "h2")
  end

  test "a composition date shows as a range, a single year, or the note alone" do
    range =
      complete_play(%{
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    single = complete_play(%{"composition_date_from" => 1614, "composition_date_to" => 1614})
    note_only = complete_play(%{"composition_date_note" => "¿1694? y ¿1605?"})

    dir = generate!([range, single, note_only])
    page = fn play -> read!(dir, "plays/#{play.code}/index.html") end

    assert page.(range) =~ "1606–1607"
    assert page.(range) =~ "1606; 1607"
    assert page.(single) =~ "1614"
    refute page.(single) =~ "1614–1614"
    assert page.(note_only) =~ "¿1694? y ¿1605?"
  end

  test "one play can be added to or removed from a generated site" do
    first = complete_play(%{"title" => "Primera"})
    dir = generate!([first])
    second = complete_play(%{"title" => "Segunda"})

    :ok = StaticSite.generate_single_play(second.id, output_dir: dir)
    assert StaticSite.list_exported_codes(dir) == Enum.sort([first.code, second.code])

    :ok = StaticSite.remove_single_play(first.code, output_dir: dir)
    assert StaticSite.list_exported_codes(dir) == [second.code]
    refute File.exists?(Path.join([dir, "plays", "#{first.code}.html"]))
    assert read!(dir, "index.html") =~ "Segunda"
    refute read!(dir, "index.html") =~ "Primera"
  end

  test "the HEEx annotations dev compiles in never reach the archive" do
    # config/dev.exs turns them on; the test env cannot, so the function is tested directly.
    html =
      ~s(<!-- <Playcode.X.y> lib/x.ex:3 (playcode) --><p data-phx-loc="12">Hi</p>) <>
        ~s(<!-- </Playcode.X.y> --><!-- @caller lib/y.ex:9 (playcode) -->)

    assert Pages.strip_annotations(html) == "<p>Hi</p>"
  end
end
```

In `test/mix/tasks_test.exs`, in the `playcode.export.site` test, change the `page` function to:

```elixir
      page = fn play -> File.exists?(Path.join([dir, "plays", play.code, "index.html"])) end
```

- [ ] **Step 3: Run them**

Run: `mix test test/playcode/export/static_site_test.exs test/mix/tasks_test.exs`
Expected: FAIL — `plays/<CODE>/index.html` does not exist; `Pages` is undefined (compile error until Step 6).

- [ ] **Step 4: Fetch the fonts and their licences**

Save as `$SCRATCHPAD/fetch_fonts.py` (your session scratchpad, not the repo) and run it from the repo root with `python3 $SCRATCHPAD/fetch_fonts.py`:

```python
# Downloads Source Serif 4 (400, 600, 400 italic) and Inter (400, 600) as woff2,
# Latin and Latin Extended subsets, from the Google Fonts CSS2 API.
import pathlib
import re
import urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
OUT = pathlib.Path("priv/static_site/fonts")
OUT.mkdir(parents=True, exist_ok=True)
FAMILIES = {
    "source-serif-4": "Source+Serif+4:ital,wght@0,400;0,600;1,400",
    "inter": "Inter:wght@400;600",
}

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA})).read()

for slug, spec in FAMILIES.items():
    css = get(f"https://fonts.googleapis.com/css2?family={spec}&display=swap").decode()
    for subset, block in re.findall(r"/\* (latin(?:-ext)?) \*/\s*(@font-face \{.*?\})", css, re.S):
        style = re.search(r"font-style: (\w+)", block).group(1)
        weight = re.search(r"font-weight: (\d+)", block).group(1)
        url = re.search(r"url\((https://[^)]+\.woff2)\)", block).group(1)
        name = f"{slug}-{weight}{'i' if style == 'italic' else ''}-{subset}.woff2"
        (OUT / name).write_bytes(get(url))
        print(name, "|", re.search(r"unicode-range: ([^;]+);", block).group(1))
```

Then:

```bash
curl -sL https://raw.githubusercontent.com/adobe-fonts/source-serif/release/LICENSE.md -o priv/static_site/fonts/OFL-SourceSerif4.txt
curl -sL https://raw.githubusercontent.com/rsms/inter/master/LICENSE.txt -o priv/static_site/fonts/OFL-Inter.txt
ls -l priv/static_site/fonts && du -cb priv/static_site/fonts/*.woff2 | tail -1
```

Expected: ten `.woff2` files named `source-serif-4-{400,600,400i}-latin{,-ext}.woff2` and `inter-{400,600}-latin{,-ext}.woff2`, two licence files, total woff2 ≤ 300,000 bytes. If over, delete `inter-*-latin-ext.woff2` (the interface is English) and their two `@font-face` rules below. If the sandbox blocks the network, stop and ask the user to run these two commands.

- [ ] **Step 5: Write the stylesheet and the first `site.js`**

`priv/static_site/style.css`. If the script printed different `unicode-range` values, use the printed ones.

```css
/* EMOTHE static edition. Spec: docs/superpowers/specs/2026-10-02-static-site-redesign-design.md
   Every colour is a token with a dark counterpart; nothing loads from another host. */

@font-face { font-family: "Source Serif 4"; font-style: normal; font-weight: 400; font-display: swap;
  src: url(fonts/source-serif-4-400-latin.woff2) format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: "Source Serif 4"; font-style: normal; font-weight: 400; font-display: swap;
  src: url(fonts/source-serif-4-400-latin-ext.woff2) format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: "Source Serif 4"; font-style: normal; font-weight: 600; font-display: swap;
  src: url(fonts/source-serif-4-600-latin.woff2) format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: "Source Serif 4"; font-style: normal; font-weight: 600; font-display: swap;
  src: url(fonts/source-serif-4-600-latin-ext.woff2) format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: "Source Serif 4"; font-style: italic; font-weight: 400; font-display: swap;
  src: url(fonts/source-serif-4-400i-latin.woff2) format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: "Source Serif 4"; font-style: italic; font-weight: 400; font-display: swap;
  src: url(fonts/source-serif-4-400i-latin-ext.woff2) format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: Inter; font-style: normal; font-weight: 400; font-display: swap;
  src: url(fonts/inter-400-latin.woff2) format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: Inter; font-style: normal; font-weight: 400; font-display: swap;
  src: url(fonts/inter-400-latin-ext.woff2) format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: Inter; font-style: normal; font-weight: 600; font-display: swap;
  src: url(fonts/inter-600-latin.woff2) format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
@font-face { font-family: Inter; font-style: normal; font-weight: 600; font-display: swap;
  src: url(fonts/inter-600-latin-ext.woff2) format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }

:root {
  color-scheme: light;
  --paper: #fbfbf9; --raised: #ffffff; --ink: #1b2430; --ink-2: #4b5563; --muted: #6b7684; --faint: #9aa3ae;
  --hair: #e3e6ea; --hair-2: #eef0f2; --accent: #1f3a5f; --mark: #e4ecf6;
  --f-romance: #2f66a8; --f-spanish: #cf6a3a; --f-italianate: #22a07a; --f-other: #a3abb5;
  --serif: "Source Serif 4", Georgia, "Times New Roman", serif;
  --sans: Inter, system-ui, -apple-system, "Segoe UI", sans-serif;
  --gutter: 3.2rem; --margin: 7rem;
}
@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
    --paper: #121519; --raised: #181c21; --ink: #e6e8eb; --ink-2: #b9c1cb; --muted: #98a2ae; --faint: #717b88;
    --hair: #2a3038; --hair-2: #20252b; --accent: #9dbbe3; --mark: #23344d;
    --f-romance: #4f84cf; --f-spanish: #d2703f; --f-italianate: #24a07a; --f-other: #717b88;
  }
}

*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 400 1.0625rem/1.6 var(--serif); }
a { color: var(--accent); text-underline-offset: .15em; }
h1, h2, h3 { line-height: 1.2; }
h1 { font-size: 2rem; font-weight: 600; margin: .1rem 0 .4rem; }
h2 { font-size: 1.25rem; font-weight: 600; margin: 2.25rem 0 .5rem; }
.lede, .note { font: .8125rem/1.5 var(--sans); color: var(--muted); }
.sr-only { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

/* Top bar */
.bar { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: .5rem 1.5rem;
  padding: .85rem clamp(1rem, 4vw, 2rem); border-bottom: 1px solid var(--hair);
  font-variant: all-small-caps; letter-spacing: .08em; font-size: 1.125rem; }
.wordmark { font-weight: 600; letter-spacing: .16em; color: var(--accent); text-decoration: none; }
.bar nav { display: flex; gap: 1.5rem; }
.bar nav a { color: var(--muted); text-decoration: none; }
.bar nav a[aria-current="page"] { color: var(--accent); border-bottom: 1px solid currentColor; }

/* Frame, rail, footer */
.frame { display: grid; grid-template-columns: minmax(0, 1fr); }
.rail { border-bottom: 1px solid var(--hair); padding: .75rem clamp(1rem, 4vw, 2rem); font: .8125rem/1.5 var(--sans); color: var(--ink-2); }
.rail > summary { cursor: pointer; font-weight: 600; color: var(--accent); }
.rail h2 { font: 600 .6875rem var(--sans); text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin: 1.25rem 0 .5rem; }
.rail ul { list-style: none; margin: 0; padding: 0; }
.rail li { padding: .15rem 0; }
.rail ul ul { padding-left: .75rem; }
.rail a { color: var(--ink-2); text-decoration: none; }
.rail a[aria-current="page"] { color: var(--accent); font-weight: 600; box-shadow: inset 2px 0 var(--accent); padding-left: .5rem; margin-left: -.625rem; }
@media (min-width: 960px) {
  .frame.with-rail { grid-template-columns: 13.5rem minmax(0, 1fr); }
  .rail { border-bottom: 0; border-right: 1px solid var(--hair); padding: 1.5rem 1.25rem; position: sticky; top: 0; align-self: start; max-height: 100vh; overflow: auto; }
  .rail > summary { display: none; }
  .rail h2:first-of-type { margin-top: 0; }
}
main { padding: 1.75rem clamp(1rem, 4vw, 2.75rem) 3rem; min-width: 0; }
.foot { border-top: 1px solid var(--hair); padding: 1.25rem clamp(1rem, 4vw, 2rem) 2rem; font: .75rem/1.6 var(--sans); color: var(--muted); }
.foot p { margin: .2rem 0; }

/* Reading tools */
.tools label { display: flex; gap: .5rem; align-items: center; padding: .15rem 0; }
.seg { display: inline-flex; border: 1px solid var(--hair); border-radius: 6px; overflow: hidden; }
.seg button { font: inherit; border: 0; background: var(--raised); color: var(--ink-2); padding: .25rem .7rem; cursor: pointer; }
.seg button[aria-pressed="true"] { background: var(--accent); color: var(--paper); }
.tools select { font: inherit; width: 100%; padding: .25rem; border: 1px solid var(--hair); border-radius: 6px; background: var(--raised); color: var(--ink); }

/* Title page */
.title-page { max-width: 44rem; }
.title-page ul { padding-left: 1.1rem; }
.author { font: .875rem var(--sans); color: var(--muted); margin: 0; }
.original-title { font-style: italic; color: var(--ink-2); margin: 0; }
.facts { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: .35rem 1.25rem; margin: 1.5rem 0; padding: 1rem 0; border-block: 1px solid var(--hair); font-size: .9375rem; }
.facts dt { font: 600 .6875rem/2 var(--sans); text-transform: uppercase; letter-spacing: .08em; color: var(--muted); }
.facts dd { margin: 0; }
.facts .note { display: block; }
.role { font: .8125rem var(--sans); color: var(--muted); }
.cast { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: .2rem 1rem; }
.cast dt { font: 600 .75rem/1.9 var(--sans); letter-spacing: .06em; text-transform: uppercase; color: var(--accent); }
.cast dd { margin: 0; color: var(--ink-2); }
.cite p { padding: .75rem 1rem; background: var(--raised); border: 1px solid var(--hair); border-radius: 6px; font-size: .9375rem; }
.copy, .more { font: .8125rem var(--sans); color: var(--accent); background: none; border: 1px solid var(--hair); border-radius: 6px; padding: .3rem .8rem; cursor: pointer; }

/* Play pages */
.play-head { margin-bottom: 1rem; }
.play-head h1 { font-size: 1.75rem; margin: 0; }
.play-head h1 a { color: inherit; text-decoration: none; }
.pager { display: flex; justify-content: space-between; gap: 1rem; margin: 1rem 0; font: .8125rem var(--sans); max-width: 44rem; }
.pager a[rel="next"] { margin-left: auto; }
.text { max-width: 44rem; }
.act-head { font: 600 .75rem var(--sans); text-transform: uppercase; letter-spacing: .1em; color: var(--accent); border-bottom: 1px solid var(--hair); padding-bottom: .4rem; margin: 2rem 0 1rem; }
.scene-head { font: italic 400 1rem var(--serif); color: var(--ink-2); margin: 1.5rem 0 .5rem var(--gutter); }
.sp { margin: .75rem 0; }
.spk { margin: 0 0 .1rem var(--gutter); font: 600 .6875rem/1.6 var(--sans); letter-spacing: .06em; text-transform: uppercase; color: var(--accent); }
.lg + .lg { margin-top: .55rem; }
.l { display: grid; grid-template-columns: var(--gutter) minmax(0, 1fr) var(--margin); align-items: baseline; scroll-margin-top: 1rem; }
.l:target, .pr:target, .sd:target { background: var(--mark); }
.l .n { grid-column: 1; text-align: right; padding-right: 1.1rem; font: .6875rem/1 var(--sans); color: var(--faint); text-decoration: none; font-variant-numeric: tabular-nums; }
.l .t { grid-column: 2; }
.l.indent .t { padding-left: 2em; }
.l .margin { grid-column: 3; padding-left: 1rem; font: italic .6875rem/1.3 var(--sans); color: var(--faint); }
.l .margin > * { display: block; }
.ghost { visibility: hidden; }
.sd { margin: .6rem var(--margin) .6rem var(--gutter); font-style: italic; color: var(--ink-2); }
.pr { margin: .2rem var(--margin) .5rem var(--gutter); }
body[data-ln="5"] .l .n:not(.m5), body[data-ln="off"] .l .n { visibility: hidden; }
body[data-sd="off"] .sd { display: none; }
body[data-vf="off"] .l .vf { display: none; }

/* Statistics */
.tiles { display: flex; flex-wrap: wrap; margin: 1.25rem 0 .5rem; padding: .25rem 0; border-block: 1px solid var(--hair); }
.tiles > div { display: flex; flex-direction: column-reverse; padding: .6rem 1.5rem .6rem 0; }
.tiles dt { font: .75rem var(--sans); color: var(--muted); }
.tiles dd { margin: 0; font-size: 1.6rem; font-weight: 600; line-height: 1.1; }
.band { display: flex; gap: 2px; height: 2.1rem; margin: .5rem 0 .25rem; }
.band .seg { min-width: 2px; border-radius: 3px; display: flex; align-items: center; padding-left: .35rem; overflow: hidden; }
.band .seg span { font: 600 .625rem var(--sans); color: #fff; white-space: nowrap; }
.band .sep { flex: none; width: 0; border-left: 1px dashed var(--faint); margin: 0 3px; }
.f-romance { background: var(--f-romance); }
.f-spanish { background: var(--f-spanish); }
.f-italianate { background: var(--f-italianate); }
.f-other { background: var(--f-other); }
.legend { display: flex; flex-wrap: wrap; gap: .4rem 1.25rem; list-style: none; padding: 0; margin: .75rem 0 1rem; font: .8125rem var(--sans); color: var(--ink-2); }
.legend b { color: var(--ink); font-weight: 600; }
i.sw { display: inline-block; width: .65rem; height: .65rem; border-radius: 2px; margin-right: .4rem; vertical-align: -.05rem; }
main table { border-collapse: collapse; width: 100%; font: .8125rem/1.4 var(--sans); }
main thead th { text-align: left; font-weight: 600; font-size: .6875rem; text-transform: uppercase; letter-spacing: .07em; color: var(--muted); padding: .35rem .5rem; border-bottom: 1px solid var(--hair); }
main tbody th { text-align: left; font: 600 .9rem var(--serif); color: var(--ink); padding: .3rem .5rem; border-bottom: 1px solid var(--hair-2); }
main td { padding: .3rem .5rem; border-bottom: 1px solid var(--hair-2); }
.num { text-align: right; font-variant-numeric: tabular-nums; }
.share { min-width: 9rem; white-space: nowrap; }
.track { display: inline-block; width: calc(100% - 3rem); height: .5rem; background: var(--hair-2); border-radius: 2px; vertical-align: middle; margin-right: .4rem; }
.track > span { display: block; height: 100%; background: var(--accent); border-radius: 2px; }
.scroll { overflow-x: auto; }
.matrix { width: auto; }
.matrix thead th, .matrix td.c { padding: 2px; border: 0; }
.matrix td.c::before { content: ""; display: block; width: 1.1rem; height: .85rem; border-radius: 2px; background: var(--hair-2); }
.matrix td.c.on::before { background: var(--accent); }
.matrix .act-start { padding-left: .6rem; }
.matrix thead i.sw { display: block; width: 1.1rem; height: .3rem; margin: 0 auto; }

/* Catalogue */
.controls { display: flex; flex-wrap: wrap; gap: .75rem; align-items: center; margin: 1rem 0; font: .8125rem var(--sans); color: var(--muted); }
.controls input[type="search"] { flex: 1 1 16rem; font: .875rem var(--sans); padding: .5rem .75rem; border: 1px solid var(--hair); border-radius: 6px; background: var(--raised); color: var(--ink); }
.works { list-style: none; margin: 0; padding: 0; max-width: 48rem; }
.work { padding: .85rem 0; border-top: 1px solid var(--hair-2); }
.entry { display: flex; flex-wrap: wrap; align-items: baseline; gap: .15rem .6rem; }
.entry-title { color: var(--ink); text-decoration: none; }
.entry-title.lead { font-size: 1.2rem; font-weight: 600; }
.entry .author { flex-basis: 100%; font: .875rem var(--serif); color: var(--ink-2); }
.entry .meta { margin-left: auto; font: .75rem var(--sans); color: var(--muted); }
.tag { font: 600 .625rem/1.5 var(--sans); letter-spacing: .06em; text-transform: uppercase; color: var(--accent); border: 1px solid var(--hair); border-radius: 4px; padding: 0 .3rem; min-width: 2.1em; text-align: center; }
.code { font: .6875rem var(--sans); color: var(--faint); font-variant-numeric: tabular-nums; }
.translations { list-style: none; margin: .4rem 0 0 1.1rem; padding: 0; font-size: .9375rem; }
.facet { border: 0; margin: 0 0 1rem; padding: 0; }
.facet legend { font: 600 .6875rem var(--sans); text-transform: uppercase; letter-spacing: .08em; color: var(--muted); padding: 0; margin-bottom: .35rem; }
.facet label { display: flex; align-items: center; gap: .4rem; padding: .1rem 0; cursor: pointer; }
.facet .count { margin-left: auto; color: var(--faint); font-variant-numeric: tabular-nums; }
.facet input:checked + span { color: var(--accent); font-weight: 600; }

/* Search */
[data-search-form] { display: flex; flex-wrap: wrap; gap: .5rem .75rem; align-items: center; margin: 1rem 0; max-width: 48rem; }
[data-search-form] input[type="search"] { flex: 1 1 18rem; font: 1.125rem var(--serif); padding: .55rem .9rem; border: 1px solid var(--faint); border-radius: 8px; background: var(--raised); color: var(--ink); }
.mode { display: flex; gap: .75rem; border: 0; margin: 0; padding: 0; font: .8125rem var(--sans); color: var(--ink-2); }
[data-search-form] button { font: 600 .875rem var(--sans); background: var(--accent); color: var(--paper); border: 0; border-radius: 6px; padding: .55rem 1rem; cursor: pointer; }
.group { border-top: 1px solid var(--hair); padding: .75rem 0; max-width: 48rem; }
.group h2 { margin: 0; font-size: 1.125rem; font-style: italic; }
.group-meta { margin: .1rem 0 .4rem; font: .75rem var(--sans); color: var(--muted); }
.hits { list-style: none; margin: 0; padding: 0; }
.hit { display: grid; grid-template-columns: 5.5rem 8rem minmax(0, 1fr); gap: .75rem; align-items: baseline; padding: .15rem 0; }
.hit .ref { font: .75rem var(--sans); color: var(--muted); font-variant-numeric: tabular-nums; }
.hit .spk { margin: 0; }
.hit .stage { font-style: italic; color: var(--ink-2); }
mark { background: var(--mark); color: var(--accent); font-weight: 600; padding: 0 .1em; border-radius: 2px; }

@media (max-width: 600px) {
  :root { --gutter: 2.4rem; --margin: 0rem; }
  .l .margin { display: none; }
  .hit { grid-template-columns: 4.5rem minmax(0, 1fr); }
  .hit .spk { display: none; }
}

@media print {
  body { background: #fff; color: #000; font-size: 11pt; }
  .bar, .rail, .pager, .foot, .tools, .controls { display: none !important; }
  .frame { display: block; }
  main { padding: 0; }
  .l .n.m5 { visibility: visible !important; }
  .l .n:not(.m5) { visibility: hidden !important; }
  .division + .division { break-before: page; }
  .sp, .l { break-inside: avoid; }
  a { color: inherit; text-decoration: none; }
}
```

`priv/static_site/site.js`:

```js
/* EMOTHE static edition: progressive enhancement only. Every page reads fine without it. */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};

  if (!root.document) return;

  document.addEventListener('DOMContentLoaded', function () {
    // The rail is open in the markup so it shows without JS; on a narrow screen it
    // starts closed once JS is here to open it.
    if (root.matchMedia && root.matchMedia('(max-width: 959px)').matches) {
      document.querySelectorAll('details.rail').forEach(function (d) { d.open = false; });
    }
  });
})(typeof window !== 'undefined' ? window : globalThis);
```

(`E` is used from Task 6 on; until then the `var E` line is harmless.)

- [ ] **Step 6: Create `Edition`, `Pages`, `Components` and the two templates**

`lib/playcode/export/static_site/edition.ex`:

```elixir
defmodule Playcode.Export.StaticSite.Edition do
  @moduledoc """
  One play prepared for the static site: which page each division goes on, the
  anchor and citation reference of every line, the ghost text that aligns a split
  verse, and where each metrical passage starts. The pages and the search index both
  read it, so a line's address is decided once.
  """

  alias Playcode.{Catalogue, PlayContent, Statistics}
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Statistics.Metrics

  defstruct [
    :play,
    :characters,
    :divisions,
    :stats,
    :pages,
    :items,
    :anchors,
    :refs,
    :ghosts,
    :passage_starts,
    :page_of
  ]

  @doc "Loads play `id` and everything the site derives from it."
  def load(id) do
    divisions = PlayContent.load_play_content(id)
    items = Metrics.items(divisions)
    pages = pages(divisions)

    %__MODULE__{
      play: Catalogue.get_play_with_all!(id),
      characters: PlayContent.list_characters(id),
      divisions: divisions,
      stats: Statistics.get_statistics(id).data,
      pages: pages,
      items: items,
      anchors: anchors(items, pages),
      refs: refs(items),
      ghosts: ghosts(items),
      passage_starts: passage_starts(Metrics.passages(items)),
      page_of: page_of(pages, items)
    }
  end

  @doc "Each page with the pages before and after it: `{page, previous, next}`."
  def neighbours(pages), do: Enum.zip([pages, [nil | pages], Enum.drop(pages, 1) ++ [nil]])

  @doc "An act number in Roman numerals."
  def roman(n) do
    [{10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}]
    |> Enum.reduce({n, ""}, fn {value, numeral}, {left, acc} ->
      {rem(left, value), acc <> String.duplicate(numeral, div(left, value))}
    end)
    |> elem(1)
  end

  # Every top-level division with text gets a page: acts are act-N by their ordinal
  # among all acts, as in the statistics; anything else is named by its type, with
  # -2, -3 for repeats. The cast list goes on the title page.
  defp pages(divisions) do
    {pages, _counts} =
      Enum.map_reduce(divisions, %{}, fn division, counts ->
        base = if division.type in Metrics.act_types(), do: "act", else: division.type
        n = Map.get(counts, base, 0) + 1
        slug = if base == "act" or n > 1, do: "#{base}-#{n}", else: base
        title = division.title || String.capitalize(division.type)
        {%{slug: slug, title: title, division: division}, Map.put(counts, base, n)}
      end)

    Enum.reject(pages, &(&1.division.type == "elenco" or empty?(&1.division)))
  end

  defp empty?(division),
    do: division.loaded_elements == [] and Enum.all?(division.children, &(&1.loaded_elements == []))

  defp page_of(pages, items) do
    slug_of = Map.new(pages, &{&1.division.id, &1.slug})

    for item <- items, Map.has_key?(slug_of, item.division.id), into: %{} do
      {item.element.id, slug_of[item.division.id]}
    end
  end

  # A verse is `l<number>`. A play that numbers each scene from 1 gets
  # `l<act>-<scene>-<number>`; anything without a number is `p<n>`, counted through
  # the play. A clash left after that (a data error) gets a numeric suffix.
  defp anchors(items, pages) do
    restarts? = restarts?(items)

    {elements, _state} =
      Enum.map_reduce(items, {MapSet.new(), 0}, fn item, {used, p} ->
        {base, p} =
          case item.element.line_number do
            n when is_integer(n) and restarts? -> {"l#{item.act || 0}-#{scene_ordinal(item)}-#{n}", p}
            n when is_integer(n) -> {"l#{n}", p}
            nil -> {"p#{p + 1}", p + 1}
          end

        anchor = unique(base, used, 1)
        {{item.element.id, anchor}, {MapSet.put(used, anchor), p}}
      end)

    divisions =
      Enum.flat_map(pages, fn page ->
        scenes = Enum.map(page.division.children, &{&1.id, "#{page.slug}-s#{&1.position + 1}"})
        [{page.division.id, page.slug} | scenes]
      end)

    Map.new(elements ++ divisions)
  end

  defp unique(base, used, 1), do: if(MapSet.member?(used, base), do: unique(base, used, 2), else: base)

  defp unique(base, used, k) do
    candidate = "#{base}-#{k}"
    if MapSet.member?(used, candidate), do: unique(base, used, k + 1), else: candidate
  end

  defp restarts?(items) do
    numbers = for %{element: %{line_number: n}} when is_integer(n) <- items, do: n
    length(numbers) != length(Enum.uniq(numbers))
  end

  defp scene_ordinal(%{scene: nil}), do: 0
  defp scene_ordinal(%{scene: scene}), do: scene.position + 1

  # How a line is cited in search results: "II, 1236"; "II.3, 45" when the play
  # numbers each scene from 1; the division alone for prose and stage directions.
  defp refs(items) do
    restarts? = restarts?(items)

    Map.new(items, fn item ->
      where = where(item)
      where = if restarts? and item.scene, do: "#{where}.#{scene_ordinal(item)}", else: where
      {item.element.id, if(item.number, do: "#{where}, #{item.number}", else: where)}
    end)
  end

  defp where(%{act: act}) when is_integer(act), do: roman(act)
  defp where(%{division: division}), do: division.title || String.capitalize(division.type)

  # The text of a split verse's earlier fragments, rendered invisible before an M or
  # F fragment so it starts where the previous fragment ended.
  defp ghosts(items) do
    {ghosts, _open} =
      items
      |> Enum.filter(&(&1.kind == :verse))
      |> Enum.reduce({%{}, []}, fn %{element: el}, {ghosts, open} ->
        text = InlineMarkup.plain(el.content)

        case el.part do
          "I" ->
            {ghosts, [text]}

          part when part in ["M", "F"] and open != [] ->
            ghosts = Map.put(ghosts, el.id, open |> Enum.reverse() |> Enum.join(" "))
            {ghosts, if(part == "M", do: [text | open], else: [])}

          _ ->
            {ghosts, []}
        end
      end)

    ghosts
  end

  defp passage_starts(passages) do
    for %{form: form, element_ids: [first | _]} <- passages, form != "unmarked", into: %{} do
      {first, form}
    end
  end
end
```

`lib/playcode/export/static_site/pages.ex`:

```elixir
defmodule Playcode.Export.StaticSite.Pages do
  @moduledoc """
  The static site's page templates (`pages/*.html.heex`), rendered to strings. HEEx
  escapes every interpolation, which is why the site is no longer built by string
  concatenation.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.Components
  alias PlaycodeWeb.PlayLabels

  embed_templates "pages/*"

  @doc "Renders page template `name` (`:title`, `:division`, …) with `assigns` to HTML."
  def render(name, assigns) do
    __MODULE__
    |> apply(name, [Map.put(assigns, :__changed__, nil)])
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> strip_annotations()
  end

  @doc """
  Removes the source-path comments and `data-phx-loc` attributes that dev compiles
  into HEEx (`config/dev.exs`), so an archive generated on a laptop carries no paths.
  """
  def strip_annotations(html) do
    html
    |> String.replace(~r/<!-- (?:<\/?[^>]+>|@caller)[^>]*-->/, "")
    |> String.replace(~r/ data-phx-loc="\d+"/, "")
  end
end
```

`lib/playcode/export/static_site/components.ex`:

```elixir
defmodule Playcode.Export.StaticSite.Components do
  @moduledoc """
  The pieces the static site's pages are built from. Plain semantic HTML: the classes
  belong to `priv/static_site/style.css`, and the `data-*` attributes are the hooks
  `site.js` and `search.js` enhance.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
  alias PlaycodeWeb.PlayLabels

  attr :root, :string, required: true, doc: ~s(path from the page to the site root: "" or "../../")
  attr :title, :string, required: true
  attr :site, :map, required: true
  attr :current, :atom, default: nil
  attr :rail_label, :string, default: "Contents & tools"
  slot :rail
  slot :inner_block, required: true

  def shell(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <link
          rel="preload"
          href={@root <> "assets/fonts/source-serif-4-400-latin.woff2"}
          as="font"
          type="font/woff2"
          crossorigin
        />
        <link rel="stylesheet" href={@root <> "assets/style.css"} />
        <script src={@root <> "assets/site.js"} defer>
        </script>
      </head>
      <body data-ln="5">
        <header class="bar">
          <a class="wordmark" href={@root <> "index.html"}>EMOTHE</a>
          <nav aria-label="Site">
            <a href={@root <> "index.html"} aria-current={@current == :catalogue && "page"}>catalogue</a>
            <a href={@root <> "search.html"} aria-current={@current == :search && "page"}>search</a>
            <a href={@root <> "about.html"} aria-current={@current == :about && "page"}>about</a>
          </nav>
        </header>
        <div class={["frame", @rail != [] && "with-rail"]}>
          <details :if={@rail != []} class="rail" open>
            <summary>{@rail_label}</summary>
            {render_slot(@rail)}
          </details>
          <main id="main">{render_slot(@inner_block)}</main>
        </div>
        <footer class="foot">
          <p>EMOTHE · version {@site.version} · built {@site.build_date}</p>
          <p>
            A static edition following the
            <a href="https://endings.uvic.ca/principles.html">Endings principles</a>; every play's TEI-XML source is published beside it.
          </p>
        </footer>
      </body>
    </html>
    """
  end

  attr :edition, :map, required: true
  attr :current, :string, required: true

  def play_rail(assigns) do
    ~H"""
    <nav aria-label="Contents">
      <h2>Contents</h2>
      <.play_contents edition={@edition} current={@current} />
    </nav>
    """
  end

  attr :edition, :map, required: true
  attr :current, :string, default: nil
  attr :all_scenes, :boolean, default: false

  def play_contents(assigns) do
    ~H"""
    <ul>
      <li><a href="index.html" aria-current={@current == "index" && "page"}>Title page</a></li>
      <li :for={page <- @edition.pages}>
        <a href={page.slug <> ".html"} aria-current={@current == page.slug && "page"}>{page.title}</a>
        <ul :if={(@all_scenes or @current == page.slug) and page.division.children != []}>
          <li :for={scene <- page.division.children}>
            <a href={"#{page.slug}.html##{@edition.anchors[scene.id]}"}>
              {scene.title || "Scene #{scene.position + 1}"}
            </a>
          </li>
        </ul>
      </li>
      <li><a href="text.html" aria-current={@current == "text" && "page"}>Full text</a></li>
      <li>
        <a href="statistics.html" aria-current={@current == "statistics" && "page"}>Statistics</a>
      </li>
    </ul>
    """
  end

  attr :play, :map, required: true

  def study(assigns) do
    ~H"""
    <%= if @play.historical_time do %>
      <dt>Historical time</dt>
      <dd>
        {PlayLabels.historical_time_label(@play.historical_time)}
        <span :if={@play.historical_time_note} class="note">{@play.historical_time_note}</span>
      </dd>
    <% end %>
    <%= if @play.composition_date_from || @play.composition_date_note do %>
      <dt>Composition</dt>
      <dd>
        {composition_years(@play)}
        <span :if={@play.composition_date_note} class="note">{@play.composition_date_note}</span>
      </dd>
    <% end %>
    """
  end

  attr :play, :map, required: true
  attr :published, :any, required: true

  def family(assigns) do
    published? = &(&1 && MapSet.member?(assigns.published, &1.code))

    assigns =
      assign(assigns,
        original: if(published?.(assigns.play.parent_play), do: assigns.play.parent_play),
        translations: Enum.filter(assigns.play.derived_plays, published?)
      )

    ~H"""
    <section :if={@original || @translations != []}>
      <h2>Work family</h2>
      <p :if={@original}>
        Translation of <a href={"../#{@original.code}/index.html"}><cite>{@original.title}</cite></a>
      </p>
      <ul :if={@translations != []}>
        <li :for={translation <- @translations}>
          <a href={"../#{translation.code}/index.html"}><cite>{translation.title}</cite></a>
          <span class="role">{Play.language_name(translation.language)}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :play, :map, required: true

  def places(assigns) do
    assigns = assign(assigns, :links, place_links(assigns.play))

    ~H"""
    <section :if={@links != []}>
      <h2>Places</h2>
      <ul>
        <li :for={{name, mentioned?, note} <- @links}>
          {name}<span :if={mentioned?} class="role"> (mentioned)</span><span :if={note}> — {note}</span>
        </li>
      </ul>
    </section>
    """
  end

  defp place_links(%{play_places: [_ | _] = links}) do
    gazetteer = Playcode.Places.gazetteer()

    links
    |> Enum.sort_by(&{&1.role != "setting", &1.position})
    |> Enum.map(&{Playcode.Places.breadcrumb(&1.place, gazetteer, "es"), &1.role == "mentioned", &1.note})
  end

  defp place_links(_play), do: []

  @doc "The cast as published: every character not marked hidden."
  def cast(characters), do: Enum.reject(characters, & &1.is_hidden)

  @doc "What the title page says about the play's form, from the computed verse count."
  def form_summary(%{"verses" => n}) when is_integer(n) and n > 0, do: "Verse · #{number(n)} verses"
  def form_summary(_stats), do: "Prose"

  @doc "An integer with its thousands separated by commas."
  def number(nil), do: "0"

  def number(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  def source_text(source) do
    [source.author, source.title, source.editor, source.pub_place, source.publisher, source.pub_date, source.note]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(". ")
  end

  def paragraphs(nil), do: []
  def paragraphs(text), do: String.split(text, ~r/\n\s*\n/, trim: true)

  def note_heading("dedicatoria"), do: "Dedication"
  def note_heading("introduccion_editor"), do: "Editor's introduction"
  def note_heading("argumento"), do: "Argument"
  def note_heading("prologo"), do: "Prologue"
  def note_heading(_other), do: "Note"

  @doc "The citation shown on the title page; JS adds the page's URL when copying."
  def citation(play, site) do
    editors = for e <- play.editors, e.role in ~w(editor critical_editor), do: e.person_name

    [
      play.author_name,
      play.title,
      editors != [] && "ed. " <> Enum.join(editors, ", "),
      "EMOTHE, version #{site.version} (#{String.slice(site.build_date, 0, 4)})"
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(". ")
    |> Kernel.<>(".")
  end

  def composition_years(%{composition_date_from: nil}), do: nil

  def composition_years(%{composition_date_from: from, composition_date_to: to}) when to in [nil, from],
    do: "#{from}"

  def composition_years(%{composition_date_from: from, composition_date_to: to}), do: "#{from}–#{to}"
end
```

`lib/playcode/export/static_site/pages/title.html.heex`:

```heex
<Components.shell root="../../" title={"#{@edition.play.title} — EMOTHE"} site={@site}>
  <:rail><Components.play_rail edition={@edition} current="index" /></:rail>
  <article class="title-page">
    <p class="author">{@edition.play.author_name}</p>
    <h1>{@edition.play.title}</h1>
    <p :if={@edition.play.original_title not in [nil, @edition.play.title]} class="original-title">
      {@edition.play.original_title}
    </p>
    <dl class="facts">
      <dt>Code</dt>
      <dd>{@edition.play.code}</dd>
      <dt>Language</dt>
      <dd>{Play.language_name(@edition.play.language)}</dd>
      <dt>Form</dt>
      <dd>{Components.form_summary(@edition.stats)}</dd>
      <Components.study play={@edition.play} />
    </dl>
    <Components.family play={@edition.play} published={@site.published} />
    <Components.places play={@edition.play} />
    <section :if={@edition.play.editors != []}>
      <h2>Edition</h2>
      <ul>
        <li :for={editor <- @edition.play.editors}>
          {editor.person_name} <span class="role">{PlayLabels.editor_role_label(editor.role)}</span>
        </li>
      </ul>
    </section>
    <section :if={@edition.play.sources != []}>
      <h2>Sources</h2>
      <ul>
        <li :for={source <- @edition.play.sources}>{Components.source_text(source)}</li>
      </ul>
    </section>
    <section :for={note <- @edition.play.editorial_notes}>
      <h2>{note.heading || Components.note_heading(note.section_type)}</h2>
      <p :for={paragraph <- Components.paragraphs(note.content)}>{paragraph}</p>
    </section>
    <section :if={Components.cast(@edition.characters) != []}>
      <h2>Dramatis personae</h2>
      <dl class="cast">
        <%= for character <- Components.cast(@edition.characters) do %>
          <dt>{character.name}</dt>
          <dd>{character.description}</dd>
        <% end %>
      </dl>
    </section>
    <section>
      <h2>Contents</h2>
      <Components.play_contents edition={@edition} all_scenes />
    </section>
    <section class="cite">
      <h2>Cite this edition</h2>
      <p data-citation>{Components.citation(@edition.play, @site)}</p>
    </section>
    <p :if={@edition.play.licence_text || @edition.play.licence_url} class="lede">
      {@edition.play.licence_text}
      <a :if={@edition.play.licence_url} href={@edition.play.licence_url}>
        {@edition.play.licence_url}
      </a>
    </p>
    <p><a href={"#{@edition.play.code}.xml"} download>Download the TEI-XML source</a></p>
  </article>
</Components.shell>
```

`lib/playcode/export/static_site/pages/redirect.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="refresh" content={"0; url=#{@code}/index.html"} />
    <link rel="canonical" href={"#{@code}/index.html"} />
    <title>{@title}</title>
  </head>
  <body>
    <p>This page has moved: <a href={"#{@code}/index.html"}>{@title}</a>.</p>
  </body>
</html>
```

- [ ] **Step 7: Rewrite the orchestrator**

`lib/playcode/export/static_site.ex`:

```elixir
defmodule Playcode.Export.StaticSite do
  @moduledoc """
  Generates the published EMOTHE archive: HTML, CSS and JS that work from any web host
  and from the unzipped archive opened as `file://`, following the Endings Project
  principles. Design: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`.

  Only plays marked complete are published unless `all: true`. The archive is in
  English whatever locale the admin generating it uses.
  """

  alias Playcode.Catalogue
  alias Playcode.Export.TeiXml
  alias Playcode.Export.StaticSite.{Edition, Pages, Renderer, Search}

  @type progress_info :: %{
          step: :assets | :catalogue | :play,
          current: non_neg_integer(),
          total: non_neg_integer(),
          detail: String.t()
        }

  @doc """
  Generates the site.

  Options: `:output_dir` (default `"_site"`), `:play_codes` (default all), `:all`
  (include incomplete plays), `:version` (default `"1.0"`), `:build_date` (ISO date,
  default today), `:on_progress` (`fun(progress_info) -> any`).
  """
  def generate(opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      plays = load_plays(opts[:play_codes], opts[:all])
      total = length(plays)

      if plays == [] do
        {:error, "no plays to export (none marked as complete)"}
      else
        dir = opts[:output_dir]
        File.rm_rf!(dir)
        File.mkdir_p!(Path.join(dir, "plays"))

        opts[:on_progress].(%{step: :assets, current: 0, total: total, detail: "Writing assets..."})
        write_assets(dir)
        site = site(opts, MapSet.new(plays, & &1.code))

        results =
          plays
          |> Enum.with_index(1)
          |> Enum.map(fn {play, n} ->
            opts[:on_progress].(%{step: :play, current: n, total: total, detail: play.code})
            play.id |> Edition.load() |> write_play(dir, site)
          end)

        opts[:on_progress].(%{step: :catalogue, current: 0, total: total, detail: "Generating catalogue..."})
        write_index_pages(plays, results, dir, opts)

        {:ok, %{plays: total, size: dir_size(dir), output_dir: dir}}
      end
    end)
  end

  @doc "Exports one play into an existing site, then rebuilds the catalogue and index."
  def generate_single_play(play_id, opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      File.mkdir_p!(Path.join(dir, "plays"))

      edition = Edition.load(play_id)
      published = MapSet.new([edition.play.code | list_exported_codes(dir)])
      write_play(edition, dir, site(opts, published))
      rebuild_index(opts)
      :ok
    end)
  end

  @doc "Removes one play from an existing site, then rebuilds the catalogue and index."
  def remove_single_play(code, opts \\ []) do
    dir = Keyword.get(opts, :output_dir, "_site")
    File.rm_rf!(Path.join([dir, "plays", code]))
    File.rm(Path.join([dir, "plays", "#{code}.html"]))
    rebuild_index(opts)
    :ok
  end

  @doc "Rebuilds the catalogue, about, search pages and search index from the plays on disk."
  def rebuild_index(opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      codes = list_exported_codes(dir)
      plays = Catalogue.list_plays(sort: :title_sort) |> Enum.filter(&(&1.code in codes))

      File.mkdir_p!(dir)
      write_assets(dir)
      write_index_pages(plays, Enum.map(plays, fn _ -> %{} end), dir, opts)
    end)
  end

  @doc "Codes of the plays the site holds: folders under `plays/` with an `index.html`."
  def list_exported_codes(output_dir \\ "_site") do
    plays_dir = Path.join(output_dir, "plays")

    if File.dir?(plays_dir) do
      plays_dir
      |> File.ls!()
      |> Enum.filter(&File.regular?(Path.join([plays_dir, &1, "index.html"])))
      |> Enum.sort()
    else
      []
    end
  end

  defp in_english(fun), do: Gettext.with_locale(PlaycodeWeb.Gettext, "en", fun)

  defp defaults(opts) do
    defaults = [
      output_dir: "_site",
      version: "1.0",
      build_date: Date.to_iso8601(Date.utc_today()),
      on_progress: fn _ -> :ok end,
      all: false
    ]

    Keyword.merge(defaults, Enum.reject(opts, fn {_key, value} -> is_nil(value) end))
  end

  defp site(opts, published) do
    %{
      version: opts[:version],
      build_date: opts[:build_date],
      published: published,
      play_count: MapSet.size(published)
    }
  end

  defp load_plays(nil, all?), do: Catalogue.list_plays(sort: :title_sort, complete: !all?)

  defp load_plays(codes, all?) when is_list(codes),
    do: load_plays(nil, all?) |> Enum.filter(&(&1.code in codes))

  defp write_assets(dir) do
    assets = Path.join(dir, "assets")
    File.rm_rf!(assets)
    File.cp_r!(Application.app_dir(:playcode, "priv/static_site"), assets)
  end

  # Writes one play's pages and TEI; returns what the index pages need from it.
  defp write_play(%Edition{play: play} = edition, dir, site) do
    play_dir = Path.join([dir, "plays", play.code])
    File.rm_rf!(play_dir)
    File.mkdir_p!(play_dir)
    assigns = %{edition: edition, site: site}

    File.write!(Path.join(play_dir, "index.html"), Pages.render(:title, assigns))
    File.write!(Path.join(play_dir, "#{play.code}.xml"), TeiXml.generate(play))

    File.write!(
      Path.join([dir, "plays", "#{play.code}.html"]),
      Pages.render(:redirect, %{code: play.code, title: play.title})
    )

    %{}
  end

  # The catalogue is still the old renderer's until Task 6.
  defp write_index_pages(plays, _results, dir, opts) do
    File.write!(Path.join(dir, "index.html"), Renderer.catalogue_page(plays, opts))
    File.write!(Path.join(dir, "style.css"), Renderer.site_css())
    File.write!(Path.join(dir, "search.js"), Search.search_js())
  end

  defp dir_size(path) do
    path
    |> File.ls!()
    |> Enum.reduce(0, fn entry, acc ->
      full = Path.join(path, entry)

      case File.stat(full) do
        {:ok, %{type: :regular, size: size}} -> acc + size
        {:ok, %{type: :directory}} -> acc + dir_size(full)
        _ -> acc
      end
    end)
  end
end
```

In `renderer.ex`, in `render_catalogue_entry/1`, change `href="plays/#{escape_attr(play.code)}.xml"` to `href="plays/#{escape_attr(play.code)}/#{escape_attr(play.code)}.xml"` and `href="plays/#{escape_attr(play.code)}.html"` to `href="plays/#{escape_attr(play.code)}/index.html"`. Then delete `play_page/5` and every private function only it used (`render_sources`, `render_editors`, `render_study`, `render_historical_time`, `render_composition_date`, `composition_years`, `meta_note`, `render_places`, `render_verse_info`, `render_editorial_notes`, `render_inline_cast_list`, `do_render_inline_cast_list`, `render_division_nav`, `render_divisions`, `division_heading`, `child_heading`, `render_elements`, `render_element`, `render_characters_table`, `render_statistics`, `render_stat_cards`, `render_bar_chart`, `bar_percent`, the label helpers, and the `@act_types` attribute; `footer` stays because the catalogue uses it). `mix compile --warnings-as-errors` reports any you missed as unused.

- [ ] **Step 8: Run the tests**

Run: `mix test test/playcode/export/static_site_test.exs test/mix/tasks_test.exs`
Expected: PASS. If `mix format` reflows a HEEx template, re-run.

- [ ] **Step 9: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all pass.

```bash
git add lib/playcode/export priv/static_site test/support/static_site_helpers.ex test/playcode/export/static_site_test.exs test/mix/tasks_test.exs
git commit -m "feat: static site title pages on HEEx, one folder per play

StaticSite.Edition prepares a play once (pages, anchors, refs, split-verse
ghosts); Pages renders HEEx to strings and strips dev annotations. Plays
now live at plays/<CODE>/ with a redirect stub at the old address. Fonts
are Source Serif 4 and Inter, self-hosted with their OFL licences.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Act pages and the full text

**Files:**
- Create: `lib/playcode/export/static_site/pages/division.html.heex`, `pages/text.html.heex`
- Modify: `lib/playcode/export/static_site/components.ex` (play text components), `lib/playcode/export/static_site.ex` (`write_play/3`)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `%Edition{}` fields and `Edition.neighbours/1` (Task 3); `InlineMarkup.parts/1`, `PlayLabels.verse_form_label/1` (Task 1).
- Produces: `Components.play_header/1` (attr `play`), `Components.pager/1` (attrs `prev`, `next`), `Components.division_text/1` (attrs `edition`, `division`), `Components.inline/1` (attr `text`), `Components.cite_prefix(play, page | nil)`. Pages `plays/<CODE>/<slug>.html` and `plays/<CODE>/text.html`. Every line has `id` = its anchor; `.text` carries `data-cite`; speeches carry `data-who` (space-separated character `xml_id`s).

- [ ] **Step 1: Write the tests**

`test/playcode/export/static_site_play_test.exs`:

```elixir
defmodule Playcode.Export.StaticSitePlayTest do
  @moduledoc "A play's reading pages in the static site: one per act, the full text, statistics."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

  @two_acts """
  <div1 type="jornada" n="1"><head>Jornada I</head>
    <stage>Salen músicos cantando</stage>
    <sp><speaker>Segismundo</speaker>
      <lg type="redondilla">
        <l n="1">¡Válgame el cielo!, ¿qué veo?</l>
        <l n="2">Dulce <emph>sueño</emph> mío</l>
        <l n="3">uno &amp; &lt;script&gt;alert(1)&lt;/script&gt;</l>
        <l n="4">con mucha duda lo creo.</l>
      </lg>
      <lg type="redondilla"><l n="5">¿Yo en palacios suntuosos?</l></lg>
    </sp>
    <sp><speaker>Clarín</speaker><lg type="free" part="I"><l n="6" part="I">A mí.</l></lg></sp>
    <sp><speaker>Criado 2</speaker><lg type="free" part="F"><l part="F">Llega a hablarle ya.</l></lg></sp>
  </div1>
  <div1 type="jornada" n="2"><head>Jornada II</head>
    <sp><speaker>Clotaldo</speaker><p>Señor, despierta.</p></sp>
  </div1>
  """

  defp publish!(body) do
    play = import_tei!(tei(body: body))
    {play, generate!([play], all: true)}
  end

  defp page(dir, play, file), do: html!(dir, "plays/#{play.code}/#{file}")
  defp ids(html), do: html |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")

  test "each act has its own page, linked to the acts before and after it" do
    {play, dir} = publish!(@two_acts)
    first = page(dir, play, "act-1.html")
    second = page(dir, play, "act-2.html")

    assert first |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq() == ["act-2.html"]
    assert second |> LazyHTML.query(~s(a[rel="prev"])) |> LazyHTML.attribute("href") |> Enum.uniq() == ["act-1.html"]
    assert LazyHTML.text(first) =~ "Salen músicos cantando"
    refute LazyHTML.text(first) =~ "Señor, despierta."
    assert LazyHTML.text(second) =~ "Señor, despierta."
  end

  test "a verse is anchored by its number and keeps its italics, escaped" do
    {play, dir} = publish!(@two_acts)
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query("#l2 em") |> LazyHTML.text() == "sueño"
    assert act |> LazyHTML.query("#l2") |> LazyHTML.text() =~ "Dulce sueño mío"
    refute read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;&lt;"
    assert act |> LazyHTML.query("#l3") |> LazyHTML.text() =~ "uno & <script>alert(1)</script>"
    assert act |> LazyHTML.query("script") |> LazyHTML.attribute("src") == ["../../assets/site.js"]
  end

  test "the second half of a split verse starts where the first half ended" do
    {play, dir} = publish!(@two_acts)

    assert texts(page(dir, play, "act-1.html"), ~s([aria-hidden="true"])) == ["A mí."]
  end

  test "a verse form is named once, where its passage starts" do
    {play, dir} = publish!(@two_acts)
    text = LazyHTML.text(page(dir, play, "act-1.html"))

    assert length(String.split(text, "Redondilla")) == 2
  end

  test "the full text carries every act on one page" do
    {play, dir} = publish!(@two_acts)
    full = page(dir, play, "text.html")

    assert Enum.filter(texts(full, "h2"), &String.starts_with?(&1, "Jornada")) == ["Jornada I", "Jornada II"]
    assert LazyHTML.text(full) =~ "Señor, despierta."
  end

  test "a play that numbers each scene from 1 still gives every line its own anchor" do
    {play, dir} =
      publish!("""
      <div1 type="act" n="1"><head>Act I</head>
        <div2 type="scene" n="1"><head>Scene 1</head><sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
        <div2 type="scene" n="2"><head>Scene 2</head><sp><speaker>B</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
      </div1>
      """)

    anchors = ids(page(dir, play, "text.html"))

    assert anchors == Enum.uniq(anchors)
    assert "l1-2-1" in anchors
  end

  test "a play with no acts has no act pages; its prologue gets one named after it" do
    {play, dir} =
      publish!(~s(<div1 type="prologue"><head>Prologue</head><sp><speaker>A</speaker><l n="1">one</l></sp></div1>))

    assert File.exists?(Path.join([dir, "plays", play.code, "text.html"]))
    assert File.exists?(Path.join([dir, "plays", play.code, "prologue.html"]))
    refute File.exists?(Path.join([dir, "plays", play.code, "act-1.html"]))
  end
end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL — `act-1.html` does not exist (`File.Error`).

- [ ] **Step 3: Add the play-text components**

In `components.ex` add `alias Playcode.PlayContent.{Element, InlineMarkup}` beside the other aliases, then add:

```elixir
  attr :play, :map, required: true

  def play_header(assigns) do
    ~H"""
    <header class="play-head">
      <p class="author">{@play.author_name}</p>
      <h1><a href="index.html">{@play.title}</a></h1>
    </header>
    """
  end

  attr :prev, :map, default: nil
  attr :next, :map, default: nil

  def pager(assigns) do
    ~H"""
    <nav :if={@prev || @next} class="pager" aria-label="Acts">
      <a :if={@prev} href={@prev.slug <> ".html"} rel="prev">← {@prev.title}</a>
      <a :if={@next} href={@next.slug <> ".html"} rel="next">{@next.title} →</a>
    </nav>
    """
  end

  @doc "What a copied line link is cited as, before its verse number."
  def cite_prefix(play, page) do
    [play.author_name, play.title, page && page.title]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  attr :edition, :map, required: true
  attr :division, :map, required: true

  def division_text(assigns) do
    ~H"""
    <section class="division" id={@edition.anchors[@division.id]}>
      <h2 :if={@division.title} class="act-head">{@division.title}</h2>
      <.el :for={el <- @division.loaded_elements} el={el} edition={@edition} />
      <section :for={scene <- @division.children} id={@edition.anchors[scene.id]}>
        <h3 :if={scene.title} class="scene-head">{scene.title}</h3>
        <.el :for={el <- scene.loaded_elements} el={el} edition={@edition} />
      </section>
    </section>
    """
  end

  attr :el, :map, required: true
  attr :edition, :map, required: true

  defp el(%{el: %{type: "speech"}} = assigns) do
    assigns = assign(assigns, :who, who(assigns.el))

    ~H"""
    <div class="sp" data-who={@who}>
      <p :if={@el.speaker_label} class="spk">{@el.speaker_label}</p>
      <.el :for={child <- @el.children} el={child} edition={@edition} />
    </div>
    """
  end

  defp el(%{el: %{type: "line_group"}} = assigns) do
    ~H"""
    <div class="lg">
      <.el :for={child <- @el.children} el={child} edition={@edition} />
    </div>
    """
  end

  # One line of markup, kept from the formatter by phx-no-format (which HEEx drops from
  # the output): a newline between these spans would be a visible space.
  defp el(%{el: %{type: "verse_line"}} = assigns) do
    edition = assigns.edition

    assigns =
      assign(assigns,
        anchor: edition.anchors[assigns.el.id],
        ghost: edition.ghosts[assigns.el.id],
        form: edition.passage_starts[assigns.el.id]
      )

    ~H"""
    <div phx-no-format class={["l", @el.rend == "indent" && "indent"]} id={@anchor}><a :if={@el.line_number} class={["n", rem(@el.line_number, 5) == 0 && "m5"]} href={"#" <> @anchor}>{@el.line_number}</a><span class="t"><span :if={@ghost} class="ghost" aria-hidden="true">{@ghost} </span><.inline text={@el.content} /></span><span :if={@form || @el.is_aside} class="margin"><span :if={@form} class="vf">{PlayLabels.verse_form_label(@form)}</span><span :if={@el.is_aside} class="aparte">aparte</span></span></div>
    """
  end

  defp el(%{el: %{type: "stage_direction"}} = assigns) do
    ~H"""
    <p class="sd" id={@edition.anchors[@el.id]}><.inline text={@el.content} /></p>
    """
  end

  defp el(%{el: %{type: "prose"}} = assigns) do
    ~H"""
    <p class="pr" id={@edition.anchors[@el.id]}><.inline text={@el.content} /></p>
    """
  end

  defp el(assigns), do: ~H""

  defp who(speech) do
    case for(character <- Element.characters(speech), character.xml_id, do: character.xml_id) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  attr :text, :string, default: nil

  def inline(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text))

    ~H"""
    <%= for part <- @parts do %><%= if part.italic do %><em>{part.text}</em><% else %>{part.text}<% end %><% end %>
    """
  end
```

The empty-note slot (spec "Text rendering") is the `.l` grid's third column, `.margin`; the notes project fills it. No extra markup per line.

- [ ] **Step 4: Add the two templates**

`pages/division.html.heex`:

```heex
<Components.shell
  root="../../"
  title={"#{@page.title} — #{@edition.play.title} — EMOTHE"}
  site={@site}
>
  <:rail><Components.play_rail edition={@edition} current={@page.slug} /></:rail>
  <Components.play_header play={@edition.play} />
  <Components.pager prev={@prev} next={@next} />
  <div
    class="text"
    lang={@edition.play.language}
    data-cite={Components.cite_prefix(@edition.play, @page)}
  >
    <Components.division_text edition={@edition} division={@page.division} />
  </div>
  <Components.pager prev={@prev} next={@next} />
</Components.shell>
```

`pages/text.html.heex`:

```heex
<Components.shell root="../../" title={"#{@edition.play.title}, full text — EMOTHE"} site={@site}>
  <:rail><Components.play_rail edition={@edition} current="text" /></:rail>
  <Components.play_header play={@edition.play} />
  <div
    class="text"
    lang={@edition.play.language}
    data-cite={Components.cite_prefix(@edition.play, nil)}
  >
    <Components.division_text :for={page <- @edition.pages} edition={@edition} division={page.division} />
  </div>
</Components.shell>
```

- [ ] **Step 5: Write the pages**

In `StaticSite.write_play/3`, after the `index.html` line:

```elixir
    for {page, prev, next} <- Edition.neighbours(edition.pages) do
      html = Pages.render(:division, Map.merge(assigns, %{page: page, prev: prev, next: next}))
      File.write!(Path.join(play_dir, "#{page.slug}.html"), html)
    end

    File.write!(Path.join(play_dir, "text.html"), Pages.render(:text, assigns))
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: PASS. If the ghost test fails with `["A mí. "]`-style whitespace, check `texts/2` squishes; if a verse line shows an extra space, `mix format` reflowed the `.l` line, which `phx-no-format` must prevent.

- [ ] **Step 7: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add lib/playcode/export test/playcode/export/static_site_play_test.exs
git commit -m "feat: one static page per act, plus the full text

Lines are anchored by verse number (per scene when the numbering restarts),
split verses align on invisible ghost text, italics render as <em>, and a
verse form is named in the margin where its passage starts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Statistics page

**Files:**
- Create: `lib/playcode/export/static_site/pages/statistics.html.heex`
- Modify: `lib/playcode/export/static_site/components.ex`, `lib/playcode/export/static_site.ex`
- Modify: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md` (one line)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: stats keys from Task 2; `Edition.roman/1`, `Components.number/1` (Task 3).
- Produces: `Components.stat_tiles/1`, `synopsis/1`, `character_table/1`, `presence/1`; `plays/<CODE>/statistics.html` with section ids `tiles`, `synopsis`, `characters`, `presence`.
- Hover tooltips are native `title` attributes on every segment, share bar and matrix cell, so the charts need no JS at all. That is simpler than the spec's "JS adds hover tooltips"; Step 5 updates the spec to match.

- [ ] **Step 1: Write the tests**

Append inside `Playcode.Export.StaticSitePlayTest`:

```elixir
  describe "the statistics page" do
    test "shows the metrical synopsis, the characters and who shares the stage" do
      {play, dir} = publish!(@two_acts)
      stats = page(dir, play, "statistics.html")

      assert rows(stats, "#synopsis tbody tr") == [["I", "Redondilla", "1–5", "5"], ["I", "Unmarked", "6", "1"]]

      characters = rows(stats, "#characters tbody tr")
      assert Enum.map(characters, &hd/1) == ["Segismundo", "Criado 2", "Clarín", "Clotaldo"]
      assert ["Segismundo", "1", "5" | _] = hd(characters)
      assert "I, 1" in hd(characters)

      assert texts(stats, "#presence tbody th") == ["Segismundo", "Criado 2", "Clarín", "Clotaldo"]
      assert stats |> LazyHTML.query("#presence td[title]") |> Enum.count() == 3
      assert LazyHTML.text(stats) =~ "metrical passages"
    end

    test "a play in prose has no synopsis and measures its characters in words" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><p>Buenos días, señor.</p></sp>
          <sp><speaker>JUAN</speaker><p>Hola.</p></sp>
        </div1>
        """)

      stats = page(dir, play, "statistics.html")

      assert stats |> LazyHTML.query("#synopsis") |> Enum.empty?()
      assert [["ANA", "1", "0", "3" | _], ["JUAN", "1", "0", "1" | _]] = rows(stats, "#characters tbody tr")
      assert LazyHTML.text(stats) =~ "most words"
      refute "verses" in texts(stats, "#tiles dt")
    end
  end
```

Order check for the first test: Segismundo 5 lines; Criado 2 and Clarín have 1 line each, Criado 2 more words; Clotaldo has 0 lines. Clotaldo's prose is in no metrical passage, so his matrix row has no filled cell, and three cells have a `title`.

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL — `statistics.html` does not exist.

- [ ] **Step 3: Add the statistics components**

In `components.ex` add `alias Playcode.Export.StaticSite.Edition`, then:

```elixir
  attr :stats, :map, required: true

  def stat_tiles(assigns) do
    s = assigns.stats

    tiles =
      Enum.reject(
        [
          {s["num_acts"], "acts"},
          {s["verses"], "verses"},
          {length(s["metrical_passages"] || []), "metrical passages"},
          {s["speeches"], "speeches"},
          {length(s["characters"] || []), "speaking characters"},
          {s["total_stage_directions"], "stage directions"},
          {s["aside_verses"], "verses in asides"}
        ],
        fn {value, _label} -> value in [nil, 0] end
      )

    assigns = assign(assigns, :tiles, tiles)

    ~H"""
    <dl id="tiles" class="tiles">
      <div :for={{value, label} <- @tiles}>
        <dt>{label}</dt>
        <dd>{number(value)}</dd>
      </div>
    </dl>
    """
  end

  attr :passages, :list, required: true

  def synopsis(assigns) do
    total = assigns.passages |> Enum.map(& &1["verses"]) |> Enum.sum() |> max(1)

    families =
      assigns.passages
      |> Enum.group_by(& &1["family"])
      |> Enum.map(fn {family, passages} -> {family, passages |> Enum.map(& &1["verses"]) |> Enum.sum()} end)
      |> Enum.sort_by(&(-elem(&1, 1)))

    assigns = assign(assigns, segments: segments(assigns.passages, total), families: families, total: total)

    ~H"""
    <section id="synopsis">
      <h2>Metrical synopsis</h2>
      <p class="lede">The verse forms in order, each passage drawn to scale. Dashed lines mark the acts.</p>
      <div class="band" role="img" aria-label="Metrical synopsis drawn to scale; the table below lists every passage.">
        <%= for segment <- @segments do %>
          <span :if={segment.sep} class="sep"></span>
          <span class={["seg", "f-" <> segment.family]} style={"flex-grow: #{segment.verses}"} title={segment.title}>
            <span :if={segment.label}>{segment.label}</span>
          </span>
        <% end %>
      </div>
      <ul class="legend">
        <li :for={{family, verses} <- @families}>
          <i class={"sw f-" <> family}></i><b>{PlayLabels.verse_family_label(family)}</b>
          {number(verses)} vv. · {percent(verses, @total)}
        </li>
      </ul>
      <table>
        <thead>
          <tr><th>Act</th><th>Form</th><th>vv.</th><th class="num">Verses</th></tr>
        </thead>
        <tbody>
          <tr :for={passage <- @passages}>
            <td>{passage["act"] && Edition.roman(passage["act"])}</td>
            <td><i class={"sw f-" <> passage["family"]}></i>{PlayLabels.verse_form_label(passage["form"])}</td>
            <td>{range(passage)}</td>
            <td class="num">{number(passage["verses"])}</td>
          </tr>
        </tbody>
      </table>
      <p class="note">Rhyme is not encoded, so two consecutive romances with different assonance show as one passage.</p>
    </section>
    """
  end

  defp segments(passages, total) do
    passages
    |> Enum.with_index()
    |> Enum.map(fn {passage, i} ->
      label = PlayLabels.verse_form_label(passage["form"])

      %{
        sep: i > 0 and Enum.at(passages, i - 1)["act"] != passage["act"],
        family: passage["family"],
        verses: passage["verses"],
        title: "#{label} · vv. #{range(passage)} · #{passage["verses"]} verses",
        label: if(passage["verses"] / total > 0.06, do: label)
      }
    end)
  end

  defp range(%{"from" => from, "to" => to}) when from == to, do: "#{from}"
  defp range(%{"from" => from, "to" => to}), do: "#{from}–#{to}"

  defp percent(part, total), do: "#{round(part / max(total, 1) * 100)}%"

  attr :characters, :list, required: true
  attr :unit, :string, required: true, doc: ~s("lines" or "words")
  attr :total, :integer, required: true

  def character_table(assigns) do
    top = assigns.characters |> Enum.sort_by(&(-&1[assigns.unit])) |> Enum.take(12)
    max = top |> Enum.map(& &1[assigns.unit]) |> Enum.max(fn -> 1 end) |> max(1)
    assigns = assign(assigns, top: top, max: max)

    ~H"""
    <section :if={@top != []} id="characters">
      <h2>Characters</h2>
      <p class="lede">
        The {length(@top)} speaking characters with the most {@unit}{if length(@characters) > length(@top), do: " (of #{length(@characters)})"}. A shared verse counts for each speaker.
      </p>
      <table>
        <thead>
          <tr>
            <th>Character</th><th class="num">Speeches</th><th class="num">Lines</th><th class="num">Words</th>
            <th>Share of the play</th><th>First words</th><th>Main forms</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={character <- @top}>
            <th scope="row">{character["name"]}</th>
            <td class="num">{number(character["speeches"])}</td>
            <td class="num">{number(character["lines"])}</td>
            <td class="num">{number(character["words"])}</td>
            <td class="share" title={"#{character[@unit]} of #{@total} #{@unit}"}>
              <span class="track"><span style={"width: #{round(character[@unit] / @max * 100)}%"}></span></span>{percent(character[@unit], @total)}
            </td>
            <td>{first_words(character["first"])}</td>
            <td>{main_forms(character["forms"])}</td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp first_words(%{"act" => act, "line" => line}) when is_integer(act) and is_integer(line),
    do: "#{Edition.roman(act)}, #{line}"

  defp first_words(%{"act" => act}) when is_integer(act), do: Edition.roman(act)
  defp first_words(_first), do: "—"

  defp main_forms(forms) do
    forms
    |> Map.delete("unmarked")
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.take(2)
    |> Enum.map_join(" · ", &PlayLabels.verse_form_label(elem(&1, 0)))
  end

  attr :stats, :map, required: true

  def presence(assigns) do
    presence = assigns.stats["presence"] || %{}

    rows =
      (assigns.stats["characters"] || [])
      |> Enum.take(12)
      |> Enum.map(fn c -> {c["name"], Map.new(c["columns"], fn [i, n] -> {i, n} end)} end)

    assigns = assign(assigns, basis: presence["basis"], columns: presence["columns"] || [], rows: rows)

    ~H"""
    <section :if={@columns != [] and @rows != []} id="presence">
      <h2>Who shares the stage</h2>
      <p class="lede">{basis_note(@basis, length(@columns))}</p>
      <div class="scroll">
        <table class="matrix">
          <thead>
            <tr>
              <th></th>
              <th :for={{column, i} <- Enum.with_index(@columns)} scope="col" title={column_title(column)} class={act_start(@columns, i)}>
                <i :if={column["family"]} class={"sw f-" <> column["family"]}></i>
                <span class="sr-only">{column_title(column)}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{name, cells} <- @rows}>
              <th scope="row">{name}</th>
              <td
                :for={{column, i} <- Enum.with_index(@columns)}
                class={["c", cells[i] && "on", act_start(@columns, i)]}
                title={cells[i] && "#{name} · #{column_title(column)} · #{cells[i]} lines"}
              >
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp basis_note("scene", _n), do: "A filled cell means the character speaks in that scene."

  defp basis_note("passage", n),
    do: "This play encodes no scenes, so the columns are its #{n} metrical passages. A filled cell means the character speaks in that passage."

  defp basis_note(_basis, _n), do: "A filled cell means the character speaks in that division."

  defp column_title(%{"form" => form} = column), do: "#{PlayLabels.verse_form_label(form)} · vv. #{range(column)}"
  defp column_title(%{"act" => act, "label" => label}) when is_integer(act), do: "#{Edition.roman(act)}: #{label}"
  defp column_title(%{"label" => label}), do: label || ""

  defp act_start(columns, i),
    do: if(i > 0 and Enum.at(columns, i - 1)["act"] != Enum.at(columns, i)["act"], do: "act-start")
```

- [ ] **Step 4: Add the template and write the page**

`pages/statistics.html.heex`:

```heex
<Components.shell root="../../" title={"Statistics — #{@edition.play.title} — EMOTHE"} site={@site}>
  <:rail><Components.play_rail edition={@edition} current="statistics" /></:rail>
  <Components.play_header play={@edition.play} />
  <h2>Statistics</h2>
  <Components.stat_tiles stats={@edition.stats} />
  <Components.synopsis
    :if={(@edition.stats["metrical_passages"] || []) != []}
    passages={@edition.stats["metrical_passages"]}
  />
  <Components.character_table
    characters={@edition.stats["characters"] || []}
    unit={if (@edition.stats["verses"] || 0) > 0, do: "lines", else: "words"}
    total={if (@edition.stats["verses"] || 0) > 0, do: @edition.stats["verses"], else: @edition.stats["words"] || 0}
  />
  <Components.presence stats={@edition.stats} />
</Components.shell>
```

In `StaticSite.write_play/3`, after `text.html`:

```elixir
    File.write!(Path.join(play_dir, "statistics.html"), Pages.render(:statistics, assigns))
```

- [ ] **Step 5: Correct the spec's unit rule**

In the spec, section "Statistics › `characters`", replace the line

`Share of the play is measured in lines for a verse play and in words for a prose play (\`is_verse\`).`

with

`Share of the play is measured in lines when the play has verse and in words when it has none. The computed verse count decides, not \`is_verse\`: that flag comes from \`<extent>\` (\`tei_parser.ex:406\`), so a file without an extent would read as prose.`

In the spec, section "Pages › Statistics page", replace

`Charts are server-rendered HTML/CSS; JS adds hover tooltips. Every chart's numbers are also in a table.`

with

`Charts are server-rendered HTML/CSS with native \`title\` tooltips, so they need no JS. Every chart's numbers are also in a table.`

- [ ] **Step 6: Run the tests, everything, and commit**

Run: `mix test test/playcode/export/static_site_play_test.exs`, then `mix format && mix compile --warnings-as-errors && mix test`
Expected: PASS.

Open one generated `statistics.html` in a browser (generate with `mix playcode.export.site --plays EMOTHE0020_LaVidaEsSueno --all -o /tmp/site`, using the code as it is in your dev DB) and look at the band, legend and matrix for collisions in light and dark mode.

```bash
git add lib/playcode/export docs/superpowers/specs/2026-10-02-static-site-redesign-design.md test/playcode/export/static_site_play_test.exs
git commit -m "feat: static statistics page with the metrical synopsis

Band, family legend and passage table; characters by lines (or words when a
play has no verse); a character x scene matrix, or character x passage for
plays that encode no scenes. The unit follows the computed verse count,
since is_verse comes from <extent> and is false without one.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Catalogue page, the shared normaliser, and the end of `Renderer`

**Files:**
- Create: `lib/playcode/export/static_site/pages/catalogue.html.heex`, `test/playcode/export/static_site_catalogue_test.exs`, `test/playcode/export/static_site_search_test.exs`, `test/fixtures/search_normalisation.json`
- Modify: `lib/playcode/export/static_site/search.ex` (rewrite), `components.ex`, `static_site.ex`, `priv/static_site/site.js`
- Delete: `lib/playcode/export/static_site/renderer.ex`

**Interfaces:**
- Produces: `Search.normalise(text | nil) :: String.t()`, `Search.words(text) :: [String.t()]`; `Components.catalogue_entry/1` (attrs `play`, `lead`), `Components.kind(play) :: "original" | "translation"`, `Components.collection(play) :: "EMOTHE" | "ARTELOPE"`; `EMOTHE.normalise(s)`, `EMOTHE.words(s)` in `site.js`. Catalogue hooks: `[data-works]` (the list), `[data-play]` (one entry, with `data-lang`, `data-form`, `data-kind`, `data-coll`, `data-text`), `[data-facets]`, `[data-filter]`, `[data-sort]`, `[data-count]`, `[data-catalogue-controls]`.

- [ ] **Step 1: Write the normaliser cases and their Elixir test**

`test/fixtures/search_normalisation.json`:

```json
{
  "words": [
    {"text": "¡Válgame el cielo!, ¿qué veo?", "words": ["valgame", "el", "cielo", "que", "veo"]},
    {"text": "Sueños, SUEÑOS", "words": ["sueños", "sueños"]},
    {"text": "año y ano", "words": ["año", "y", "ano"]},
    {"text": "mañana", "words": ["mañana"]},
    {"text": "l’onde où je suis", "words": ["l", "onde", "ou", "je", "suis"]},
    {"text": "Garçon, Œdipe", "words": ["garcon", "œdipe"]},
    {"text": "Dulce <<sueño>> mío", "words": ["dulce", "sueño", "mio"]},
    {"text": "v. 1236 — fin.", "words": ["v", "1236", "fin"]},
    {"text": "¿¡ !?", "words": []}
  ],
  "shards": [
    {"word": "sueño", "key": "su", "file": "su"},
    {"word": "ñaque", "key": "ña", "file": "u00f1a"},
    {"word": "y", "key": "y", "file": "y"},
    {"word": "œdipe", "key": "œd", "file": "u0153d"},
    {"word": "1236", "key": "12", "file": "12"}
  ]
}
```

`test/playcode/export/static_site_search_test.exs`:

```elixir
defmodule Playcode.Export.StaticSiteSearchTest do
  @moduledoc """
  Full-text search in the static site. The normaliser is tested directly because the
  browser's copy in `site.js` must agree with it word for word; both run the cases in
  `test/fixtures/search_normalisation.json` (the JS side: `test/js/search.test.mjs`).
  """
  use Playcode.DataCase, async: true

  alias Playcode.Export.StaticSite.Search

  defp cases, do: "test/fixtures/search_normalisation.json" |> File.read!() |> Jason.decode!()

  test "the build-time normaliser splits words as the browser does" do
    for %{"text" => text, "words" => words} <- cases()["words"] do
      assert Search.words(text) == words, text
    end
  end
end
```

- [ ] **Step 2: Run it**

Run: `mix test test/playcode/export/static_site_search_test.exs`
Expected: FAIL — `Search.words/1` is undefined.

- [ ] **Step 3: Rewrite `search.ex` with the normaliser**

```elixir
defmodule Playcode.Export.StaticSite.Search do
  @moduledoc """
  Full-text search for the static site: the normaliser here, the index files from
  Task 8 on. Both are read in the browser by `priv/static_site/search.js`.

  `normalise/1` and `words/1` must agree with `EMOTHE.normalise` and `EMOTHE.words` in
  `site.js`; `test/fixtures/search_normalisation.json` runs against both.
  """

  @doc """
  Lowercase, accents dropped, `ñ` kept (so *año* and *ano* stay apart), NFC first so a
  decomposed `n` + tilde counts as `ñ`.
  """
  def normalise(nil), do: ""

  def normalise(text) do
    text
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.replace("ñ", "")
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace("", "ñ")
  end

  @doc "The searchable words of `text`: runs of letters and digits, normalised."
  def words(text), do: ~r/[\p{L}\p{N}]+/u |> Regex.scan(normalise(text)) |> List.flatten()
end
```

In `static_site.ex`, delete the `File.write!(Path.join(dir, "search.js"), Search.search_js())` line from `write_index_pages/4`: that was the old catalogue's filter script, and the old catalogue still renders without it until Step 7 replaces it.

Run the test: PASS.

- [ ] **Step 4: Write the catalogue tests**

`test/playcode/export/static_site_catalogue_test.exs`:

```elixir
defmodule Playcode.Export.StaticSiteCatalogueTest do
  @moduledoc "The static site's catalogue page: one entry per work, facets, filter hooks."
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  defp works(index), do: index |> LazyHTML.query("[data-works] > li") |> Enum.to_list()

  test "a translation is listed under its original, one entry per work" do
    %{original: original, translation: translation} = translation_family_fixture()

    assert [work] = works(html!(generate!([original, translation]), "index.html"))

    assert work |> LazyHTML.query("a") |> LazyHTML.attribute("href") ==
             ["plays/#{original.code}/index.html", "plays/#{translation.code}/index.html"]
  end

  test "a translation whose original is not published stands on its own, marked as a translation" do
    %{translation: translation} = translation_family_fixture()

    assert [work] = works(html!(generate!([translation]), "index.html"))
    assert LazyHTML.text(work) =~ "translation"
  end

  test "a translation of a translation is listed under the original of the chain" do
    %{original: original, translation: translation} = translation_family_fixture()

    second =
      play_fixture(%{
        "title" => "Second-hand",
        "parent_play_id" => translation.id,
        "relationship_type" => "traduccion",
        "is_complete" => true
      })

    assert [work] = works(html!(generate!([original, translation, second]), "index.html"))
    assert LazyHTML.text(work) =~ "Second-hand"
  end

  test "facets count the plays by language, form, kind and collection" do
    es = play_fixture(%{"is_complete" => true, "language" => "es"})
    fr = play_fixture(%{"is_complete" => true, "language" => "fr", "is_verse" => false})
    al = play_fixture(%{"is_complete" => true, "code" => "AL#{System.unique_integer([:positive])}"})

    labels = texts(html!(generate!([es, fr, al]), "index.html"), "[data-facets] label")

    assert "Español 2" in labels
    assert "Français 1" in labels
    assert "Prose 1" in labels
    assert "Originals 3" in labels
    assert "ARTELOPE 1" in labels
  end

  test "each entry carries what the filter and facets match on" do
    play = play_fixture(%{"is_complete" => true, "title" => "La Vida es Sueño"})
    entry = html!(generate!([play]), "index.html") |> LazyHTML.query("[data-play]")

    assert LazyHTML.attribute(entry, "data-lang") == ["es"]
    assert LazyHTML.attribute(entry, "data-kind") == ["original"]
    assert [text] = LazyHTML.attribute(entry, "data-text")
    assert text =~ "la vida es sueño"
  end

  test "titles and authors are escaped" do
    play = play_fixture(%{"is_complete" => true, "title" => "Tom & <Jerry>"})

    assert read!(generate!([play]), "index.html") =~ "Tom &amp; &lt;Jerry&gt;"
  end
end
```

- [ ] **Step 5: Run them**

Run: `mix test test/playcode/export/static_site_catalogue_test.exs`
Expected: FAIL — no `[data-works]` in the old catalogue.

- [ ] **Step 6: Add the catalogue component and template**

In `components.ex` add `alias Playcode.Export.StaticSite.Search` (extend the existing `alias Playcode.Export.StaticSite.Edition` to `alias Playcode.Export.StaticSite.{Edition, Search}`) and:

```elixir
  def kind(%{relationship_type: nil}), do: "original"
  def kind(_play), do: "translation"

  def collection(%{code: "AL" <> _}), do: "ARTELOPE"
  def collection(_play), do: "EMOTHE"

  attr :play, :map, required: true
  attr :lead, :boolean, default: false

  def catalogue_entry(assigns) do
    ~H"""
    <div
      class="entry"
      data-play
      data-lang={@play.language}
      data-form={if @play.is_verse, do: "verse", else: "prose"}
      data-kind={kind(@play)}
      data-coll={collection(@play)}
      data-text={Search.normalise(Enum.join([@play.title, @play.original_title, @play.author_name, @play.code], " "))}
    >
      <span class="tag">{@play.language}</span>
      <a class={["entry-title", @lead && "lead"]} href={"plays/#{@play.code}/index.html"}>{@play.title}</a>
      <span class="code">{@play.code}</span>
      <span :if={@lead and kind(@play) == "translation"} class="tag">translation</span>
      <span class="meta">{entry_meta(@play)}</span>
      <span :if={@lead} class="author">{@play.author_name}</span>
    </div>
    """
  end

  defp entry_meta(play) do
    [composition_years(play), if(play.is_verse and play.verse_count, do: "#{number(play.verse_count)} vv.", else: "Prose")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
```

`pages/catalogue.html.heex`:

```heex
<Components.shell root="" title="EMOTHE — Catalogue" current={:catalogue} site={@site} rail_label="Filters">
  <:rail>
    <form class="facets" data-facets hidden>
      <fieldset :for={{name, legend, options} <- @facets} class="facet">
        <legend>{legend}</legend>
        <label>
          <input type="radio" name={name} value="" checked /> <span>All</span> <span class="count">{@count}</span>
        </label>
        <label :for={{value, label, count} <- options}>
          <input type="radio" name={name} value={value} /> <span>{label}</span> <span class="count">{count}</span>
        </label>
      </fieldset>
    </form>
  </:rail>
  <h1>Catalogue</h1>
  <p class="lede">{@count} plays · {@authors} authors</p>
  <div class="controls" data-catalogue-controls hidden>
    <input type="search" data-filter placeholder="Filter by title, author or code" aria-label="Filter the catalogue" />
    <label>
      Sort
      <select data-sort aria-label="Sort the catalogue">
        <option value="author">Author</option>
        <option value="title">Title</option>
        <option value="date">Date</option>
      </select>
    </label>
  </div>
  <p data-count aria-live="polite" class="lede"></p>
  <ol class="works" data-works>
    <li :for={work <- @works} class="work" data-author={work.sort_author} data-title={work.sort_title} data-date={work.date}>
      <Components.catalogue_entry play={work.play} lead />
      <ul :if={work.translations != []} class="translations">
        <li :for={translation <- work.translations}><Components.catalogue_entry play={translation} /></li>
      </ul>
    </li>
  </ol>
</Components.shell>
```

- [ ] **Step 7: Build works and facets in the orchestrator; drop `Renderer`**

In `static_site.ex`: change the alias to `alias Playcode.Export.StaticSite.{Components, Edition, Pages, Search}`, add `alias Playcode.Catalogue.Play`, and replace `write_index_pages/4` with:

```elixir
  defp write_index_pages(plays, _results, dir, opts) do
    site = site(opts, MapSet.new(plays, & &1.code))

    assigns = %{
      site: site,
      works: works(plays),
      facets: facets(plays),
      count: length(plays),
      authors: plays |> Enum.map(& &1.author_name) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()
    }

    File.write!(Path.join(dir, "index.html"), Pages.render(:catalogue, assigns))
  end

  # One entry per work: each published play under the published play at the root of
  # its translation chain.
  defp works(plays) do
    by_id = Map.new(plays, &{&1.id, &1})

    plays
    |> Enum.group_by(&root_id(&1, by_id))
    |> Enum.map(fn {root, members} ->
      lead = by_id[root]

      %{
        play: lead,
        translations: members |> Enum.reject(&(&1.id == root)) |> Enum.sort_by(&Search.normalise(&1.title_sort || &1.title)),
        sort_author: Search.normalise(lead.author_sort || lead.author_name),
        sort_title: Search.normalise(lead.title_sort || lead.title),
        date: lead.composition_date_from
      }
    end)
    |> Enum.sort_by(&{&1.sort_author, &1.sort_title})
  end

  defp root_id(play, by_id) do
    case by_id[play.parent_play_id] do
      nil -> play.id
      parent -> root_id(parent, by_id)
    end
  end

  defp facets(plays) do
    [
      {"lang", "Language",
       plays
       |> Enum.frequencies_by(& &1.language)
       |> Enum.sort_by(&(-elem(&1, 1)))
       |> Enum.map(fn {code, n} -> {code, Play.language_name(code), n} end)},
      {"form", "Form", options(plays, &if(&1.is_verse, do: "verse", else: "prose"), %{"verse" => "Verse", "prose" => "Prose"})},
      {"kind", "Kind", options(plays, &Components.kind/1, %{"original" => "Originals", "translation" => "Translations"})},
      {"coll", "Collection", options(plays, &Components.collection/1, %{"EMOTHE" => "EMOTHE", "ARTELOPE" => "ARTELOPE"})}
    ]
  end

  defp options(plays, value_of, labels) do
    plays
    |> Enum.frequencies_by(value_of)
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map(fn {value, n} -> {value, labels[value], n} end)
  end
```

Delete `lib/playcode/export/static_site/renderer.ex`. `Play`'s `language` defaults to `"es"`, so `frequencies_by` never sees nil.

- [ ] **Step 8: Add the normaliser and the catalogue to `site.js`**

Replace `priv/static_site/site.js` with:

```js
/* EMOTHE static edition: progressive enhancement only. Every page reads fine without it. */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};

  // Must agree with Playcode.Export.StaticSite.Search.normalise/1 and words/1:
  // test/fixtures/search_normalisation.json runs against both.
  E.normalise = function (s) {
    return String(s || '').normalize('NFC').toLowerCase().replace(/ñ/g, '')
      .normalize('NFD').replace(/\p{Mn}/gu, '').replace(//g, 'ñ');
  };
  E.words = function (s) { return E.normalise(s).match(/[\p{L}\p{N}]+/gu) || []; };

  if (!root.document) return;

  function initCatalogue() {
    var list = document.querySelector('[data-works]');
    if (!list) return;
    var controls = document.querySelector('[data-catalogue-controls]');
    var facets = document.querySelector('[data-facets]');
    var filter = document.querySelector('[data-filter]');
    var sort = document.querySelector('[data-sort]');
    var count = document.querySelector('[data-count]');
    var works = Array.prototype.slice.call(list.children);
    controls.hidden = false;
    facets.hidden = false;

    function chosen() {
      var out = {};
      facets.querySelectorAll('input:checked').forEach(function (input) { if (input.value) out[input.name] = input.value; });
      return out;
    }

    function matches(entry, query, want) {
      var data = entry.dataset;
      return (!query || data.text.indexOf(query) !== -1) &&
        (!want.lang || data.lang === want.lang) && (!want.form || data.form === want.form) &&
        (!want.kind || data.kind === want.kind) && (!want.coll || data.coll === want.coll);
    }

    function update() {
      var query = E.normalise(filter.value).trim();
      var want = chosen();
      var shown = 0;
      works.forEach(function (work) {
        var visible = Array.prototype.some.call(work.querySelectorAll('[data-play]'), function (entry) {
          return matches(entry, query, want);
        });
        work.hidden = !visible;
        if (visible) shown++;
      });
      count.textContent = shown === works.length ? '' : shown + ' of ' + works.length + ' works';
    }

    function reorder() {
      var key = sort.value;
      works.sort(function (a, b) {
        var x = a.dataset[key] || '', y = b.dataset[key] || '';
        if (x === y) return 0;
        if (key === 'date') { x = x ? Number(x) : Infinity; y = y ? Number(y) : Infinity; return x - y; }
        return x.localeCompare(y);
      });
      works.forEach(function (work) { list.appendChild(work); });
    }

    filter.addEventListener('input', update);
    facets.addEventListener('change', update);
    sort.addEventListener('change', reorder);
  }

  document.addEventListener('DOMContentLoaded', function () {
    // The rail is open in the markup so it shows without JS; on a narrow screen it
    // starts closed once JS is here to open it.
    if (root.matchMedia && root.matchMedia('(max-width: 959px)').matches) {
      document.querySelectorAll('details.rail').forEach(function (d) { d.open = false; });
    }
    initCatalogue();
  });
})(typeof window !== 'undefined' ? window : globalThis);
```

- [ ] **Step 9: Run the tests, everything, and commit**

Run: `mix test test/playcode/export`, then `mix format && mix compile --warnings-as-errors && mix test`
Expected: PASS. The older `static_site_test.exs` tests ("only complete plays…", "one play can be added…") now read the new catalogue.

```bash
git add -A lib/playcode/export priv/static_site/site.js test/playcode/export test/fixtures/search_normalisation.json
git commit -m "feat: static catalogue of works with facets; Renderer removed

One entry per work, translations nested under the root of their chain; a
translation whose original is not published stands alone, marked. The
search normaliser lives in Search and in site.js, pinned by one shared case
file.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Reading tools, line links, citation copy, and the about page

**Files:**
- Create: `lib/playcode/export/static_site/pages/about.html.heex`
- Modify: `components.ex` (`play_rail/1` gains `tools`), `pages/division.html.heex`, `pages/text.html.heex`, `pages/title.html.heex`, `static_site.ex`, `priv/static_site/site.js`
- Test: `test/playcode/export/static_site_play_test.exs`, `test/playcode/export/static_site_test.exs`

**Interfaces:**
- Produces: hooks `[data-tools]` (hidden until JS), `[data-ln-set]`, `[data-toggle="sd"|"vf"]`, `[data-highlight]` (options = cast `xml_id`s), `[data-copy-citation]`; `body[data-ln|data-sd|data-vf]` attributes driven by JS and read by CSS; `about.html`.

- [ ] **Step 1: Write the tests**

In `static_site_play_test.exs`, add `import Playcode.TestFixtures` and:

```elixir
  test "reading tools ship hidden, ready for JS, with the cast to highlight" do
    %{play: play} = play_with_structure_fixture()
    act = html!(generate!([play], all: true), "plays/#{play.code}/act-1.html")

    assert act |> LazyHTML.query("[data-tools][hidden]") |> Enum.count() == 1
    assert act |> LazyHTML.query("[data-highlight] option") |> LazyHTML.attribute("value") == ["", "ALFA"]
    assert act |> LazyHTML.query("body") |> LazyHTML.attribute("data-ln") == ["5"]
    assert act |> LazyHTML.query("[data-cite]") |> LazyHTML.attribute("data-cite") == ["Tester, Structured Play, ACT I"]
  end
```

In `static_site_test.exs`:

```elixir
  test "the about page says what the archive holds and how to cite it" do
    dir = generate!([complete_play(), complete_play()], version: "2.1")
    about = html!(dir, "about.html")

    assert texts(about, "h1") == ["About this edition"]
    assert LazyHTML.text(about) =~ "2 plays"
    assert LazyHTML.text(about) =~ "version 2.1"
  end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export`
Expected: FAIL — no `[data-tools]`, no `about.html`.

- [ ] **Step 3: Add the tools to the rail**

Replace `play_rail/1` in `components.ex` with:

```elixir
  attr :edition, :map, required: true
  attr :current, :string, required: true
  attr :tools, :boolean, default: false

  def play_rail(assigns) do
    assigns = assign(assigns, :cast, Enum.filter(cast(assigns.edition.characters), & &1.xml_id))

    ~H"""
    <nav aria-label="Contents">
      <h2>Contents</h2>
      <.play_contents edition={@edition} current={@current} />
    </nav>
    <div :if={@tools} class="tools" data-tools hidden>
      <h2>Line numbers</h2>
      <div class="seg" role="group" aria-label="Line numbers">
        <button type="button" data-ln-set="all">All</button>
        <button type="button" data-ln-set="5">5</button>
        <button type="button" data-ln-set="off">Off</button>
      </div>
      <h2>Show</h2>
      <label><input type="checkbox" data-toggle="sd" checked /> Stage directions</label>
      <label><input type="checkbox" data-toggle="vf" checked /> Verse forms</label>
      <%= if @cast != [] do %>
        <h2>Highlight</h2>
        <select data-highlight aria-label="Highlight a character">
          <option value="">No one</option>
          <option :for={character <- @cast} value={character.xml_id}>{character.name}</option>
        </select>
      <% end %>
    </div>
    """
  end
```

Add `tools` to the `<Components.play_rail …/>` call in `division.html.heex` and `text.html.heex`. In `title.html.heex`, after `<p data-citation>…</p>`, add:

```heex
      <button type="button" class="copy" data-copy-citation hidden>Copy citation</button>
```

- [ ] **Step 4: Add the about page**

`pages/about.html.heex`:

```heex
<Components.shell root="" title="About — EMOTHE" current={:about} site={@site}>
  <article class="title-page">
    <h1>About this edition</h1>
    <%!-- Text about the project itself comes from the project; add it here, by hand.
          The build states only what it knows. --%>
    <p>
      This archive holds {@site.play_count} {if @site.play_count == 1, do: "play", else: "plays"}, published as version {@site.version} on {@site.build_date}.
    </p>
    <h2>Reading</h2>
    <p>
      Every play has a title page, one page per act, the full text on one page, and its statistics. Verse is numbered every fifth line; each line has its own address, so a link to it can be shared.
    </p>
    <h2>Citing</h2>
    <p>
      Each title page gives a citation for the edition. To cite a line, link to it: tapping a verse number copies its address and a citation.
    </p>
    <h2>Sources</h2>
    <p>Each play's TEI-XML source is published beside its pages and can be downloaded from its title page.</p>
    <h2>Principles</h2>
    <p>
      The archive is plain HTML, CSS and JavaScript with no server and nothing loaded from elsewhere, following the
      <a href="https://endings.uvic.ca/principles.html">Endings principles</a>. It works the same opened from a disk.
    </p>
  </article>
</Components.shell>
```

In `static_site.ex`, at the end of `write_index_pages/4`:

```elixir
    File.write!(Path.join(dir, "about.html"), Pages.render(:about, %{site: site}))
```

- [ ] **Step 5: Add the tools, line links and citation copy to `site.js`**

Insert before the `document.addEventListener('DOMContentLoaded', …)` call:

```js
  function remembered(key, value) {
    try {
      if (value === undefined) return root.localStorage.getItem('reader.' + key);
      root.localStorage.setItem('reader.' + key, value);
    } catch (e) { return null; }
  }

  function initTools() {
    var tools = document.querySelector('[data-tools]');
    if (!tools) return;
    var body = document.body;
    tools.hidden = false;
    ['ln', 'sd', 'vf'].forEach(function (key) { var v = remembered(key); if (v) body.setAttribute('data-' + key, v); });

    var buttons = tools.querySelectorAll('[data-ln-set]');
    buttons.forEach(function (button) {
      button.setAttribute('aria-pressed', String(button.dataset.lnSet === body.dataset.ln));
      button.addEventListener('click', function () {
        body.dataset.ln = button.dataset.lnSet;
        remembered('ln', button.dataset.lnSet);
        buttons.forEach(function (b) { b.setAttribute('aria-pressed', String(b === button)); });
      });
    });

    tools.querySelectorAll('[data-toggle]').forEach(function (box) {
      var key = box.dataset.toggle;
      box.checked = body.getAttribute('data-' + key) !== 'off';
      box.addEventListener('change', function () {
        var value = box.checked ? 'on' : 'off';
        body.setAttribute('data-' + key, value);
        remembered(key, value);
      });
    });

    var select = tools.querySelector('[data-highlight]');
    if (select) {
      var style = document.createElement('style');
      document.head.appendChild(style);
      select.addEventListener('change', function () {
        style.textContent = select.value
          ? '.text .sp:not([data-who~="' + CSS.escape(select.value) + '"]){opacity:.4}' : '';
      });
    }
  }

  function copy(text, button) {
    if (!root.navigator.clipboard) return;
    root.navigator.clipboard.writeText(text).then(function () {
      var label = button.textContent;
      button.textContent = 'Copied';
      setTimeout(function () { button.textContent = label; }, 1500);
    }, function () {});
  }

  function initLinks() {
    var text = document.querySelector('[data-cite]');
    if (text) {
      text.addEventListener('click', function (event) {
        var number = event.target.closest('a[href^="#l"]');
        if (!number) return;
        var url = root.location.href.split('#')[0] + number.getAttribute('href');
        copy(text.dataset.cite + ', v. ' + number.textContent.trim() + '. ' + url, number);
      });
    }
    var button = document.querySelector('[data-copy-citation]');
    var citation = document.querySelector('[data-citation]');
    if (button && citation) {
      button.hidden = false;
      button.addEventListener('click', function () {
        copy(citation.textContent.trim() + ' ' + root.location.href.split('#')[0], button);
      });
    }
  }
```

and add `initTools();` and `initLinks();` after `initCatalogue();` in the `DOMContentLoaded` handler. Clicking a number still follows its `#l…` link; the copy is extra.

- [ ] **Step 6: Run the tests, everything, and commit**

Run: `mix test test/playcode/export`, then `mix format && mix compile --warnings-as-errors && mix test`
Expected: PASS.

Check by hand in a browser (these behaviours are JS on the DOM, with no browser in the test suite): the line-number buttons, both toggles, the highlight, the copy on a number and on the citation, and the rail collapsing below 960 px.

```bash
git add lib/playcode/export priv/static_site/site.js test/playcode/export
git commit -m "feat: reading tools, line links and the about page

Line numbers (all, every 5th, off), stage-direction and verse-form toggles,
character highlight; choices remembered per reader. Tapping a verse number
copies its address and a citation. The DOM behaviour is checked by hand:
the suite has no browser.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The search index

**Files:**
- Modify: `lib/playcode/export/static_site/search.ex`, `lib/playcode/export/static_site.ex`
- Test: `test/playcode/export/static_site_search_test.exs`

**Interfaces:**
- Consumes: `%Edition{items, anchors, refs, page_of, play}` (Task 3).
- Produces:
  - `Search.shard_key(word) :: String.t()`, `Search.shard_file(key) :: String.t()`
  - `Search.write_play(dir, edition, play_index) :: %{word => [play_index, line_index, kind_flag, …]}` (flat triples; flag 1 for a stage direction, 0 for spoken text); writes `search/lines/<CODE>.js` with `%{"speakers" => [name], "lines" => [[slug, anchor, ref, speaker_index | nil, "v" | "p" | "s", text]]}`.
  - `Search.write_index(dir, plays, [postings]) :: %{index_bytes, largest_shard_bytes}`; writes `search/plays.js` (list of `%{"code", "title", "author", "language", "language_name", "kind"}`) and `search/index/<file>.js`.

- [ ] **Step 1: Write the tests**

Append inside `Playcode.Export.StaticSiteSearchTest` (add `import Playcode.ImportHelpers` and `import Playcode.StaticSiteHelpers` at the top):

```elixir
  test "shard keys and file names match the browser's" do
    for %{"word" => word, "key" => key, "file" => file} <- cases()["shards"] do
      assert Search.shard_key(word) == key
      assert Search.shard_file(key) == file
    end
  end

  describe "the index files" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>Rosaura</speaker><l n="1">Hipogrifo violento</l></sp>
            </div1>
            <div1 type="jornada" n="2"><head>Jornada II</head>
              <sp><speaker>Segismundo</speaker><l n="12">Decir que sueño es engaño</l></sp>
              <stage>Vase Segismundo</stage>
              <sp><speaker>Clarín</speaker><l n="13">¡Ñaque!</l></sp>
            </div1>
            """
          )
        )

      %{play: play, dir: generate!([play], all: true)}
    end

    test "a word's shard points at its line, and the lines file holds the line as printed", %{play: play, dir: dir} do
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")
      {"lines", code, %{"speakers" => speakers, "lines" => lines}} = load_js!(dir, "search/lines/#{play.code}.js")

      assert code == play.code
      line = Enum.find_index(lines, &(Enum.at(&1, 1) == "l12"))
      assert shard["sueño"] == [0, line, 0]
      assert ["act-2", "l12", "II, 12", speaker, "v", "Decir que sueño es engaño"] = Enum.at(lines, line)
      assert Enum.at(speakers, speaker) == "Segismundo"
    end

    test "a stage direction is marked as one", %{dir: dir} do
      {"index", "va", shard} = load_js!(dir, "search/index/va.js")

      assert [0, _line, 1] = shard["vase"]
    end

    test "a word that starts with ñ lives in a shard named by its code point", %{dir: dir} do
      {"index", "ña", shard} = load_js!(dir, "search/index/u00f1a.js")

      assert Map.has_key?(shard, "ñaque")
    end

    test "the play list is in index order, with what the facets need", %{play: play, dir: dir} do
      assert {"plays", "all", [%{"code" => code, "kind" => "original", "language_name" => "Español"}]} =
               load_js!(dir, "search/plays.js")

      assert code == play.code
    end
  end

  test "adding a play to a generated site adds it to the index" do
    first = import_tei!(tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">sueño primero</l></sp></div1>)))
    second = import_tei!(tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>B</speaker><l n="1">sueño segundo</l></sp></div1>)))
    dir = generate!([first], all: true)

    :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

    {"plays", "all", plays} = load_js!(dir, "search/plays.js")
    {"index", "su", shard} = load_js!(dir, "search/index/su.js")
    assert length(plays) == 2
    assert length(shard["sueño"]) == 6
  end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_search_test.exs`
Expected: FAIL — `Search.shard_key/1` undefined, then missing `search/` files.

- [ ] **Step 3: Write the index builder**

Append to `search.ex` (and add the aliases `alias Playcode.Catalogue.Play`, `alias Playcode.Export.StaticSite.{Components, Edition}`, `alias Playcode.PlayContent.InlineMarkup` under `@moduledoc`; update the moduledoc's first paragraph to say the module also writes the index). Also add to the moduledoc: "Files are JS that call `EMOTHE.search.load/3`, not JSON, because browsers refuse `fetch` on `file://` while a `<script>` tag still works there."

```elixir
  @kinds %{verse: "v", prose: "p", stage: "s"}

  @doc "The shard a word lives in: its first two characters (code points)."
  def shard_key(word), do: word |> String.codepoints() |> Enum.take(2) |> Enum.join()

  @doc "A shard key as a file name: `a-z` and `0-9` as they are, anything else as `u` + 4 hex digits."
  def shard_file(key) do
    key
    |> String.codepoints()
    |> Enum.map_join(fn char ->
      if char =~ ~r/\A[a-z0-9]\z/ do
        char
      else
        <<code::utf8>> = char
        "u" <> (code |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
      end
    end)
  end

  @doc """
  Writes `search/lines/<CODE>.js` for one play and returns its postings:
  `%{word => [play_index, line_index, kind_flag, ...]}`, flat triples.
  """
  def write_play(dir, %Edition{} = edition, play_index) do
    entries =
      for item <- edition.items, Map.has_key?(edition.page_of, item.element.id) do
        %{
          slug: edition.page_of[item.element.id],
          anchor: edition.anchors[item.element.id],
          ref: edition.refs[item.element.id],
          speaker: speaker(item),
          kind: @kinds[item.kind],
          text: InlineMarkup.plain(item.element.content)
        }
      end

    speakers = entries |> Enum.map(& &1.speaker) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    index_of = speakers |> Enum.with_index() |> Map.new()
    lines = Enum.map(entries, &[&1.slug, &1.anchor, &1.ref, index_of[&1.speaker], &1.kind, &1.text])

    write_js!(
      Path.join([dir, "search", "lines", "#{edition.play.code}.js"]),
      "lines",
      edition.play.code,
      %{"speakers" => speakers, "lines" => lines}
    )

    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, line} ->
      flag = if entry.kind == "s", do: 1, else: 0
      entry.text |> words() |> Enum.uniq() |> Enum.map(&{&1, [play_index, line, flag]})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {word, postings} -> {word, List.flatten(postings)} end)
  end

  defp speaker(%{speakers: []}), do: nil
  defp speaker(%{speakers: speakers}), do: Enum.map_join(speakers, " / ", &elem(&1, 1))

  @doc """
  Writes `search/plays.js` and every `search/index/<shard>.js` from the postings of all
  plays, given in the order of `plays`. Returns the total and the largest shard size.
  """
  def write_index(dir, plays, postings) do
    write_js!(Path.join([dir, "search", "plays.js"]), "plays", "all", Enum.map(plays, &play_entry/1))

    index_dir = Path.join([dir, "search", "index"])
    File.rm_rf!(index_dir)
    File.mkdir_p!(index_dir)

    sizes =
      postings
      |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _word, earlier, later -> earlier ++ later end))
      |> Enum.group_by(fn {word, _postings} -> shard_key(word) end)
      |> Enum.map(fn {key, words} ->
        write_js!(Path.join(index_dir, shard_file(key) <> ".js"), "index", key, Map.new(words))
      end)

    %{index_bytes: Enum.sum(sizes), largest_shard_bytes: Enum.max(sizes, fn -> 0 end)}
  end

  defp play_entry(play) do
    %{
      "code" => play.code,
      "title" => play.title,
      "author" => play.author_name,
      "language" => play.language,
      "language_name" => Play.language_name(play.language),
      "kind" => Components.kind(play)
    }
  end

  defp write_js!(path, kind, key, data) do
    File.mkdir_p!(Path.dirname(path))

    js = [
      "EMOTHE.search.load(",
      Jason.encode!(kind),
      ",",
      Jason.encode!(key),
      ",",
      Jason.encode!(data, escape: :javascript_safe),
      ");\n"
    ]

    File.write!(path, js)
    IO.iodata_length(js)
  end
```

- [ ] **Step 4: Call it from the orchestrator**

In `generate/1`, replace the `play.id |> Edition.load() |> write_play(dir, site)` line with:

```elixir
            edition = Edition.load(play.id)
            Map.put(write_play(edition, dir, site), :postings, Search.write_play(dir, edition, n - 1))
```

In `rebuild_index/1`, replace `Enum.map(plays, fn _ -> %{} end)` with:

```elixir
      plays
      |> Enum.with_index()
      |> Enum.map(fn {play, i} -> %{postings: Search.write_play(dir, Edition.load(play.id), i)} end)
```

(`generate_single_play/2` and `remove_single_play/2` go through `rebuild_index/1`, so the index always matches the plays on disk.) At the start of `rebuild_index/1`'s body, after `dir = …`, add `File.rm_rf!(Path.join(dir, "search"))` so a removed play's lines file goes too.

In `write_index_pages/4`, rename `_results` to `results` and add at its end:

```elixir
    Search.write_index(dir, plays, Enum.map(results, & &1.postings))
```

Make `write_index_pages/4` return that report (it is the last expression), so Task 10 can use it.

- [ ] **Step 5: Run the tests, everything, and commit**

Run: `mix test test/playcode/export/static_site_search_test.exs`, then `mix format && mix compile --warnings-as-errors && mix test`
Expected: PASS.

```bash
git add lib/playcode/export test/playcode/export/static_site_search_test.exs
git commit -m "feat: full-text search index for the static site

An inverted index sharded by a word's first two letters, plus one lines
file per play, all written as .js that call EMOTHE.search.load so the
unzipped archive can search from file://.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Search page and `search.js`

**Files:**
- Create: `lib/playcode/export/static_site/pages/search.html.heex`, `priv/static_site/search.js`, `test/js/search.test.mjs`
- Modify: `lib/playcode/export/static_site.ex`, `.github/workflows/ci.yml`
- Test: `test/playcode/export/static_site_search_test.exs`

**Interfaces:**
- Consumes: `EMOTHE.normalise`/`EMOTHE.words` (`site.js`, Task 6); the files from Task 8.
- Produces: `EMOTHE.search.load`, `.shardKey`, `.shardFile`, `.parse(query) -> {words, phrases}`, `.matches(token, word, mode)`, `.hasPhrase(tokens, phrase, mode)`, `.hits(shard, word, mode) -> {"p:l": flag}`, `.intersect([maps])`; `search.html` with hooks `[data-search-form]`, `[data-search-results]`, `[data-search-count]`, `[data-search-facets]`.

- [ ] **Step 1: Write the JS tests**

`test/js/search.test.mjs`:

```js
// The browser half of the static site's search, run with `node --test`. site.js and
// search.js are plain browser scripts; vm runs them with no `document`, so only their
// pure functions load.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');
const context = vm.createContext({});
vm.runInContext(read('../../priv/static_site/site.js'), context);
vm.runInContext(read('../../priv/static_site/search.js'), context);
const { EMOTHE } = context;
const S = EMOTHE.search;
const cases = JSON.parse(read('../fixtures/search_normalisation.json'));
const plain = (value) => JSON.parse(JSON.stringify(value)); // across vm realms

test('words match the build-time normaliser', () => {
  for (const c of cases.words) assert.deepEqual([...EMOTHE.words(c.text)], c.words, c.text);
});

test('shard keys and file names match the build', () => {
  for (const c of cases.shards) {
    assert.equal(S.shardKey(c.word), c.key);
    assert.equal(S.shardFile(c.key), c.file);
  }
});

test('quoted words are a phrase, and every word must occur', () => {
  assert.deepEqual(plain(S.parse('"la vida es" Sueño')), { words: ['sueño', 'la', 'vida', 'es'], phrases: [['la', 'vida', 'es']] });
});

test('a query of punctuation has no words', () => {
  assert.deepEqual(plain(S.parse('¿¡ "" !?')), { words: [], phrases: [] });
  assert.deepEqual(plain(S.parse('')), { words: [], phrases: [] });
});

test('starts-with matches a prefix, except a one-letter word, which matches whole', () => {
  assert.ok(S.matches('sueños', 'sueño', 'prefix'));
  assert.ok(!S.matches('sueños', 'sueño', 'word'));
  assert.ok(S.matches('y', 'y', 'prefix'));
  assert.ok(!S.matches('yo', 'y', 'prefix'));
});

test('a phrase must occur in order', () => {
  assert.ok(S.hasPhrase(['toda', 'la', 'vida', 'es', 'sueño'], ['la', 'vida'], 'word'));
  assert.ok(!S.hasPhrase(['vida', 'la'], ['la', 'vida'], 'word'));
});

test('hits gather every matching word of a shard and keep the stage flag', () => {
  const shard = { 'sueño': [0, 4, 0], 'sueños': [1, 2, 1], 'suelo': [0, 9, 0] };
  assert.deepEqual(plain(S.hits(shard, 'sueño', 'prefix')), { '0:4': 0, '1:2': 1 });
  assert.deepEqual(plain(S.hits(undefined, 'sueño', 'prefix')), {});
  assert.deepEqual(plain(S.intersect([{ '0:4': 0, '1:2': 1 }, { '0:4': 0 }])), { '0:4': 0 });
  assert.deepEqual(plain(S.intersect([])), {});
});
```

And the page test, appended to `static_site_search_test.exs`:

```elixir
  test "the search page works only with JavaScript, and says so without it" do
    dir = generate!([Playcode.TestFixtures.play_fixture(%{"is_complete" => true})])
    page = html!(dir, "search.html")

    assert page |> LazyHTML.query(~s(form[hidden][role="search"])) |> Enum.count() == 1
    assert page |> LazyHTML.query("noscript") |> LazyHTML.text() =~ "Search needs JavaScript"
    assert "assets/search.js" in (page |> LazyHTML.query("script") |> LazyHTML.attribute("src"))
  end
```

- [ ] **Step 2: Run them**

Run: `node --test test/js/search.test.mjs` and `mix test test/playcode/export/static_site_search_test.exs`
Expected: FAIL — `search.js` does not exist (ENOENT); `search.html` does not exist.

- [ ] **Step 3: Write `search.js`**

`priv/static_site/search.js`:

```js
/* EMOTHE static edition: full-text search over the files StaticSite.Search writes.
   Loaded only by search.html, after site.js (EMOTHE.normalise, EMOTHE.words). */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};
  var S = E.search = E.search || {};
  var store = { plays: null, index: {}, lines: {} };
  var waiting = {};

  S.load = function (kind, key, value) {
    if (kind === 'plays') store.plays = value; else store[kind][key] = value;
    var id = kind + ':' + key, callbacks = waiting[id] || [];
    delete waiting[id];
    callbacks.forEach(function (resolve) { resolve(); });
  };

  S.shardKey = function (word) { return Array.from(word).slice(0, 2).join(''); };

  S.shardFile = function (key) {
    return Array.from(key).map(function (c) {
      return /^[a-z0-9]$/.test(c) ? c : 'u' + c.codePointAt(0).toString(16).padStart(4, '0');
    }).join('');
  };

  // Words in quotes are a phrase; every word, in a phrase or not, must occur in the line.
  S.parse = function (query) {
    var phrases = [];
    var rest = String(query || '').replace(/"([^"]*)"/g, function (_, inner) {
      var words = E.words(inner);
      if (words.length) phrases.push(words);
      return ' ';
    });
    var all = E.words(rest);
    phrases.forEach(function (phrase) { all = all.concat(phrase); });
    return { words: all.filter(function (w, i) { return all.indexOf(w) === i; }), phrases: phrases };
  };

  // A one-letter word has a shard of its own, so it can only match whole.
  S.matches = function (token, word, mode) {
    return mode === 'prefix' && Array.from(word).length > 1 ? token.indexOf(word) === 0 : token === word;
  };

  S.hasPhrase = function (tokens, phrase, mode) {
    for (var i = 0; i + phrase.length <= tokens.length; i++) {
      var ok = true;
      for (var j = 0; j < phrase.length && ok; j++) ok = S.matches(tokens[i + j], phrase[j], mode);
      if (ok) return true;
    }
    return false;
  };

  // Hits for one word: {"play:line": 1 for a stage direction, 0 for spoken text}.
  S.hits = function (shard, word, mode) {
    var hits = {};
    Object.keys(shard || {}).forEach(function (token) {
      if (!S.matches(token, word, mode)) return;
      var p = shard[token];
      for (var i = 0; i < p.length; i += 3) hits[p[i] + ':' + p[i + 1]] = p[i + 2];
    });
    return hits;
  };

  S.intersect = function (maps) {
    var out = {};
    if (!maps.length) return out;
    Object.keys(maps[0]).forEach(function (k) {
      if (maps.every(function (m) { return k in m; })) out[k] = maps[0][k];
    });
    return out;
  };

  if (!root.document) return;

  var form, results, count, facetsEl, state = null, renders = 0;
  var FACETS = [
    ['language', 'Language', function (play) { return play.language_name; }],
    ['author', 'Author', function (play) { return play.author || '—'; }],
    ['kind', 'Kind', function (play) { return play.kind === 'original' ? 'Originals' : 'Translations'; }],
    ['type', 'Text', function (play, stage) { return stage ? 'Stage directions' : 'Spoken'; }]
  ];

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function button(label, onClick) {
    var b = el('button', 'more', label);
    b.type = 'button';
    b.addEventListener('click', onClick);
    return b;
  }

  // Loads a search file once; a missing file (a word with no shard) loads as empty.
  function need(kind, key, src) {
    var have = kind === 'plays' ? store.plays : store[kind][key];
    if (have) return Promise.resolve();
    var id = kind + ':' + key;
    return new Promise(function (resolve) {
      if (waiting[id]) { waiting[id].push(resolve); return; }
      waiting[id] = [resolve];
      var script = document.createElement('script');
      script.src = src;
      script.onerror = function () { S.load(kind, key, kind === 'index' ? {} : kind === 'plays' ? [] : { speakers: [], lines: [] }); };
      document.head.appendChild(script);
    });
  }

  function loadLines(playIndexes) {
    return Promise.all(playIndexes.map(function (p) {
      var code = store.plays[p].code;
      return need('lines', code, 'search/lines/' + code + '.js');
    }));
  }

  function playsOf(hits) {
    var seen = {};
    Object.keys(hits).forEach(function (k) { seen[k.split(':')[0]] = true; });
    return Object.keys(seen).map(Number);
  }

  function phraseFilter(hits, phrases, mode) {
    var out = {};
    Object.keys(hits).forEach(function (k) {
      var pl = k.split(':').map(Number);
      var tokens = E.words(store.lines[store.plays[pl[0]].code].lines[pl[1]][5]);
      if (phrases.every(function (p) { return S.hasPhrase(tokens, p, mode); })) out[k] = hits[k];
    });
    return out;
  }

  function run() {
    var query = form.elements.q.value, mode = form.elements.mode.value;
    root.history.replaceState(null, '', '?' + new URLSearchParams({ q: query, mode: mode }).toString());
    var parsed = S.parse(query);
    if (!parsed.words.length) { state = null; render(); return; }
    var keys = parsed.words.map(S.shardKey).filter(function (k, i, a) { return a.indexOf(k) === i; });
    count.textContent = 'Searching…';
    need('plays', 'all', 'search/plays.js')
      .then(function () {
        return Promise.all(keys.map(function (k) { return need('index', k, 'search/index/' + S.shardFile(k) + '.js'); }));
      })
      .then(function () {
        var hits = S.intersect(parsed.words.map(function (w) { return S.hits(store.index[S.shardKey(w)], w, mode); }));
        // ponytail: a phrase loads the lines of every candidate play; fine for this corpus.
        if (!parsed.phrases.length) return hits;
        return loadLines(playsOf(hits)).then(function () { return phraseFilter(hits, parsed.phrases, mode); });
      })
      .then(function (hits) {
        state = { hits: hits, words: parsed.words, mode: mode, open: {}, filters: {}, allPlays: false };
        render();
      });
  }

  function passes(play, stage, skip) {
    return FACETS.every(function (f) {
      var want = state.filters[f[0]];
      return f === skip || !want || f[2](play, stage) === want;
    });
  }

  function render() {
    var token = ++renders;
    results.textContent = '';
    facetsEl.textContent = '';
    if (!state) { count.textContent = ''; return; }

    var groups = {};
    Object.keys(state.hits).forEach(function (k) {
      var pl = k.split(':').map(Number);
      if (passes(store.plays[pl[0]], state.hits[k] === 1)) (groups[pl[0]] = groups[pl[0]] || []).push(pl[1]);
    });
    var order = Object.keys(groups).map(Number).sort(function (a, b) {
      return groups[b].length - groups[a].length || store.plays[a].title.localeCompare(store.plays[b].title);
    });
    var total = order.reduce(function (n, p) { return n + groups[p].length; }, 0);
    count.textContent = total + (total === 1 ? ' line' : ' lines') + ' in ' + order.length + (order.length === 1 ? ' play' : ' plays');
    renderFacets();

    var shown = state.allPlays ? order : order.slice(0, 20);
    loadLines(shown).then(function () {
      if (token !== renders) return;
      shown.forEach(function (p) { results.appendChild(group(p, groups[p].sort(function (a, b) { return a - b; }))); });
      if (order.length > shown.length) {
        results.appendChild(button('Show all ' + order.length + ' plays', function () { state.allPlays = true; render(); }));
      }
    });
  }

  function renderFacets() {
    FACETS.forEach(function (f) {
      var counts = {};
      Object.keys(state.hits).forEach(function (k) {
        var p = Number(k.split(':')[0]), stage = state.hits[k] === 1, play = store.plays[p];
        if (passes(play, stage, f)) { var v = f[2](play, stage); counts[v] = (counts[v] || 0) + 1; }
      });
      var values = Object.keys(counts).sort(function (a, b) { return counts[b] - counts[a]; });
      if (values.length < 2 && !state.filters[f[0]]) return;
      var fieldset = el('fieldset', 'facet');
      fieldset.appendChild(el('legend', null, f[1]));
      [''].concat(values).forEach(function (v) {
        var label = el('label'), input = el('input');
        input.type = 'radio';
        input.name = 'facet-' + f[0];
        input.value = v;
        input.checked = (state.filters[f[0]] || '') === v;
        input.addEventListener('change', function () { state.filters[f[0]] = v; state.open = {}; render(); });
        label.appendChild(input);
        label.appendChild(el('span', null, v || 'All'));
        label.appendChild(el('span', 'count', v ? String(counts[v]) : ''));
        fieldset.appendChild(label);
      });
      facetsEl.appendChild(fieldset);
    });
  }

  function group(p, lines) {
    var play = store.plays[p], data = store.lines[play.code];
    var section = el('section', 'group'), heading = el('h2'), link = el('a', null, play.title);
    link.href = 'plays/' + play.code + '/index.html';
    heading.appendChild(link);
    section.appendChild(heading);
    var meta = [play.author, play.kind === 'translation' ? 'translation' : null, lines.length + (lines.length === 1 ? ' line' : ' lines')];
    section.appendChild(el('p', 'group-meta', meta.filter(Boolean).join(' · ')));
    var list = el('ol', 'hits'), limit = state.open[p] ? lines.length : 5;
    lines.slice(0, limit).forEach(function (l) { list.appendChild(hit(play, data, data.lines[l])); });
    section.appendChild(list);
    if (lines.length > limit) section.appendChild(button('Show all ' + lines.length, function () { state.open[p] = true; render(); }));
    return section;
  }

  function hit(play, data, row) {
    var li = el('li', 'hit'), ref = el('a', 'ref', row[2]);
    ref.href = 'plays/' + play.code + '/' + row[0] + '.html#' + row[1];
    li.appendChild(ref);
    li.appendChild(el('span', 'spk', row[3] === null ? '' : data.speakers[row[3]]));
    var text = el('span', row[4] === 's' ? 'line stage' : 'line');
    highlight(text, row[5]);
    li.appendChild(text);
    return li;
  }

  // Built with text nodes, never innerHTML: the line text is data.
  function highlight(target, text) {
    text.split(/([\p{L}\p{M}\p{N}]+)/u).forEach(function (part, i) {
      var word = i % 2 === 1 && E.normalise(part);
      if (word && state.words.some(function (w) { return S.matches(word, w, state.mode); })) {
        target.appendChild(el('mark', null, part));
      } else if (part) {
        target.appendChild(document.createTextNode(part));
      }
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    form = document.querySelector('[data-search-form]');
    if (!form) return;
    results = document.querySelector('[data-search-results]');
    count = document.querySelector('[data-search-count]');
    facetsEl = document.querySelector('[data-search-facets]');
    form.hidden = false;
    var params = new URLSearchParams(root.location.search);
    form.elements.q.value = params.get('q') || '';
    if (params.get('mode') === 'word') form.elements.mode.value = 'word';
    form.addEventListener('submit', function (event) { event.preventDefault(); run(); });
    if (form.elements.q.value) run();
  });
})(typeof window !== 'undefined' ? window : globalThis);
```

- [ ] **Step 4: Add the page**

`pages/search.html.heex`:

```heex
<Components.shell root="" title="Search — EMOTHE" current={:search} site={@site} rail_label="Filters">
  <:rail>
    <div data-search-facets></div>
  </:rail>
  <h1>Search</h1>
  <noscript>
    <p>Search needs JavaScript. <a href="index.html">Browse the catalogue</a> instead.</p>
  </noscript>
  <form data-search-form role="search" hidden>
    <label for="q" class="sr-only">Search the texts</label>
    <input id="q" name="q" type="search" autocomplete="off" placeholder="Search every line of every play" />
    <fieldset class="mode">
      <legend class="sr-only">Match</legend>
      <label><input type="radio" name="mode" value="word" /> Whole word</label>
      <label><input type="radio" name="mode" value="prefix" checked /> Starts with</label>
    </fieldset>
    <button type="submit">Search</button>
  </form>
  <p class="lede" data-search-count aria-live="polite"></p>
  <div data-search-results></div>
  <script src="assets/search.js" defer>
  </script>
</Components.shell>
```

In `static_site.ex`, in `write_index_pages/4` before the `Search.write_index` line:

```elixir
    File.write!(Path.join(dir, "search.html"), Pages.render(:search, %{site: site}))
```

- [ ] **Step 5: Run the CI step locally and add it to CI**

In `.github/workflows/ci.yml`, after the `Run tests` step:

```yaml
      # The browser half of the static site's search; Node is preinstalled on the runner.
      - name: Run JS tests
        run: node --test test/js/search.test.mjs
```

Run: `node --test test/js/search.test.mjs` and `mix test test/playcode/export/static_site_search_test.exs`
Expected: all PASS.

- [ ] **Step 6: Run everything, check by hand, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test && node --test test/js/search.test.mjs`

By hand: `mix playcode.export.site --all -o /tmp/site`, open `/tmp/site/search.html` straight from disk (`file://`) and search `sueño`, `"la vida es"`, `y`, `¿¡`; then the same through `cd /tmp/site && python3 -m http.server 8000`. Check that results group by play, "Show all" works, facets narrow the hits, a hit link lands on its highlighted line, and the URL keeps `?q=…&mode=…`.

```bash
git add lib/playcode/export priv/static_site/search.js test/js/search.test.mjs test/playcode/export/static_site_search_test.exs .github/workflows/ci.yml
git commit -m "feat: static search page, grouped by play

Loads one shard per query word by <script>, so it works from file://;
phrases are checked against the line text; facets by language, author,
original/translation and spoken/stage. The pure functions are tested with
node --test against the same cases as the Elixir normaliser.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Size budget, build report, and documentation

**Files:**
- Modify: `lib/playcode/export/static_site.ex`, `lib/mix/tasks/playcode.export.site.ex`, `CLAUDE.md`
- Test: `test/playcode/export/static_site_test.exs`, `test/mix/tasks_test.exs`

**Interfaces:**
- Produces: `generate/1` returns `{:ok, %{plays, size, output_dir, largest_page_gzip, index_bytes, largest_shard_bytes}}`; the mix task prints the last three.

- [ ] **Step 1: Write the tests**

In `static_site_test.exs`:

```elixir
  test "the shared assets stay inside the size budget and nothing loads from another host" do
    %{play: play} = play_with_structure_fixture()
    dir = generate!([play], all: true)
    size = fn file -> File.stat!(Path.join([dir, "assets", file])).size end

    assert size.("style.css") <= 25_000
    assert size.("site.js") <= 15_000
    assert size.("search.js") <= 15_000

    fonts = dir |> Path.join("assets/fonts/*.woff2") |> Path.wildcard() |> Enum.map(&File.stat!(&1).size)
    assert Enum.sum(fonts) <= 300_000

    for page <- Path.wildcard(Path.join(dir, "**/*.html")) do
      refute File.read!(page) =~ ~r/<(?:script|link|img)[^>]+(?:src|href)="https?:/, "#{page} loads from another host"
    end

    refute File.read!(Path.join([dir, "assets", "style.css"])) =~ ~r/url\(\s*["']?https?:/
  end

  test "a generated site reports its largest page and its index sizes" do
    %{play: play} = play_with_structure_fixture()
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, %{largest_page_gzip: page, index_bytes: index, largest_shard_bytes: shard}} =
             StaticSite.generate(output_dir: dir, play_codes: [play.code], all: true)

    assert page > 0 and index > 0 and shard > 0
  end
```

In `test/mix/tasks_test.exs`, at the end of the `playcode.export.site` test:

```elixir
      assert run("playcode.export.site", ["-o", dir, "--all"]) =~ "largest act page"
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_test.exs test/mix/tasks_test.exs`
Expected: FAIL on the report keys and the mix output; the budget test passes if Task 3's font check held. If it fails on fonts, apply Task 3 Step 4's fallback.

- [ ] **Step 3: Report the sizes**

In `write_play/3`, wrap the division-page loop so it records sizes, and return them:

```elixir
    largest =
      edition.pages
      |> Edition.neighbours()
      |> Enum.map(fn {page, prev, next} ->
        html = Pages.render(:division, Map.merge(assigns, %{page: page, prev: prev, next: next}))
        File.write!(Path.join(play_dir, "#{page.slug}.html"), html)
        byte_size(:zlib.gzip(html))
      end)
      |> Enum.max(fn -> 0 end)
```

(this replaces the `for` loop from Task 4) and make the function's last line `%{largest_page_gzip: largest}` instead of `%{}`.

In `generate/1`, replace the success tuple with:

```elixir
        report = write_index_pages(plays, results, dir, opts)

        {:ok,
         Map.merge(report, %{
           plays: total,
           size: dir_size(dir),
           output_dir: dir,
           largest_page_gzip: results |> Enum.map(& &1.largest_page_gzip) |> Enum.max(fn -> 0 end)
         })}
```

(and delete the earlier bare `write_index_pages(plays, results, dir, opts)` call it replaces).

In `lib/mix/tasks/playcode.export.site.ex`, replace the `{:ok, …}` branch with:

```elixir
      {:ok, %{plays: count, size: size, output_dir: dir} = report} ->
        Mix.shell().info("\n✓ Static site generated: #{count} plays → #{dir}/ (#{format_size(size)})")

        Mix.shell().info(
          "  largest act page #{format_size(report.largest_page_gzip)} gzipped (budget 80 KB); " <>
            "search index #{format_size(report.index_bytes)}, largest shard #{format_size(report.largest_shard_bytes)}"
        )
```

and update its `@shortdoc`/`@moduledoc` "all plays" wording if needed (it already says complete plays by default).

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/export/static_site_test.exs test/mix/tasks_test.exs`
Expected: PASS.

- [ ] **Step 5: Update CLAUDE.md**

1. In **Project Structure**, replace the `static_site.ex` block under `export/` with:

```
│       └── static_site.ex            # Static site orchestrator
│           ├── edition.ex            # One play prepared: pages, anchors, refs, split-verse ghosts
│           ├── pages.ex              # embed_templates "pages/*" → HTML strings
│           ├── components.ex         # Shell, rail, play text, charts, catalogue entry
│           ├── search.ex             # Normaliser + full-text index writer
│           └── deployer.ex           # GitHub Pages deployment
```

and add under `statistics/`: `│   │   └── metrics.ex                # Passages, characters, presence, divisions (pure)`, and under `play_content/`: `│   │   └── inline_markup.ex          # The <<…>> italics markers`.

2. Replace the whole **Static Site Export** section's *Architecture* and *Output structure* subsections with:

```markdown
Spec: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`. No third-party requests, and everything, search included, works from the unzipped archive opened as `file://`.

### Architecture

- `Playcode.Export.StaticSite` — orchestrator: loads plays, writes pages, copies `priv/static_site/` to `assets/`, builds the search index
- `StaticSite.Edition` — one play prepared once: pages (`act-N`, or the division type), line anchors (`#l<n>`; `#l<act>-<scene>-<n>` when numbering restarts per scene; `#p<n>` otherwise), citation refs, split-verse ghost text, passage starts
- `StaticSite.Pages` (`pages/*.html.heex`) and `StaticSite.Components` — HEEx rendered to strings with `Phoenix.HTML.Safe.to_iodata/1`; dev's HEEx annotations are stripped
- `StaticSite.Search` — the normaliser (must agree with `EMOTHE.normalise` in `site.js`: `test/fixtures/search_normalisation.json` runs against both) and the index: `search/index/<shard>.js`, `search/lines/<CODE>.js`, `search/plays.js`, all calling `EMOTHE.search.load`
- `Playcode.Statistics.Metrics` — metrical passages, characters, presence, divisions; cached by `Playcode.Statistics` (bump `@version` when what it stores changes)
- `priv/static_site/` — `style.css`, `site.js` (reading tools, catalogue filter, normaliser), `search.js`, `fonts/` (Source Serif 4 and Inter, OFL)
- `StaticSite.Deployer` — pushes `_site/` to a GitHub Pages branch

### Output structure

```
_site/
├── index.html  search.html  about.html
├── assets/                    style.css, site.js, search.js, fonts/
├── search/                    plays.js, index/<shard>.js, lines/<CODE>.js
└── plays/
    ├── <CODE>.html            redirect stub to the old address
    └── <CODE>/
        ├── index.html         title page
        ├── act-1.html …       one per act; prologue.html etc. for other divisions
        ├── text.html          full text
        ├── statistics.html
        └── <CODE>.xml         TEI-XML
```

`node --test test/js/search.test.mjs` runs the browser half of search; CI runs it after `mix test`.
```

3. In **What Has Been Implemented**, replace the three lines for `StaticSite`, `StaticSite.Renderer` and `StaticSite.Search` with:

```markdown
- [x] `Playcode.Export.StaticSite` - static archive on HEEx: title page, one page per act, full text, statistics page (metrical synopsis, characters, who shares the stage), catalogue of works with facets, full-text search that works from `file://`, reading tools. Spec: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`; deferred work: `docs/static-site-improvements.md`
```

4. In **Known Roundtrip Gaps** / the found-by list, leave the in-text `<note>` line as it is.

- [ ] **Step 6: Final verification**

Run: `mix format && mix compile --warnings-as-errors && mix test && node --test test/js/search.test.mjs`
Expected: everything passes. Paste the summary lines into the task report.

Then the manual check from the spec:

1. `mix playcode.export.site --all -o /tmp/site` and note the printed sizes against the budget (largest act page ≤ 80 KB gzipped; largest shard plus the five largest files in `search/lines/` ≤ 300 KB: `ls -S /tmp/site/search/lines | head -5`).
2. Open `/tmp/site/index.html` from `file://`, and again through `cd /tmp/site && python3 -m http.server 8000`.
3. Check *La vida es sueño* (split verses at 1251, the synopsis ending Jornada II with décimas 2018–2187), *Antony and Cleopatra* (scenes, translations nested in the catalogue), and a prose play.
4. Check each at 400 px wide, in dark mode, in print preview of `text.html`, and with JavaScript disabled.

Report anything that fails with what you saw; do not claim the redesign done until all four pass.

- [ ] **Step 7: Commit**

```bash
git add lib/playcode/export lib/mix/tasks/playcode.export.site.ex test CLAUDE.md
git commit -m "feat: size budget and build report for the static site; docs

The asset budget and the no-third-party rule are tests; generate/1 reports
the largest act page (gzipped) and the index sizes, and the mix task prints
them. CLAUDE.md describes the new layout.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
