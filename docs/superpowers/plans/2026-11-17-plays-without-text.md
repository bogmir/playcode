# Plays Without a Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A play with no verse line and no line of prose is an ordinary play everywhere: it exports to a valid TEI file that imports back to the same rows, and every admin page, download and static page knows what to do with it.

**Architecture:** "Has a text" is read from `plays.auto_form`, which Playcode already recomputes from the elements on every import and content edit; it becomes nullable and nil means no text, behind one function, `Play.has_text?/1`. The TEI export writes `<body><p/></body>` for an empty body. Each output asks `Play.has_text?/1` and leaves out what needs a text.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto/PostgreSQL, Saxy and xml_builder (TEI), HEEx templates for the static site, ExUnit.

**Spec:** `docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md`, sections 5, 7.1, 7.2, 7.3. Read them before Task 1. `CLAUDE.md` holds the project rules; its blocks on TDD, testing through the outermost API, the complete copy, and the static site apply to every task.

## Global Constraints

- Work on branch `feature/plays-without-text` in a git worktree of its own (other sessions switch branches in the main checkout). Check the branch before every commit.
- Every task is red, green, refactor: write the failing test, run it and read the failure, write the smallest code that passes, run it, then clean what you wrote while it stays green, then commit.
- A test written for code that already works proves nothing: break the line it covers and watch it go red with `bin/bites FILE OLD NEW TEST_PATH`, and say so in the commit message.
- Tests go through the outermost API (`live/2`, `get`, `Mix.Task.rerun/2`, `TeiImport.import_file/1`, `StaticSite.generate/1`) and read back through public functions, never `Repo` (CLAUDE.md, *Testing through the outermost API*).
- Run plain `mix test PATH`; `mix format` after every task; no `export PATH=…` prefix.
- Commit messages: `feat:`/`fix:`/`docs:` and a sentence, as `git log` shows. Never a `Co-Authored-By` trailer.
- The word is "play without a text" in prose and "sin texto" / "no text" in the interface. The notice is exactly: msgid `EMOTHE does not hold the text of this play.`, Spanish `EMOTHE no dispone del texto de esta obra.`
- New strings go through gettext: `mix gettext.extract --merge`, then fill `priv/gettext/es/LC_MESSAGES/default.po` and check every entry it marked fuzzy.
- Definition (spec 7.1): a play has a text when it has at least one element of type `verse_line` or `prose`.

## Review Focus

1. **A play with acts and stage directions but no verse or prose** counts as without a text. Its divisions are still written to `<body>` (no `<p/>`), it imports back the same, and the site writes its record only. Test in Task 2.
2. **A published play that loses its last line** (deleted in the content editor): the next `apply_changes/2` removes its `text.html`, division pages, `statistics.html`, and its translations' `compare.html`. Test in Task 6.
3. **A play without a text whose translation has a text and is published**: the translation's title page links the original's record, there is no `compare.html`, and the catalogue's lead has no Compare icon. Test in Task 6.
4. **A file with a text imported over a play without one** (a FileMaker work whose TEI file arrives later): the play gains its text in place, same id, `auto_form` recomputed, curated columns kept, `removes_text` nil. Test in Task 4.
5. **Plays already stored with no text when the migration runs**: `auto_form` and `verse_count` become NULL; a play with a text is untouched; the down migration restores `'prose'`. Checked by hand in Task 1, Step 7.

---

### Task 1: `Play.has_text?/1`, worked out from the elements

**Files:**
- Create: `priv/repo/migrations/20261117100000_play_auto_form_nil_without_text.exs`
- Modify: `lib/playcode/catalogue/play.ex` (field at line 59, `form/1` at 174, `auto_form/2` at 187, moduledoc line 23)
- Modify: `lib/playcode/catalogue.ex` (`update_form_and_verse_count/1` at 216; `without_text/1` at 250; `apply_status(query, :no_text)` at 537)
- Modify: `lib/playcode_web/live/admin/play_list_live.ex` (lines 108, 184-190, 328)
- Modify: `test/support/fixtures.ex` (add `play_without_text_fixture/1`)
- Modify: `test/playcode_web/live/admin/play_list_live_test.exs` (the "No text" describe's `empty` play)
- Modify: `docs/schema.md`
- Test: `test/playcode/catalogue_test.exs`

**Interfaces:**
- Produces: `Playcode.Catalogue.Play.has_text?(%Play{}) :: boolean` (`not is_nil(auto_form)`); `Play.form/1` may return nil; `Playcode.TestFixtures.play_without_text_fixture(attrs \\ %{})` (a `play_fixture/1` with `"auto_form" => nil`); `Catalogue.list_plays(status: :no_text)` unchanged for callers.
- Removes: `Catalogue.without_text/1`.

- [ ] **Step 1: Write the failing tests** in `test/playcode/catalogue_test.exs`, a new `describe "a play's text"`:

```elixir
test "a play made with nothing in it has no text, and no form" do
  {:ok, play} = Catalogue.create_play(%{"title" => "Sin texto", "code" => unique_code(), "language" => "es"})
  refute Play.has_text?(play)
  assert Play.form(play) == nil
  assert play.verse_count == nil
end

test "its first line gives it a text, and deleting its last takes it away" do
  play = play_without_text_fixture()
  {:ok, act} = PlayContent.create_division(%{"play_id" => play.id, "type" => "acto", "position" => 1})
  refute Play.has_text?(Catalogue.get_play!(play.id))          # an act alone is no text

  {:ok, stage} = PlayContent.create_element(%{"play_id" => play.id, "division_id" => act.id, "type" => "stage_direction", "content" => "Sale.", "position" => 1})
  refute Play.has_text?(Catalogue.get_play!(play.id))          # nor a stage direction (Review Focus 1)

  {:ok, line} = PlayContent.create_element(%{"play_id" => play.id, "division_id" => act.id, "type" => "prose", "content" => "", "position" => 2})
  assert Play.has_text?(Catalogue.get_play!(play.id))          # an empty line of prose is a line
  assert Play.form(Catalogue.get_play!(play.id)) == "prose"

  {:ok, _} = PlayContent.delete_element(line)
  refute Play.has_text?(Catalogue.get_play!(play.id))
  assert Catalogue.get_play!(play.id).verse_count == nil
  _ = stage
end

test "the play list's no-text filter finds it" do
  without = play_without_text_fixture()
  with_text = play_fixture()
  codes = Catalogue.list_plays(status: :no_text) |> Enum.map(& &1.code)
  assert without.code in codes
  refute with_text.code in codes
end
```

Take the element and division attribute names from an existing test in `test/playcode/play_content_test.exs` if these differ; the assertions stay.

- [ ] **Step 2: Run** `mix test test/playcode/catalogue_test.exs` — expected: FAIL, `Play.has_text?/1 is undefined`.

- [ ] **Step 3: Implement**
  - Migration `up`: `ALTER TABLE plays ALTER COLUMN auto_form DROP NOT NULL, ALTER COLUMN auto_form DROP DEFAULT`; then `UPDATE plays p SET auto_form = NULL, verse_count = NULL WHERE NOT EXISTS (SELECT 1 FROM play_elements e WHERE e.play_id = p.id AND e.type IN ('verse_line','prose'))`. `down`: `UPDATE plays SET auto_form = 'prose' WHERE auto_form IS NULL`, then restore `NOT NULL DEFAULT 'prose'`. Its `@moduledoc` says why (spec 7.1).
  - `Play`: `field :auto_form, :string` with no default; `def has_text?(%__MODULE__{auto_form: auto_form}), do: not is_nil(auto_form)` with the `@doc` of spec 7.1.
  - `Catalogue.update_form_and_verse_count/1`: also select `count(e.id)` over the same two types; when it is 0 write `auto_form: nil, verse_count: nil`, else as today.
  - Delete `Catalogue.without_text/1`; `apply_status(query, :no_text)` becomes `where(query, [p], is_nil(p.auto_form))` (keep `text_elements/0` only if still used).
  - `PlayListLive`: drop the `without_text` assign; the badge and `verses/1` ask `Play.has_text?(play)`.
  - `play_without_text_fixture/1` in `test/support/fixtures.ex`; `play_fixture/1` keeps `"auto_form" => "verse"` (a comment says why: the suite's "some play" counts as having a text).
  - In `play_list_live_test.exs`, the "No text" describe makes its `empty` play with `play_without_text_fixture/1`.

- [ ] **Step 4: Run** `mix ecto.migrate && mix test test/playcode/catalogue_test.exs test/playcode_web/live/admin/play_list_live_test.exs` — expected: PASS.

- [ ] **Step 5: Refactor while green.** One query in `update_form_and_verse_count/1`, no second round trip; no caller left reading `auto_form` to decide "has a text" except `has_text?/1` (`grep -rn "auto_form" lib`).

- [ ] **Step 6: Run** `mix test` — expected: 0 failures. A failure here is a caller of `Play.form/1` meeting nil in a test that builds a play with nothing: fix it in Task 3 if it is an admin page, Task 6 if the static site, and leave the test red only if you move straight to that task.

- [ ] **Step 7: Check the migration by hand (Review Focus 5).** `mix ecto.rollback --step 1 && mix ecto.migrate`; then `mix run -e 'IO.inspect(Playcode.Repo.query!("select count(*) filter (where auto_form is null), count(*) from plays").rows)'` — the first number is the plays with no text on dev (4 on 2026-11-17), not 0 and not all.

- [ ] **Step 8: `docs/schema.md`**: `auto_form` is nullable; nil means no verse line and no line of prose; read through `Play.has_text?/1`.

- [ ] **Step 9: Commit** — `feat: a play's text is known from its form, nil with none`

---

### Task 2: The TEI file of a play without a text

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`build_extent/1` at 271, the `:body` element in `build_text/4` near 928, and where `build_extent(play)` is called near 139)
- Modify: `docs/tei-mapping.md` (the `body` and `extent` lines)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/roundtrip_test.exs` (slow, schema)

**Interfaces:**
- Consumes: `Play.has_text?/1`, `Play.form/1` (Task 1), `play_without_text_fixture/1`.
- Produces: `TeiXml.generate/2` output with `<body><p/></body>` when the body section has no item, and no `<extent>` when `Play.form/1` is nil.

- [ ] **Step 1: Write the failing tests** in `test/playcode/tei_roundtrip_test.exs`, `describe "a play without a text"`:

```elixir
test "its body is one empty paragraph, and it has no extent" do
  xml = export_tei(play_without_text_fixture())
  assert xml_elements(xml, "p", within: "body") == [{[], ""}]
  assert xml_elements(xml, "extent") == []
end

test "with a form its curator chose, the extent says the form and no count" do
  xml = export_tei(play_without_text_fixture(%{"form" => "verse"}))
  assert [{attrs, ""}] = xml_elements(xml, "extent")
  assert {"ana", "verso"} in attrs
end

test "comes back from its file without a text, and writes the same file again" do
  xml = export_tei(play_without_text_fixture(%{"code" => "EMOTHE9701"}))
  play = import_tei!(xml)                       # same code: re-imported in place
  refute Play.has_text?(play)
  assert Play.form(play) == nil
  assert export_tei(play) == xml
end

test "acts and stage directions alone are written as they are, with no empty paragraph" do
  # Review Focus 1
  xml = roundtrip(~s(… a TEI file whose body is <div1 type="acto" n="1"><head>ACTO I</head><stage>Sale.</stage></div1> …))
  assert xml_elements(xml, "p", within: "body") == []
  assert [_act] = xml_elements(xml, "div1")
  assert xml_elements(xml, "extent") == []
end
```

Build the last file's header with the helper the neighbouring tests use (`tei/1` or its equivalent in `test/support/import_helpers.ex`).

- [ ] **Step 2: Run** `mix test test/playcode/tei_roundtrip_test.exs` — expected: FAIL on `<body/>` (no `p`) and on the `extent` still written.

- [ ] **Step 3: Implement.** In `build_text/4`, an empty body list becomes `[element(:p, nil)]`. `build_extent/1` returns nil when `Play.form(play)` is nil, and its caller drops a nil child as the neighbouring optional elements do.

- [ ] **Step 4: Run** the same file — expected: PASS.

- [ ] **Step 5: Add the schema check.** In `test/playcode/roundtrip_test.exs` (tagged `:slow`), beside the test that validates an export: export `play_without_text_fixture()` and assert `TeiValidator.validate(xml) == {:ok, :valid}`. If the bare fixture's header fails for a reason of its own (an empty `publicationStmt`), build the play with the columns the existing schema test fills. Run `mix test test/playcode/roundtrip_test.exs --include slow` — expected: PASS; with `[element(:p, nil)]` reverted it fails with "Expecting an element, got nothing" (`bin/bites`).

- [ ] **Step 6: Refactor while green**, then `docs/tei-mapping.md`: `body` — "a play without a text: one empty `<p/>`, read back as nothing"; `extent` — "left out when the play has no form".

- [ ] **Step 7: Commit** — `feat: a play without a text exports a valid TEI file and imports back`

---

### Task 3: The admin pages and the downloads

**Files:**
- Modify: `lib/playcode_web/play_labels.ex` (`form_label/1` near 179, the two functions at 186 and 195)
- Modify: `lib/playcode_web/live/admin/play_detail_live.ex` (line 169, the `download_group` at 174)
- Modify: `lib/playcode_web/components/core_components.ex` (`download_group/1` at 519)
- Modify: `lib/playcode_web/controllers/export_controller.ex`
- Modify: `lib/playcode_web/live/admin/play_statistics_live.ex`, `lib/playcode_web/live/admin/play_compare_live.ex`, `lib/playcode_web/live/play_comparison.ex` (`build_family/1` at 56)
- Modify: `lib/playcode_web/components/statistics_panel.ex` (line 21) only if a play without a text can reach it
- Test: `test/playcode_web/live/admin/play_detail_live_test.exs`, `play_form_live_test.exs`, `play_statistics_live_test.exs`, `play_compare_live_test.exs` (admin), `test/playcode_web/controllers/export_controller_test.exs`, `pdf_download_test.exs`

**Interfaces:**
- Consumes: `Play.has_text?/1`, `play_without_text_fixture/1`.
- Produces: `<.download_group base=… formats={~w(tei)} />` (attr `formats`, default `~w(tei html pdf epub)`); `PlayComparison.build_family/1` returns only plays with a text.

- [ ] **Step 1: Write the failing tests.** One per page, each on `play_without_text_fixture()`, logged in as `user_fixture()`:

```elixir
# play_detail_live_test.exs
test "a play without a text offers its TEI file alone, and names no form", %{conn: conn} do
  play = play_without_text_fixture()
  {:ok, view, html} = live(conn, ~p"/admin/plays/#{play.id}")
  assert has_element?(view, ~s(a[href="/admin/plays/#{play.id}/export/tei"]))
  for format <- ~w(html pdf epub), do: refute has_element?(view, ~s(a[href="/admin/plays/#{play.id}/export/#{format}"]))
  refute html =~ t("Prose")
end

# play_form_live_test.exs
test "the form of a play without a text is automatic, with none to name", %{conn: conn} do
  play = play_without_text_fixture()
  {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
  assert html =~ t("Automatic (no text)")
end

# play_statistics_live_test.exs
test "a play without a text has the notice in place of the figures", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play_without_text_fixture().id}/statistics")
  assert html =~ t("EMOTHE does not hold the text of this play.")
end

# admin/play_compare_live_test.exs
test "a play without a text is not compared: back to its page, with the notice", %{conn: conn} do
  play = play_without_text_fixture()
  assert {:error, {:live_redirect, %{to: to, flash: _}}} = live(conn, ~p"/admin/plays/#{play.id}/compare")
  assert to == ~p"/admin/plays/#{play.id}"
end

test "a relative without a text is not offered as a panel", %{conn: conn} do
  # an original with a text and a translation without one: the translation's title is not in the menu
end

# export_controller_test.exs, for each of ~w(html pdf epub), on /export/:id/… and /admin/plays/:id/export/…
test "a play without a text has no #{format}: back to its preview, with the notice", %{conn: conn} do
  play = play_without_text_fixture()
  conn = get(conn, "/export/#{play.id}/#{format}")
  assert redirected_to(conn) == ~p"/plays/#{play.code}"
  assert Phoenix.Flash.get(conn.assigns.flash, :info) == t("EMOTHE does not hold the text of this play.")
end

test "its TEI file downloads", %{conn: conn} do
  assert response(get(conn, "/export/#{play_without_text_fixture().id}/tei"), 200) =~ "<body>"
end

# pdf_download_test.exs
test "a play without a text is never rendered", %{conn: conn} do
  get(conn, ~p"/export/#{play_without_text_fixture().id}/pdf")
  refute_receive {:pdf_render, _}, 200     # the stub's message: use the name the file's other tests match on
  assert File.ls!(PdfCache.dir()) == []
end
```

Write the second compare test in full from `translation_family_fixture/0`, setting the translation's text aside with `play_without_text_fixture(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"})`.

- [ ] **Step 2: Run** the six test files — expected: FAIL (the detail and form pages raise `FunctionClauseError` in `form_label/1` on nil, or print "Prose"; the downloads answer 200).

- [ ] **Step 3: Implement.**
  - `PlayLabels`: the form option list names the automatic form `gettext("Automatic (no text)")` when it is nil; the play's form line (186) is nil for a play without a text, and its callers print nothing. Do not add `form_label(nil)`: a nil form is not a label.
  - `PlayDetailLive`: the form in the header only when `Play.form/1` is not nil; `formats={if Play.has_text?(@play), do: ~w(tei html pdf epub), else: ~w(tei)}`.
  - `ExportController`: `html/2`, `pdf/2` and `epub/2` start with a private `with_text(conn, play, fun)` that, for a play without a text, does `conn |> put_flash(:info, notice) |> redirect(to: ~p"/plays/#{play.code}")` and never calls the renderer or `PdfCache`.
  - `PlayStatisticsLive`: the notice in place of the panel. Admin `PlayCompareLive.mount/3`: `push_navigate` to the play's page with the flash. `PlayComparison.build_family/1`: `Enum.filter(&Play.has_text?/1)`.

- [ ] **Step 4: Run** the six files, then `mix test test/playcode_web/accessibility_test.exs test/playcode_web/authorization_test.exs` — expected: PASS.

- [ ] **Step 5: Refactor while green.** The notice's msgid appears once, in a function both the controller and the LiveViews call (`PlayLabels.no_text_notice/0`).

- [ ] **Step 6: gettext** (extract, merge, Spanish: `Automática (sin texto)`, the notice), `mix format`, commit — `feat: admin pages and downloads know a play without a text`

---

### Task 4: The import preview warns before a text is removed

**Files:**
- Modify: `lib/playcode/import/tei_import.ex` (`preview/2` near 135)
- Modify: `lib/playcode_web/live/admin/import_live.ex` (the preview list near 276-300)
- Modify: `lib/playcode/import/tei_corpus.ex` (`replace_lines/2` near 142)
- Test: `test/playcode/import/tei_preview_test.exs`, `test/playcode_web/live/admin/import_live_test.exs`, `test/mix/tasks_test.exs`, `test/playcode/import/tei_reimport_test.exs`

**Interfaces:**
- Produces: `TeiImport.preview_import/2`'s map gains `removes_text: pos_integer() | nil` — the number of verse lines and lines of prose the stored play holds, when it holds some and the file holds none; nil otherwise.

- [ ] **Step 1: Write the failing tests.**

```elixir
# tei_preview_test.exs
test "a file with no text over a play with one says how many lines go" do
  play = import_tei!(file_with_two_verses(code: "EMOTHE9702"))
  path = write_tmp!(export_tei(play_without_text_fixture()) |> String.replace(~r/EMOTHE\d+/, "EMOTHE9702"))
  assert {:ok, %{removes_text: 2}} = TeiImport.preview_import(path, numbering: false)
end

test "removes_text is nil for a new play, for a file with a text, and over a play without one" do
  # three previews, each asserting removes_text == nil
end

# tei_reimport_test.exs — Review Focus 4
test "a file with a text over a play without one gives it the text in place" do
  without = play_without_text_fixture(%{"code" => "EMOTHE9703", "team_note" => "de FileMaker", "is_complete" => true})
  play = import_tei!(file_with_two_verses(code: "EMOTHE9703"))
  assert play.id == without.id
  assert Play.has_text?(play)
  assert play.team_note == "de FileMaker"
end

# import_live_test.exs
test "the confirmation warns that the play's text will be removed", %{conn: conn} do
  # upload the no-text file of the first test over the play with two verses
  assert render(view) =~ t("This file has no text: the play's %{count} lines will be removed.", count: 2)
end

# tasks_test.exs
test "the dry run of the TEI import says a file with no text would remove the play's lines" do
  # Mix.Task.rerun("playcode.import.tei", ["--dry-run", "--force", dir]); the output names the code and "no text: 2 lines would be removed"
end
```

Use the file builders these test files already have for "a file with two verses"; give each play a code no other test uses.

- [ ] **Step 2: Run** the four files — expected: FAIL, no `removes_text` key.

- [ ] **Step 3: Implement.** In `preview/2`: count the parsed file's `verse_line` and `prose` elements (walk `tei.divisions` as `parts_out_of_order/1` does); when it is 0 and `existing` holds some (a count query scoped to the play), `removes_text` is that number. `ImportLive` prints it in the warning style of the `edited` line; `TeiCorpus.replace_lines/2` appends `"; no text: N lines would be removed"`.

- [ ] **Step 4: Run** the four files — expected: PASS.

- [ ] **Step 5: Refactor while green**; gettext (Spanish: `Este archivo no tiene texto: se eliminarán las %{count} líneas de la obra.`); commit — `feat: the import preview says when a file with no text removes a play's text`

---

### Task 5: The complete copy holds a play without a text

**Files:**
- Modify: `test/playcode/complete_copy_test.exs` (a third test beside lines 50 and 69, a builder beside `rare_play/0` at 282)

**Interfaces:**
- Consumes: the file's own builders (`credits!/2`, `witnesses!/1`, `bibliography!/1`, `places!/1`, `performances!/1`, `paratexts!/2`, `cast!/2`, `round_trip/1`).

- [ ] **Step 1: Write the test** `"a play without a text comes back whole from its TEI file"`: a builder `play_without_text/0` that makes a play with every curated column filled as `ordinary_play/1` fills them, credits, a witness, a bibliography link, a place, a performance, a paratext before and after, and a cast list with two characters (`cast!/2`), and no act, scene or line; then `assert round_trip(&play_without_text/0) == []` in the shape the two existing tests use.

- [ ] **Step 2: Run** `mix test test/playcode/complete_copy_test.exs` — expected: PASS if Tasks 1 and 2 are right. Prove it bites twice with `bin/bites`: revert the `[element(:p, nil)]` of Task 2 (the import then fails or the file differs), and revert the nil `verse_count` of Task 1 (the column differs, nil against 0).

- [ ] **Step 3: If a difference shows** (a cast list or paratext placed differently with no act between them), it is a real break of the complete copy: fix the export or the import, not the test, and add the case to `tei_roundtrip_test.exs`.

- [ ] **Step 4: Refactor while green**: share with `ordinary_play/1` what both builders fill. Commit — `test: the complete copy holds a play without a text`

---

### Task 6: The static site

**Files:**
- Modify: `lib/playcode/export/static_site.ex` (`write_play/4` at 549, `write_comparison/4` at 599, `works/1` at 672)
- Modify: `lib/playcode/export/static_site/pages/title.html.heex`
- Modify: `lib/playcode/export/static_site/components.ex` (`play_rail/1`, `play_contents/1` at 290, `form_summary/2` at 639, `catalogue_entry/1` at 1576, `entry_meta/1` at 1617)
- Modify: `lib/playcode/export/static_site/comparison.ex` (`menu/1`'s input)
- Modify: `docs/static-site.md`
- Test: `test/playcode/export/static_site_play_test.exs`, `static_site_catalogue_test.exs`, `static_site_compare_test.exs`, `static_site_changes_test.exs`

**Interfaces:**
- Consumes: `Play.has_text?/1`, `play_without_text_fixture/1`, `generate!/2`, `html!/3`, `read!/2`, `texts/2` (`test/support/static_site_helpers.ex`).
- Produces: for a play without a text, `plays/CODE/` holds exactly `index.html` and `CODE.xml`; its catalogue row carries `<span class="tag">` with the words "sin texto" / "no text". Plan 2 reads `Play.has_text?/1` only.

- [ ] **Step 1: Write the failing tests.**

```elixir
# static_site_play_test.exs
test "a play without a text has its record and its TEI file, and nothing else" do
  play = play_without_text_fixture(%{"is_complete" => true})
  dir = generate!([play])
  assert dir |> Path.join("plays/#{play.code}") |> File.ls!() |> Enum.sort() == ["#{play.code}.xml", "index.html"]
  assert File.exists?(Path.join(dir, "plays/#{play.code}.html"))      # the old layout's redirect
  assert File.dir?(Path.join(dir, "search/lines/#{play.code}"))       # the index's bookkeeping
end

test "its title page says there is no text, in a Text section, and lists no page to go to" do
  play = play_without_text_fixture(%{"is_complete" => true})
  page = html!(generate!([play]), "plays/#{play.code}/index.html", "es")
  assert "Texto" in texts(page, "article h2")
  refute "Índice" in texts(page, "article h2")
  assert texts(page, "article") |> Enum.join() =~ "EMOTHE no dispone del texto de esta obra."
  refute "Forma" in texts(page, "dl.facts dt")
  links = page |> LazyHTML.query("a") |> LazyHTML.attribute("href")
  for gone <- ~w(text.html statistics.html notes.html), do: refute gone in links
  assert "#{play.code}.xml" in links
end

test "its cast list, witnesses and performances print as any play's" do
  # a play without a text with cast!/witness/performance fixtures: the names are on the title page
end

# static_site_catalogue_test.exs
test "a play without a text is in the catalogue, tagged, with its years and no form" do
  play = play_without_text_fixture(%{"is_complete" => true, "title" => "El Adonis", "composition_date_from" => 1632})
  row = html!(generate!([play]), "index.html", "es") |> LazyHTML.query("[data-play]")
  assert texts(row, ".tag") |> Enum.member?("sin texto")
  assert texts(row, ".meta") == ["1632"]
end

# static_site_compare_test.exs — Review Focus 3
test "a translation is not compared with an original that has no text" do
  original = play_without_text_fixture(%{"is_complete" => true})
  translation = play_fixture(%{"is_complete" => true, "parent_play_id" => original.id, "relationship_type" => "traduccion"})
  dir = generate!([original, translation])
  refute File.exists?(Path.join(dir, "plays/#{translation.code}/compare.html"))
  assert html!(dir, "index.html") |> LazyHTML.query("a.compare") |> Enum.empty?()
  assert "../#{original.code}/index.html" in (html!(dir, "plays/#{translation.code}/index.html") |> LazyHTML.query("a") |> LazyHTML.attribute("href"))
end

# static_site_changes_test.exs — Review Focus 2
test "a published play that loses its text keeps its record alone" do
  # import a two-verse play, complete; apply_changes([{:add, id}]); delete its elements through
  # PlayContent.delete_elements/1; apply_changes([{:add, id}]) again:
  # text.html, statistics.html and the act page are gone; index.html and CODE.xml remain
end
```

- [ ] **Step 2: Run** the four files — expected: FAIL (`text.html` and `statistics.html` exist; "Índice" printed; `form_summary/2` raises on nil).

- [ ] **Step 3: Implement.**
  - `write_play/4`: for `not Play.has_text?(play)`, write `index.html`, the TEI file and the redirect stub, and return `%{largest_page_gzip: 0, compare_gzip: 0}`. Structure it as two clauses or one early branch, not `if` around each file.
  - `write_comparison/4`: its condition also needs `Play.has_text?/1` of the play and of the parent. `works/1`: `compare` finds the first derived play with a text, and only for a lead with one. The comparison menu takes only plays with a text.
  - `title.html.heex`: with a text, as today; without, `<section><h2>{t("Text")}</h2><p>{t("EMOTHE does not hold the text of this play.")}</p></section>` in place of the Contents section; the Form `dt`/`dd` only when `Play.form/1` is not nil.
  - `play_rail/1` / `play_contents/1`: for a play without a text, the title page entry and the title page's own anchors only.
  - `catalogue_entry/1`: the `no text` tag; `entry_meta/1` gives the years alone (or nothing) when the form is nil.

- [ ] **Step 4: Run** the four files, then `mix test test/playcode/export` — expected: PASS.

- [ ] **Step 5: Refactor while green.** `Play.has_text?/1` is asked in `static_site.ex` and the templates, never re-derived from `edition.items`.

- [ ] **Step 6: `docs/static-site.md`**: what a play without a text gets. gettext (Spanish: `Texto`, `sin texto`). `mix format`. Commit — `feat: the site publishes a play without a text as its record`

---

### Task 7: The preview page (skip if the preview is the site's pages)

**Skip this task when `lib/playcode_web/live/play_show_live.ex` does not exist**: the branch `feature/preview-real-site-pages` made `/plays/:code` the static title page, which Task 6 covers. In that case add one test to `test/playcode_web/controllers/play_preview_controller_test.exs`: the preview of a play without a text serves a title page holding the notice, and `/plays/:code/compare` is a 404; then commit.

**Files (when the file exists):**
- Modify: `lib/playcode_web/live/play_show_live.ex`, `lib/playcode_web/live/play_compare_live.ex`
- Test: `test/playcode_web/live/play_show_live_test.exs`, `test/playcode_web/live/play_compare_live_test.exs`

- [ ] **Step 1: Write the failing tests**: `/plays/CODE` of a play without a text renders the notice where the text goes and no statistics tab; `/plays/CODE/compare` redirects to `/plays/CODE` with the notice.
- [ ] **Step 2: Run** both files — expected: FAIL (an empty text area; the compare page renders).
- [ ] **Step 3: Implement** with `Play.has_text?/1` and `PlayLabels.no_text_notice/0`.
- [ ] **Step 4: Run** both files and `test/playcode_web/accessibility_test.exs` — expected: PASS.
- [ ] **Step 5: Refactor while green; commit** — `feat: the preview of a play without a text says so`

---

### Task 8: The words, the documents, the whole suite

**Files:**
- Modify: `CONTEXT.md` (the two entries of spec 7.1, word for word)
- Modify: `docs/architecture.md` (file map: nothing new; the decision "a play's text is known from `auto_form`")
- Modify: `docs/stakeholder/ida-y-vuelta.html` (a row "Una obra sin texto": admin yes; TEI export yes, `<body><p/></body>`; TEI import yes; HTML/PDF/EPUB none, by design; play page the notice; static site the record)
- Modify: `docs/backlog.md` (the item *Plays without a text* is rewritten in this session's design; mark this plan's part done) and `docs/history.md` (the entry, with its tests)

- [ ] **Step 1:** Write the documents. In `ida-y-vuelta.html` follow the markup of a neighbouring row; "none, by design" is an exception the page explains, not a backlog item.
- [ ] **Step 2: Run** `mix precommit`, then `mix test --include slow test/playcode/roundtrip_test.exs`, then `node --test test/js/*.test.mjs` — expected: 0 failures in each. Paste the three summaries into the commit body.
- [ ] **Step 3: Commit** — `docs: plays without a text`
- [ ] **Step 4:** Tell the owner the branch is ready to merge. Do not open a pull request (solo project); merge and push only when told.
