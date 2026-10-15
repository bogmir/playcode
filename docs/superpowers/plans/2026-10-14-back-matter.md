# Paratexts: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every text before or after a play's text (a *paratext*, `CONTEXT.md`) comes back from the file with its kind, its place and its line breaks, is printed where the file puts it, and can be corrected and reordered in the admin; the table and the code speak the glossary.

**Architecture:** `play_editorial_notes` becomes `play_paratexts` (`Paratext`, column `kind`), with a `back` flag. A fixed map in `Paratext` tells an editorial text and the scene of the action from the rest. One placement rule, `PlayLabels.split_paratexts/2` → `{front, scene, back}`, feeds the play page, the downloads and the site. Line breaks are `\n` inside a paragraph, as a witness's fields hold them.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, Saxy (parser), xml_builder (export), BUPE (EPUB).

**Spec:** `docs/superpowers/specs/2026-10-14-back-matter-design.md` (read it first: the survey, the decisions table and what is left out). Glossary: `CONTEXT.md`.

## Global Constraints

- Branch `paratexts` from `main`. **No commit until the user asks**; the commit lines below are the messages to use then, one commit or one per task as they choose.
- TDD in CLAUDE.md's order: failing test, watch it fail, smallest implementation, watch it pass, **refactor while green**, then `mix test` (whole suite). A test written for code that already works is broken once to show it bites.
- `mix format` after every task; `mix compile --warnings-as-errors` before any commit. Run mix plainly, no PATH export.
- Test through the outermost API: TEI as round trips (`roundtrip/1`, `xml_texts/3`, `xml_elements/3` in `test/support/import_helpers.ex`); LiveViews with `live/2`, `form/3`, `render_submit/1`; downloads with `get`; the API with `get`; the site through `generate!/1`. Read back through context functions, never `Repo`.
- The parser stays pure: no new app call from `TeiParser` unless it goes on `@pure_helpers` in `test/playcode/import/tei_parser_test.exs`. The kind map lives in `Paratext`, which the parser does not call: the parser only renames the two aliases.
- The file names no FileMaker or Playcode identifier.
- A paratext's text holds `<<…>>` italics: print it through the renderers (`PlayText.inline_content`, `Components.inline`, `NoteMarkup.inline`), plain where markup cannot go (`InlineMarkup.plain/1`).
- Words from `CONTEXT.md` in code, docs and the admin: paratext, editorial text, kind, licence to print, scene of the action. Not "editorial note", "section", "section type".
- Slow-suite DBConnection timeouts under load are noted, not chased.

## Review Focus

1. **A play already in Playcode, re-imported.** Its hand-entered paratexts (`origin: "manual"`) keep `back`, kind and order; only `tei` rows are replaced. Pinned in Task 3.
2. **A kind the admin does not know**, from a file: editing the paratext's heading must not change its kind. Pinned in Task 2.
3. **The scene of the action marked "after the text"**: refused, never a `<set>` inside `<back>`. Pinned in Task 3.
4. **Line breaks round-trip**: `<lb/>` in, `<lb/>` out; `<lb/><lb/>` comes back as two paragraphs and stays so. Pinned in Task 4.
5. **The schema**: every kind written stays a valid `@type`; `<back>` validates with paratexts before the bibliography; `<lb/>` inside a paratext's `<p>` validates. Pinned in Tasks 2–4 (`tei_validator_test.exs`, slow).
6. **The rename**: nothing still says `editorial_note` outside migrations and the activity-log migration; old activity-log rows still render. Pinned in Task 1.
7. **The preview's count**: a freshly imported play reports 0 edited rows. Pinned in Task 8.

## File map

| File | Change |
|---|---|
| `priv/repo/migrations/20261015100000_rename_editorial_notes_to_paratexts.exs` | table and column rename; activity-log rows `editorial_note` → `paratext` |
| `priv/repo/migrations/20261015110000_add_back_to_play_paratexts.exs` | `back` boolean, default false, not null |
| `lib/playcode/catalogue/paratext.ex` (from `play_editorial_note.ex`) | `kind`, `back`; `kinds/0`, `editorial?/1`, `scene?/1`; token check; heading or content; scene not `back` |
| `lib/playcode/catalogue.ex`, `catalogue/play.ex` | `*_paratext*` functions, `reorder_paratexts/2`, `Play.paratexts` |
| `lib/playcode_web/play_labels.ex` | `kind_label/1`, `kind_options/1` (grouped); `split_paratexts/2` replaces `split_front_matter/2` |
| `lib/playcode/import/tei_parser.ex` | kinds kept, two aliases; back paratexts; heading-only; line breaks; moduledoc |
| `lib/playcode/import/tei_import.ex`, `word_parser.ex` | `paratexts`; the preview's edited-row count |
| `lib/mix/tasks/playcode.import.tei.ex` | `--dry-run` prints the edited-row count |
| `lib/playcode/export/tei_xml.ex` | front writes the non-`back` paratexts, `build_back` the `back` ones before the bibliography; `\n` → `<lb/>` |
| `lib/playcode_web/live/admin/play_content_editor_live.ex` | tab "Paratexts"; grouped "Kind" select; "After the text"; drag order; new one last |
| `lib/playcode_web/live/play_show_live.ex` | back paratexts after the text, in the navigation; line breaks |
| `lib/playcode/export/html.ex`, `epub.ex` | back paratexts after the text |
| `lib/playcode/export/static_site/components.ex`, `pages/text.html.heex`, `pages/division.html.heex`, `pages/title.html.heex` | back paratexts; Contents entries; line breaks; `note_heading/1` removed |
| `lib/playcode_web/controllers/api/play_controller.ex` | `paratexts`, `scene_of_action` |
| `lib/playcode/activity_log/entry.ex`, `live/admin/activity_log_live.ex` | type `paratext` |
| `lib/playcode_web/demo/ui_demo_data.ex`, `controllers/demo_ui_html/public_play.html.heex` | the rename |
| tests | the rename across `test/`; new tests in `tei_roundtrip_test.exs`, `tei_import_test.exs`, `tei_validator_test.exs`, `roundtrip_test.exs`, `play_content_editor_live_test.exs`, `play_show_live_test.exs`, `export_controller_test.exs`, `static_site_test.exs`, `api/play_controller_test.exs`, `test/mix/tasks_test.exs` |
| `priv/gettext/es/LC_MESSAGES/default.po` | the kinds, the tab, the checkbox, the select's groups |
| docs | round-trip page, backlog, history, `CLAUDE.md` (TEI mappings, the `play_paratexts` lines) |

---

### Task 1: The rename: editorial notes are paratexts

A rename first, on its own, so every later diff speaks the glossary. Behaviour stays the same except the words a person sees (the admin tab, the activity log).

**Files:** every file in `grep -rln "editorial_note\|EditorialNote" lib test` (24 today), the first migration above.

- [ ] **Step 1: Failing tests.** In `play_content_editor_live_test.exs`, the tab and its button by their new words:

```elixir
  # The glossary's word (CONTEXT.md): a dedication, an epilogue or an editor's
  # introduction is a paratext, not an "editorial note".
  test "the paratexts tab adds a paratext", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form", paratext: %{"kind" => "dedicatoria", "content" => "Al duque."})
    |> render_submit()

    assert [%{kind: "dedicatoria", content: "Al duque."}] = Catalogue.list_paratexts(play.id)
  end
```

and in the activity log's test, an entry of type `paratext` renders as "paratext" (`t("paratext")`). Check the tab's real selector in the existing editorial-notes tests first and keep it.

- [ ] **Step 2: Run, watch them fail** (no such tab, no `list_paratexts/1`).

- [ ] **Step 3: Migration.**

```elixir
defmodule Playcode.Repo.Migrations.RenameEditorialNotesToParatexts do
  use Ecto.Migration

  # The glossary's word (CONTEXT.md). A renamed table keeps its play_row_changed() trigger.
  def change do
    rename table(:play_editorial_notes), to: table(:play_paratexts)
    rename table(:play_paratexts), :section_type, to: :kind

    execute(
      "UPDATE activity_logs SET resource_type = 'paratext' WHERE resource_type = 'editorial_note'",
      "UPDATE activity_logs SET resource_type = 'editorial_note' WHERE resource_type = 'paratext'"
    )
  end
end
```

Check the index and constraint names the table rename leaves (`play_editorial_notes_play_id_index`, the foreign key); rename them too with `execute/2` so `\d play_paratexts` reads cleanly, or say in the moduledoc why not.

- [ ] **Step 4: Rename.** `PlayEditorialNote` → `Paratext` (`git mv` the file), `section_type` → `kind`, `Play.editorial_notes` → `Play.paratexts`, `Catalogue.list_play_editorial_notes/1` → `list_paratexts/1` and likewise `get_paratext/2`, `create_paratext/1`, `update_paratext/2`, `delete_paratext/1`, `change_paratext/2`; the parser's and the Word parser's `editorial_notes:` → `paratexts:`; the preview's `notes:` count key → `paratexts:` (and the import page and `--dry-run` wording); the admin tab "Paratexts", button "Add Paratext", form `#paratext-form` (`as={:paratext}`), events `new_paratext`, rows `paratext-#{id}`, flashes "Paratext saved." / "Paratext deleted.", the modal title; the activity-log type `paratext` in `Entry` and its label in `activity_log_live.ex`; `content_version_test.exs`'s table name. The API keeps `editorial_notes` until Task 7. Migrations stay as written.

- [ ] **Step 5: Spanish** in `default.po`: Paratextos, Añadir paratexto, Paratexto guardado., Paratexto eliminado., paratexto (`mix gettext.extract --merge`, then check every fuzzy entry).

- [ ] **Step 6: Pass; prove nothing is left.** `mix test`; then `grep -rn "editorial_note\|EditorialNote\|section_type" lib test` prints nothing but migrations' history (the API's `editorial_notes` key until Task 7). The fingerprint test (`fingerprint_test.exs`) names the export's modules: update it if it names the old one.

- [ ] **Step 7: Refactor while green**, `mix format`, `mix compile --warnings-as-errors`.

Commit message: `refactor: editorial notes are paratexts, as the glossary names them`

---

### Task 2: Every paratext keeps its kind; the kind decides the concept

**Files:** `lib/playcode/catalogue/paratext.ex`, `lib/playcode/import/tei_parser.ex` (`section_type/1`, renamed `kind/1`), `lib/playcode_web/play_labels.ex`, `lib/playcode_web/live/admin/play_content_editor_live.ex` (remove its private `section_type_options/0` and `section_type_label/1`), `lib/playcode/export/static_site/components.ex` (remove `note_heading/1`), `pages/title.html.heex`.
**Test:** `tei_roundtrip_test.exs`, `play_content_editor_live_test.exs`, `catalogue_test.exs` (or the paratexts' context test), `roundtrip_test.exs`.

**Interfaces:**
- Produces: `Paratext.kinds() :: [String.t()]`, `Paratext.editorial?(kind) :: boolean`, `Paratext.scene?(kind) :: boolean`; `PlayLabels.kind_label(kind) :: String.t()` (the word itself for an unknown kind); `PlayLabels.kind_options(current \\ nil) :: [{group, [{label, kind}]}]`.

- [ ] **Step 1: Failing round-trip tests:**

```elixir
  # Until 2026-10-15 any kind outside five became "nota": 285 paratexts on dev lost theirs.
  test "a paratext keeps its kind, a new one included; nota is a note on the digital edition" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="nota_edicion_digital"><head>Nota a esta edición digital</head><p>Texto.</p></div>
          <div type="epistola"><head>Épître</head><p>Sire.</p></div>
          <div type="carta_al_lector"><p>Lector.</p></div>
          <div type="nota"><p>Note sur cette édition numérique.</p></div>
          <div><p>Sin tipo.</p></div>
          """
        )
      )

    assert xml_elements(xml, "div", within: "front") |> Enum.map(&elem(&1, 0)["type"]) ==
             ~w(nota_edicion_digital epistola carta_al_lector nota_edicion_digital nota_edicion_digital)
  end

  # 45 files give the scene of the action as a div; <set> is TEI's element for it.
  test "a circunstancia_accion div is the scene of the action, after the cast list" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="elenco"><castList><castItem><role xml:id="DON">Don</role></castItem></castList></div>
          <div type="circunstancia_accion"><head>The Scene:</head><p>London</p></div>
          """
        )
      )

    assert xml_texts(xml, "p", within: "set") == ["London"]
    refute xml =~ "circunstancia_accion"
  end
```

(`xml_elements/3` returns `{attrs, text}`; adapt the `Enum.map` to the helper's exact shape.)

- [ ] **Step 2: Run, watch them fail**: kinds come back as `nota`; no `<set>`.

- [ ] **Step 3: Failing admin tests** in `play_content_editor_live_test.exs`:

```elixir
  # As a stage direction's: the select offers the known kinds and keeps a file's other word.
  test "a paratext keeps a kind the admin does not offer", %{conn: conn} do
    play = import_tei!(tei(front: ~s(<div type="carta_al_lector"><p>Lector.</p></div>)))
    [paratext] = Playcode.Catalogue.list_paratexts(play.id)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("#paratext-#{paratext.id} button[aria-label='#{t("Edit")}']") |> render_click()

    lv |> form("#paratext-form", paratext: %{"heading" => "Al lector"}) |> render_submit()

    assert [{%{"type" => "carta_al_lector"}, _}] = xml_elements(export_tei(play), "div", within: "front")
  end

  # Three groups, so the 19 kinds can be found: what the early edition printed, what this
  # edition wrote, and the scene of the action.
  test "the kind select is grouped", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    assert has_element?(lv, "#paratext-form label", t("Kind"))
    assert has_element?(lv, ~s(optgroup[label="#{t("Editorial texts")}"] option[value="apendice"]))
    assert has_element?(lv, ~s(optgroup[label="#{t("Printed with the play")}"] option[value="licencia"]), t("Licence to print"))
  end
```

(Check the row id and the edit button's label in the template first; use what the page renders.) Also, in the context test: `create_paratext/1` with `kind: "two words"` returns `{:error, changeset}` with an error on `:kind`.

- [ ] **Step 4: Run, watch them fail.**

- [ ] **Step 5: Implement.** `Paratext`:

```elixir
  @printed ~w(dedicatoria epistola introduccion_autor prologo argumento licencia
              noticia_representacion title_page head_title epilogo despedida colofon)
  @editorial ~w(nota_edicion_digital introduccion_editor_digital introduccion_editor
                introduccion_traductor apendice)
  @scene "lugar_accion"

  @doc "The kinds Playcode names, in the admin's order; a file may give another word, which is kept."
  def kinds, do: @printed ++ @editorial ++ [@scene]

  @doc "Whether a kind is an editorial text, written for this edition (CONTEXT.md)."
  def editorial?(kind), do: kind in @editorial

  @doc "Whether a kind is the scene of the action, printed with the cast list."
  def scene?(kind), do: kind == @scene

  # in changeset/2, replacing validate_inclusion(:kind, …): one TEI token
  # (teidata.enumerated), so whatever is stored exports schema-valid.
  |> validate_format(:kind, ~r/^[^\p{C}\p{Z}]+$/u)
```

Expose the three lists to `PlayLabels` (`printed_kinds/0`, `editorial_kinds/0`, or `kinds_by_group/0`; whichever reads best). The moduledoc says what a paratext is (CONTEXT.md), that the kind decides the concept, and names `lugar_accion`.

Parser, `section_type/1` renamed `kind/1`:

```elixir
  # The file's own word, kept as a stage direction's is. The scene of the action, which 45
  # files give as a div, is TEI's <set>; nota (0784's only) is a note on the digital edition.
  defp kind("circunstancia_accion"), do: "lugar_accion"
  defp kind(type) when type in ~w(nota front), do: "nota_edicion_digital"
  defp kind(type), do: type
```

(`front/1` gives `"front"` for a div with no `@type`.)

`PlayLabels`, beside the stage directions' pair, reusing `with_current/3`:

```elixir
  @doc "The name of a paratext's kind (`Paratext.kinds/0`); a file's other word as itself."
  def kind_label("dedicatoria"), do: gettext("Dedication")
  def kind_label("epistola"), do: gettext("Epistle")
  def kind_label("introduccion_autor"), do: gettext("Author's address to the reader")
  def kind_label("prologo"), do: gettext("Prologue")
  def kind_label("argumento"), do: gettext("Argument")
  def kind_label("licencia"), do: gettext("Licence to print")
  def kind_label("noticia_representacion"), do: gettext("Performance notice")
  def kind_label("title_page"), do: gettext("Title page")
  def kind_label("head_title"), do: gettext("Head title")
  def kind_label("epilogo"), do: gettext("Epilogue")
  def kind_label("despedida"), do: gettext("Post-script")
  def kind_label("colofon"), do: gettext("Colophon")
  def kind_label("nota_edicion_digital"), do: gettext("Note on the digital edition")
  def kind_label("introduccion_editor_digital"), do: gettext("Introduction to the digital edition")
  def kind_label("introduccion_editor"), do: gettext("Editor's introduction")
  def kind_label("introduccion_traductor"), do: gettext("Translator's note")
  def kind_label("apendice"), do: gettext("Appendix")
  def kind_label("lugar_accion"), do: gettext("Scene of the action")
  def kind_label(kind), do: kind

  @doc "The kinds for a grouped select, keeping `current` when a file gave another word."
  def kind_options(current \\ nil)
```

`kind_options/1` returns `[{gettext("Printed with the play"), [...]}, {gettext("Editorial texts"), [...]}, {gettext("Scene of the action"), [...]}]`, which `Phoenix.HTML.Form.options_for_select/2` (behind `<.input type="select">`) renders as `<optgroup>`s; an unknown `current` goes first, ungrouped (look at how `with_current/3` adds it for stage directions and do the same). Content editor: the select's label "Kind", `options={PlayLabels.kind_options(@editing && @editing.kind)}`; its list rows call `PlayLabels.kind_label/1`; delete the private pair.

Site: `title.html.heex` uses `PlayLabels.kind_label(paratext.kind)`; delete `Components.note_heading/1` (the site renders in English, `StaticSite.in_english/1`).

Spanish in `default.po` (`mix gettext.extract --merge`, then check every fuzzy entry): Tipo, Impreso con la obra, Textos editoriales, Epístola, Advertencia del autor al lector, Licencia de impresión, Noticia de la representación, Portada, Título de cabecera, Epílogo, Despedida, Colofón, Nota a la edición digital, Introducción a la edición digital, Nota del traductor, Apéndice.

- [ ] **Step 6: Corpus counters.** `roundtrip_test.exs`'s `count_front_note_divs/1` counts a `circunstancia_accion` div in the original and a `<set>` in the export: count a front `<set>` with paragraphs as a paratext on both sides, with a comment saying why. Run `mix test --include slow test/playcode/roundtrip_test.exs`: the fixtures with `circunstancia_accion` (0281, 0341, 0346, 0502, 0648…) stay green.

- [ ] **Step 7: Pass; prove the bite**: put `defp kind(_type), do: "nota"` back for a run, see the round-trip and admin tests red, restore.

- [ ] **Step 8: Refactor while green**, then `mix test`, `mix format`.

Commit message: `feat(tei): every paratext keeps its kind, and circunstancia_accion is the scene of the action`

---

### Task 3: Paratexts after the text, and heading-only ones, are read, stored and written back

**Files:** the `back` migration; `paratext.ex`; `tei_parser.ex` (`text/1`, new `back_matter/2`, `paratext/3` keeps a heading-only div); `tei_xml.ex` (`build_front/3`, `build_text/3`, `build_back`); the content editor (checkbox, list row).
**Test:** `tei_roundtrip_test.exs`, `tei_import_test.exs`, `tei_validator_test.exs`, `roundtrip_test.exs`, `play_content_editor_live_test.exs`.

**Interfaces:**
- Consumes: Task 2's `kind/1`.
- Produces: `Paratext.back :: boolean`; parser maps `paratexts: [%{kind, heading, content, position, back}]`.

- [ ] **Step 1: Failing tests.** Round trip:

```elixir
  # The Rover's epilogue and post-script, Everyman's appendices: after the text, before the
  # bibliography, as the files put them.
  test "a paratext after the text comes back after it, before the bibliography" do
    xml =
      roundtrip(
        tei(
          body: ~s(<div1 type="acto" n="1"><head>ACT I</head><sp><speaker>A</speaker><p>Hola.</p></sp></div1>),
          back: """
          <div type="epilogo"><head>EPILOGUE</head><p>The banished <emph>cavaliers</emph>!</p></div>
          <div type="despedida"><head>POST-SCRIPT</head><p>This play had been sooner in print.</p></div>
          <div type="bibliografia"><listBibl type="ediciones_modernas"><biblStruct type="book"><monogr><title>T</title><imprint><date>1990</date></imprint></monogr></biblStruct></listBibl></div>
          """
        )
      )

    assert xml_elements(xml, "div", within: "back") |> Enum.map(&elem(&1, 0)["type"]) ==
             ~w(epilogo despedida bibliografia)

    assert xml_texts(xml, "head", within: "back") == ["EPILOGUE", "POST-SCRIPT"]
    assert xml =~ "<emph>cavaliers</emph>"
    refute xml_texts(xml, "head", within: "front") |> Enum.member?("EPILOGUE")
  end

  # 12 head titles and 4 notes on the digital edition are a heading alone.
  test "a paratext with a heading and no paragraphs comes back" do
    xml = roundtrip(tei(front: ~s(<div type="head_title"><head>THE MALCONTENT</head></div>)))

    assert [{%{"type" => "head_title"}, _}] = xml_elements(xml, "div", within: "front")
    assert xml_texts(xml, "head", within: "front") |> Enum.member?("THE MALCONTENT")
  end
```

In `tei_import_test.exs` (review focus 1):

```elixir
  test "a re-import adds the file's paratexts after the text and keeps a hand-entered one" do
    path = write_tmp!(tei(code: "TBACK1", back: ~s(<div type="colofon"><p>Loado sea.</p></div>)))
    {:ok, play} = TeiImport.import_file(path)
    {:ok, _} = Catalogue.create_paratext(%{play_id: play.id, kind: "dedicatoria", content: "A mano."})

    {:ok, _} = TeiImport.import_file(path)

    paratexts = Catalogue.list_paratexts(play.id)
    assert [%{content: "A mano.", back: false}] = Enum.filter(paratexts, &(&1.origin == "manual"))
    assert [%{kind: "colofon", back: true}] = Enum.filter(paratexts, &(&1.origin == "tei"))
  end
```

- [ ] **Step 2: Run, watch them fail** (nothing after the text in the export; the heading-only div dropped; `back` is no field).

- [ ] **Step 3: Migration and schema.**

```elixir
defmodule Playcode.Repo.Migrations.AddBackToPlayParatexts do
  use Ecto.Migration

  # A paratext after the text (TEI's <back>): an epilogue, a licence to print, a colophon.
  # play_paratexts has its play_row_changed() trigger; a column needs nothing.
  def change do
    alter table(:play_paratexts) do
      add :back, :boolean, default: false, null: false
    end
  end
end
```

`Paratext`: `field :back, :boolean, default: false`, cast it; `content` is required only without a heading; and

```elixir
  # The scene of the action is printed with the cast list and written as the front's <set>.
  defp validate_scene_before_text(changeset) do
    if scene?(get_field(changeset, :kind)) and get_field(changeset, :back),
      do: add_error(changeset, :back, dgettext("errors", "the scene of the action stands with the cast list")),
      else: changeset
  end
```

(Use the error idiom the other changesets use; check whether they translate messages.) `mix ecto.migrate` (dev); the test database migrates on `mix test`.

- [ ] **Step 4: Parser.** In `text/1`, read the back after the body, positions continuing:

```elixir
    front = front(find_child(children, "front"))
    body = body(find_child(children, "body"), front.next_position)
    back = find_child(children, "back")

    %{
      characters: front.characters,
      paratexts: front.paratexts ++ back_matter(back, front.next_position + length(body)),
      divisions: front.divisions ++ body,
      bibliography: bibliography(back)
    }
```

```elixir
  # --- Back: paratexts after the text ---

  # Each div but the bibliography and a cast list (question 29), read as a front paratext
  # is. A paratext in verse (two files' sonnet) has no paragraphs and no heading of its own
  # kind, and gives nothing (question 30).
  defp back_matter(nil, _first), do: []

  defp back_matter({_name, _attrs, children}, first) do
    for(
      {"div", attrs, div_children} <- children,
      type = attr_value(attrs, "type") || "front",
      type not in ~w(bibliografia elenco),
      do: {type, div_children}
    )
    |> Enum.with_index(first)
    |> Enum.flat_map(fn {{type, div_children}, pos} -> paratext(type, div_children, pos) end)
    |> Enum.map(&Map.put(&1, :back, true))
  end
```

`paratext/3` (today's `editorial_note/3`) adds `back: false`, and keeps a div that has a heading or paragraphs. The sonnet has a heading ("SONNET"): decide in the test whether a heading-only epilogue of 0542 should come in; the spec says the sonnet stays out until question 30, so skip a back div whose children hold an `lg` (comment it). Update the moduledoc's `paratexts:` line.

- [ ] **Step 5: Export.** `build_text/3` passes the `back` paratexts to `build_back`; `build_front/3` filters them out:

```elixir
    {back, front} = play.paratexts |> Enum.sort_by(& &1.position) |> Enum.split_with(& &1.back)
```

`build_back(paratexts, bibliography_groups)`: `Enum.map(paratexts, &paratext_element/1)` (today's `front_section/1`, renamed: it serves both) then the bibliography's div; check what `build_back([])` writes today (`element(:back)`) and keep that when both are empty. A heading-only paratext writes `<div type><head/></div>` (valid: `div` needs no `p`).

- [ ] **Step 6: Admin.** In `#paratext-form`, after the kind select, `<.input field={@form[:back]} type="checkbox" label={gettext("After the text")} />`; the list row shows "After the text" for a `back` paratext. Test (review focus 3):

```elixir
  test "a paratext is placed after the text, but not the scene of the action", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form", paratext: %{"kind" => "lugar_accion", "content" => "A wood.", "back" => "true"})
    |> render_submit()

    assert lv |> element("#paratext-form") |> render() =~ "stands with the cast list"

    lv
    |> form("#paratext-form", paratext: %{"kind" => "colofon", "content" => "Loado sea.", "back" => "true"})
    |> render_submit()

    assert xml_texts(export_tei(play), "p", within: "back") == ["Loado sea."]
  end
```

- [ ] **Step 7: Schema** (`tei_validator_test.exs`, slow): the full-play test gets a paratext after the text beside its bibliography and a heading-only head title; `mix test --include slow test/playcode/export/tei_validator_test.exs` passes.

- [ ] **Step 8: Corpus counters.** `roundtrip_test.exs` gains `back_paratexts`: `<back>` divs other than `bibliografia` and `elenco`, holding no `lg`, with a heading or a non-empty `<p>`, counted on both sides (`extract_back/1` beside `extract_front/1`), added to `@fields`; and the front count includes heading-only divs on both sides. Fixtures 0542/0743: 0 on both sides.

- [ ] **Step 9: Pass, bite, refactor.** Break `back_matter/2` (return `[]`): the round-trip and import tests go red; restore. Then `mix test`, `mix format`.

Commit message: `feat(tei): paratexts after the text, and those that are a heading alone, come back from the file`

---

### Task 4: A paratext keeps its line breaks

Question 10 is answered (2026-10-15): readers see every break. In a paratext: `<lb/>` is `\n`; `<lb/><lb/>` is a blank line, which is the paragraph separator, so it comes back as a new paragraph.

**Files:** `tei_parser.ex` (`paratext/3`), `tei_xml.ex` (`paratext_element/1`), `play_show_live.ex`, `html.ex`, `epub.ex`, `static_site/components.ex` (or wherever the site prints a paratext's paragraphs).
**Test:** `tei_roundtrip_test.exs`, `tei_validator_test.exs`, `play_show_live_test.exs`, `export_controller_test.exs`, `static_site_test.exs`.

- [ ] **Step 1: Failing round-trip test:**

```elixir
  # Question 10: every break shown. A double break, an empty line before a signature in 140
  # plays, is a new paragraph: the same gap for readers, and what a blank line means in the
  # admin's textbox.
  test "a paratext keeps its line breaks; a double break is a new paragraph" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="dedicatoria"><p>A Vuestra Excelencia<lb/>guarde Dios<lb/><lb/>Frey Lope Félix de Vega Carpio</p></div>
          """
        )
      )

    assert xml_texts(xml, "p", within: "front") |> Enum.take(-2) ==
             ["A Vuestra Excelencia guarde Dios", "Frey Lope Félix de Vega Carpio"]

    assert xml =~ ~r{A Vuestra Excelencia\s*<lb/>\s*guarde Dios}
  end
```

(`xml_texts/3`'s treatment of `<lb/>` decides the exact first assertion; check the helper and assert what the reader sees.)

- [ ] **Step 2: Run, watch it fail** (the break comes back as a space; no `<lb/>`).

- [ ] **Step 3: Implement.** Parser: each `<p>` of a paratext through `lines_text/1` (the witnesses' reader) instead of `text_content/1`; the paragraphs still joined with `"\n\n"`. An empty chunk between two breaks yields `"\n\n"` inside a paragraph, which is the separator: split and trim so no paragraph is empty. Export: each paragraph through `lines(paragraph, &build_inline_content/1)` (the witnesses' writer), so `\n` becomes `<lb/>` and the italics stay. Check `lines/2`'s `build` shape against `build_inline_content/1` (a list of nodes); adapt with `List.wrap`.

- [ ] **Step 4: Printing tests, then printing.** One per output, on The Rover's shape (`<p>The banished cavaliers!<lb/>A roving blade!</p>`): the play page renders the two lines on two lines (`whitespace-pre-line` is there already: assert the `\n` reaches the markup); the HTML download likewise (`.editorial-note`, renamed `.paratext`, has `white-space: pre-line`); the EPUB's chapter and the site's page print a `<br>` (or `pre-line`; whichever the renderer already uses for a witness's lines — look for it and reuse). Watch each fail, then make it pass.

- [ ] **Step 5: Schema** (`tei_validator_test.exs`, slow): a paratext with `<lb/>` validates.

- [ ] **Step 6: Bite, refactor**: put `text_content/1` back in `paratext/3` for a run, see the round trip red; restore. `mix test`, `mix format`.

Commit message: `feat(tei): a paratext keeps its line breaks`

---

### Task 5: Paratexts after the text are printed after it

**Files:** `play_labels.ex` (`split_paratexts/2`), `play_show_live.ex`, `html.ex`, `epub.ex`, `static_site/components.ex`, `pages/text.html.heex`, `pages/division.html.heex`.
**Test:** `play_show_live_test.exs`, `export_controller_test.exs`, `static_site_test.exs`.

**Interfaces:**
- Consumes: `back` (Task 3), `PlayLabels.kind_label/1` (Task 2).
- Produces: `PlayLabels.split_paratexts(paratexts, divisions) :: {front, scene, back}`; `Components.back_matter(edition)`.

- [ ] **Step 1: Failing tests, one per output.** A shared TEI: an act ending "Verso final." and in the back `<div type="epilogo"><head>EPILOGUE</head><p>The banished <emph>cavaliers</emph>!</p></div>` plus an untitled `<div type="colofon"><p>Loado sea.</p></div>`.

Play page:

```elixir
  # Where emothe.uv.es prints them: after the text, each listed in the navigation.
  test "the paratexts after the text follow it", %{conn: conn} do
    play = import_tei!(tei(body: @act_with_last_line, back: @back_paratexts))
    TestFixtures.mark_complete!(play)
    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    assert [_text, after_text] = String.split(html, "Verso final.")
    assert after_text =~ ~r/EPILOGUE.*<em>cavaliers<\/em>.*Loado sea\./s
    assert has_element?(view, "nav a", "EPILOGUE")
    assert has_element?(view, "nav a", t("Colophon"))
  end
```

(Use the sidebar's actual selector for the play's sections.)

Downloads (`export_controller_test.exs`): the HTML and the EPUB have "EPILOGUE" and "Loado sea." after "Verso final.", `<em>cavaliers</em>`, and the EPUB's last chapters hold them.

Site (`static_site_test.exs`): the full-text page and the last text page have `EPILOGUE` as a heading after the text; the title page's Contents has an "EPILOGUE" entry and a "Colophon" entry linking to the last text page's anchors; the title page prints neither text.

- [ ] **Step 2: Run, watch all fail.**

- [ ] **Step 3: The rule.** In `PlayLabels`, replacing `split_front_matter/2`:

```elixir
  @doc """
  A play's paratexts as printed: those before the text; its scene of the action, printed
  after the cast list as emothe.uv.es prints it (with those before the text when the play
  has no cast list); and those after the text (`back`).
  """
  def split_paratexts(paratexts, divisions) do
    {back, front} = Enum.split_with(paratexts, & &1.back)

    {front, scene} =
      if Enum.any?(divisions, &(&1.type == "elenco")),
        do: Enum.split_with(front, &(not Paratext.scene?(&1.kind))),
        else: {front, []}

    {front, scene, back}
  end
```

Every caller (`html.ex`, `epub.ex`, `play_show_live.ex`, `components.ex`) moves to the three-tuple.

- [ ] **Step 4: Each output.**
  - Play page: assign `:back_paratexts`; after `<.play_body …/>` in the text tab, the same markup as the front ones (`<.inline_content>`, `whitespace-pre-line`), ids `back-paratext-#{index}`; `build_sections_navigation/4` appends `%{id: "back-paratext-#{i}", label: heading (plain) or kind_label, depth: 0}` to `play_sections`.
  - HTML: the back paratexts after the `play-text` div.
  - EPUB: one chapter per back paratext after the text's chapters (`"back-#{i}"`, title `InlineMarkup.plain(heading)` or the kind's label).
  - Site: `Components.back_matter(edition)` (third element of the split) and a `back_paratexts` component printing `<section id=…>`s with an `<h2>` heading-or-label and the paragraphs; rendered in `text.html.heex` after the divisions and in `division.html.heex` on the last text page only (check `@next` is nil only there; else test against `List.last(@edition.pages)`). `play_contents/1` lists each, after the divisions and before "Full text", linking `"#{last_page.slug}.html##{id}"`.

- [ ] **Step 5: Pass, bite** (make `split_paratexts/2` return `[]` as back: every new test red), **refactor**, `mix test`, `mix format`. `accessibility_test.exs` still passes (headings inside landmarks). The fingerprint test still passes (the site calls nothing new outside `PlayLabels`/`Paratext`; if it calls `Paratext.scene?/1`, fingerprint it or move the map into `PlayLabels`).

Commit message: `feat(site): paratexts after the text are printed after it`

---

### Task 6: Editors order the paratexts

**Files:** `catalogue.ex` (`reorder_paratexts/2`), the content editor.
**Test:** `play_content_editor_live_test.exs`.

- [ ] **Step 1: Failing tests:**

```elixir
  # As the cast list: a file's order may be wrong, and only an editor can fix it.
  test "the paratexts are dragged into order", %{conn: conn} do
    play = import_tei!(tei(front: ~s(<div type="dedicatoria"><p>A.</p></div><div type="argumento"><p>B.</p></div>)))
    [a, b] = Catalogue.list_paratexts(play.id)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()

    lv |> element("#paratext-list") |> render_hook("reorder_paratexts", %{"ids" => [b.id, a.id]})

    assert Catalogue.list_paratexts(play.id) |> Enum.map(& &1.content) == ["B.", "A."]
  end

  # Today a new one takes the count as its position, which can tie with a file's position
  # (positions are shared with the cast list division) or fall among the back ones.
  test "a new paratext goes last", %{conn: conn} do
    play = import_tei!(tei(front: ~s(<div type="dedicatoria"><p>A.</p></div><div type="elenco"><castList><castItem><role>X</role></castItem></castList></div><div type="argumento"><p>B.</p></div>)))
    # … add "C." through the form …
    assert Catalogue.list_paratexts(play.id) |> Enum.map(& &1.content) == ["A.", "B.", "C."]
  end
```

and an id from another play in the event is ignored (CLAUDE.md: an id in an event came from the browser; filter to the play's own rows).

- [ ] **Step 2: Run, watch them fail.**

- [ ] **Step 3: Implement.** `Catalogue.reorder_paratexts(play_id, ids)` as `PlayContent.reorder_characters/2` does it (scoped by `play_id` in the `where`, so a foreign id updates nothing). Positions are rewritten 0…n-1 in the dragged order; that also renumbers away from the division positions, which only the export's ordering read, and the export sorts paratexts among themselves only (check `build_front/3`; if it interleaves with the cast list by position, keep the cast list's place another way and say so). The list gets `id="paratext-list"`, `phx-hook=".DragSortList"`, `data-event="reorder_paratexts"`, `data-id` on each row, as the cast list. A new paratext's position is `max(position) + 1` over the play's paratexts.

- [ ] **Step 4: Pass, bite** (drop the `play_id` scope: the foreign-id test goes red), refactor, `mix test`, `mix format`.

Commit message: `feat(admin): paratexts are dragged into order, and a new one goes last`

---

### Task 7: The API returns paratexts

**Files:** `api/play_controller.ex`. **Test:** `test/playcode_web/controllers/api/play_controller_test.exs`.

- [ ] **Step 1: Failing test:** a play with a dedication, an editor's introduction, a scene of the action and a colophon after the text (two lines) returns

```elixir
    assert %{
             "paratexts" => [
               %{"kind" => "dedicatoria", "back" => false, "editorial" => false},
               %{"kind" => "introduccion_editor", "editorial" => true},
               %{"kind" => "colofon", "back" => true, "content" => "Loado sea.\nEn Madrid"}
             ],
             "scene_of_action" => [%{"content" => "London"}]
           } = json
    refute Map.has_key?(json, "editorial_notes")
```

(match the fields with `heading` too; the order is the play's.)

- [ ] **Step 2: Watch it fail. Step 3: implement** (`paratext_json/1` with `kind`, `heading`, `content`, `back`, `editorial: Paratext.editorial?(kind)`; the scene split off with `Paratext.scene?/1`). **Step 4: pass, bite, refactor, `mix test`, `mix format`.**

Commit message: `feat(api): a play's paratexts, and its scene of the action, by their own names`

---

### Task 8: The import preview counts the rows an editor changed

A re-import replaces a play's text and its rows from the file; an editor's fix to one of them is lost without a word. The preview says how many.

**Files:** `tei_import.ex` (`preview_import/1`), `lib/mix/tasks/playcode.import.tei.ex`, the admin import page's preview.
**Test:** `tei_import_test.exs` (or wherever `preview_import/1` is tested), `test/mix/tasks_test.exs`, the import page's LiveView test.

- [ ] **Step 1: Failing tests:**

```elixir
  # A fresh import edits nothing (review focus 7): the count must not flag the importer's own
  # follow-up updates.
  test "the preview counts the file's rows edited since their import" do
    path = write_tmp!(tei(code: "TEDIT1", front: ~s(<div type="licencia"><p>Privilège.</p></div>)))
    {:ok, play} = TeiImport.import_file(path)
    assert %{edited: 0} = TeiImport.preview_import(path)

    [paratext] = Catalogue.list_paratexts(play.id)
    age!(paratext)  # updated_at must move past inserted_at; see the note below
    {:ok, _} = Catalogue.update_paratext(paratext, %{kind: "noticia_representacion"})

    assert %{edited: 1} = TeiImport.preview_import(path)
  end
```

(`updated_at` and `inserted_at` are `:utc_datetime`, second precision: an update in the same second as the insert is not "after". Age the row's `inserted_at` the way the token tests age a token, with `Repo` aliased in place and a comment saying why.) Then `--dry-run` prints "1 edited by hand since import" for that play, and the import page shows it.

- [ ] **Step 2: Watch them fail. Step 3: implement**: `edited_counts/1` beside `replaced_counts/1`, one query per table (`updated_at > inserted_at`), over the rows a re-import replaces (divisions, elements, notes, and the `tei` paratexts, editors, sources, witnesses, place links); the preview map gets `edited:` (the sum, and per table if the page shows it). If a fresh import does leave rows updated after insert, find the update and either fold it into the insert or exclude it, and say which in a comment.

- [ ] **Step 4: Pass, bite** (return 0: red), refactor, `mix test`, `mix format`.

Commit message: `feat(import): the preview counts the rows edited since their import`

---

### Task 9: Docs and rollout

- [ ] `docs/stakeholder/ida-y-vuelta.html`: the back-matter row (yes across: read, stored, edited, exported, printed; note: the sonnet waits on question 30, the back cast lists on 29); the front paratexts' row: every kind comes back (285 had become "nota"), `circunstancia_accion` is the scene of the action, line breaks kept; the "not read yet" tally; the words (paratext); header date line.
- [ ] `docs/stakeholder/preguntas.html` was updated during the design (questions 29–35, answers to 9 and 10 recorded, the kinds to correct). Check its "Playcode is being changed to…" sentence once this work is live, and say "Playcode reads…".
- [ ] `docs/backlog.md`: remove "Back matter other than the bibliography"; add the play text's line breaks and prose line numbers (answers 9 and 10, its rollout needs a re-import of every play: plan around the preview's edited count); add 0404/0718 under question 29, the sonnet under 30, questions 31–35; extend "Front-matter notes dropped" to the note in 0133's licence; "A second cast list" gains 0404.
- [ ] `docs/history.md`: the entry.
- [ ] `CLAUDE.md`: the schema line (`play_paratexts`: kind, heading, content with `\n` line breaks, `back`, origin; the kind map); TEI mappings (`text/front/div` keeps its `@type`, `circunstancia_accion` → `lugar_accion`, `nota` → `nota_edicion_digital`; `text/back/div` → paratexts with `back`; `<lb/>` a line break in a paratext); *Archiving and provenance* (`play_paratexts.origin`).
- [ ] Dev data: `mix ecto.migrate`; `mix playcode.import.tei --force`; then check on dev: no paratext of kind `nota`; the 45 `circunstancia_accion` are `lugar_accion`; back paratexts per play match the survey (0460 four, 0503 two…); The Rover's epilogue holds 43 line breaks.
- [ ] **Production rollout** (with the user, after deploy): (1) on production, `select p.code, x.kind from play_paratexts x join plays p on p.id = x.play_id where x.origin = 'tei' and x.updated_at > x.inserted_at` (after the migration; `play_editorial_notes` and `section_type` before it) — any row is a hand fix the re-import would lose: show the user before going on; (2) re-import every play (`Playcode.Release`, `--force`); (3) tell the project the kinds can now be corrected (the list on the questions page).
- [ ] Republish the round-trip and questions artifacts **only when the user is on the personal account** (memory: stakeholder-artifacts-account).

---

### Task 10: External review, then the final checks

- [ ] A fresh reviewer (code-reviewer subagent, most capable model) reads the spec, `CONTEXT.md`, this plan and `git diff main...paratexts`, looking for: a word the glossary avoids left in code or the admin; a caller of `split_front_matter/2` missed; a renderer printing `<<…>>` raw or dropping a line break; a kind that breaks the TEI schema; hand-entered paratexts lost or reordered on re-import; an id from the browser not scoped to the play; the preview's count flagging a fresh import; tests that pass without the change. Fix what it finds, with a test for each real bug.
- [ ] `mix test`; `mix test --include slow` (validator and corpus); `mix format --check-formatted`; `mix compile --warnings-as-errors`; `node --test test/js/*.test.mjs` if site JS changed (it should not).
- [ ] Report to the user with the outputs; commit when they ask.
