# The Downloads Print the Edition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The HTML (and so the PDF) and EPUB downloads print a translation's or adaptation's original, the publication details, the licence, the project statement, the identifiers, and a critical edition's witnesses.

**Architecture:** `Playcode.Export.Html` gets three public renderers, each returning markup valid as both HTML and XHTML, the way `Html.dating/1` is already shared: `original/1`, `publication/2`, `witnesses/2`. `Html.generate/1` and `Epub.generate/1` print them in the same places. The PDF is `Html.generate/1` through Chrome, so it follows with no code of its own.

**Tech Stack:** Elixir, string-built HTML/XHTML (`Export.Html`, `Export.Epub`), `Witnesses.html/1`, `NoteMarkup.inline/3`, `PlayLabels`, LazyHTML and `:zip` in the tests.

**Spec:** `docs/backlog.md`, *What the downloads leave out* (line 24), and question 24 in `docs/stakeholder/preguntas.html` (`#t-downloads`, the three *Answered/Decided* paragraphs).

## Global Constraints

- Print: a translation's original (an adaptation's too); the publication details; the licence; the project statement; the identifiers; a critical edition's witnesses. Nothing else: not the editorial statement (`editorial_declaration`), the bibliography, the places, the verse forms, the statistics, "Procedencia" (`play_sources.distributor`).
- A critical edition is a play with variant readings or a critical apparatus after the text (decided by Playcode, 2026-10-19).
- The downloads are in English, whatever the play's language (`Html.dating/1` precedent: `Gettext.with_locale(PlaycodeWeb.Gettext, "en", …)`).
- Every value is escaped: the EPUB chapters are XHTML, and a bare `&` makes a reader reject the book.
- No new module enters the PDF's rendering. If one does, add it to `PdfCache.code_version/0` (`lib/playcode/export/pdf_cache.ex:146`), or a cached PDF is served stale.
- Do not add `:parent_play` or `:witnesses` to the `Repo.preload` in `Html.generate/1` or `Epub.generate/1`. Both callers pass the play as `Catalogue.get_play_with_all!/2` loads it: witnesses in order, and the original scoped so a visitor never sees a draft. A preload added here would load the original unscoped for any caller that passed a bare play.
- "Colophon" is a paratext in `CONTEXT.md`. The new block is the **publication** block (`publication/2`, `class="publication"`).
- One test file: `test/playcode_web/controllers/export_controller_test.exs`, in a new `describe "what the downloads print of the edition (question 24)"`, through `get(conn, ~p"/export/#{id}/html")` and `/epub`. Reuse the file's `epub_text/2` (defined at line 363, module-wide).

## Decisions this plan makes (owner to confirm or veto in review)

1. **Publication details** = TEI's `publicationStmt`: `publisher`, `pub_place`, `publication_date`, `authority`. `sponsor` and `funder` (`titleStmt`, 7 and 5 plays) stay out.
2. **The licence** includes `availability_note`, the paragraph TEI's `<availability>` holds beside `<licence>`: 226 of the 407 plays on dev have no licence, so that paragraph is their only statement of terms.
3. **Identifiers** = `code` and `emothe_id` (`idno type="code"` and `type="EMOTHE"`, 213 plays).
4. **Placement**: after the header and before the text, as a printed book's title-page verso: the publication block, then the witnesses. The EPUB prints both in its front chapter, after the header.
5. **Critical edition** = variants *as printed* (none when `show_variants` is off), or a paratext headed "Critical Apparatus". So a play with its variants hidden and no apparatus prints no witnesses: with no readings, nothing names them. **Eight plays qualify on dev, not seven**: EMOTHE0551 *La paloma de Toledo* (309 variants, 3 witnesses) came in on 2026-10-21 with the GitHub copy, two days after the answer that listed seven.
6. **Kind words** come from `PlayLabels.relationship_type_label/1` in English ("Translation of", "Adaptation of", "Reworking of", "Version of"), as `Html.dating/1` uses `PlayLabels`. The site's `Components.kind_name/1` would say "refundición", but it would pull the site's module into the PDF cache key, so every site tweak re-renders every PDF.
7. **The original** is printed by its title alone, with no link: a downloaded file has no site to link into.

## Review Focus

- A visitor downloads a translation whose original is a draft: the download must not name it (Task 1, `a visitor's download names no draft original`).
- `licence_url` is not a web address (`javascript:alert(1)`): printed as text, never as an `href` (Task 3).
- A header value with `&` or `<` ("Norton & Company"): escaped in both formats, the EPUB still XHTML (Task 3).
- An appendix that is not a critical apparatus (0310's "Nota del traductor a la lista de personajes", an `apendice` after the text) must not make a critical edition (Task 2).
- A blank value (nil or `""`) prints no empty label such as `Publication: ` (Task 3, `prints only what the play has`).

---

### Task 1: The original of a translation or adaptation

**Files:**
- Modify: `lib/playcode/export/html.ex` (header in `generate/1`, new `original/1`, CSS)
- Modify: `lib/playcode/export/epub.ex` (`render_front/2`, CSS)
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: `play.relationship_type`, `play.parent_play` as `Catalogue.get_play_with_all!/2` preloads it (nil for a visitor when the original is a draft); `PlayLabels.relationship_type_label/1`.
- Produces: `Html.original(play) :: String.t()`: `~s(<p class="original">Translation of <cite>Hamlet</cite></p>)`, or `""` when `relationship_type` or `parent_play` is nil.

- [ ] **Step 1: Write the failing tests**

```elixir
describe "what the downloads print of the edition (question 24)" do
  test "the HTML and EPUB downloads name the play a translation translates", %{conn: conn} do
    %{translation: translation} = Playcode.TestFixtures.translation_family_fixture()

    html = response(get(conn, ~p"/export/#{translation.id}/html"), 200)

    assert html |> LazyHTML.from_document() |> LazyHTML.query(".original") |> LazyHTML.text() ==
             "Translation of Original Play"

    assert epub_text(conn, translation) =~
             ~s(<p class="original">Translation of <cite>Original Play</cite></p>)

    # A play linked with no kind names no relation, as the play page and the site do.
    {:ok, _} = Playcode.Catalogue.update_play(translation, %{relationship_type: nil})
    refute response(get(conn, ~p"/export/#{translation.id}/html"), 200) =~ ~s(class="original")
  end

  test "a visitor's download names no draft original", %{conn: conn} do
    %{original: original, translation: translation} =
      Playcode.TestFixtures.translation_family_fixture()

    {:ok, _} = Playcode.Catalogue.update_play(original, %{is_complete: false})

    refute response(get(conn, ~p"/export/#{translation.id}/html"), 200) =~ "Original Play"
    refute epub_text(conn, translation) =~ "Original Play"
  end
end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: the first test FAILS (no `.original`); the draft test passes already (nothing prints the original yet). After Step 4, prove it bites: drop the `complete:` option in `ExportController.visible_play!/2` for a moment, see the test go red, put it back.

- [ ] **Step 3: Implement `Html.original(play) :: String.t()`**

`@doc` it like `dating/1`. The label is `Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn -> PlayLabels.relationship_type_label(type) end) <> " of "`; the title goes through `escape/1`. Print it in `generate/1` right after the `<h1 class="title">`, and in `Epub.render_front/2` right after its `<h1>`. CSS in both: `.header .original` as `.header .verse-info` (0.75rem, `rgba(51, 51, 51, 0.5)`), with `cite` italic.

- [ ] **Step 4: Run the tests again**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: PASS

- [ ] **Step 5: Refactor while green**

Match `dating/1`'s shape and naming. Re-run the file after each change.

- [ ] **Step 6: Whole suite, format, compile, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -10`
Expected: `0 failures`

```bash
git add lib/playcode/export/html.ex lib/playcode/export/epub.ex test/playcode_web/controllers/export_controller_test.exs
git commit -m "feat: the downloads name a translation's original"
```

---

### Task 2: A critical edition's witnesses

**Files:**
- Modify: `lib/playcode/export/html.ex` (new `witnesses/2`, called in `generate/1`, CSS)
- Modify: `lib/playcode/export/epub.ex` (`render_front` takes `divisions`, CSS)
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: `play.witnesses` (ordered, from `get_play_with_all!/2`), `play.paratexts`, the `divisions` each `generate/1` already loads with `variants: play.show_variants`; `Witnesses.html/1` (returns `{:safe, iodata}`; `Phoenix.HTML.safe_to_string/1` it); `Note.reading_order/1`, `Note.variant?/1`, `InlineMarkup.plain/1`.
- Produces: `Html.witnesses(play, divisions) :: String.t()`:
  `<section class="witnesses"><h2>Witnesses</h2><ul><li>…</li></ul></section>`, or `""` when the play has no witnesses or is not a critical edition.

- [ ] **Step 1: Write the failing tests** (inside the Task 1 `describe`)

```elixir
@list_wit ~s(<listWit><witness xml:id="Q1" n="Q1"><bibl type="edicion_antigua" subtype="suelta"><title>THE Tragicall Historie of HAMLET</title><pubPlace>London</pubPlace><date when="1603">1603</date></bibl></witness></listWit>)

defp witness_play(opts) do
  [source_desc: @list_wit] |> Keyword.merge(opts) |> tei() |> import_tei!()
  |> Playcode.TestFixtures.mark_complete!()
end

test "the downloads print the witnesses of a play with variants", %{conn: conn} do
  play =
    witness_play(
      body:
        ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso<app n="1"><lem wit="#Q1">Verso</lem><rdg wit="#B">Canto</rdg></app></l></sp></div1>)
    )

  html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
  doc = LazyHTML.from_document(html)
  assert doc |> LazyHTML.query(".witnesses h2") |> LazyHTML.text() == "Witnesses"
  assert doc |> LazyHTML.query(".witnesses li") |> LazyHTML.text() =~ "Tragicall Historie of HAMLET"
  assert epub_text(conn, play) =~ "Tragicall Historie of HAMLET"

  # Its variants hidden, nothing names the witnesses (decision 5).
  {:ok, _} = Playcode.Catalogue.update_play(play, %{show_variants: false})
  refute response(get(conn, ~p"/export/#{play.id}/html"), 200) =~ "Tragicall"
end

test "a critical apparatus after the text makes a critical edition; another appendix does not",
     %{conn: conn} do
  body = ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso</l></sp></div1>)

  apparatus =
    witness_play(
      body: body,
      back: ~s(<div type="apendice"><head>Critical Apparatus</head><p>1 Verso] Canto Q1.</p></div>)
    )

  note =
    witness_play(
      body: body,
      back: ~s(<div type="apendice"><head>Nota del traductor</head><p>Una nota.</p></div>)
    )

  assert response(get(conn, ~p"/export/#{apparatus.id}/html"), 200) =~ "Tragicall"
  assert epub_text(conn, apparatus) =~ "Tragicall"
  refute response(get(conn, ~p"/export/#{note.id}/html"), 200) =~ "Tragicall"
  refute epub_text(conn, note) =~ "Tragicall"
end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: both new tests FAIL on the first positive `assert` (no `.witnesses`).

- [ ] **Step 3: Implement `Html.witnesses(play, divisions) :: String.t()`**

A private `critical_edition?(play, divisions)`: `divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1)` (as `Edition.load/1` computes `variants`), or any paratext whose `InlineMarkup.plain(heading)`, downcased and trimmed, is `"critical apparatus"`. Add a `ponytail:` comment naming the ceiling: the heading is the only mark the corpus gives (0460, 0644), and an apparatus headed in another language would need its own word. Print the section after the publication block's place (Task 3 puts that block first; until then, straight after `</header>`), in `generate/1` and after the header `div` in the EPUB's front chapter. `render_front(play, items)` becomes `render_front(play, divisions, items)`; `generate/1` already holds `divisions`. CSS in both: as `.paratext` for width; each `li` a hanging indent (`padding-left: 1.5rem; text-indent: -1.5rem`), no bullet, 0.8rem.

- [ ] **Step 4: Run the tests again**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: PASS

- [ ] **Step 5: Refactor while green**

One rendering, two callers; no copy of the list markup in `epub.ex`. Re-run the file after each change.

- [ ] **Step 6: Whole suite, format, compile, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -10`
Expected: `0 failures`

```bash
git add lib/playcode/export/html.ex lib/playcode/export/epub.ex test/playcode_web/controllers/export_controller_test.exs
git commit -m "feat: the downloads print a critical edition's witnesses"
```

---

### Task 3: The publication details, identifiers, licence and project statement

**Files:**
- Modify: `lib/playcode/export/html.ex` (new `publication/2`, called in `generate/1`, CSS)
- Modify: `lib/playcode/export/epub.ex` (front chapter, CSS)
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: `play.publisher`, `pub_place`, `publication_date`, `authority`, `code`, `emothe_id`, `licence_text`, `licence_url`, `availability_note`, `project_description`; `NoteMarkup.inline/3`.
- Produces: `Html.publication(play, format :: :html | :epub) :: String.t()`: a `<section class="publication">` of `<p>`s, in this order, each only when its value is not blank (nil or `""`):
  1. `Publication: ` + the present of publisher, pub_place, publication_date joined with `", "`
  2. `Authority: ` + authority
  3. `Identifiers: ` + code, then `, EMOTHE ` + emothe_id when present (the code is always there)
  4. `Licence: ` + licence_text, then the URL: an `<a href>` when it starts `http://` or `https://` (the site's `web_url?` rule, a one-line private copy), plain escaped text otherwise
  5. availability_note
  6. each paragraph of project_description (split on `~r/\n\s*\n/`, as `Components.paragraphs/1` does)

  Text through `NoteMarkup.inline(text, [], format)` (escapes, and prints `<<…>>` as italics); the `href` through `escape/1`.

- [ ] **Step 1: Write the failing tests** (inside the same `describe`)

```elixir
defp publication_lines(html),
  do: html |> LazyHTML.from_document() |> LazyHTML.query(".publication p") |> Enum.map(&LazyHTML.text/1)

test "the downloads print the publication details, the identifiers, the licence and the project statement",
     %{conn: conn, play: play} do
  {:ok, play} =
    Playcode.Catalogue.update_play(play, %{
      publisher: "Norton & Company",
      pub_place: "Valencia",
      publication_date: "2012",
      authority: "Universitat de València",
      emothe_id: "0555",
      licence_text: "CC BY-NC-ND 4.0",
      licence_url: "https://creativecommons.org/licenses/by-nc-nd/4.0/",
      availability_note: "Se ruega citar la procedencia.",
      project_description: "El proyecto EMOTHE.\n\nCarlos Muñoz Pons es responsable.",
      editorial_declaration: "Las presentes ediciones digitales están basadas…"
    })

  html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

  assert publication_lines(html) == [
           "Publication: Norton & Company, Valencia, 2012",
           "Authority: Universitat de València",
           "Identifiers: #{play.code}, EMOTHE 0555",
           "Licence: CC BY-NC-ND 4.0 https://creativecommons.org/licenses/by-nc-nd/4.0/",
           "Se ruega citar la procedencia.",
           "El proyecto EMOTHE.",
           "Carlos Muñoz Pons es responsable."
         ]

  assert html =~ ~s(<a href="https://creativecommons.org/licenses/by-nc-nd/4.0/">)

  epub = epub_text(conn, play)
  assert epub =~ "Publication: Norton &amp; Company, Valencia, 2012"
  assert epub =~ "<p>Carlos Muñoz Pons es responsable.</p>"

  # The editorial statement, the same paragraph in every file, stays out (question 24).
  for text <- [html, epub], do: refute(text =~ "Las presentes ediciones")
end

test "the downloads print only what the play has, and link a licence only to a web address",
     %{conn: conn, play: play} do
  assert publication_lines(response(get(conn, ~p"/export/#{play.id}/html"), 200)) ==
           ["Identifiers: #{play.code}"]

  {:ok, play} = Playcode.Catalogue.update_play(play, %{licence_url: "javascript:alert(1)"})
  html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

  assert publication_lines(html) == ["Identifiers: #{play.code}", "Licence: javascript:alert(1)"]
  refute html =~ ~s(href="javascript:)
end
```

If the setup play's import fills a header column with a default (the second test's first assertion then lists it), the test's expectation is wrong, not the code: set that column to nil in the test and say why in a comment.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: both FAIL: `publication_lines/1` returns `[]`.

- [ ] **Step 3: Implement `Html.publication(play, format) :: String.t()`**

Print it in `generate/1` straight after `</header>` and before Task 2's witnesses, and in the EPUB's front chapter in the same place. CSS in both: as `.paratext` for width; 0.75rem, `rgba(51, 51, 51, 0.5)`, `text-align: justify`, a little space between the `p`s.

- [ ] **Step 4: Run the tests again**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: PASS

- [ ] **Step 5: Refactor while green**

One blank test for every value (the site writes `not in [nil, ""]`); no line-building duplicated between the six lines. Re-run the file after each change.

- [ ] **Step 6: Whole suite, format, compile, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -10`
Expected: `0 failures`

```bash
git add lib/playcode/export/html.ex lib/playcode/export/epub.ex test/playcode_web/controllers/export_controller_test.exs
git commit -m "feat: the downloads print the publication details, licence, project and identifiers"
```

---

### Task 4: The docs say it is built

**Files:**
- Modify: `docs/backlog.md` (remove *What the downloads leave out*)
- Modify: `docs/history.md` (add it as `[x]`, 2026-10-25, what was built and decisions 1–7 in a sentence each)
- Modify: `docs/stakeholder/ida-y-vuelta.html`: Downloads cells "Title, author, publication details, licence" (`Partly` 1 → `Yes` 1), "Which play a translation translates" and "Witnesses" (`Not yet` 32 → `Yes` 32); notes 1 and 32 and the bullet at line 315 say what the downloads now print and where, and note 32 says *eight* plays, 0551 among them
- Modify: `docs/stakeholder/preguntas.html`, question 24: a `<p>Built on 25 October 2026: …</p>` after the *Decided* paragraph, naming 0551 as the eighth critical edition by the rule (the answer invited "name any other")
- Modify: `CONTEXT.md`, *The critical apparatus*: a **Critical edition** entry (a play with variants, or an appendix headed "Critical Apparatus"; its downloads print its witnesses)

- [ ] **Step 1: Make the edits.** `grep -n "downloads" docs/stakeholder/ida-y-vuelta.html` for any other sentence that still says "not built yet" about question 24.
- [ ] **Step 2: Check:** `grep -n "not built yet\|Not yet" docs/stakeholder/ida-y-vuelta.html` shows no question-24 leftover.
- [ ] **Step 3: Commit**

```bash
git add docs/backlog.md docs/history.md docs/stakeholder/ida-y-vuelta.html docs/stakeholder/preguntas.html CONTEXT.md
git commit -m "docs: the downloads print what question 24 asked"
```

- [ ] **Step 4: Ask the owner** before republishing the Round Trip and Questions artifacts (memory: *Stakeholder artifacts account*, for the recipe). Publishing is outward-facing.
