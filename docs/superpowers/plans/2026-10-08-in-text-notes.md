# In-text Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A TEI `<note>` inside the play text stops being pasted into the line it glosses: it is stored on its own, anchored after its word, written back by the TEI export, shown as a numbered pop-up on the static site and `/plays/:code`, as endnotes in the HTML/PDF/EPUB downloads, and edited in the content editor.

**Architecture:** A `play_notes` table holds each note with the element or division it hangs on and a grapheme `offset` into that anchor's plain text. The importer reads the play text with a mark where each note was, then takes the marks out as offsets. `InlineMarkup.parts/2` splices notes back between the text pieces, and every renderer (TEI, static site, live page, downloads) goes through it. Edits to a line carry its notes' offsets through `String.myers_difference/2`.

**Tech Stack:** Elixir 1.19.5 / OTP 28, Phoenix 1.8.3, LiveView 1.1.22, Ecto 3.14 (`preload_order`), Saxy, XmlBuilder 2.4, LazyHTML in tests, native HTML `popover`.

**Spec:** `docs/superpowers/specs/2026-10-08-in-text-notes-design.md`

## Global Constraints

- Run mix plainly: `mix test`, `mix compile`. Never prefix `export PATH=…`.
- Test-driven, red → green → refactor, every task: write the test, run it and watch it fail for the right reason, write the least code that passes, run it green, then refactor while green.
- Before any claim that something works: `mix test` (whole suite) green, with the output.
- After every task: `mix format`, then `mix compile --warnings-as-errors`, then commit.
- Test through the outermost API (`CLAUDE.md`, *How To Work In This Repo*): TEI import/export as round trips through `ImportHelpers`, LiveViews with `live/2`, controllers with `get`. Read back through context functions, never `Repo`. Select by visible text, `aria-label` or a stable id, never `phx-click` attributes or CSS classes.
- A new table with a `play_id` whose rows show on a play's pages needs the `play_row_changed()` trigger in its migration.
- Offsets count graphemes of `InlineMarkup.plain(anchor_text)`, the `<<`/`>>` markers excluded. The anchor text is a division's `title`, a speech's `speaker_label`, any other element's `content`.
- Static site: no third-party requests, works opened as `file://`, `priv/static_site/site.js` untouched, `style.css` within its 25 KB budget (asserted in `static_site_test.exs`).
- Labels are gettext strings in `PlaycodeWeb.PlayLabels` with English msgids. The static site and the downloads render them in English; the live page and the admin in Spanish, through `priv/gettext/es/LC_MESSAGES/default.po`. After `mix gettext.extract --merge`, check every entry it marks fuzzy.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never write `Emothe` as the application's name (`test/rename_guard_test.exs`).

## Review Focus

The inputs most likely to bite a reader or curator that no single feature test would naturally hit; each has its test in the task named.

- **Two notes at one spot** (`Sale<note/><note/> el rey`): both kept, in source order. Task 2.
- **`&` or `<` in a note's text:** escaped in the TEI, the HTML and the EPUB's XHTML, which must stay well-formed. Tasks 2 and 6.
- **Re-importing a file:** its notes are replaced, never doubled. Task 2.
- **Deleting the word a note follows:** the note moves to where the deletion was, still inside the line. Task 7.
- **Editing only the text of an imported note that sits after punctuation** (`tiene,<note/>`, not at a word's end): saving must not move it. Task 8.

---

## File Structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/20261008120000_create_play_notes.exs` (new) | The table, its anchor check, indexes, the content-version trigger |
| `lib/playcode/play_content/note.ex` (new) | Schema, `paragraphs/1`, `reading_order/1`, `word_ends/1`, `types/0` |
| `lib/playcode/play_content.ex` | Note CRUD, notes preloaded and numbered in `load_play_content/1`, `anchor_text/1`, offsets carried in `update_element/2` and `update_division/2` |
| `lib/playcode/play_content/element.ex`, `division.ex` | `has_many :notes` |
| `lib/playcode/play_content/inline_markup.ex` | `parts/2`: notes spliced between text pieces |
| `lib/playcode/import/tei_parser.ex` | Notes read out of the play text and stored |
| `lib/playcode/export/tei_xml.ex` | `<note>` written back at its offset |
| `lib/playcode_web/play_labels.ex` | `note_type_label/1`, `note_type_options/0` |
| `lib/playcode/export/static_site/{components,edition,fingerprint}.ex`, `pages/{division,text}.html.heex`, `pages.ex`, `priv/static_site/style.css` | Markers and endnotes on the static site |
| `lib/playcode_web/components/play_text.ex`, `assets/css/app.css` | Markers and endnotes on the live pages |
| `lib/playcode/export/note_markup.ex` (new), `html.ex`, `epub.ex` | Markers and endnotes in the downloads |
| `lib/playcode_web/live/admin/notes_component.ex` (new), `play_content_editor_live.ex` | The note editor in the content editor's modals |
| `lib/playcode/activity_log/entry.ex`, `lib/playcode_web/live/admin/activity_log_live.ex` | `"note"` as a resource type |
| `test/support/import_helpers.ex` | `xml_notes/1`, `reading_texts/2` |

---

### Task 1: The notes table and its context functions

**Files:**
- Create: `priv/repo/migrations/20261008120000_create_play_notes.exs`
- Create: `lib/playcode/play_content/note.ex`
- Modify: `lib/playcode/play_content/element.ex` (schema block)
- Modify: `lib/playcode/play_content/division.ex` (schema block)
- Modify: `lib/playcode/play_content.ex` (alias line 13; new `# --- Notes ---` section after `delete_element/1`)
- Test: `test/playcode/content_version_test.exs`, `test/playcode/play_content_test.exs`

**Interfaces:**
- Produces: `Playcode.PlayContent.Note` (fields `offset`, `position`, `n`, `type`, `term`, `body`, virtual `number`; `belongs_to` `play`, `element`, `division`), `Note.types/0 :: [String.t()]`, `Note.paragraphs/1 :: [String.t()]`, `PlayContent.list_notes(%Element{} | %Division{}) :: [Note]` (by offset, then position), `PlayContent.create_note(map) :: {:ok, Note} | {:error, Changeset}`, `PlayContent.change_note(Note, map)`, `PlayContent.update_note(Note, map)`, `PlayContent.delete_note(Note)`, `has_many :notes` on `Element` and `Division`, ordered by offset then position.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/content_version_test.exs`, in the `edits` keyword list of "every edit to the text, cast, credits, notes or places moves the play", add after the `element:` entry:

```elixir
      text_note: fn ->
        PlayContent.create_note(%{play_id: play.id, element_id: line.id, offset: 0, body: "Glosa"})
      end,
```

In `test/playcode/play_content_test.exs`, add at the end of the module:

```elixir
  describe "in-text notes" do
    test "a note hangs on an element or a division, never on both or neither" do
      %{play: play, act: act, verse_line: line} = play_with_structure_fixture()
      note = %{play_id: play.id, offset: 0, body: "Glosa"}

      assert {:ok, _} = PlayContent.create_note(Map.put(note, :element_id, line.id))
      assert {:ok, _} = PlayContent.create_note(Map.put(note, :division_id, act.id))
      assert {:error, _} = PlayContent.create_note(note)

      assert {:error, _} =
               PlayContent.create_note(Map.merge(note, %{element_id: line.id, division_id: act.id}))
    end

    test "a line's notes list in text order, and go when the line goes" do
      %{play: play, verse_line: line} = play_with_structure_fixture()

      for {offset, body} <- [{5, "Segunda"}, {1, "Primera"}] do
        {:ok, _} =
          PlayContent.create_note(%{play_id: play.id, element_id: line.id, offset: offset, body: body})
      end

      assert Enum.map(PlayContent.list_notes(line), & &1.body) == ["Primera", "Segunda"]

      {:ok, _} = PlayContent.delete_element(line)
      assert PlayContent.list_notes(line) == []
    end
  end
```

If `play_content_test.exs` does not already `import Playcode.TestFixtures`, add it at the top of the module.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/content_version_test.exs test/playcode/play_content_test.exs`
Expected: compile error `undefined function create_note/1` (module `Playcode.PlayContent`).

- [ ] **Step 3: Write the migration**

`priv/repo/migrations/20261008120000_create_play_notes.exs`:

```elixir
defmodule Playcode.Repo.Migrations.CreatePlayNotes do
  @moduledoc """
  In-text notes: an editor's or translator's gloss on one word of a line, a speaker label
  or a division heading, stored apart from that text and anchored by `offset`. Spec:
  docs/superpowers/specs/2026-10-08-in-text-notes-design.md.

  A note hangs on exactly one element or division, and goes with it.
  """
  use Ecto.Migration

  def change do
    create table(:play_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :element_id, references(:play_elements, type: :binary_id, on_delete: :delete_all)
      add :division_id, references(:play_divisions, type: :binary_id, on_delete: :delete_all)
      add :offset, :integer, null: false
      add :position, :integer, null: false, default: 0
      add :n, :string
      add :type, :string
      add :term, :text
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:play_notes, :one_anchor,
             check: "(element_id IS NULL) <> (division_id IS NULL)"
           )

    create constraint(:play_notes, :offset_not_negative, check: ~s("offset" >= 0))
    create index(:play_notes, [:element_id, :offset, :position])
    create index(:play_notes, [:division_id, :offset, :position])
    create index(:play_notes, [:play_id])

    execute "CREATE TRIGGER play_notes_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_notes FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_notes_touch_play ON play_notes"
  end
end
```

- [ ] **Step 4: Write the schema**

`lib/playcode/play_content/note.ex`:

```elixir
defmodule Playcode.PlayContent.Note do
  @moduledoc """
  An editor's or translator's gloss on one word of the play text: a TEI `<note>` in the
  body. It hangs on an element (a verse line, a prose paragraph, a stage direction, a
  trailer, or a speech, whose note is on its speaker label) or on a division's heading,
  `offset` graphemes into that text's plain form (`InlineMarkup.plain/1`, so the `<<…>>`
  markers do not count). `position` orders the notes at one offset.

  `n` is the source's number, kept for the TEI export and never shown: readers see
  `number`, which `PlayContent.load_play_content/1` fills in reading order. `type` is
  TEI's (`types/0` lists the corpus's); the importer keeps whatever the file says.
  `body` is paragraphs separated by a blank line, italics as `<<…>>`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(traductor editor editor_critico editor_digital autor)

  schema "play_notes" do
    field :offset, :integer
    field :position, :integer, default: 0
    field :n, :string
    field :type, :string
    field :term, :string
    field :body, :string
    field :number, :integer, virtual: true

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :element, Playcode.PlayContent.Element
    belongs_to :division, Playcode.PlayContent.Division

    timestamps(type: :utc_datetime)
  end

  @doc "The note types the corpus uses, as TEI spells them."
  def types, do: @types

  @doc "The note's paragraphs, in order."
  def paragraphs(%__MODULE__{body: body}) do
    body
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :offset,
      :position,
      :n,
      :type,
      :term,
      :body,
      :play_id,
      :element_id,
      :division_id
    ])
    |> validate_required([:offset, :body, :play_id])
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> check_constraint(:element_id, name: :one_anchor)
  end
end
```

(No custom `message:`: `test/playcode_web/error_translations_test.exs` requires a Spanish translation for every custom changeset message, and the default "is invalid" has one.)

- [ ] **Step 5: Add the associations**

In `lib/playcode/play_content/element.ex`, in the `schema` block after `has_many :element_characters …`:

```elixir
    has_many :notes, Playcode.PlayContent.Note, preload_order: [asc: :offset, asc: :position]
```

In `lib/playcode/play_content/division.ex`, after `has_many :elements, Playcode.PlayContent.Element`:

```elixir
    has_many :notes, Playcode.PlayContent.Note, preload_order: [asc: :offset, asc: :position]
```

- [ ] **Step 6: Add the context functions**

In `lib/playcode/play_content.ex`, change the alias line to:

```elixir
  alias Playcode.PlayContent.{Character, Division, Element, ElementCharacter, Note}
```

and add after `delete_element/1`:

```elixir
  # --- Notes ---

  @doc "The notes on an element or a division, in text order."
  def list_notes(%Element{id: id}), do: notes_query() |> where(element_id: ^id) |> Repo.all()
  def list_notes(%Division{id: id}), do: notes_query() |> where(division_id: ^id) |> Repo.all()

  defp notes_query, do: from(n in Note, order_by: [n.offset, n.position])

  @doc "Creates a note; `attrs` carry its `play_id` and its `element_id` or `division_id`."
  def create_note(attrs), do: %Note{} |> Note.changeset(attrs) |> Repo.insert()

  @doc "A note's changeset, for a form."
  def change_note(%Note{} = note, attrs \\ %{}), do: Note.changeset(note, attrs)

  @doc "Updates a note."
  def update_note(%Note{} = note, attrs), do: note |> Note.changeset(attrs) |> Repo.update()

  @doc "Deletes a note."
  def delete_note(%Note{} = note), do: Repo.delete(note)
```

- [ ] **Step 7: Run the migration and the tests**

Run: `mix ecto.migrate && mix test test/playcode/content_version_test.exs test/playcode/play_content_test.exs`
Expected: PASS, including "every table with a play_id has the content trigger, or is not page data".

- [ ] **Step 8: Refactor while green**

Reread the migration and `Note` against the spec's *The model*. Nothing else to reshape here; rerun the two files if anything changed.

- [ ] **Step 9: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add priv/repo/migrations/20261008120000_create_play_notes.exs lib/playcode/play_content/note.ex lib/playcode/play_content/element.ex lib/playcode/play_content/division.ex lib/playcode/play_content.ex test/playcode/content_version_test.exs test/playcode/play_content_test.exs
git commit -m "feat(notes): a table for in-text notes

A note hangs on one element or division, at a grapheme offset into its
text, and moves the play's content_version like the rest of its text.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Notes survive a TEI round trip

The importer stops pasting a note into its line and stores it; the export writes it back where it was.

**Files:**
- Modify: `test/support/import_helpers.ex` (two readers)
- Modify: `lib/playcode/play_content/inline_markup.ex` (`parts/2`)
- Modify: `lib/playcode/play_content.ex` (`load_play_content/1` preloads)
- Modify: `lib/playcode/import/tei_parser.ex` (text reading, the element and division creation sites)
- Modify: `lib/playcode/export/tei_xml.ex` (`build_body/1`, `build_element/1`, `build_inline_content`)
- Test: `test/playcode/tei_roundtrip_test.exs`

**Interfaces:**
- Consumes: `PlayContent.create_note/1`, `Note.paragraphs/1`, `has_many :notes` (Task 1).
- Produces: `InlineMarkup.parts(text | nil, [Note]) :: [%{text: String.t(), italic: boolean} | %{note: Note}]`; every element and division returned by `PlayContent.load_play_content/1` has `notes` preloaded, in offset order; `ImportHelpers.xml_notes(xml) :: [%{in: tag, after: String.t(), n: String.t() | nil, type: String.t() | nil, term: String.t() | nil, paragraphs: [String.t()], text: String.t()}]`; `ImportHelpers.reading_texts(xml, tag) :: [String.t()]`.

- [ ] **Step 1: Add the two readers to `ImportHelpers`**

In `test/support/import_helpers.ex`, after `xml_texts/3`:

```elixir
  @doc """
  The text of every `tag` element in the body, outside notes, as a reader reads it: its
  notes left out, its pieces joined as written (`Iliria<note/>.` reads "Iliria."),
  whitespace collapsed.
  """
  def reading_texts(xml, tag) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&outside_notes(&1, tag))
    |> Enum.map(fn element ->
      element
      |> tokens()
      |> Enum.filter(&is_binary/1)
      |> Enum.join()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
    end)
  end

  @doc """
  Every `<note>` in the body, in document order, as a map: `in`, the tag of the line,
  paragraph, stage direction, speaker or heading it sits in; `after`, that element's text
  before it (notes left out, whitespace collapsed); its `n`, `type` and `term`; the text
  of each `<p>`; and `text`, all of its text.
  """
  def xml_notes(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&leaf_notes/1)
  end

  @leaves ~w(l p stage speaker head trailer)

  defp leaf_notes({name, _, _} = leaf) when name in @leaves do
    {notes, _before} =
      leaf
      |> tokens()
      |> Enum.flat_map_reduce("", fn
        {:note, note}, before -> {[note_map(note, name, before)], before}
        text, before -> {[], before <> text}
      end)

    notes
  end

  defp leaf_notes({_name, _, children}), do: Enum.flat_map(children, &leaf_notes/1)
  defp leaf_notes(_text), do: []

  # An element's text and notes in order: text as binaries, each note as {:note, element}.
  defp tokens({_name, _, children}) do
    Enum.flat_map(children, fn
      {"note", _, _} = note -> [{:note, note}]
      {_, _, _} = element -> tokens(element)
      text -> [text]
    end)
  end

  defp note_map({"note", attrs, children} = note, tag, before) do
    attrs = Map.new(attrs)

    %{
      in: tag,
      after: before |> String.replace(~r/\s+/u, " ") |> String.trim(),
      n: attrs["n"],
      type: attrs["type"],
      term:
        case children_named(note, "term") do
          [term | _] -> text(term)
          [] -> nil
        end,
      paragraphs: note |> children_named("p") |> Enum.map(&text/1),
      text: text(note)
    }
  end

  defp outside_notes({"note", _, _}, _tag), do: []

  defp outside_notes({name, _, children} = element, tag) do
    own = if name == tag, do: [element], else: []
    own ++ Enum.flat_map(children, &outside_notes(&1, tag))
  end

  defp outside_notes(_text, _tag), do: []
```

- [ ] **Step 2: Write the failing round-trip tests**

In `test/playcode/tei_roundtrip_test.exs`, add before the test "exporting, re-importing and exporting again changes nothing":

```elixir
  describe "in-text notes" do
    @noted """
    <div1 type="acto" n="1"><head>ACTO I</head>
      <div2 type="escena" n="1"><head>ESCENA PRIMERA<note n="1" type="traductor"><term>PRIMERA</term><p>Argumento.</p></note></head>
        <sp><speaker>AMINTAS<note n="2" type="editor"><term>AMINTAS</term><p>Corregimos «Andromire».</p></note></speaker>
          <l n="1">Nous voyent<note n="3" type="editor"><term>voyent</term><p>Forme archaïque.</p><p>Deux syllabes &amp; plus.</p></note> dans la ville</l>
          <l n="2">de Grecia y de Iliria<note n="4" type="traductor"><term>Iliria</term><p>Región de los Balcanes.</p></note>.</l>
          <l n="3">con dos caras que tiene,<note n="5" type="editor_digital">
              <term>tiene,</term>
              <p>Este verso aparece <emph>erróneamente</emph> aquí.</p>
            </note>
          </l>
          <l n="4">un <emph>sueño<note n="6" type="editor"><p>En cursiva.</p></note> breve</emph> fue</l>
          <l n="5">sin glosa<note type="lines"/></l>
          <p>Buscad por todas partes …<note n="7" type="traductor"><p><emph>"partes …"</emph></p><p>(14) De aquí en adelante.</p></note></p>
          <stage>Sale<note n="8" type="editor"><p>Una.</p></note><note n="9" type="editor"><p>Dos.</p></note> el rey</stage>
        </sp>
      </div2>
    </div1>
    """

    test "a note leaves the text it glosses, and comes back after the same word" do
      xml = roundtrip(tei(body: @noted))

      assert reading_texts(xml, "l") == [
               "Nous voyent dans la ville",
               "de Grecia y de Iliria.",
               "con dos caras que tiene,",
               "un sueño breve fue",
               "sin glosa"
             ]

      assert reading_texts(xml, "p") == ["Buscad por todas partes …"]
      assert reading_texts(xml, "stage") == ["Sale el rey"]
      assert reading_texts(xml, "speaker") == ["AMINTAS"]
      assert reading_texts(xml, "head") == ["ACTO I", "ESCENA PRIMERA"]

      assert Enum.map(xml_notes(xml), &{&1.in, &1.after, &1.n}) == [
               {"head", "ESCENA PRIMERA", "1"},
               {"speaker", "AMINTAS", "2"},
               {"l", "Nous voyent", "3"},
               {"l", "de Grecia y de Iliria", "4"},
               {"l", "con dos caras que tiene,", "5"},
               {"l", "un sueño", "6"},
               {"p", "Buscad por todas partes …", "7"},
               {"stage", "Sale", "8"},
               {"stage", "Sale", "9"}
             ]
    end

    test "a note keeps its type, term and paragraphs, italics and all" do
      xml = roundtrip(tei(body: @noted))
      notes = xml_notes(xml)

      assert %{type: "editor", term: "voyent", paragraphs: ["Forme archaïque.", "Deux syllabes & plus."]} =
               Enum.at(notes, 2)

      assert %{type: "traductor", term: nil, paragraphs: ["\"partes …\"", "(14) De aquí en adelante."]} =
               Enum.at(notes, 6)

      assert %{type: "editor_digital", term: "tiene,", paragraphs: ["Este verso aparece erróneamente aquí."]} =
               Enum.at(notes, 4)

      assert xml_texts(xml, "emph", within: "note") == ["erróneamente", "\"partes …\""]
    end

    test "importing a file again replaces its notes, never doubles them" do
      path =
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
        |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiParser.import_file(path)
      {:ok, play} = Playcode.Import.TeiParser.import_file(path)

      assert [%{after: "uno"}] = play |> export_tei() |> xml_notes()
    end
  end
```

And in the fixpoint test "exporting, re-importing and exporting again changes nothing", replace the line

```elixir
        <lg type="redondilla"><l n="1" part="F">dos</l><l n="2" rend="indent"><seg type="aside">tres</seg></l></lg>
```

with

```elixir
        <lg type="redondilla"><l n="1" part="F">dos</l><l n="2" rend="indent"><seg type="aside">tres</seg></l>
          <l n="3">cuatro<note n="1" type="editor"><term>cuatro</term><p>Una <emph>glosa</emph>.</p></note>.</l></lg>
```

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: the three "in-text notes" tests FAIL. The first shows the note text inside the line, e.g. `"Nous voyent voyent Forme archaïque. Deux syllabes & plus. dans la ville"`, and `xml_notes` returns `[]`. The fixpoint test may still pass (the pasted text round-trips stably); it guards the export format once notes exist.

- [ ] **Step 4: `InlineMarkup.parts/2`**

In `lib/playcode/play_content/inline_markup.ex`, extend the moduledoc's first paragraph with: "`parts/2` also places a line's notes between the pieces." and add after `parts/1`:

```elixir
  @doc """
  As `parts/1`, with each of `notes` placed as a `%{note: note}` part after the first
  `note.offset` graphemes of the plain text. A note at the end of a piece follows that
  piece; one inside an italic run splits it. Notes at one offset keep their order in
  `notes`, and a note past the end of the text goes last.
  """
  def parts(text, []), do: parts(text)

  def parts(text, notes) do
    notes = Enum.sort_by(notes, &{&1.offset, &1.position})
    {parts, {_at, rest}} = Enum.flat_map_reduce(parts(text), {0, notes}, &place_notes/2)
    parts ++ Enum.map(rest, &%{note: &1})
  end

  # Splits `part` (which starts `at` graphemes into the text) at every note that falls
  # inside it or at its end.
  defp place_notes(part, {at, notes}) do
    length = String.length(part.text)
    {here, later} = Enum.split_while(notes, &(&1.offset <= at + length))

    {pieces, cut} =
      Enum.reduce(here, {[], 0}, fn note, {pieces, cut} ->
        k = max(note.offset - at, cut)
        piece = %{part | text: String.slice(part.text, cut, k - cut)}
        {[%{note: note} | prepend_text(pieces, piece)], k}
      end)

    rest = %{part | text: String.slice(part.text, cut..-1//1)}
    {Enum.reverse(prepend_text(pieces, rest)), {at + length, later}}
  end

  defp prepend_text(pieces, %{text: ""}), do: pieces
  defp prepend_text(pieces, part), do: [part | pieces]
```

- [ ] **Step 5: Preload notes in `load_play_content/1`**

In `lib/playcode/play_content.ex`, `load_play_content/1`: change the divisions' preload to

```elixir
      |> Repo.preload([
        :notes,
        children: from(d in Division, order_by: d.position, preload: :notes)
      ])
```

and the elements' preload to

```elixir
      |> Repo.preload([
        :notes,
        element_characters: ec_preload,
        children:
          from(e in Element,
            order_by: e.position,
            preload: [
              :notes,
              element_characters: ^ec_preload,
              children:
                ^from(c in Element,
                  order_by: c.position,
                  preload: [:notes, element_characters: ^ec_preload]
                )
            ]
          )
      ])
```

- [ ] **Step 6: The importer reads notes out of the play text**

In `lib/playcode/import/tei_parser.ex`, replace `text_content/1`, `extract_plain_text/1` and their clauses (around lines 1515–1551) with:

```elixir
  # The text of an element, whitespace collapsed, italics as <<…>>. A <note> inside it is
  # pasted in (:paste, what the header and the front matter read) or left as a mark
  # (:mark, the play text), which take_notes/2 turns into the note's offset.
  defp text_content(element, notes \\ :paste)

  defp text_content({name, attrs, children}, notes) do
    if emph_element?(name, attrs) do
      "<<" <> extract_plain_text(children, notes) <> ">>"
    else
      children
      |> pieces(notes, &text_content(&1, notes))
      |> Enum.join(" ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
    end
  end

  defp text_content(text, _notes) when is_binary(text), do: String.trim(text)
  defp text_content(_, _notes), do: ""

  defp extract_plain_text(children, notes) when is_list(children) do
    children
    |> pieces(notes, &extract_plain_text(elem(&1, 2), notes))
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Each child's text, read by `fun`; under :mark a <note> child is its mark instead.
  defp pieces(children, notes, fun) do
    children
    |> Enum.with_index()
    |> Enum.map(fn
      {{"note", _, _} = note, i} when notes == :mark -> note_mark(note, children, i)
      {text, _} when is_binary(text) -> String.trim(text)
      {child, _} when is_tuple(child) -> fun.(child)
      _ -> ""
    end)
  end

  # Where a note was in the text being read: "<key><s|n>". The key finds the
  # note again among the element's (take_notes/2); "s" records that the source had
  # whitespace beside the note, so the words either side stay apart, and "n" that it had
  # none, so "Iliria<note/>." reads "Iliria.".
  defp note_mark(note, siblings, i) do
    before = if i > 0, do: Enum.at(siblings, i - 1)
    next = Enum.at(siblings, i + 1)

    spaced =
      (is_binary(before) and before =~ ~r/\s\z/u) or (is_binary(next) and next =~ ~r/\A\s/u)

    "#{:erlang.phash2(note)}#{if spaced, do: "s", else: "n"}"
  end

  @note_mark ~r/ ?\x{E000}(\d+)([sn])\x{E001} ?/u

  # Takes the note marks out of `marked`, text `element` was read into with :mark.
  # Returns the text and `[{offset, note}]`, the offset counting graphemes of the text
  # without its << and >> markers, as InlineMarkup.plain/1 does. A note whose mark the
  # reading dropped (inside a stripped aside <stage>) is dropped with it.
  defp take_notes(marked, element) do
    by_key = Map.new(nested_notes(element), &{Integer.to_string(:erlang.phash2(&1)), &1})

    {text, found} =
      @note_mark
      |> Regex.split(marked, include_captures: true)
      |> Enum.reduce({"", []}, fn piece, {text, found} ->
        case Regex.run(@note_mark, piece) do
          [_, key, spaced] ->
            space = if spaced == "s" and text != "", do: " ", else: ""
            {text <> space, [{plain_length(text), Map.fetch!(by_key, key)} | found]}

          nil ->
            {text <> piece, found}
        end
      end)

    text = String.trim_trailing(text)
    last = plain_length(text)
    {text, found |> Enum.reverse() |> Enum.map(fn {offset, note} -> {min(offset, last), note} end)}
  end

  defp plain_length(text), do: String.length(text) - 2 * length(Regex.scan(~r/<<|>>/, text))

  # The <note>s inside an element, not counting notes inside notes.
  defp nested_notes({_name, _attrs, children}) do
    Enum.flat_map(children, fn
      {"note", _, _} = note -> [note]
      {_, _, _} = child -> nested_notes(child)
      _text -> []
    end)
  end

  # An element of the play text read with its notes taken out: `{text, [{offset, note}]}`,
  # or `{nil, []}` for no element.
  defp text_and_notes(nil), do: {nil, []}
  defp text_and_notes(element), do: element |> text_content(:mark) |> take_notes(element)

  # A note's own fields, or nil when it has no text: there is nothing to show (the
  # empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children}) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content({"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))})

        paragraphs ->
          paragraphs |> Enum.map(&text_content/1) |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")
      end

    term = safe_text(find_child(children, "term"))

    if body != "" do
      %{
        n: attr_value(attrs, "n"),
        type: attr_value(attrs, "type"),
        term: if(term in [nil, ""], do: nil, else: term),
        body: body
      }
    end
  end

  # Stores the notes take_notes/2 found on `anchor`, %{element_id: id} or
  # %{division_id: id}. `position` orders the notes at one offset.
  defp create_text_notes(anchor, notes, play) do
    notes
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(&Enum.with_index/1)
    |> Enum.each(fn {{offset, note}, position} ->
      with %{} = fields <- parse_note(note) do
        attrs =
          fields
          |> Map.merge(anchor)
          |> Map.merge(%{play_id: play.id, offset: offset, position: position})

        case PlayContent.create_note(attrs) do
          {:ok, _note} -> :ok
          {:error, cs} -> Repo.rollback({:note_create_failed, cs})
        end
      end
    end)
  end
```

Then change the creation sites:

`import_body/3`: replace `heading = safe_text(find_child(act_children, "head"))` with `{heading, head_notes} = text_and_notes(find_child(act_children, "head"))`, and after the `act_div = case … end` block add `create_text_notes(%{division_id: act_div.id}, head_notes, play)`.

`import_act_content/3`, the `{"div2", …}` clause: replace `heading = safe_text(find_child(scene_children, "head"))` with `{heading, head_notes} = text_and_notes(find_child(scene_children, "head"))`, and after the `scene_div = case … end` block add `create_text_notes(%{division_id: scene_div.id}, head_notes, play)`.

`import_speech/5`: replace `speaker_label = safe_text(speaker_elem)` with `{speaker_label, speaker_notes} = text_and_notes(speaker_elem)`, and after the `speech = case … end` block add `create_text_notes(%{element_id: speech.id}, speaker_notes, play)`.

`import_verse_line/5`: replace `content = verse_line_content({name, attrs, children}, is_aside)` with

```elixir
    line = {name, attrs, children}
    {content, notes} = line |> verse_line_content(is_aside) |> take_notes(line)
```

and its `{:ok, _el} -> :ok` with `{:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)`.

`verse_line_content/2`: replace both clauses with

```elixir
  # The spoken text of a verse line, read with note marks (text_content/2). An aside line
  # is its <seg type="aside"> text, with the line's own notes kept beside it; with no
  # <seg>, the line without its delivery <stage>.
  defp verse_line_content({_name, _attrs, children}, true) do
    kept =
      if aside_in_children?(children) do
        Enum.filter(children, &(aside_seg?(&1) or match?({"note", _, _}, &1)))
      else
        Enum.reject(children, &match?({"stage", _, _}, &1))
      end

    kept
    |> pieces(:mark, &text_content(&1, :mark))
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp verse_line_content(line, false), do: text_content(line, :mark)

  defp aside_seg?({"seg", attrs, _}), do: attr_value(attrs, "type") == "aside"
  defp aside_seg?(_), do: false
```

and make `aside_in_children?/1` use it: `defp aside_in_children?(children) when is_list(children), do: Enum.any?(children, &aside_seg?/1)`.

`import_stage_direction/5`: replace `content = text_content(stage)` with `{content, notes} = text_and_notes(stage)`, and `{:ok, _el} -> :ok` with `{:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)`.

`import_trailer/4`: before `case`, add `{content, notes} = text_and_notes(trailer)`; use `content: content` in the attrs, and `{:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)`.

`import_prose/5`: replace the `content = …` line with

```elixir
    marked = if is_aside, do: prose_aside_content(children), else: text_content(para, :mark)
    {content, notes} = take_notes(marked, para)
```

and `{:ok, _el} -> :ok` with `{:ok, el} -> create_text_notes(%{element_id: el.id}, notes, play)`.

`prose_aside_content/1`:

```elixir
  # An aside paragraph's <seg type="aside"> text, with the paragraph's own notes beside it.
  defp prose_aside_content(children) do
    children
    |> Enum.filter(&(aside_seg?(&1) or match?({"note", _, _}, &1)))
    |> pieces(:mark, &text_content(&1, :mark))
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
```

- [ ] **Step 7: The export writes notes back**

In `lib/playcode/export/tei_xml.ex`, add `alias Playcode.PlayContent.{InlineMarkup, Note}` under `alias Playcode.PlayContent`. In `build_body/1`, replace `children = if div.title, do: [element(:head, div.title)], else: []` with

```elixir
        children =
          if div.title,
            do: [inline_element(:head, %{}, build_inline_content(div.title, div.notes))],
            else: []
```

and `child_head = if child.title, do: [element(:head, child.title)], else: []` with

```elixir
            child_head =
              if child.title,
                do: [inline_element(:head, %{}, build_inline_content(child.title, child.notes))],
                else: []
```

In `build_element/1`:
- speech: `[element(:speaker, el.speaker_label) | children]` becomes `[inline_element(:speaker, %{}, build_inline_content(el.speaker_label, el.notes)) | children]`
- verse line: `inline = build_inline_content(el.content)` becomes `inline = build_inline_content(el.content, el.notes)`, and `element(:l, attrs, content)` becomes `inline_element(:l, attrs, content)`
- stage direction: `inline_element(:stage, attrs, build_inline_content(el.content, el.notes))`
- prose: `inline = build_inline_content(el.content, el.notes)` and `inline_element(:p, %{}, content)`
- trailer: `inline_element(:trailer, %{}, build_inline_content(el.content, el.notes))`

Replace the comment and both `build_inline_content` clauses at the end of the module with:

```elixir
  # A text as TEI: <<…>> becomes <emph>, as the EMOTHE corpus writes italics (<hi
  # rend="italic"> would do too, per TEI P5), and each note goes back at its offset
  # (InlineMarkup.parts/2).
  defp build_inline_content(text, notes) do
    (text || "")
    |> InlineMarkup.parts(notes)
    |> Enum.map(fn
      %{note: note} -> build_note(note)
      %{italic: true, text: text} -> element(:emph, text)
      %{text: text} -> text
    end)
    |> case do
      [] -> ""
      [single] when is_binary(single) -> single
      list -> list
    end
  end

  defp build_note(note) do
    attrs = for {key, value} <- [n: note.n, type: note.type], value, into: %{}, do: {key, value}
    term = if note.term, do: [element(:term, build_inline_content(note.term, []))], else: []
    paragraphs = Enum.map(Note.paragraphs(note), &element(:p, build_inline_content(&1, [])))
    element(:note, attrs, term ++ paragraphs)
  end

  # An element whose text holds others (<emph>, <note>) goes out on one line, its text
  # exactly as it runs: :indent would put line breaks inside it, and a break before a
  # <note> reads back as a space between the word and what follows it.
  defp inline_element(name, attrs, content) when is_list(content),
    do: {:iodata, XmlBuilder.generate(element(name, attrs, content), format: :none)}

  defp inline_element(name, attrs, content), do: element(name, attrs, content)
```

- [ ] **Step 8: Run the round-trip tests**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS, all of them, the fixpoint test included.

- [ ] **Step 9: Refactor while green**

`text_content/2`, `extract_plain_text/2`, `verse_line_content/2` and `prose_aside_content/1` now share `|> Enum.join(" ") |> String.replace(~r/\s+/, " ") |> String.trim()`: pull it into `defp squeeze(pieces)` and use it in all four. Rerun `mix test test/playcode/tei_roundtrip_test.exs test/playcode/import`.

- [ ] **Step 10: Format, compile, full suite, commit**

Run `mix format`, `mix compile --warnings-as-errors`, `mix test`. Expect other tests that matched the export's exact layout around `<emph>` to need nothing: a line with italics is now written on one line, which only a test asserting raw indentation would notice. If one fails, read it first: fix the test only if it asserted layout, not content, and say so in the commit.

```bash
git add lib/playcode/play_content/inline_markup.ex lib/playcode/play_content.ex lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex test/support/import_helpers.ex test/playcode/tei_roundtrip_test.exs
git commit -m "fix(import): a note in the play text is stored, not pasted into its line

The importer read a <note>'s paragraphs into the line it glossed (Hamlet,
act 5: a translator's note after \"partes …\"). It now marks the note's
place, stores the note at that offset, and the TEI export writes it back
after the same word.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The real corpus round-trips its notes

**Files:**
- Modify: `test/playcode/roundtrip_test.exs`

**Interfaces:**
- Consumes: `ImportHelpers.xml_notes/1`, `ImportHelpers.reading_texts/2` (Task 2).

- [ ] **Step 1: Add the checks**

In `test/playcode/roundtrip_test.exs`:

1. Add `alias Playcode.ImportHelpers` under `use Playcode.DataCase, async: true`.
2. Add `notes` to `@fields`: `~w(acts scenes … speaker_refs notes)a`.
3. In `structural_counts/1`, add `notes: count_notes(xml)`.
4. Add `EMOTHE0705_LaVirginie.xml` to `@default_fixtures`, and extend the comment above it: "…one prose play, and one with in-text notes (17: on lines and speakers)."
5. Add these helpers after `count_aside_leaves/1`:

```elixir
  # The body as a document of its own, for the ImportHelpers readers.
  defp body_doc(xml), do: "<body>" <> extract_body(xml) <> "</body>"

  # Notes with text: an empty <note/> (EMOTHE0010's test file) carries nothing and is
  # rightly not imported.
  defp count_notes(xml),
    do: xml |> body_doc() |> ImportHelpers.xml_notes() |> Enum.count(&(&1.text != ""))

  # Each note as {the element it sits in, the last 12 non-blank characters before it there,
  # n, type}. Blanks are ignored because the importer joins a line's pieces with spaces
  # where an element splits them (a<emph>b</emph> reads "a b"). Only the last characters,
  # because an aside line's delivery <stage> is not exported, so its text no longer
  # precedes the notes after it.
  defp note_anchors(xml) do
    xml
    |> body_doc()
    |> ImportHelpers.xml_notes()
    |> Enum.reject(&(&1.text == ""))
    |> Enum.map(fn note ->
      tail = note.after |> String.replace(~r/\s+/u, "") |> String.slice(-12..-1//1)
      {note.in, tail, note.n, note.type}
    end)
  end

  # No note's text is left in the text it glosses, the bug these checks came with
  # (Hamlet, act 5: a translator's note pasted after "partes …"). Notes under 30
  # characters are skipped: a short gloss may repeat words of the play.
  defp assert_no_pasted_notes(code, original_xml, exported_xml) do
    exported = body_doc(exported_xml)

    text =
      ~w(l p stage speaker head trailer)
      |> Enum.flat_map(&ImportHelpers.reading_texts(exported, &1))
      |> Enum.join()
      |> squash()

    for note <- ImportHelpers.xml_notes(body_doc(original_xml)),
        String.length(note.text) >= 30 do
      refute String.contains?(text, squash(note.text)),
             "#{code}: note #{note.n} is pasted into the text"
    end
  end

  defp squash(text), do: String.replace(text, ~r/\s+/u, "")
```

6. In the per-fixture test, after `assert_metadata_roundtrip(@code, play_full, exported_xml)`:

```elixir
      assert_order_preserved(
        @code,
        "notes (where each sits)",
        note_anchors(original_xml),
        note_anchors(exported_xml)
      )

      assert_no_pasted_notes(@code, original_xml, exported_xml)
```

- [ ] **Step 2: Run the default round trips**

Run: `mix test test/playcode/roundtrip_test.exs`
Expected: PASS, three fixtures (0746, 0776, 0705) plus the places round trip.

- [ ] **Step 3: Prove the checks bite**

In `lib/playcode/import/tei_parser.ex`, temporarily change `text_and_notes/1` to `element |> text_content(:paste) |> take_notes(element)`.
Run: `mix test test/playcode/roundtrip_test.exs`
Expected: `roundtrip: EMOTHE0705_LaVirginie` FAILS, on `notes` (original 17, exported 0), and on the anchors and the pasted text. Put `text_content(:mark)` back and rerun: PASS.

- [ ] **Step 4: Sweep the corpus**

Run: `mix test test/playcode/roundtrip_test.exs --include slow`
Expected: every fixture passes (83 on a full checkout, a few minutes). If one fails on notes, read the failure before touching anything: it names the fixture and the note. A real importer gap gets its own failing case in `tei_roundtrip_test.exs` first (Task 2's file), then the fix. Never widen `note_anchors/1` to make a fixture pass.

- [ ] **Step 5: Refactor while green**

Nothing structural. Check that the `@default_fixtures` comment matches the three files.

- [ ] **Step 6: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add test/playcode/roundtrip_test.exs
git commit -m "test(roundtrip): every note of a real file sits after the same text after export

Counts notes, compares where each sits, and checks no note's text is
left in the line. EMOTHE0705 joins the default run, so every mix test
round-trips a play with notes. Proved to bite by reading notes in paste
mode: 0705 fails on all three.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Repair the dev database (with the user's go-ahead)**

Ask the user first: a `--force` re-import replaces every play's text in `playcode_dev`, and any hand edit to a line there is lost (curated columns survive, `@platform_owned`). Then:

Run: `mix playcode.import.tei --force`
Then check Hamlet through Tidewave's `execute_sql_query` (or `psql playcode_dev`):

```sql
SELECT count(*) FROM play_elements e JOIN plays p ON p.id = e.play_id
 WHERE p.code = 'EMOTHE0053_Hamlet' AND e.content LIKE '%(14) De aquí%';
-- expected 0

SELECT count(*) FROM play_notes n JOIN plays p ON p.id = n.play_id
 WHERE p.code = 'EMOTHE0053_Hamlet';
-- expected: Hamlet's notes with text, about 147
```

---

### Task 4: Numbered notes on the static site

**Files:**
- Modify: `lib/playcode/play_content/note.ex` (`reading_order/1`)
- Modify: `lib/playcode/play_content.ex` (number notes in `load_play_content/1`)
- Modify: `lib/playcode_web/play_labels.ex` (`note_type_label/1`, `note_type_options/0`)
- Modify: `lib/playcode/export/static_site/components.ex` (`inline/1`, `part/1`, `el/1`, headings, `endnotes/1`)
- Modify: `lib/playcode/export/static_site/edition.ex` (`page_notes/1`)
- Modify: `lib/playcode/export/static_site/pages.ex` (aliases)
- Modify: `lib/playcode/export/static_site/pages/division.html.heex`, `pages/text.html.heex`
- Modify: `lib/playcode/export/static_site/fingerprint.ex` (`@modules`)
- Modify: `priv/static_site/style.css`
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po` (through `mix gettext.extract --merge`)
- Test: `test/playcode/export/static_site_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2`, preloaded `notes` (Task 2).
- Produces: `Note.reading_order([Division] | Division) :: [Note]`; every note from `load_play_content/1` has `number` (1, 2, 3… in `reading_order`); `PlayLabels.note_type_label(type | nil) :: String.t()`; `PlayLabels.note_type_options() :: [{String.t(), String.t()}]`; `Edition.page_notes(page) :: [Note]`.

- [ ] **Step 1: Write the failing test**

In `test/playcode/export/static_site_test.exs`, add `import Playcode.ImportHelpers` under the other imports, and at the end of the module:

```elixir
  describe "in-text notes" do
    defp noted_play do
      tei(
        body: """
        <div1 type="acto" n="1"><head>ACTO I</head>
          <sp><speaker>ANA</speaker>
            <l n="1">Nous voyent<note n="6089" type="editor"><term>voyent</term><p>Forme archaïque.</p><p>Deux syllabes.</p></note> dans la ville</l>
            <l n="2">sin nota</l>
          </sp>
        </div1>
        <div1 type="acto" n="2"><head>ACTO II</head>
          <sp><speaker>BLAS</speaker><p>Buscad por todas partes …<note n="121" type="traductor"><p><emph>"partes …"</emph></p><p>(14) De aquí en adelante.</p></note></p></sp>
        </div1>
        """
      )
      |> import_tei!()
      |> mark_complete!()
    end

    defp marker_target(page, label) do
      page |> LazyHTML.query(~s(button[aria-label="#{label}"])) |> LazyHTML.attribute("popovertarget")
    end

    test "a note is a number after its word, opening the note, listed on its own page" do
      play = noted_play()
      dir = generate!([play])
      act1 = html!(dir, "plays/#{play.code}/act-1.html")
      act2 = html!(dir, "plays/#{play.code}/act-2.html")

      assert squish(LazyHTML.text(act1)) =~ "Nous voyent1 dans la ville"
      assert marker_target(act1, "Editor's note 1") == ["note-1"]
      assert act1 |> LazyHTML.query("#note-1") |> LazyHTML.attribute("popover") == [""]
      assert texts(act1, "#note-1 b") == ["Editor's note"]
      assert texts(act1, "#note-1 i") == ["voyent"]
      assert texts(act1, "#note-1 p") == ["Forme archaïque.", "Deux syllabes."]
      assert act1 |> LazyHTML.query("#note-2") |> Enum.count() == 0

      assert squish(LazyHTML.text(act2)) =~ "Buscad por todas partes …2"
      assert marker_target(act2, "Translator's note 2") == ["note-2"]
      assert texts(act2, "#note-2 p") == ["\"partes …\"", "(14) De aquí en adelante."]
      assert act2 |> LazyHTML.text() |> String.split("(14) De aquí") |> length() == 2
    end

    test "the full text lists every note, numbered through the play" do
      play = noted_play()
      text_page = html!(generate!([play]), "plays/#{play.code}/text.html")

      assert marker_target(text_page, "Editor's note 1") == ["note-1"]
      assert marker_target(text_page, "Translator's note 2") == ["note-2"]
      assert text_page |> LazyHTML.query("li[popover]") |> Enum.count() == 2
    end
  end
```

`mark_complete!/1` comes from `Playcode.TestFixtures`, already imported.

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode/export/static_site_test.exs`
Expected: both new tests FAIL. The page text reads "Nous voyent dans la ville" with no number, and `marker_target` is `[]`.

- [ ] **Step 3: Reading order and numbers**

In `lib/playcode/play_content/note.ex`, add `alias Playcode.PlayContent.{Division, Element}` under `import Ecto.Changeset`, and after `paragraphs/1`:

```elixir
  @doc """
  The notes in `divisions` (as `PlayContent.load_play_content/1` gives them) in reading
  order: a division's heading, its own text, then its scenes; an element's own notes (a
  speech's, on its speaker), then its children's. Note numbers follow this order.
  """
  def reading_order(divisions) when is_list(divisions),
    do: Enum.flat_map(divisions, &reading_order/1)

  def reading_order(%Division{} = division) do
    division.notes ++
      Enum.flat_map(division.loaded_elements, &element_notes/1) ++
      reading_order(loaded(division.children))
  end

  defp element_notes(%Element{} = element),
    do: element.notes ++ Enum.flat_map(loaded(element.children), &element_notes/1)

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(list), do: list
```

In `lib/playcode/play_content.ex`, end `load_play_content/1` with `divisions |> attach_elements(elements_by_division) |> number_notes()` (replacing `attach_elements(divisions, elements_by_division)`), and add after `attach_elements/2`:

```elixir
  # Gives each note its `number`: its place in Note.reading_order/1, from 1.
  defp number_notes(divisions) do
    numbers =
      divisions
      |> Note.reading_order()
      |> Enum.with_index(1)
      |> Map.new(fn {note, number} -> {note.id, number} end)

    Enum.map(divisions, &number_division(&1, numbers))
  end

  defp number_division(division, numbers) do
    %{
      division
      | notes: number(division.notes, numbers),
        loaded_elements: Enum.map(division.loaded_elements, &number_element(&1, numbers)),
        children: Enum.map(division.children, &number_division(&1, numbers))
    }
  end

  defp number_element(element, numbers) do
    children =
      case element.children do
        %Ecto.Association.NotLoaded{} = not_loaded -> not_loaded
        children -> Enum.map(children, &number_element(&1, numbers))
      end

    %{element | notes: number(element.notes, numbers), children: children}
  end

  defp number(notes, numbers), do: Enum.map(notes, &%{&1 | number: numbers[&1.id]})
```

- [ ] **Step 4: Labels**

In `lib/playcode_web/play_labels.ex`, add `alias Playcode.PlayContent.Note` to the aliases, and:

```elixir
  @doc "The heading of a note of TEI `type`, as readers see it."
  def note_type_label("traductor"), do: gettext("Translator's note")
  def note_type_label("editor"), do: gettext("Editor's note")
  def note_type_label("editor_critico"), do: gettext("Critical editor's note")
  def note_type_label("editor_digital"), do: gettext("Digital editor's note")
  def note_type_label("autor"), do: gettext("Author's note")
  def note_type_label(_other), do: gettext("Note")

  @doc "`{label, type}` pairs for a select: an untyped note first, then the corpus's types."
  def note_type_options,
    do: [{note_type_label(nil), ""} | Enum.map(Note.types(), &{note_type_label(&1), &1})]
```

- [ ] **Step 5: Markers and endnotes**

In `lib/playcode/export/static_site/components.ex`, add `alias Playcode.PlayContent.Note`. Replace `inline/1`'s attr and first line:

```elixir
  attr :text, :string, default: nil
  attr :notes, :list, default: []

  def inline(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text, assigns.notes))
```

Add a `part/1` clause before the italic one:

```elixir
  # A note's marker: its number, a button that opens the note (endnotes/1) as a popover.
  defp part(%{note: note}) do
    number = Integer.to_string(note.number)
    label = escape("#{PlayLabels.note_type_label(note.type)} #{number}")

    [
      ~s(<button type="button" class="nref" popovertarget="note-),
      number,
      ~s(" aria-label="),
      label,
      ~s(">),
      number,
      "</button>"
    ]
  end
```

In `el/1`, pass each element's notes:
- speech: `<p :if={@el.speaker_label} class="spk"><.inline text={@el.speaker_label} notes={@el.notes} /></p>`
- verse line: `<.inline text={@el.content} notes={@el.notes} />` (inside the `phx-no-format` line)
- stage direction and prose: `<.inline text={@el.content} notes={@el.notes} />`

In `division_text/1` and both `page_text/1` clauses that print headings, replace each `{@division.title}`, `{@page.division.title}` and `{scene.title}` / `{@page.scene.title}` inside an `h2`/`h3` with an `<.inline>` carrying that division's notes, e.g.:

```heex
      <h2 :if={@division.title} class="act-head"><.inline text={@division.title} notes={@division.notes} /></h2>
```

```heex
        <h3 :if={scene.title} class="scene-head"><.inline text={scene.title} notes={scene.notes} /></h3>
```

Add the endnotes component:

```elixir
  attr :notes, :list, required: true

  @doc """
  A page's notes. Each is a popover its marker opens (`part/1`); in print, and in a
  browser without popover, they are the page's endnotes.
  """
  def endnotes(assigns) do
    ~H"""
    <section :if={@notes != []} class="notes" role="doc-endnotes" aria-label="Notes">
      <ol>
        <li :for={note <- @notes} id={"note-#{note.number}"} popover value={note.number}>
          <button
            type="button"
            popovertarget={"note-#{note.number}"}
            popovertargetaction="hide"
            aria-label="Close"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(note.type)}</b>
          <i :if={note.term}><.inline text={note.term} /></i>
          <p :for={paragraph <- Note.paragraphs(note)}><.inline text={paragraph} /></p>
        </li>
      </ol>
    </section>
    """
  end
```

In `lib/playcode/export/static_site/edition.ex`, add `alias Playcode.PlayContent.Note` and:

```elixir
  @doc "The notes in a page's text, in reading order: the endnotes it lists."
  def page_notes(%{scene: nil, split: false, division: division}),
    do: Note.reading_order(division)

  def page_notes(%{scene: nil, split: true, division: division}),
    do: Note.reading_order(%{division | children: []})

  def page_notes(%{scene: scene, division: division}),
    do: division.notes ++ Note.reading_order(scene)
```

In `lib/playcode/export/static_site/pages.ex`, add `alias Playcode.Export.StaticSite.Edition` and `alias Playcode.PlayContent.Note`.

In `pages/division.html.heex`, after `<Components.page_text edition={@edition} page={@page} />`:

```heex
    <Components.endnotes notes={Edition.page_notes(@page)} />
```

In `pages/text.html.heex`, after the `<Components.division_text … />` block, inside the same `div`:

```heex
    <Components.endnotes notes={
      @edition.pages |> Enum.reject(& &1.scene) |> Enum.map(& &1.division) |> Note.reading_order()
    } />
```

In `lib/playcode/export/static_site/fingerprint.ex`, add `Playcode.PlayContent.Note` to `@modules`, after `Playcode.PlayContent.Element`: its `paragraphs/1` and `reading_order/1` decide what a page shows.

- [ ] **Step 6: Styles**

In `priv/static_site/style.css`, before the `@media (max-width: 600px)` block:

```css
/* In-text notes: the number after a glossed word opens its note, a popover. In print,
   and where popover is unsupported, the notes are the page's endnotes. */
.nref { font: 600 .62em/0 var(--sans); vertical-align: super; padding: 0 .12em; border: 0; background: none; color: var(--accent); cursor: pointer; }
.notes ol { margin: 0; padding: 0; }
.notes [popover] { max-width: min(34rem, calc(100vw - 2rem)); padding: 1rem 1.25rem; border: 1px solid var(--hair); border-radius: 6px; background: var(--raised); color: var(--ink); font: .875rem/1.55 var(--sans); }
.notes [popover] > button { float: right; margin: -.4rem -.5rem 0 .5rem; border: 0; background: none; color: var(--muted); font-size: 1.2rem; cursor: pointer; }
.notes [popover] p { margin: .5em 0 0; }
```

and inside `@media print { … }`:

```css
  .nref { color: inherit; }
  .notes [popover] { display: list-item; position: static; inset: auto; width: auto; height: auto; overflow: visible; margin: 0 0 .6em 1.5em; padding: 0; border: 0; max-width: none; background: none; }
  .notes [popover] > button { display: none; }
```

- [ ] **Step 7: Translations**

Run: `mix gettext.extract --merge`
In `priv/gettext/es/LC_MESSAGES/default.po`, fill: "Translator's note" → "Nota del traductor", "Editor's note" → "Nota del editor", "Critical editor's note" → "Nota del editor crítico", "Digital editor's note" → "Nota del editor digital", "Author's note" → "Nota del autor". Check every entry marked `#, fuzzy`: fix its `msgstr` and remove the flag. ("Note" already has "Nota".)

- [ ] **Step 8: Run the tests**

Run: `mix test test/playcode/export/static_site_test.exs test/playcode/export/static_site/fingerprint_test.exs`
Expected: PASS, including the asset budget and the fingerprint's two tests.

- [ ] **Step 9: Refactor while green**

The verse line in `el/1` is one `phx-no-format` line; check that no whitespace crept between the text and the marker (the "Nous voyent1" assertion guards it). Rerun the static site tests if anything changed.

- [ ] **Step 10: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/playcode/play_content/note.ex lib/playcode/play_content.ex lib/playcode_web/play_labels.ex lib/playcode/export/static_site priv/static_site/style.css priv/gettext test/playcode/export/static_site_test.exs
git commit -m "feat(static-site): in-text notes as numbered pop-ups and endnotes

A number after the glossed word opens the note (native popover, no
script); each page lists its notes, which print as endnotes. Numbers run
through the play in reading order.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Numbered notes on the live play pages

**Files:**
- Modify: `lib/playcode_web/components/play_text.ex`
- Modify: `assets/css/app.css`
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2`, `Note.reading_order/1`, `Note.paragraphs/1`, numbered notes from `load_play_content/1`, `PlayLabels.note_type_label/1` (Tasks 2 and 4).

`PlayText.play_body/1` also draws the compare pages (public and admin) and the content editor's preview, all from `load_play_content/1`, so they show notes too. Ids are `note-<uuid>`, unique on a compare page that shows two plays.

- [ ] **Step 1: Write the failing test**

In `test/playcode_web/live/play_show_live_test.exs`, after the italics test:

```elixir
  test "a note is a number after its word, opening the note with its type, term and text",
       %{conn: conn} do
    play =
      tei(
        body: """
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><lg><l n="1">Nous voyent<note n="6089" type="traductor"><term>voyent</term><p>Forma arcaica.</p></note> dans la ville</l></lg></sp>
        </div1>
        """
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
    doc = LazyHTML.from_fragment(html)
    squish = &(&1 |> String.replace(~r/\s+/u, " ") |> String.trim())

    assert [target] =
             doc
             |> LazyHTML.query(~s(button[aria-label="#{t("Translator's note")} 1"]))
             |> LazyHTML.attribute("popovertarget")

    note = squish.(doc |> LazyHTML.query("#" <> target) |> LazyHTML.text())
    assert note =~ t("Translator's note")
    assert note =~ "voyent"
    assert note =~ "Forma arcaica."

    assert squish.(LazyHTML.text(doc)) =~ "Nous voyent1 dans la ville"
    assert doc |> LazyHTML.text() |> String.split("Forma arcaica.") |> length() == 2
  end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: FAIL at `assert [target] = …` (no such button, `[]`).

- [ ] **Step 3: Markers and endnotes in `PlayText`**

In `lib/playcode_web/components/play_text.ex`:

```elixir
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.PlayContent.{Division, InlineMarkup, Note}
  alias PlaycodeWeb.PlayLabels
```

In `play_body/1`, as the last child of `<div class="play-text">`:

```heex
      <.endnotes notes={Note.reading_order(@divisions)} />
```

In `division_heading/1`, replace both `{@division.title}` with `<.inline_content text={@division.title} notes={@division.notes} />`. In the speech clause of `render_element/1`, replace `{@element.speaker_label}` with `<.inline_content text={@element.speaker_label} notes={@element.notes} />`. In the verse line, stage direction and prose clauses, add `notes={@element.notes}` to `<.inline_content … />`.

Replace `inline_content/1` with:

```elixir
  attr :text, :string, default: nil
  attr :notes, :list, default: []

  # One line, kept from the formatter by phx-no-format: a line break between a word and
  # its note's number would show as a space.
  defp inline_content(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text, assigns.notes))

    ~H"""
    <span phx-no-format><%= for part <- @parts do %><%= case part do %><% %{note: note} -> %><button type="button" class="nref" popovertarget={"note-#{note.id}"} aria-label={note_label(note)}>{note.number}</button><% %{italic: true} -> %><em>{part.text}</em><% _ -> %>{part.text}<% end %><% end %></span>
    """
  end

  defp note_label(note), do: "#{PlayLabels.note_type_label(note.type)} #{note.number}"

  attr :notes, :list, required: true

  # The play's notes, each a popover its number opens.
  defp endnotes(assigns) do
    ~H"""
    <section
      :if={@notes != []}
      class="play-notes"
      role="doc-endnotes"
      aria-label={gettext("Notes")}
    >
      <ol>
        <li :for={note <- @notes} id={"note-#{note.id}"} popover value={note.number}>
          <button
            type="button"
            popovertarget={"note-#{note.id}"}
            popovertargetaction="hide"
            aria-label={gettext("Close")}
            class="float-right"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(note.type)}</b>
          <i :if={note.term}><.inline_content text={note.term} /></i>
          <p :for={paragraph <- Note.paragraphs(note)}><.inline_content text={paragraph} /></p>
        </li>
      </ol>
    </section>
    """
  end
```

- [ ] **Step 4: Styles**

In `assets/css/app.css`, after the `.play-text .verse-line .part-f` rule:

```css
/* In-text notes: the number after a glossed word opens its note, a popover. */
.play-text .nref {
  font-size: 0.65em;
  line-height: 0;
  vertical-align: super;
  padding: 0 0.1em;
  color: var(--color-primary);
  cursor: pointer;
}

.play-notes ol {
  margin: 0;
  padding: 0;
}

.play-notes [popover] {
  max-width: min(32rem, calc(100vw - 2rem));
  padding: 1rem 1.25rem;
  border: 1px solid var(--color-base-300);
  border-radius: var(--radius-box);
  background: var(--color-base-100);
  color: var(--color-base-content);
}

.play-notes [popover] p {
  margin-top: 0.5em;
}
```

- [ ] **Step 5: Run the test**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode_web/live/play_compare_live_test.exs test/playcode_web/live/admin`
Expected: PASS. (If `play_compare_live_test.exs` lives elsewhere, run `mix test test/playcode_web` instead.)

- [ ] **Step 6: Refactor while green**

The italics test above this one asserts `<em>` without `&lt;&lt;`; it must still pass with the new `inline_content`. Nothing else to reshape.

- [ ] **Step 7: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/playcode_web/components/play_text.ex assets/css/app.css test/playcode_web/live/play_show_live_test.exs
git commit -m "feat(public): in-text notes as numbered pop-ups on the play page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Notes in the HTML, PDF and EPUB downloads

**Files:**
- Create: `lib/playcode/export/note_markup.ex`
- Modify: `lib/playcode/export/html.ex`, `lib/playcode/export/epub.ex`
- Test: `test/playcode_web/controllers/admin/export_controller_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2`, `Note.reading_order/1`, `Note.paragraphs/1`, numbered notes, `PlayLabels.note_type_label/1`.
- Produces: `NoteMarkup.inline(text | nil, [Note], :html | :epub) :: String.t()`, `NoteMarkup.endnotes([Note], :html | :epub) :: String.t()`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/controllers/admin/export_controller_test.exs`, at the end of the module:

```elixir
  describe "a play with in-text notes" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>ANA</speaker>
                <l n="1">Nous <emph>voyent</emph><note n="6089" type="editor"><term>voyent</term><p>Forme &amp; archaïque.</p></note> dans la ville</l>
              </sp>
            </div1>
            """
          )
        )

      %{noted: play}
    end

    test "the HTML download numbers a note after its word and lists it after the act",
         %{conn: conn, noted: play} do
      doc =
        conn
        |> get(~p"/admin/plays/#{play.id}/export/html")
        |> response(200)
        |> LazyHTML.from_document()

      text = doc |> LazyHTML.text() |> String.replace(~r/\s+/u, " ")

      assert text =~ "Nous voyent1 dans la ville"
      refute text =~ "<<"
      assert "voyent" in (doc |> LazyHTML.query("em") |> Enum.map(&LazyHTML.text/1))
      assert doc |> LazyHTML.query("sup a") |> LazyHTML.attribute("href") == ["#note-1"]

      endnote = doc |> LazyHTML.query("#note-1") |> LazyHTML.text()
      assert endnote =~ "Editor's note"
      assert endnote =~ "voyent"
      assert endnote =~ "Forme & archaïque."
      assert doc |> LazyHTML.query("#note-1 a") |> LazyHTML.attribute("href") == ["#ref-1"]
    end

    test "the EPUB marks a note as a noteref, with its footnote in the act's chapter",
         %{conn: conn, noted: play} do
      conn = get(conn, ~p"/admin/plays/#{play.id}/export/epub")
      {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
      {_name, chapter} = Enum.find(files, fn {name, _} -> to_string(name) =~ "chapter-001" end)

      # Well-formed XHTML, or e-readers refuse the chapter. Saxy is given it without its
      # DOCTYPE, which is not what is being checked.
      assert {:ok, _} =
               chapter |> String.replace(~r/<!DOCTYPE[^>]*>/, "") |> Saxy.SimpleForm.parse_string()

      assert chapter =~ ~s(xmlns:epub="http://www.idpf.org/2007/ops")
      assert chapter =~ ~s(<a epub:type="noteref" href="#note-1">1</a>)
      assert chapter =~ ~s(<aside epub:type="footnote" id="note-1">)
      assert chapter =~ "Forme &amp; archaïque."
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/controllers/admin/export_controller_test.exs`
Expected: both FAIL. The HTML's text holds `<<voyent>>` and the note's text, and the chapter has no `noteref`.

- [ ] **Step 3: `NoteMarkup`**

`lib/playcode/export/note_markup.ex`:

```elixir
defmodule Playcode.Export.NoteMarkup do
  @moduledoc """
  A line's text as HTML for the HTML (and so PDF) and EPUB downloads: italics as `<em>`,
  each in-text note as a reference to its endnote, and an act's notes as endnotes.
  `:html` links a superscript number to its endnote and back; `:epub` marks them
  `noteref` and `footnote`, which e-readers show as pop-ups. The labels are English, as
  the rest of the downloads are.
  """

  alias Playcode.PlayContent.{InlineMarkup, Note}
  alias PlaycodeWeb.PlayLabels

  @doc "`text`, with `<<…>>` italics, and its `notes`, as escaped HTML."
  def inline(text, notes, format),
    do: text |> InlineMarkup.parts(notes) |> Enum.map_join(&part(&1, format))

  defp part(%{note: %{number: n}}, :html),
    do: ~s(<sup class="nref"><a id="ref-#{n}" href="#note-#{n}">#{n}</a></sup>)

  defp part(%{note: %{number: n}}, :epub),
    do: ~s(<sup><a epub:type="noteref" href="#note-#{n}">#{n}</a></sup>)

  defp part(%{italic: true, text: text}, _format), do: "<em>#{escape(text)}</em>"
  defp part(%{text: text}, _format), do: escape(text)

  @doc "`notes` as endnotes: an `<ol>` section for `:html`, footnote asides for `:epub`."
  def endnotes([], _format), do: ""

  def endnotes(notes, :html) do
    items =
      Enum.map_join(notes, "\n", fn note ->
        ~s(<li id="note-#{note.number}" value="#{note.number}">#{body(note, "")}) <>
          ~s( <a href="#ref-#{note.number}" aria-label="Back to the text">↩</a></li>)
      end)

    ~s(<section class="notes"><ol>\n#{items}\n</ol></section>\n)
  end

  def endnotes(notes, :epub) do
    Enum.map_join(notes, "", fn note ->
      ~s(<aside epub:type="footnote" id="note-#{note.number}">#{body(note, "#{note.number}. ")}</aside>\n)
    end)
  end

  defp body(note, prefix) do
    label =
      Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn -> PlayLabels.note_type_label(note.type) end)

    term = if note.term, do: " <i>#{inline(note.term, [], :html)}</i>", else: ""
    paragraphs = Enum.map_join(Note.paragraphs(note), &"<p>#{inline(&1, [], :html)}</p>")
    "<p><b>#{prefix}#{escape(label)}</b>#{term}</p>#{paragraphs}"
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
```

- [ ] **Step 4: The HTML download**

In `lib/playcode/export/html.ex`, add `alias Playcode.Export.NoteMarkup` and `alias Playcode.PlayContent.Note`. Then:
- `render_divisions/2`: after `children = …`, add `notes = NoteMarkup.endnotes(Note.reading_order(div), :html)`, and end the division string with `#{children}\n#{notes}    </div>` in place of `#{children}\n    </div>`.
- `division_heading/1`'s two title clauses take the division: `defp division_heading(%{title: title, type: type} = div) when type in @act_types` printing `#{NoteMarkup.inline(title, div.notes, :html)}`, and the same for the scene clause and `child_heading/1`.
- speech: `#{NoteMarkup.inline(el.speaker_label, el.notes, :html)}`
- verse line, stage direction, prose: `#{NoteMarkup.inline(el.content, el.notes, :html)}` in place of `#{escape(el.content || "")}`

In its `css/0`, add:

```css
    .nref { font-size: 0.7em; line-height: 0; }
    .nref a { text-decoration: none; }
    .notes { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #ddd; font-size: 0.9rem; }
    .notes li p { margin: 0.3rem 0; }
```

- [ ] **Step 5: The EPUB**

In `lib/playcode/export/epub.ex`, the same aliases and the same changes with `:epub`: headings, speaker, verse line, stage direction and prose through `NoteMarkup.inline(…, :epub)`, and `render_division/2` ending with `#{children}\n#{NoteMarkup.endnotes(Note.reading_order(div), :epub)}</div>`. In `write_chapter/5`, the `<html …>` tag gains `xmlns:epub="http://www.idpf.org/2007/ops"`:

```elixir
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang}" lang="#{lang}">
```

In its `css/0`, add:

```css
    aside { font-size: 0.9em; }
    sup a { text-decoration: none; }
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/playcode_web/controllers/admin/export_controller_test.exs test/playcode_web/controllers/export_controller_test.exs`
Expected: PASS.

- [ ] **Step 7: Refactor while green**

`html.ex` and `epub.ex` each keep a private `escape/1` for the fields they still print themselves; leave them. Check that no `escape(el.content` is left in either file: `grep -n "escape(el.content" lib/playcode/export/html.ex lib/playcode/export/epub.ex` prints nothing.

- [ ] **Step 8: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/playcode/export/note_markup.ex lib/playcode/export/html.ex lib/playcode/export/epub.ex test/playcode_web/controllers/admin/export_controller_test.exs
git commit -m "feat(export): in-text notes in the HTML, PDF and EPUB downloads

A number after the glossed word links to the note, listed after its act;
the EPUB marks them noteref and footnote. Italics now render in these
downloads instead of printing <<…>>.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: A note stays after its word when the text around it is edited

**Files:**
- Modify: `lib/playcode/play_content.ex` (`update_element/2`, `update_division/2`, `anchor_text/1`, offset carrying)
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Consumes: `has_many :notes`, `InlineMarkup.plain/1`.
- Produces: `PlayContent.anchor_text(%Element{} | %Division{}) :: String.t() | nil`; `update_element/2` and `update_division/2` keep their `{:ok, struct} | {:error, changeset}` contract and move the notes in the same transaction.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/play_content_editor_live_test.exs`, add:

```elixir
  describe "notes when their text is edited" do
    setup %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO<note n="2" type="editor"><p>Glosa del título.</p></note></head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Buscad por todas partes<note n="1" type="traductor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
    end

    defp note_after(play, tag) do
      for %{in: ^tag, after: text} <- xml_notes(export_tei(play)), do: text
    end

    test "a line's note follows its word through edits, and stays in the line when the word goes",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit = fn from, to ->
        lv |> element("span[title='#{from}']") |> render_click()
        lv |> element("form[id^='inline-edit-']") |> render_submit(%{"value" => to})
      end

      edit.("Buscad por todas partes ya", "Ya buscad por todas partes ya")
      assert note_after(play, "l") == ["Ya buscad por todas partes"]

      edit.("Ya buscad por todas partes ya", "Ya buscad por todas ya")
      assert note_after(play, "l") == ["Ya buscad por todas"]
      assert reading_texts(export_tei(play), "l") == ["Ya buscad por todas ya"]
    end

    test "a heading's note follows its word when the heading is renamed",
         %{conn: conn, play: play} do
      lv = open_structure(conn, play)

      [act] =
        Regex.run(~r/id="(division-[^"]+)"[^>]*>(?:(?!id="division-).)*ACTO PRIMERO/s, render(lv),
          capture: :all_but_first
        )

      lv |> element("##{act} button[aria-label='#{t("Edit metadata")}']") |> render_click()
      lv |> form("#division-form", division: %{"title" => "EL ACTO PRIMERO"}) |> render_submit()

      assert note_after(play, "head") == ["EL ACTO PRIMERO"]
    end
  end
```

(The regex finds the act's DOM id the way "an act is added, retitled and deleted" does.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs`
Expected: both FAIL. The note stays at its old offset: after "Ya buscad por todas par", and after "EL ACTO PRIM".

- [ ] **Step 3: Carry the offsets**

In `lib/playcode/play_content.ex`, add `InlineMarkup` to the `alias Playcode.PlayContent.{…}` line. Replace `update_division/2` and `update_element/2` with:

```elixir
  @doc """
  Updates a division. Its notes keep their place in its title (`carry/2`).
  """
  def update_division(%Division{} = division, attrs),
    do: division |> Division.changeset(attrs) |> update_anchor(division_id: division.id)
```

```elixir
  @doc """
  Updates an element. Its notes keep their place in its text (`carry/2`).
  """
  def update_element(%Element{} = element, attrs),
    do: element |> Element.changeset(attrs) |> update_anchor(element_id: element.id)
```

and add to the `# --- Notes ---` section:

```elixir
  @doc """
  The text a note on `anchor` counts its offset in: a division's title, a speech's
  speaker label, any other element's content.
  """
  def anchor_text(%Division{title: title}), do: title
  def anchor_text(%Element{type: "speech", speaker_label: label}), do: label
  def anchor_text(%Element{content: content}), do: content

  # Saves an element's or a division's changeset and, in the same transaction, moves its
  # notes through the change to its text.
  defp update_anchor(changeset, where) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated} ->
          carry_notes(where, anchor_text(changeset.data), anchor_text(updated))
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp carry_notes(_where, same, same), do: :ok

  defp carry_notes(where, old, new) do
    diff = String.myers_difference(InlineMarkup.plain(old), InlineMarkup.plain(new))

    Note
    |> where(^where)
    |> Repo.all()
    |> Enum.each(fn note ->
      case carry(note.offset, diff) do
        offset when offset == note.offset -> :ok
        offset -> note |> Ecto.Changeset.change(offset: offset) |> Repo.update!()
      end
    end)
  end

  # Where offset `k` of the old text lands in the new one, through
  # String.myers_difference/2's script: a kept run carries it along (a note at the end of
  # a run stays after it), an insertion before it pushes it right, and a deletion holding
  # it leaves it where the deletion was.
  defp carry(k, diff) do
    {_old, new, landed} =
      Enum.reduce(diff, {0, 0, nil}, fn
        _step, {_old, _new, landed} = done when landed != nil ->
          done

        {:eq, run}, {old, new, nil} ->
          length = String.length(run)
          if k <= old + length, do: {old, new, new + k - old}, else: {old + length, new + length, nil}

        {:ins, run}, {old, new, nil} ->
          {old, new + String.length(run), nil}

        {:del, run}, {old, new, nil} ->
          length = String.length(run)
          if k < old + length, do: {old, new, new}, else: {old + length, new, nil}
      end)

    landed || new
  end
```

(`InlineMarkup.plain(nil)` is `""`, so a cleared speaker label carries its notes to offset 0.)

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode/content_version_test.exs test/playcode/play_content_test.exs`
Expected: PASS.

- [ ] **Step 5: Refactor while green**

`update_element/2`'s and `update_division/2`'s docs now say what they do with notes; check the moduledoc of `PlayContent` mentions notes among what it manages ("characters, divisions (acts/scenes), elements and their notes"). Rerun the same files.

- [ ] **Step 6: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/playcode/play_content.ex test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit -m "feat(notes): a note stays after its word when its line is edited

update_element/2 and update_division/2 carry every note's offset through
String.myers_difference/2 in the same transaction, so the inline edit,
the modal and the bulk speaker relabel all keep notes in place.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Curators add, change and delete notes

**Files:**
- Create: `lib/playcode_web/live/admin/notes_component.ex`
- Modify: `lib/playcode/play_content/note.ex` (`word_ends/1`)
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (`<.modal_content>` call around line 1950, `modal_content/1` attrs around line 2569, the division and element clauses)
- Modify: `lib/playcode/activity_log/entry.ex` (`@resource_types`), `lib/playcode_web/live/admin/activity_log_live.ex` (`translate_resource_type/1`)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Consumes: `PlayContent.list_notes/1`, `create_note/1`, `change_note/2`, `update_note/2`, `delete_note/1`, `anchor_text/1`, `PlayLabels.note_type_label/1`, `note_type_options/0`.
- Produces: `Note.word_ends(text | nil) :: [{String.t(), non_neg_integer()}]`; `PlaycodeWeb.Admin.NotesComponent` (assigns `id`, `anchor`, `play_id`, `user`).

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/play_content_editor_live_test.exs`, add (the module's top-level `setup` gives the play with "Segunda línea"):

```elixir
  describe "the note editor" do
    defp notes_section, do: "section[aria-label='#{t("Notes")}']"

    test "a note is added to a verse, changed and deleted, each logged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)
      lv |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']") |> render_click()
      lv |> element("button", t("Add note")) |> render_click()

      lv
      |> form("#note-form",
        note: %{
          "type" => "traductor",
          "offset" => "7",
          "term" => "Segunda",
          "body" => "Primera glosa.\n\nSegundo párrafo."
        }
      )
      |> render_submit()

      assert [
               %{
                 in: "l",
                 after: "Segunda",
                 type: "traductor",
                 term: "Segunda",
                 paragraphs: ["Primera glosa.", "Segundo párrafo."]
               }
             ] = xml_notes(export_tei(play))

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"offset" => "13", "body" => "Glosa corregida."}) |> render_submit()

      assert [%{after: "Segunda línea", paragraphs: ["Glosa corregida."]}] =
               xml_notes(export_tei(play))

      lv |> element("#{notes_section()} button", t("Delete")) |> render_click()
      assert xml_notes(export_tei(play)) == []

      actions =
        [resource_type: "note", play_id: play.id]
        |> Playcode.ActivityLog.list_entries()
        |> Enum.map(& &1.action)
        |> Enum.sort()

      assert actions == ["create", "delete", "update"]
    end

    test "changing only an imported note's text leaves it where it was", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">con dos caras que tiene,<note n="5" type="editor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      lv = open_scene(conn, play)
      lv |> element("#{card(lv, "con dos caras que tiene, ya")} button[aria-label='#{t("Edit")}']") |> render_click()
      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Glosa nueva."}) |> render_submit()

      assert [%{after: "con dos caras que tiene,", paragraphs: ["Glosa nueva."]}] =
               xml_notes(export_tei(play))
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs`
Expected: both FAIL: no `button` with text `t("Add note")` in the first; no Notes section in the second.

- [ ] **Step 3: Where a note can go**

In `lib/playcode/play_content/note.ex`, add `alias Playcode.PlayContent.InlineMarkup` (extend the existing alias line) and:

```elixir
  @doc """
  Where a note can go in `text`: after each word, as `{word, offset}`, a repeated word
  numbered ("partes (2)"). The offset counts graphemes of the plain text.
  """
  def word_ends(text) do
    plain = InlineMarkup.plain(text)

    {ends, _seen} =
      ~r/[\p{L}\p{N}'’]+/u
      |> Regex.scan(plain, return: :index)
      |> Enum.map_reduce(%{}, fn [{start, length}], seen ->
        word = binary_part(plain, start, length)
        count = Map.get(seen, word, 0) + 1
        label = if count == 1, do: word, else: "#{word} (#{count})"
        offset = String.length(binary_part(plain, 0, start + length))
        {{label, offset}, Map.put(seen, word, count)}
      end)

    ends
  end
```

- [ ] **Step 4: The component**

`lib/playcode_web/live/admin/notes_component.ex`:

```elixir
defmodule PlaycodeWeb.Admin.NotesComponent do
  @moduledoc """
  The notes on one line, speaker label or heading, in the content editor's modal for it:
  a list with Edit and Delete, and a form to add a note or change one. Each change is
  saved and logged at once, apart from the modal's own form, which a note's form cannot
  sit inside.
  """
  use PlaycodeWeb, :live_component

  alias Playcode.{ActivityLog, PlayContent}
  alias Playcode.PlayContent.{Division, Note}
  alias PlaycodeWeb.PlayLabels

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:editing, fn -> nil end)
     |> assign_new(:form, fn -> nil end)
     |> assign(:notes, PlayContent.list_notes(assigns.anchor))}
  end

  @impl true
  def handle_event("new_note", _params, socket) do
    note = %Note{offset: default_offset(socket.assigns.anchor)}
    {:noreply, assign(socket, editing: note, form: to_form(PlayContent.change_note(note)))}
  end

  def handle_event("edit_note", %{"id" => id}, socket) do
    case own_note(socket, id) do
      nil -> {:noreply, socket}
      note -> {:noreply, assign(socket, editing: note, form: to_form(PlayContent.change_note(note)))}
    end
  end

  def handle_event("cancel_note", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("save_note", %{"note" => params}, socket) do
    %{editing: note, anchor: anchor, play_id: play_id} = socket.assigns
    params = Map.take(params, ~w(offset type term body))

    {action, result} =
      if note.id,
        do: {"update", PlayContent.update_note(note, params)},
        else: {"create", PlayContent.create_note(Map.merge(params, anchor_attrs(anchor, play_id)))}

    case result do
      {:ok, saved} ->
        log(socket, action, saved)

        {:noreply,
         assign(socket, editing: nil, form: nil, notes: PlayContent.list_notes(anchor))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    case own_note(socket, id) do
      nil ->
        {:noreply, socket}

      note ->
        {:ok, _} = PlayContent.delete_note(note)
        log(socket, "delete", note)
        {:noreply, assign(socket, notes: PlayContent.list_notes(socket.assigns.anchor))}
    end
  end

  # One of this anchor's notes: the id comes from the browser.
  defp own_note(socket, id), do: Enum.find(socket.assigns.notes, &(&1.id == id))

  defp anchor_attrs(%Division{id: id}, play_id), do: %{"play_id" => play_id, "division_id" => id}
  defp anchor_attrs(element, play_id), do: %{"play_id" => play_id, "element_id" => element.id}

  # A new note goes after the last word.
  defp default_offset(anchor) do
    case anchor |> PlayContent.anchor_text() |> Note.word_ends() do
      [] -> 0
      ends -> ends |> List.last() |> elem(1)
    end
  end

  # After each word; plus where the note is now when that is not after a word (an imported
  # note after punctuation), so saving its text alone does not move it; or the end of an
  # empty text.
  defp offset_options(anchor, %Note{offset: offset}) do
    ends = anchor |> PlayContent.anchor_text() |> Note.word_ends()

    cond do
      Enum.any?(ends, fn {_word, at} -> at == offset end) -> ends
      ends == [] -> [{gettext("At the end"), offset}]
      true -> Enum.sort_by([{gettext("Where it is now"), offset} | ends], &elem(&1, 1))
    end
  end

  defp log(socket, action, note) do
    ActivityLog.log!(%{
      user_id: socket.assigns.user.id,
      play_id: socket.assigns.play_id,
      action: action,
      resource_type: "note",
      resource_id: note.id,
      metadata: %{offset: note.offset, type: note.type}
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mt-6 border-t border-base-300 pt-4" aria-label={gettext("Notes")}>
      <h4 class="font-semibold mb-2">{gettext("Notes")}</h4>
      <ul :if={@notes != []} class="space-y-2 mb-3">
        <li :for={note <- @notes} class="flex items-start gap-2 text-sm">
          <div class="flex-1">
            <span class="font-medium">{PlayLabels.note_type_label(note.type)}</span>
            <em :if={note.term}>{note.term}</em>
            <span class="text-base-content/60">{String.slice(note.body, 0, 80)}</span>
          </div>
          <button
            type="button"
            phx-click="edit_note"
            phx-value-id={note.id}
            phx-target={@myself}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Edit")}
          </button>
          <button
            type="button"
            phx-click="delete_note"
            phx-value-id={note.id}
            phx-target={@myself}
            data-confirm={gettext("Delete this note?")}
            class="btn btn-ghost btn-xs text-error"
          >
            {gettext("Delete")}
          </button>
        </li>
      </ul>
      <p :if={@notes == [] and is_nil(@form)} class="text-sm text-base-content/50 mb-3">
        {gettext("No notes.")}
      </p>
      <button
        :if={is_nil(@form)}
        type="button"
        phx-click="new_note"
        phx-target={@myself}
        class="btn btn-sm"
      >
        {gettext("Add note")}
      </button>

      <.form
        :if={@form}
        for={@form}
        id="note-form"
        phx-submit="save_note"
        phx-target={@myself}
        class="space-y-3"
      >
        <.input
          field={@form[:type]}
          type="select"
          label={gettext("Type")}
          options={PlayLabels.note_type_options()}
        />
        <.input
          field={@form[:offset]}
          type="select"
          label={gettext("After")}
          options={offset_options(@anchor, @editing)}
        />
        <.input field={@form[:term]} type="text" label={gettext("Term")} />
        <.input field={@form[:body]} type="textarea" rows="4" label={gettext("Text")} />
        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          <button type="button" phx-click="cancel_note" phx-target={@myself} class="btn btn-ghost btn-sm">
            {gettext("Cancel")}
          </button>
        </div>
      </.form>
    </section>
    """
  end
end
```

- [ ] **Step 5: Place it in the modals**

In `lib/playcode_web/live/admin/play_content_editor_live.ex`:

1. The `<.modal_content …>` call (around line 1950) gains `play_id={@play.id}` and `user={@current_user}`.
2. Above `defp modal_content`, next to its other `attr`s (around line 2569):

```elixir
  attr :play_id, :string, default: nil
  attr :user, :any, default: nil
```

3. In `modal_content(%{modal: :division} = assigns)`, after `</.form>`:

```heex
    <.live_component
      :if={@editing}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
```

4. In `modal_content(%{modal: :element} = assigns)`, after its `</.form>`:

```heex
    <.live_component
      :if={@editing && @editing.type in ~w(verse_line prose stage_direction trailer speech)}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
```

- [ ] **Step 6: Log notes**

In `lib/playcode/activity_log/entry.ex`, add `note` to `@resource_types` (after `element`). In `lib/playcode_web/live/admin/activity_log_live.ex`, `translate_resource_type/1`, add `"note" -> gettext("note")` after the `"element"` clause.

- [ ] **Step 7: Translations**

Run: `mix gettext.extract --merge`. In `priv/gettext/es/LC_MESSAGES/default.po`, fill: "Add note" → "Añadir nota", "After" → "Después de", "Term" → "Término", "Delete this note?" → "¿Eliminar esta nota?", "No notes." → "Sin notas.", "At the end" → "Al final", "Where it is now" → "Donde está ahora", "note" → "nota". Check every `#, fuzzy` entry and remove the flag once its `msgstr` is right.

- [ ] **Step 8: Run the tests**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/live/admin/activity_log_live_test.exs`
Expected: PASS. (If the activity log test lives elsewhere, `mix test test/playcode_web/live/admin`.)

- [ ] **Step 9: Refactor while green**

`anchor_attrs/2` and `own_note/2` are the component's only security-relevant lines (the anchor and the note id come from the server, never the browser's params); reread them. Rerun the editor tests.

- [ ] **Step 10: Format, compile, full suite, commit**

```bash
mix format
mix compile --warnings-as-errors
mix test
git add lib/playcode_web/live/admin/notes_component.ex lib/playcode/play_content/note.ex lib/playcode_web/live/admin/play_content_editor_live.ex lib/playcode/activity_log/entry.ex lib/playcode_web/live/admin/activity_log_live.ex priv/gettext test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit -m "feat(admin): add, change and delete in-text notes in the content editor

The line, speech and division modals list their notes; a note goes after
a word of the text. Every change is logged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Documentation and the whole-branch check

**Files:**
- Modify: `CLAUDE.md`, `docs/static-site-improvements.md`, `docs/superpowers/specs/2026-10-08-in-text-notes-design.md`

- [ ] **Step 1: `CLAUDE.md`**

1. *Project Structure*, under `play_content/`: add `│   │   ├── note.ex                   # In-text notes: a gloss anchored at an offset in a line, speaker or heading`; under `export/`: `│       ├── note_markup.ex            # Italics and note references for the HTML/PDF and EPUB downloads`; under `live/admin/`: `│       ├── notes_component.ex        # The note editor inside the content editor's modals`.
2. *Database Schema*: add a bullet after `element_characters`:
   "`play_notes` - in-text notes (TEI `<note>` in the body): on one element (a line, paragraph, stage direction, trailer, or a speech's speaker label) or one division's heading, at `offset` graphemes into that text's plain form (`PlayContent.anchor_text/1`); `position` orders notes at one offset; `n`, `type`, `term`, `body` (paragraphs split by a blank line). `update_element/2` and `update_division/2` carry offsets through an edit. Numbered in reading order (`Note.reading_order/1`) by `load_play_content/1`. A `--force` re-import replaces them with the text"
3. *Found by the test rework*: mark "In-text `<note>` is pasted into the line" `[x]` and replace its text with: "now stored in `play_notes` and written back by the TEI export; shown as numbered pop-ups on the static site and `/plays/:code`, as endnotes in the downloads, edited in the content editor. Spec: `docs/superpowers/specs/2026-10-08-in-text-notes-design.md`". In the "Inline `<stage>` is flattened" item, change "Same root cause as the inline `<stage>` gap above" wording if it refers to notes as open.
4. *Static Site Export*, *Architecture*: add "In-text notes: a `<button popovertarget>` after the word, each page's notes as a `doc-endnotes` list of `popover` items (endnotes in print). `Playcode.PlayContent.Note` is in the fingerprint."
5. *Real-fixture roundtrip test* entry in *What Has Been Implemented*: "Three tracked fixtures (`EMOTHE0746`, verse; `EMOTHE0776`, prose; `EMOTHE0705`, 17 in-text notes)…", and add `notes` to the count fields with "where each note sits and that none is pasted into the text".

- [ ] **Step 2: `docs/static-site-improvements.md`**

Item 1: add "**Done** (2026-10-08), see `superpowers/specs/2026-10-08-in-text-notes-design.md`." under its heading. Item 2: "Done for `Export.Html`, `Export.Pdf` and `Export.Epub` with the notes (`Export.NoteMarkup`); `Export.CompareHtml` still prints `<<…>>`."

- [ ] **Step 3: The spec's status**

Change the spec's status line to "**Status:** implemented, 2026-10-08 (`<first>..<last>` commit range of this branch)."

- [ ] **Step 4: The whole branch, green**

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test test/playcode/roundtrip_test.exs --include slow
node --test test/js/*.test.mjs
```

Expected: all pass. Paste the summary lines in the final report.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/static-site-improvements.md docs/superpowers/specs/2026-10-08-in-text-notes-design.md
git commit -m "docs: in-text notes are stored, exported and shown

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Look at it**

With `mix phx.server` running and the dev database re-imported (Task 3, Step 7): open http://localhost:4000/plays/EMOTHE0053_Hamlet, find "Buscad por todas partes …" in act 5, click its number, and check the pop-up shows "Nota del traductor", "partes …" and "(14) De aquí en adelante…". Then generate the site at http://localhost:4000/admin/export and check the same line on `/admin/export/preview/plays/EMOTHE0053_Hamlet/act-5.html`. Report what you saw; do not deploy.
