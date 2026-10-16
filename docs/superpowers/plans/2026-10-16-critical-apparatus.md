# The Critical Apparatus (`<app>`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take every `<app>` out of the line it is pasted into, keep it as a textual variant at its offset, show it to readers as an asterisk opening its readings (each witness named), and write it back to TEI as the `<app>` it was.

**Architecture:** A variant is a `play_notes` row of type `"variante"` with three new columns (`variant_type`, `range_end`, `readings` as an `embeds_many` JSONB), so it inherits the notes' offsets, positions, editing, trigger and placement in `InlineMarkup.parts/2`. The parser reads an `<app>` with the note machinery (a mark in the text, `take_notes/2`); the export writes it where `build_note/1` writes a note. `PlayContent.load_play_content/2` numbers variants apart from notes and names each reading's sigla from the play's witnesses and modern editions; every renderer's note clause dispatches on `Note.variant?/1`, and one function, `NoteMarkup.readings/2`, prints a variant's readings for the play page, the site and the downloads.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Ecto embeds, Saxy (TEI parsing), XmlBuilder (TEI export), LazyHTML (tests).

**Spec:** `docs/superpowers/specs/2026-10-16-critical-apparatus-design.md` (the corpus analysis behind it: `docs/tei-apparatus-and-code.md`)

## Global Constraints

- TDD, red-green-refactor: write the test, run it and watch it fail, write the least code, run it green, refactor while green, then `mix test` (whole suite) before claiming anything (`CLAUDE.md`).
- Prove each new test bites: break the line it covers, watch it go red, put it back; say so in the commit.
- Test through the outermost API: TEI as round trips (`roundtrip/1`, `xml_apps/1`, `xml_notes/1`, `reading_texts/2`), pages through `live/2` / `get`, the site through `generate!/2`, the editor through its LiveView. Read back through context functions, never `Repo`.
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit. Run `mix` plainly, never with a `PATH` export.
- Work on branch `critical-apparatus`; merge to `main` with `git merge --no-ff critical-apparatus -m "Merge branch 'critical-apparatus': …"`. Do not push while a production run or a site build is going.
- Commit messages `feat(…)`/`fix(…)`/`test(…)`/`docs:`, ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- A variant's `type` is exactly `"variante"` (`Note.variant/0`); `"variantes"`, the type of 3 ordinary notes, stays a note.
- `wit`, `n`, `type` (as `variant_type`) and `to` (as `range_end`) are kept exactly as the file writes them, `#` included; the export writes no attribute for nil.
- A TEI file names no Playcode identifier; the short names of sigla are worked out on load, never stored.
- `plays.show_variants` is never written by the TEI import (`@platform_owned`) and never written to the file (spec, *Hamlet*: the owner must agree before Task 8 states it in `CLAUDE.md`).
- Muted text on Playcode's own pages is never lighter than `text-base-content/70`; `style.css` stays under 25 KB, `site.js` under 15 KB.
- Every new user-visible string goes through `gettext` with its Spanish in `priv/gettext/es/LC_MESSAGES/default.po`; after `mix gettext.extract --merge`, check every entry it marks fuzzy.

## Review Focus

1. **An `<app>` directly in a line that is all aside, beside its "(Aparte)" stage** — the entry is neither spoken text nor dropped: the line stays wholly aside, its delivery stage dropped, the entry kept after its word (Task 2 test).
2. **A variant with no note of its own, in the admin lists** — `body` is nil, and the content editor's list sliced `note.body`; opening a line holding one must not crash, and its row shows its readings (Task 7 test).
3. **A line's text edited after import** — the variant follows its word as a note does (the offsets are carried by `update_element/2` for every `play_notes` row) (Task 7 test).
4. **"Show variant readings" off** — readers see no asterisk, no switch and no variants list anywhere (play page, site, downloads), while the TEI export and a re-import keep them (Task 4, 5 and 6 tests).
5. **Sigla that name nothing, several sigla in one `wit`, and `wit="#"`** — each siglum printed, with its short name when it has one; `#` alone prints the reading with no witness (Task 3 test).

---

### Task 1: A variant in a verse line leaves the text and comes back as its `<app>`

**Files:**
- Create: `priv/repo/migrations/20261016120000_add_variants_to_play_notes.exs`
- Create: `lib/playcode/play_content/note/reading.ex`
- Modify: `lib/playcode/play_content/note.ex`
- Modify: `lib/playcode/import/tei_parser.ex` (`pieces/3`, `take_notes/2`, `nested_notes/1`, `parse_note/2`)
- Modify: `lib/playcode/export/tei_xml.ex` (`inline_node/1`, `build_note/1`)
- Modify: `test/support/import_helpers.ex` (`tokens/1`, `leaf_notes/1`, `lined/1`, new `xml_apps/1`)
- Test: `test/playcode/tei_roundtrip_test.exs` (new `describe "the critical apparatus"`)

**Interfaces:**
- Produces: `Note.variant/0` → `"variante"`; `Note.variant?/1` (any map with `:type`) → boolean; `Note.paragraphs/1` accepts a `%Note{}`, a binary or nil; `%Note{variant_type, range_end, readings: [%Note.Reading{lemma, wit, text, note, sigla}]}`; `Note.Reading.sigla/1` (`"#P3 #MP"` → `["P3", "MP"]`); test helper `xml_apps/1` → `[%{in, after, n, type, to, readings: [{tag, wit, text, note}], note}]`.

- [ ] **Step 1: The test helper reads `<app>`s, and keeps them out of texts and notes**

In `test/support/import_helpers.ex`, an `<app>` is a token of its own, like a note. Replace `tokens/1`:

```elixir
  # An element's text, notes and entries in order: text as binaries, each note as
  # {:note, element}, each entry of the critical apparatus as {:app, element}.
  defp tokens({_name, _, children}) do
    Enum.flat_map(children, fn
      {"note", _, _} = note -> [{:note, note}]
      {"app", _, _} = app -> [{:app, app}]
      {_, _, _} = element -> tokens(element)
      text -> [text]
    end)
  end
```

In `leaf_notes/1`, skip an entry (add the clause before the text one):

```elixir
        {:note, note}, before -> {[note_map(note, name, before)], before}
        {:app, _app}, before -> {[], before}
        text, before -> {[], before <> text}
```

In `lined/1`, after `defp lined({"note", _, _}), do: ""`, add `defp lined({"app", _, _}), do: ""`.

After `xml_notes/1` and its private helpers, add:

```elixir
  @doc """
  Every `<app>` of the critical apparatus in the body, outside notes, in document order,
  as a map: `in`, the tag of the line, paragraph, stage direction, speaker or heading it
  sits in; `after`, that element's text before it (notes and entries left out, whitespace
  collapsed); its `n`, `type` and `to`; `readings`, each `{tag, wit, text, note}`, the text
  without the reading's note; and `note`, the text of its own note, or nil.
  """
  def xml_apps(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&leaf_apps/1)
  end

  defp leaf_apps({name, _, _} = leaf) when name in @leaves do
    {apps, _before} =
      leaf
      |> tokens()
      |> Enum.flat_map_reduce("", fn
        {:app, app}, before -> {[app_map(app, name, before)], before}
        {:note, _note}, before -> {[], before}
        text, before -> {[], before <> text}
      end)

    apps
  end

  defp leaf_apps({_name, _, children}), do: Enum.flat_map(children, &leaf_apps/1)
  defp leaf_apps(_text), do: []

  defp app_map({"app", attrs, children} = app, tag, before) do
    attrs = Map.new(attrs)

    %{
      in: tag,
      after: squash(before),
      n: attrs["n"],
      type: attrs["type"],
      to: attrs["to"],
      readings:
        for {name, reading_attrs, reading_children} <- children, name in ~w(lem rdg) do
          {notes, words} = Enum.split_with(reading_children, &match?({"note", _, _}, &1))

          {name, Map.new(reading_attrs)["wit"], flat_text({name, [], words}),
           Enum.map(notes, &flat_text/1) |> List.first()}
        end,
      note:
        case children_named(app, "note") do
          [note] -> flat_text(note)
          [] -> nil
        end
    }
  end

  # All of an element's text, joined as written, whitespace collapsed.
  defp flat_text({_name, _attrs, children}), do: children |> Enum.map_join(&flat_text/1) |> squash()
  defp flat_text(text) when is_binary(text), do: text

  defp squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
```

(If the file already has a private `squash/1`, use it and drop this one.)

- [ ] **Step 2: Write the failing tests**

In `test/playcode/tei_roundtrip_test.exs`, after the `describe "in-text notes"` block, add:

```elixir
  describe "the critical apparatus" do
    # A lemma with its own note, readings in italics, readings only with a range and the
    # entry's note, and an empty entry (Hamlet has four). No punctuation follows an </emph>:
    # the parser reads "<emph>x</emph>." as "<<x>> .", a matter of its own.
    @apparatus """
    <div1 type="jornada" n="1"><head>JORNADA PRIMERA</head>
      <sp><speaker>FENISA</speaker>
        <l n="72">mucho la hermosura llama<app type="substantive" n="908">
            <lem wit="#H">llama<note>Corrección de <emph>Hartzenbusch</emph> aceptada.</note></lem>
            <rdg wit="#P3">falta</rdg> <rdg wit="#MP">infama</rdg>
          </app>,</l>
        <l n="73">Barnardo.<app n="2"><lem wit="#Q2">Barnardo.</lem><rdg wit="#F1 #Q1"><emph>Barnardo?</emph></rdg></app> Bien</l>
        <l n="74">lovely<app type="orthographical" n="3" to="#l75"><rdg wit="#Dyce #Collier">lively</rdg><note>vv. 74-75 Faltan en <emph>Q1</emph> y Q2.</note></app> y más</l>
        <l n="75" xml:id="l75">sin nada<app n="4"/></l>
      </sp>
    </div1>
    """

    test "an entry leaves the line, which reads as the edition's text" do
      xml = roundtrip(tei(body: @apparatus))

      assert reading_texts(xml, "l") == [
               "mucho la hermosura llama,",
               "Barnardo. Bien",
               "lovely y más",
               "sin nada"
             ]

      # A reading's note is the reading's, not a note of the line.
      assert xml_notes(xml) == []
    end

    test "an entry comes back after the same word, with its readings, their notes and its own" do
      xml = roundtrip(tei(body: @apparatus))

      assert [
               %{
                 in: "l",
                 after: "mucho la hermosura llama",
                 n: "908",
                 type: "substantive",
                 to: nil,
                 readings: [
                   {"lem", "#H", "llama", "Corrección de Hartzenbusch aceptada."},
                   {"rdg", "#P3", "falta", nil},
                   {"rdg", "#MP", "infama", nil}
                 ],
                 note: nil
               },
               %{
                 after: "Barnardo.",
                 n: "2",
                 type: nil,
                 readings: [{"lem", "#Q2", "Barnardo.", nil}, {"rdg", "#F1 #Q1", "Barnardo?", nil}]
               },
               %{
                 after: "lovely",
                 n: "3",
                 type: "orthographical",
                 to: "#l75",
                 readings: [{"rdg", "#Dyce #Collier", "lively", nil}],
                 note: "vv. 74-75 Faltan en Q1 y Q2."
               },
               %{after: "sin nada", n: "4", readings: [], note: nil}
             ] = xml_apps(xml)

      assert xml_texts(xml, "emph", within: "app") == ["Hartzenbusch", "Barnardo?", "Q1"]
    end

    test "importing a file again replaces its entries, never doubles them" do
      path = tei(body: @apparatus) |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiImport.import_file(path)
      {:ok, play} = Playcode.Import.TeiImport.import_file(path)

      assert length(xml_apps(export_tei(play))) == 4
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first = tei(code: "APP1", body: @apparatus) |> roundtrip()
      second = first |> String.replace("APP1", "APP2") |> roundtrip()

      assert String.replace(second, "APP2", "APP1") == first
    end
  end
```

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs --only describe:"the critical apparatus"`
Expected: FAIL. The lines read with the readings pasted in ("mucho la hermosura llama llama falta infama," or similar), `xml_notes/1` finds "Corrección de Hartzenbusch." as a note of the line, and `xml_apps/1` is `[]`.

- [ ] **Step 4: The migration**

Create `priv/repo/migrations/20261016120000_add_variants_to_play_notes.exs`:

```elixir
defmodule Playcode.Repo.Migrations.AddVariantsToPlayNotes do
  @moduledoc """
  An entry of the critical apparatus, a TEI `<app>`, is a play_notes row of type
  "variante": its `type` as `variant_type`, its `to` as `range_end`, its `<lem>` and
  `<rdg>`s as `readings`. Its own note is the body, which it may lack. The play_notes
  trigger covers the new columns.
  """
  use Ecto.Migration

  def change do
    alter table(:play_notes) do
      add :variant_type, :string
      add :range_end, :string
      add :readings, :jsonb, null: false, default: fragment("'[]'::jsonb")
      modify :body, :text, null: true, from: {:text, null: false}
    end
  end
end
```

Run: `mix ecto.migrate` (the test alias migrates the test database itself).

- [ ] **Step 5: `Note.Reading` and the variant in `Note`**

Create `lib/playcode/play_content/note/reading.ex`:

```elixir
defmodule Playcode.PlayContent.Note.Reading do
  @moduledoc """
  One reading of a variant (`Note.variant?/1`): a TEI `<lem>` (`lemma`, the reading the
  edition follows) or `<rdg>`. `wit` is the witnesses' sigla as the file writes them
  (`"#1623b #1626a"`), `text` the reading with `<<…>>` italics, `note` the reading's own
  note. `sigla` is filled by `PlayContent.load_play_content/2`: each siglum with what
  `Witnesses.short_names/1` says it names, or nil; it is never stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Playcode.Text

  @primary_key false
  embedded_schema do
    field :lemma, :boolean, default: false
    field :wit, :string
    field :text, :string
    field :note, :string
    field :sigla, {:array, :any}, virtual: true, default: []
  end

  def changeset(reading, attrs) do
    reading
    |> cast(attrs, [:lemma, :wit, :text, :note])
    |> update_change(:wit, &Text.squeeze/1)
    |> update_change(:text, &Text.squeeze/1)
  end

  @doc ~S|The sigla `wit` names, without their `#`: `"#P3 #MP"` is `["P3", "MP"]`; `"#"` names none.|
  def sigla(nil), do: []

  def sigla(wit),
    do: wit |> String.split() |> Enum.map(&String.trim_leading(&1, "#")) |> Enum.reject(&(&1 == ""))
end
```

In `lib/playcode/play_content/note.ex`:

1. Add to the moduledoc, after the paragraph on `body`:

```
  A variant (`variant?/1`) is an entry of the critical apparatus, a TEI `<app>`: `n` its
  `n`, `variant_type` its `type`, `range_end` its `to`, both as written, `readings` its
  `<lem>` and `<rdg>`s (`Note.Reading`), `body` its own note or nil. Spec:
  docs/superpowers/specs/2026-10-16-critical-apparatus-design.md.
```

2. Alias the reading and name the type, under the existing aliases and `@types`:

```elixir
  alias Playcode.PlayContent.Note.Reading

  # The type of an entry of the critical apparatus. Not "variantes", an ordinary note's.
  @variant "variante"
```

3. In the schema, after `field :body, :string`:

```elixir
    field :variant_type, :string
    field :range_end, :string
```

and after `field :number, :integer, virtual: true`:

```elixir
    embeds_many :readings, Reading, on_replace: :delete
```

4. After `types/0`:

```elixir
  @doc "The `type` a variant is stored with: an entry of the critical apparatus, a TEI `<app>`."
  def variant, do: @variant

  @doc "True for a variant (`variant/0`), false for a note."
  def variant?(%{type: type}), do: type == @variant
```

5. Replace `paragraphs/1`:

```elixir
  @doc "A note's paragraphs, or a text's, in order; none for no text (a variant with no note)."
  def paragraphs(%__MODULE__{body: body}), do: paragraphs(body)
  def paragraphs(nil), do: []

  def paragraphs(text) when is_binary(text) do
    text
    |> String.split(~r/\n\s*\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
```

6. Replace `changeset/2`:

```elixir
  def changeset(note, attrs) do
    changeset =
      note
      |> cast(attrs, [
        :offset,
        :position,
        :n,
        :type,
        :term,
        :body,
        :variant_type,
        :range_end,
        :play_id,
        :element_id,
        :division_id
      ])
      |> cast_embed(:readings, sort_param: :readings_order, drop_param: :readings_delete)

    # A note is its text; a variant may have no note of its own.
    required =
      if variant?(%{type: get_field(changeset, :type)}),
        do: [:offset, :play_id],
        else: [:offset, :body, :play_id]

    changeset
    |> validate_required(required)
    |> validate_number(:offset, greater_than_or_equal_to: 0)
    |> check_constraint(:element_id, name: :one_anchor)
    |> foreign_key_constraint(:element_id)
    |> foreign_key_constraint(:division_id)
  end
```

- [ ] **Step 6: The parser reads an `<app>` as it reads a note**

In `lib/playcode/import/tei_parser.ex`:

1. Add `Note` to the module's `Playcode.PlayContent` alias (it aliases `InlineMarkup` already): `alias Playcode.PlayContent.{InlineMarkup, Note}` or a separate `alias Playcode.PlayContent.Note`.

2. Above `pieces/3`, add:

```elixir
  # What leaves the play text and is stored at its offset: a note, and an entry of the
  # critical apparatus.
  @apart ~w(note app)
```

3. In `pieces/3`, the mark clause becomes:

```elixir
      {{name, _, _} = note, i} when notes == :mark and name in @apart ->
        note_mark(note, children, i)
```

and its comment: `# Each child's text, read by `fun`; under :mark a <note> or <app> child is its mark instead.`

4. Replace `nested_notes/1` with a walker both kinds use:

```elixir
  # The elements named `names` inside `element`, not counting those inside them: a line's
  # notes and entries, not a note's own entries or an entry's readings' notes.
  defp outermost({_name, _attrs, children}, names) do
    Enum.flat_map(children, fn
      {name, _, _} = child -> if name in names, do: [child], else: outermost(child, names)
      _text -> []
    end)
  end
```

and in `take_notes/2`: `by_key = Map.new(outermost(element, @apart), &{Integer.to_string(:erlang.phash2(&1)), &1})`.

5. Replace `parse_note/2` with a note clause, an entry clause and the note text they share:

```elixir
  # A note's fields at `offset`, as a list: empty when the note has no text, since there is
  # nothing to show (the empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children} = note, offset) do
    case note_text(note) do
      nil ->
        []

      body ->
        term = safe_text(find_child(children, "term"))

        [
          %{
            offset: offset,
            n: attr_value(attrs, "n"),
            type: attr_value(attrs, "type"),
            term: if(term in [nil, ""], do: nil, else: term),
            body: body
          }
        ]
    end
  end

  # An entry of the critical apparatus: a variant (Note.variant/0) at `offset`, its readings
  # in order, each without its own note, which is the reading's; the entry's own note is its
  # body. An empty entry is kept: Hamlet's damaged ones are written back as they are.
  defp parse_note({"app", attrs, children}, offset) do
    [
      %{
        offset: offset,
        n: attr_value(attrs, "n"),
        type: Note.variant(),
        variant_type: attr_value(attrs, "type"),
        range_end: attr_value(attrs, "to"),
        body: note_text(find_child(children, "note")),
        readings:
          for {name, reading_attrs, reading_children} <- children, name in ~w(lem rdg) do
            %{
              lemma: name == "lem",
              wit: attr_value(reading_attrs, "wit"),
              text: text_content({name, reading_attrs, without(reading_children, "note")}),
              note: note_text(find_child(reading_children, "note"))
            }
          end
      }
    ]
  end

  # A note's text: its paragraphs, a blank line between them, its <term> left out; nil for
  # no note, or one with no text (a note of nothing but breaks, EMOTHE0299's <p><lb/></p>).
  defp note_text(nil), do: nil

  defp note_text({"note", attrs, children}) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content(
            {"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))},
            :breaks
          )

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content(&1, :breaks))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end
      |> String.replace(@break, "\n")

    if String.trim(body) == "", do: nil, else: body
  end

  # `children` without the `name` elements, the text either side joined as written: "is" and
  # "»" around an <app> read "is»", not "is »".
  defp without(children, name) do
    children
    |> Enum.reject(&match?({^name, _, _}, &1))
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) -> [Enum.join(texts)]
      elements -> elements
    end)
  end
```

- [ ] **Step 7: The export writes a variant as an `<app>`**

In `lib/playcode/export/tei_xml.ex`:

1. `inline_node/1`'s note clause:

```elixir
  defp inline_node(%{note: note}),
    do: if(Note.variant?(note), do: build_app(note), else: build_note(note))
```

2. After `build_note/1`:

```elixir
  # A variant (Note.variant?/1) as the <app> it was read from: its readings in order, a
  # reading's note inside it, the entry's own note last.
  defp build_app(note) do
    readings =
      Enum.map(note.readings, fn reading ->
        element(
          if(reading.lemma, do: :lem, else: :rdg),
          attributes(wit: reading.wit),
          inline_children(reading.text) ++ note_element(reading.note)
        )
      end)

    element(
      :app,
      attributes(type: note.variant_type, n: note.n, to: note.range_end),
      readings ++ note_element(note.body)
    )
  end

  # The pairs that have a value, as attributes.
  defp attributes(pairs), do: for({key, value} <- pairs, value, into: %{}, do: {key, value})

  # A text as an element's children: none when it is empty.
  defp inline_children(text) do
    case build_inline_content(text) do
      "" -> []
      nodes -> List.wrap(nodes)
    end
  end

  # A text as a <note> of paragraphs, or nothing for none.
  defp note_element(nil), do: []

  defp note_element(text),
    do: [element(:note, Enum.map(Note.paragraphs(text), &element(:p, build_inline_content(&1))))]
```

- [ ] **Step 8: Run the tests and watch them pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS, the new describe and every existing test in the file.

- [ ] **Step 9: Refactor while green**

`build_note/1` builds its attributes with the same comprehension `attributes/1` now names: make it `attrs = attributes(n: note.n, type: note.type)`. Run the file again after the change. Then:

Run: `mix test`
Expected: PASS. No fixture under `test/fixtures/` holds an `<app>`, so nothing else moves.

Prove the tests bite: in `pieces/3` take `app` back out of the mark clause (`name == "note"`); "an entry leaves the line" goes red with the readings pasted in. Put it back.

- [ ] **Step 10: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add priv/repo/migrations/20261016120000_add_variants_to_play_notes.exs lib/playcode/play_content/note.ex lib/playcode/play_content/note/reading.ex lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex test/support/import_helpers.ex test/playcode/tei_roundtrip_test.exs
git commit -m "feat(tei): an <app> leaves the line it was pasted into and comes back as itself

A variant is a play_notes row of type variante: readings as JSONB, its type and to
kept as written, its own note the body. Proved: with app out of the mark clause the
line reads with its readings pasted in again.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Every place an `<app>` sits, the copies inside notes, and the six plays

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`pieces/3`, `spoken_outside_aside?/1`, `aside_content/1`, `take_notes/2`)
- Create: `test/playcode/apparatus_corpus_test.exs` (`:slow`)
- Test: `test/playcode/tei_roundtrip_test.exs` (the `describe "the critical apparatus"` block)

**Interfaces:**
- Consumes: Task 1's `parse_note({"app", …}, offset)`, `outermost/2`, `without/2`, `@apart`, `xml_apps/1`.
- Produces: nothing new for later tasks; the parser's behaviour in the spec's *Import* section.

- [ ] **Step 1: Write the failing tests**

In the `describe "the critical apparatus"` block, add:

```elixir
    @placed """
    <div1 type="acto" n="1"><head>ACTO<app n="1"><lem wit="#A">ACTO</lem><rdg wit="#B">JORNADA</rdg></app> I</head>
      <sp><speaker>ANA<app n="2"><rdg wit="#B">ANNA</rdg></app></speaker>
        <stage>Sale<app n="3"><rdg wit="#B">Entra</rdg></app> el rey</stage>
        <l n="1">Dijo <stage>(en voz<app n="4"><rdg wit="#B">a voces</rdg></app> baja)</stage> y calló.</l>
        <l n="2">un <emph>sueño<app n="5"><rdg wit="#B">cuento</rdg></app> breve</emph> fue</l>
        <l n="3"><stage type="delivery">(Aparte.)</stage><seg type="aside">¡Ay de mí!</seg><app n="6"><rdg wit="#B">¡Oh!</rdg></app></l>
        <l n="4">Calla, <seg type="aside">que viene<app n="7"><rdg wit="#B">llega</rdg></app></seg> el rey.</l>
        <p>Buscad<app n="8"><rdg wit="#B">Mirad</rdg></app> por todas partes.</p>
      </sp>
    </div1>
    """

    test "an entry comes back where it was: heading, speaker, stage direction, inline stage, italics, asides, prose" do
      xml = roundtrip(tei(body: @placed))

      assert reading_texts(xml, "head") == ["ACTO I"]
      assert reading_texts(xml, "speaker") == ["ANA"]
      assert reading_texts(xml, "p") == ["Buscad por todas partes."]

      # A line all aside stays so, its delivery stage dropped, though an entry follows the
      # seg: the entry is not spoken text.
      assert reading_texts(xml, "l") == [
               "Dijo (en voz baja) y calló.",
               "un sueño breve fue",
               "¡Ay de mí!",
               "Calla, que viene el rey."
             ]

      assert Enum.map(xml_apps(xml), &{&1.in, &1.after, &1.n}) == [
               {"head", "ACTO", "1"},
               {"speaker", "ANA", "2"},
               {"stage", "Sale", "3"},
               {"l", "Dijo (en voz", "4"},
               {"l", "un sueño", "5"},
               {"l", "¡Ay de mí!", "6"},
               {"l", "Calla, que viene", "7"},
               {"p", "Buscad", "8"}
             ]

      assert length(xml_elements(xml, "app", within: "emph")) == 1
      assert length(xml_elements(xml, "app", within: "seg")) == 2
    end

    # 62 of the corpus's 63 entries inside notes copy their line's (same n).
    test "a note that copies its line's entry keeps the line's words, and the entry is written once" do
      copy = ~s(<app n="388"><rdg wit="#Bevington">an</rdg><rdg wit="#Q1">and</rdg></app>)

      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1">an#{copy} learn me that<note n="1" type="editor"><term>an#{copy} learn me that</term><p>an#{copy} learn me that: if you teach me; Q2 «ho! Who is#{copy}»</p></note></l>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert reading_texts(xml, "l") == ["an learn me that"]

      assert [%{term: "an learn me that", paragraphs: ["an learn me that: if you teach me; Q2 «ho! Who is»"]}] =
               xml_notes(xml)

      assert [%{after: "an", n: "388"}] = xml_apps(xml)
      assert xml_elements(xml, "app", within: "note") == []
    end

    # EMOTHE0530, v. 141: n="496" is only in the note on "ne".
    test "an entry found only in a note moves into the line, just after the note" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="141">ne<note n="1" type="editor"><term>ne</term><p>1623: <emph>n’en veulent</emph>; 1632: <emph>ne veulent<app type="substantive" n="496"><lem wit="#1632">ne veulent</lem><rdg wit="#1623b #1626a">n’en veulent</rdg></app></emph>.</p></note> veulent point.</l>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert reading_texts(xml, "l") == ["ne veulent point."]
      assert [%{after: "ne", n: "1"}] = xml_notes(xml)

      assert [
               %{
                 after: "ne",
                 n: "496",
                 readings: [
                   {"lem", "#1632", "ne veulent", nil},
                   {"rdg", "#1623b #1626a", "n’en veulent", nil}
                 ]
               }
             ] = xml_apps(xml)

      # The note first, then the entry, as they were found.
      assert xml =~ ~r{<note n="1"[^>]*>.*?</note><app }s
    end

    test "every place, the copies and the moved entry: exporting, re-importing and exporting again changes nothing" do
      body = """
      #{@placed}
      <div1 type="acto" n="2"><sp><speaker>A</speaker>
        <l n="9">an<app n="388"><rdg wit="#B">an</rdg></app> learn<note n="1" type="editor"><term>an<app n="388"><rdg wit="#B">an</rdg></app> learn</term><p>Glosa.</p></note></l>
        <l n="141">ne<note n="2" type="editor"><p>Ver <emph>ne veulent<app n="496"><rdg wit="#1623b">n’en veulent</rdg></app></emph>.</p></note> veulent.</l>
      </sp></div1>
      """

      first = tei(code: "APP3", body: body) |> roundtrip()
      second = first |> String.replace("APP3", "APP4") |> roundtrip()

      assert String.replace(second, "APP4", "APP3") == first
    end
```

Create `test/playcode/apparatus_corpus_test.exs`:

```elixir
defmodule Playcode.ApparatusCorpusTest do
  @moduledoc """
  The six plays of the production corpus that carry a critical apparatus, read from
  doc/tei_corpus/ (git-ignored; without it nothing runs): every entry outside a note comes
  back as an entry, with EMOTHE0530's one found only in a note; none is left inside a note
  or pasted into a line; and the export, imported again, gives the same entries and lines.
  `mix test --include slow`.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Import.TeiImport

  @moduletag :slow

  # The entries outside notes (604 in all, 63 inside notes, 62 of those copies), plus
  # EMOTHE0530's moved one. 542 in all.
  @entries %{
    "EMOTHE0010" => 90,
    "EMOTHE0187" => 64,
    "EMOTHE0435" => 10,
    "EMOTHE0460" => 127,
    "EMOTHE0530" => 62,
    "EMOTHE0560" => 189
  }

  # What the old import made of a line (docs/tei-apparatus-and-code.md).
  @pasted %{"EMOTHE0560" => "llamafalta", "EMOTHE0010" => "Barnardo. Barnardo."}

  for path <- Path.wildcard("doc/tei_corpus/EMOTHE0{010,187,435,460,530,560}_*.xml") do
    @path path
    @code path |> Path.basename() |> String.slice(0, 10)

    test "#{@code}: every entry comes back once, out of the text, and stays so" do
      {:ok, play} = TeiImport.import_file(@path)
      first = export_tei(play)

      assert length(xml_apps(first)) == @entries[@code]
      assert xml_elements(first, "app", within: "note") == []

      if pasted = @pasted[@code],
        do: refute(Enum.any?(reading_texts(first, "l"), &String.contains?(&1, pasted)))

      {:ok, again} = first |> write_tmp!() |> TeiImport.import_file()
      second = export_tei(again)

      assert xml_apps(second) == xml_apps(first)
      assert reading_texts(second, "l") == reading_texts(first, "l")
    end
  end
end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs --only describe:"the critical apparatus"`
Expected: FAIL. Line 3 reads "(Aparte.) ¡Ay de mí!" (the entry taken for spoken text makes it partly aside); the copying note's term reads "an an and learn me that"; the moved entry is missing from `xml_apps/1` (it stays pasted in the note).

Run: `mix test test/playcode/apparatus_corpus_test.exs --include slow`
Expected: FAIL on EMOTHE0010, 0187, 0530 and 0560 (entries left inside notes; 0530 one short). Without `doc/tei_corpus/` the file has no tests: copy the corpus there first (`CLAUDE.md`, *Getting Started*).

- [ ] **Step 3: An entry is apart from spoken text, and out of a note's**

In `lib/playcode/import/tei_parser.ex`:

1. `pieces/3` leaves entries out of every reading but the play text's:

```elixir
  # Each child's text, read by `fun`. Under :mark (the play text) a <note> or <app> child is
  # its mark instead; elsewhere (a note's own text) an <app> is left out, its neighbours
  # joined as written: a note that copies its line's entry keeps the line's words.
  defp pieces(children, notes, fun) do
    children = if notes == :mark, do: children, else: without(children, "app")

    children
    |> Enum.with_index()
    |> Enum.map(fn
      {{name, _, _} = note, i} when notes == :mark and name in @apart ->
        note_mark(note, children, i)

      {text, _} when is_binary(text) ->
        String.trim(text)

      {child, _} when is_tuple(child) ->
        fun.(child)

      _ ->
        ""
    end)
  end
```

2. `spoken_outside_aside?/1`: `name not in ~w(stage note app)`.

3. `aside_content/1`'s filter: `match?({name, _, _} when name in ~w(note app lb), &1)`.

4. `take_notes/2` moves an entry found only in a note into the line, after the note. Its last expression becomes:

```elixir
    own = for {"app", attrs, _} <- outermost(element, @apart), into: MapSet.new(), do: attr_value(attrs, "n")

    {text,
     found
     |> Enum.reverse()
     |> Enum.flat_map(fn {offset, note} ->
       offset = min(offset, last)
       parse_note(note, offset) ++ Enum.flat_map(strays(note, own), &parse_note(&1, offset))
     end)}
```

(compute `own` at the top of the function, next to `by_key`), and add after `take_notes/2`:

```elixir
  # The <app>s inside a note that copy none of its element's entries (`own`, their `n`s):
  # EMOTHE0530's n="496", only in the note on "ne". They move into the line, after the
  # note; the others are copies of the line's entry, which the note's text leaves out.
  defp strays({"note", _, _} = note, own),
    do: note |> outermost(["app"]) |> Enum.reject(&(attr_value(elem(&1, 1), "n") in own))

  defp strays(_app, _own), do: []
```

Extend the comment above `take_notes/2`: "An entry inside a note that copies none of the element's comes out after the note (strays/2)."

- [ ] **Step 4: Run the tests and watch them pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS.

Run: `mix test test/playcode/apparatus_corpus_test.exs --include slow`
Expected: PASS, six tests. A count that differs from `@entries` is a finding: read the play's entries before changing a number, and record why in the comment.

- [ ] **Step 5: Refactor while green**

`nested_notes/1` is gone; check no caller or comment still names it (`grep -n nested_notes lib`). `parse_note/2` and `take_notes/2` now share `outermost/2`; keep their comments saying what each reads. Run the two commands of Step 4 again, then:

Run: `mix test`
Expected: PASS.

Prove the tests bite: drop `app` from `spoken_outside_aside?/1`'s list (line 3 reads "(Aparte.) ¡Ay de mí!"); return `[]` from `strays/2` (the moved entry disappears); in `pieces/3` keep the children whole for every reading (the term reads "an an learn me that"). Put each back.

- [ ] **Step 6: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/import/tei_parser.ex test/playcode/tei_roundtrip_test.exs test/playcode/apparatus_corpus_test.exs
git commit -m "feat(tei): an <app> comes back from every place it sits; a note's copy is read as the line's

An entry is neither spoken text in an aside line nor pasted into a note; the one
EMOTHE0530 has only in a note moves into the line after it. A slow test reads the
six corpus plays. Proved: each rule undone turns its test red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `/plays/:code` shows each variant as an asterisk opening its readings

**Files:**
- Modify: `lib/playcode/witnesses.ex` (new `short_names/1`)
- Modify: `lib/playcode/play_content/note.ex` (new `name_witnesses/2`)
- Modify: `lib/playcode/play_content.ex` (`load_play_content/1`, the numbering walker)
- Modify: `lib/playcode/export/note_markup.ex` (new `readings/2`)
- Modify: `lib/playcode_web/play_labels.ex` (`note_type_label/1`)
- Modify: `lib/playcode_web/components/play_text.ex` (`play_body/1`, `part_html/2`, `endnotes/1`)
- Modify: `lib/playcode_web/live/play_show_live.ex` (the switch, the Notes view)
- Modify: `assets/css/app.css`
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/play_show_live_test.exs`, `test/playcode_web/accessibility_test.exs`

**Interfaces:**
- Consumes: Task 1's `Note.variant?/1`, `Note.Reading.sigla/1`, `Note.paragraphs/1`.
- Produces: `Witnesses.short_names(play_id)` → `%{siglum => name}` (only sigla that name something); `Note.name_witnesses(note, names)` → note with each reading's `sigla: [{siglum, name | nil}]`; `load_play_content/1` numbers notes and variants in two sequences (`number`) and fills `sigla`; `NoteMarkup.readings(note, :html | :epub)` → HTML string, one `<p>` per reading then the note's paragraphs; `PlayText.play_body/1` attr `show_variants` (default true), rendered as `data-variants="on" | "off"` on `.play-text`; the variant marker `<button class="vref" popovertarget="var-<id>" aria-label="Textual variant N">*</button>`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/play_show_live_test.exs`, add (it imports `Playcode.ImportHelpers` and aliases `TestFixtures` already; add `import Playcode.TestFixtures, only: [bibliography_fixture: 2]` if the file does not):

```elixir
  describe "textual variants" do
    setup %{conn: conn} do
      play =
        tei(
          source_desc: """
          <listWit>
            <witness xml:id="P3" n="P3"><bibl type="edicion_antigua"><title>Doce comedias</title><pubPlace>Madrid:</pubPlace><date>1653</date></bibl></witness>
            <witness xml:id="MP" n="MP"><bibl type="edicion_antigua"><title>Comedias</title><date>1735</date></bibl></witness>
          </listWit>
          """,
          body: """
          <div1 type="jornada" n="1"><head>Jornada I</head>
            <sp><speaker>FENISA</speaker>
              <l n="72">mucho la hermosura llama<app type="substantive" n="908"><lem wit="#H">llama<note>Corrección de <emph>Hartzenbusch</emph></note></lem><rdg wit="#P3">falta</rdg><rdg wit="#MP #X">infama</rdg><note>Por la rima.</note></app>,<note n="1" type="editor"><p>Glosa.</p></note></l>
              <l n="73">lovely<app n="909"><rdg wit="#BRA #JOW">lively</rdg><rdg wit="#Dyce #POPE1">lowly</rdg><rdg wit="#">lonely</rdg></app> y más</l>
            </sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      for {siglum, editors, year} <- [
            {"H", "Hartzenbusch, J. E.", "1860"},
            {"BRA", "Bruster, Douglas; Rasmussen, Eric", "2009"},
            {"JOW", "Taylor, Gary; Jowett, John; Bourus, Terri", "2016"},
            {"Dyce", "Dyce, Alexander", "1831"},
            {"POPE1", nil, "1723"}
          ] do
        bibliography_fixture(play, %{
          "kind" => "modern_edition",
          "siglum" => siglum,
          "monogr_editors" => editors,
          "year_text" => year
        })
      end

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, play: play}
    end

    defp squished(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

    defp variant_buttons(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(button[aria-label^="#{t("Textual variant")}"]))
    end

    test "an asterisk after the word opens the readings, each witness with what it names",
         %{view: view} do
      doc = view |> render() |> LazyHTML.from_fragment()

      # The line reads as the edition's text; the asterisk is apart from the note's number,
      # and the note is still the first.
      assert doc |> LazyHTML.query("#play-tab-text") |> LazyHTML.text() |> squished() =~
               "mucho la hermosura llama*,1"

      assert has_element?(view, ~s(button[aria-label="#{t("Editor's note")} 1"]))

      [first, second] = view |> variant_buttons() |> LazyHTML.attribute("popovertarget")

      readings = fn id ->
        doc |> LazyHTML.query("##{id} p") |> Enum.map(&squished(LazyHTML.text(&1)))
      end

      assert readings.(first) == [
               "H (Hartzenbusch, 1860) llama (Corrección de Hartzenbusch)",
               "P3 (Madrid, 1653) falta",
               "MP (1735) X infama",
               "Por la rima."
             ]

      assert readings.(second) == [
               "BRA (Bruster & Rasmussen, 2009) JOW (Taylor et al., 2016) lively",
               "Dyce (1831) POPE1 (1723) lowly",
               "lonely"
             ]
    end

    test "the Variants switch hides the asterisks, and the Notes view lists notes only",
         %{conn: conn, view: view} do
      assert has_element?(view, "label", t("Variants"))
      assert has_element?(view, ~s(#play-tab-text [data-variants="on"]))

      render_click(view, "toggle_variants")
      assert has_element?(view, ~s(#play-tab-text [data-variants="off"]))

      view |> element("#play-sections-panel button", t("Notes")) |> render_click()

      assert view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#play-tab-notes li") |> Enum.count() == 1

      # A play with no variants has no switch.
      plain =
        tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>))
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, plain_view, _html} = live(conn, ~p"/plays/#{plain.code}")
      refute has_element?(plain_view, "label", t("Variants"))
    end
  end
```

In `test/playcode_web/accessibility_test.exs`'s setup, before the returned map, give the fixture play a variant, so the play page's asterisk and pop-up are checked:

```elixir
    # A textual variant, so the play page's asterisk and its readings are checked too.
    {:ok, _} =
      Playcode.PlayContent.create_note(%{
        play_id: play.id,
        element_id: structure.verse_line.id,
        offset: 0,
        type: "variante",
        readings: [%{lemma: true, wit: "#A", text: "uno"}, %{wit: "#B", text: "dos"}],
        body: "Por la rima."
      })
```

(Use the setup's own name for the structure; it returns it as `structure:`. The `body` matters until Task 7: the content editor's notes list, which the accessibility test opens on that line, slices `note.body`, and a variant with none would crash it.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs --only describe:"textual variants"`
Expected: FAIL. The variant is numbered as a note ("llama1,2"), there is no "Textual variant" button, no "Variants" switch.

- [ ] **Step 3: What a siglum names**

In `lib/playcode/witnesses.ex` (it aliases `Link` and `Entry` for `taken_sigla/1`; add `alias Playcode.Text`), after `taken_sigla/1`:

```elixir
  @doc """
  What each siglum the play's variant readings may cite names, as readers see it after the
  siglum: a witness's place and date as written ("Madrid, 1653", "1735"); else a modern
  edition's editors' surnames and year ("Hartzenbusch, 1860", "Bruster & Rasmussen, 2009",
  "Taylor et al., 2016"), the year alone when the siglum is the first surname or there
  are no editors ("1831"). A siglum that names nothing is not in the map. Spec:
  docs/superpowers/specs/2026-10-16-critical-apparatus-design.md.
  """
  def short_names(play_id) do
    editions =
      from(l in Link,
        join: e in Entry,
        on: e.id == l.entry_id,
        where: l.play_id == ^play_id and not is_nil(e.siglum),
        select: e
      )
      |> Repo.all()
      |> Map.new(&{&1.siglum, edition_name(&1)})

    witnesses =
      from(w in Witness, where: w.play_id == ^play_id and not is_nil(w.siglum))
      |> Repo.all()
      |> Map.new(&{&1.siglum, witness_name(&1)})

    editions
    |> Map.merge(witnesses)
    |> Map.reject(fn {_siglum, name} -> name == "" end)
  end

  # "London:" is a place as a title page prints it.
  defp witness_name(witness) do
    [witness.pub_place && String.trim_trailing(witness.pub_place, ":"), witness.date]
    |> Enum.map(&Text.squeeze/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp edition_name(entry) do
    surnames =
      if entry.monogr_editors,
        do: entry.monogr_editors |> Entry.people() |> Enum.map(&surname/1),
        else: []

    editors =
      case surnames do
        [] -> nil
        [first | _] when first == entry.siglum -> nil
        [one] -> one
        [one, two] -> "#{one} & #{two}"
        [first | _] -> "#{first} et al."
      end

    [editors, Text.squeeze(entry.year_text)] |> Enum.reject(&is_nil/1) |> Enum.join(", ")
  end

  # "Hartzenbusch, J. E." is filed under Hartzenbusch.
  defp surname(person), do: person |> String.split(",", parts: 2) |> hd() |> String.trim()
```

In `lib/playcode/play_content/note.ex`, after `variant?/1`:

```elixir
  @doc """
  `note` with each reading's `sigla`: every siglum its `wit` names, with what `names`
  (`Witnesses.short_names/1`) says it names, or nil.
  """
  def name_witnesses(%__MODULE__{} = note, names) do
    readings =
      Enum.map(note.readings, fn reading ->
        %{reading | sigla: Enum.map(Reading.sigla(reading.wit), &{&1, names[&1]})}
      end)

    %{note | readings: readings}
  end
```

- [ ] **Step 4: Variants numbered apart, their witnesses named**

In `lib/playcode/play_content.ex` (add `alias Playcode.Witnesses`):

1. `load_play_content/1`'s last line becomes:

```elixir
    divisions
    |> attach_elements(elements_by_division)
    |> number_notes()
    |> name_witnesses(play_id)
```

and its doc: "Loads the full play content tree: divisions with nested elements, their notes and variants (`Note.variant?/1`) numbered in reading order, each kind in its own sequence, and each variant reading's sigla named (`Note.Reading`)."

2. Replace `number_notes/1`, `number_division/2`, `number_element/2` and `number/2` with:

```elixir
  # Gives each note its `number`, its place in Note.reading_order/1 from 1, the variants
  # numbered apart: readers count the notes, and a variant's number is only its marker's id.
  defp number_notes(divisions) do
    {variants, notes} = divisions |> Note.reading_order() |> Enum.split_with(&Note.variant?/1)

    numbers =
      Map.new(Enum.with_index(notes, 1) ++ Enum.with_index(variants, 1), fn {note, number} ->
        {note.id, number}
      end)

    update_notes(divisions, fn notes -> Enum.map(notes, &%{&1 | number: numbers[&1.id]}) end)
  end

  # Each variant reading's sigla with what they name; the witnesses are read only for a
  # play that has variants.
  defp name_witnesses(divisions, play_id) do
    if divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1) do
      names = Witnesses.short_names(play_id)
      update_notes(divisions, fn notes -> Enum.map(notes, &Note.name_witnesses(&1, names)) end)
    else
      divisions
    end
  end

  # Each anchor's list of notes, through `fun`.
  defp update_notes(divisions, fun), do: Enum.map(divisions, &update_division_notes(&1, fun))

  defp update_division_notes(division, fun) do
    %{
      division
      | notes: fun.(division.notes),
        loaded_elements: Enum.map(division.loaded_elements, &update_element_notes(&1, fun)),
        children: Enum.map(division.children, &update_division_notes(&1, fun))
    }
  end

  defp update_element_notes(element, fun) do
    children =
      case element.children do
        %Ecto.Association.NotLoaded{} = not_loaded -> not_loaded
        children -> Enum.map(children, &update_element_notes(&1, fun))
      end

    %{element | notes: fun.(element.notes), children: children}
  end
```

- [ ] **Step 5: A variant's readings as HTML, once for every reader**

In `lib/playcode/export/note_markup.ex`, add to the moduledoc: "`readings/2` prints a variant's readings, for the play page and the site as well." Then, after `endnotes/2`:

```elixir
  @doc """
  A variant's readings as HTML paragraphs, one per reading in order: each siglum in italics
  followed by what it names in parentheses (`Note.Reading`, `sigla`), the reading, and the
  reading's own note in parentheses; then the entry's own note. The play page, the site and
  the downloads print a variant so.
  """
  def readings(note, format) do
    Enum.map_join(note.readings, &"<p>#{reading(&1, format)}</p>") <>
      Enum.map_join(Note.paragraphs(note), &"<p>#{inline(&1, [], format)}</p>")
  end

  defp reading(reading, format) do
    [
      witnesses(reading.sigla),
      inline(reading.text, [], format),
      reading.note && "(#{inline(reading.note, [], format)})"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp witnesses(sigla) do
    Enum.map_join(sigla, " ", fn
      {siglum, nil} -> "<i>#{escape(siglum)}</i>"
      {siglum, name} -> "<i>#{escape(siglum)}</i> (#{escape(name)})"
    end)
  end
```

- [ ] **Step 6: The label, the marker, the pop-ups, the switch**

`lib/playcode_web/play_labels.ex`, after the `"autor"` clause of `note_type_label/1`:

```elixir
  def note_type_label("variante"), do: gettext("Textual variant")
```

`lib/playcode_web/components/play_text.ex` (add `alias Playcode.Export.NoteMarkup`):

1. `play_body/1`: `attr :show_variants, :boolean, default: true`, and its wrapper becomes `<div class="play-text" data-variants={if @show_variants, do: "on", else: "off"}>`.

2. Replace the note clause of `part_html/2`:

```elixir
  # Its id is where the Notes view takes the reader back to. A variant's marker is an
  # asterisk, apart from the numbers, which the Variants switch hides (app.css).
  defp part_html(%{note: note}, _show),
    do: if(Note.variant?(note), do: variant_ref(note), else: note_ref(note))

  defp note_ref(note) do
    [
      ~s(<button type="button" id="nref-),
      escape(note.id),
      ~s(" class="nref" popovertarget="note-),
      escape(note.id),
      ~s(" aria-label="),
      escape(note_label(note)),
      ~s(">),
      Integer.to_string(note.number),
      "</button>"
    ]
  end

  defp variant_ref(note) do
    [
      ~s(<button type="button" class="vref" popovertarget="var-),
      escape(note.id),
      ~s(" aria-label="),
      escape(note_label(note)),
      ~s(">*</button>)
    ]
  end
```

3. `endnotes/1` splits notes from variants; the notes' section is as before, the variants' follows:

```elixir
  # The play's notes, each a popover its number opens, then its variants, each a popover
  # its asterisk opens.
  defp endnotes(assigns) do
    {variants, notes} = Enum.split_with(assigns.notes, &Note.variant?/1)
    assigns = assign(assigns, notes: notes, variants: variants)

    ~H"""
    <section
      :if={@notes != []}
      class="play-notes"
      role="doc-endnotes"
      aria-label={gettext("Notes")}
    >
      <%!-- unchanged <ol> of notes --%>
    </section>
    <section :if={@variants != []} class="play-notes" aria-label={gettext("Textual variants")}>
      <ul>
        <li :for={variant <- @variants} id={"var-#{variant.id}"} popover>
          <button
            type="button"
            popovertarget={"var-#{variant.id}"}
            popovertargetaction="hide"
            aria-label={gettext("Close")}
            class="float-right"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(variant.type)}</b>
          {Phoenix.HTML.raw(NoteMarkup.readings(variant, :html))}
        </li>
      </ul>
    </section>
    """
  end
```

(Keep the notes' `<ol>` markup exactly as it is; the comment above stands for it.)

`assets/css/app.css`: the note marker's rule covers the asterisk, and the switch hides it:

```css
/* In-text notes: the number after a glossed word opens its note, a popover. A textual
   variant's asterisk opens its readings; the Variants switch hides the asterisks. */
.play-text .nref,
.play-text .vref {
  /* the existing declarations, unchanged */
}

.play-text[data-variants="off"] .vref {
  display: none;
}
```

and `.play-notes ol` becomes `.play-notes ol, .play-notes ul`.

`lib/playcode_web/live/play_show_live.ex` (alias `Playcode.PlayContent.Note` if it does not):

1. In `mount/3`:

```elixir
     |> assign(:notes, divisions |> note_entries() |> Enum.reject(&Note.variant?(&1.note)))
     ...
     |> assign(:show_variants, true)
     |> assign(:has_variants, divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1))
```

2. After `toggle_verse_type`:

```elixir
  def handle_event("toggle_variants", _, socket) do
    {:noreply, assign(socket, :show_variants, !socket.assigns.show_variants)}
  end
```

3. In "Visual markers", after "Verse type":

```heex
              <label
                :if={@has_variants}
                class="flex items-center gap-2 text-xs cursor-pointer text-base-content/70"
              >
                <input
                  type="checkbox"
                  checked={@show_variants}
                  phx-click="toggle_variants"
                  class="checkbox checkbox-xs checkbox-primary"
                /> {gettext("Variants")}
              </label>
```

4. `<.play_body … show_variants={@show_variants} />`.

- [ ] **Step 7: The Spanish**

Run: `mix gettext.extract --merge`. In `priv/gettext/es/LC_MESSAGES/default.po` fill: "Textual variant" → "Variante textual", "Textual variants" → "Variantes textuales", "Variants" → "Variantes". Check every entry the merge marked `#, fuzzy` and fix or clear it.

- [ ] **Step 8: Run the tests and watch them pass**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS.

- [ ] **Step 9: Refactor while green**

`note_label/1` serves both markers; `Note.reading_order/1` is now called by `number_notes/1` and `name_witnesses/2` on the same tree, which is fine (no query). Run Step 8 again, then:

Run: `mix test`
Expected: PASS. If a static-site or download test now fails on numbering, read it: no fixture there has a variant, so it is a real change.

Prove the tests bite: number the variants with the notes (`Enum.with_index(notes ++ variants, 1)`): the note's button reads 2 and the first test goes red. Put it back. Swap `[first | _] when first == entry.siglum` for `[first | _] when false`: "Dyce (1831)" reads "Dyce (Dyce, 1831)". Put it back.

- [ ] **Step 10: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/witnesses.ex lib/playcode/play_content/note.ex lib/playcode/play_content.ex lib/playcode/export/note_markup.ex lib/playcode_web/play_labels.ex lib/playcode_web/components/play_text.ex lib/playcode_web/live/play_show_live.ex assets/css/app.css priv/gettext test/playcode_web/live/play_show_live_test.exs test/playcode_web/accessibility_test.exs
git commit -m "feat(play): a textual variant is an asterisk opening its readings, each witness named

Variants are numbered apart from notes, a reading's sigla named from the play's
witnesses and modern editions; a Variants switch hides the asterisks, and the
Notes view lists notes only. Proved: numbered with the notes, the note reads 2.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: "Show variant readings", off for Hamlet

**Files:**
- Create: `priv/repo/migrations/20261016130000_add_show_variants_to_plays.exs`
- Modify: `lib/playcode/catalogue/play.ex` (field, cast, moduledoc)
- Modify: `lib/playcode/import/tei_import.ex` (`@platform_owned`, `preserved_fields/1`)
- Modify: `lib/playcode/play_content.ex` (`load_play_content/2`, `variants:`)
- Modify: `lib/playcode_web/live/admin/play_form_live.ex` (the checkbox)
- Modify: `lib/playcode_web/live/play_show_live.ex`, `lib/playcode_web/live/play_comparison.ex` (pass the setting)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_form_live_test.exs`, `test/playcode/import/tei_preview_test.exs`

**Interfaces:**
- Consumes: Task 3's variant marker and switch on the play page.
- Produces: `plays.show_variants` (boolean, default true); `PlayContent.load_play_content(play_id, variants: boolean)` (default true) leaves variants out when false. Tasks 5 and 6 pass `variants: play.show_variants`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/play_form_live_test.exs` (import `Playcode.ImportHelpers` if it does not; its `save/2` submits `#play-form`):

```elixir
  # Hamlet's apparatus is unfinished (question 2): its variants are hidden from readers
  # until its editor has finished, and the file still carries them.
  test "Show variant readings off hides the variants from readers, never from the file",
       %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<app n="1"><rdg wit="#B">dos</rdg></app> tres</l></sp></div1>)
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
    save(view, %{"show_variants" => "false"})

    hidden? = fn ->
      {:ok, page, _html} = live(build_conn(), ~p"/plays/#{play.code}")

      not has_element?(page, ~s(button[aria-label^="#{t("Textual variant")}"])) and
        not has_element?(page, "label", t("Variants"))
    end

    assert hidden?.()
    assert [%{n: "1"}] = xml_apps(export_tei(play))

    # A re-import of its file leaves the setting as the curator left it.
    {:ok, _} = play |> export_tei() |> write_tmp!() |> Playcode.Import.TeiImport.import_file()
    assert hidden?.()
  end
```

In `test/playcode/import/tei_preview_test.exs`:

```elixir
  # Kept by every re-import; reported only when a curator has turned it off.
  test "Show variant readings is reported as kept only when it is off", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)

    assert {:ok, preview} = TeiImport.preview_import(path)
    refute :show_variants in preview.preserves_fields

    {:ok, _} = Catalogue.update_play(play, %{show_variants: false})

    assert {:ok, preview} = TeiImport.preview_import(path)
    assert :show_variants in preview.preserves_fields
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs`
Expected: FAIL: the form has no `show_variants` field (`form/3` raises), the preview test fails on `update_play` (nothing to cast) or on the first `refute`.

- [ ] **Step 3: The column, off for EMOTHE0010**

Create `priv/repo/migrations/20261016130000_add_show_variants_to_plays.exs`:

```elixir
defmodule Playcode.Repo.Migrations.AddShowVariantsToPlays do
  @moduledoc """
  "Show variant readings": whether readers see a play's textual variants. Hamlet's
  apparatus is unfinished (question 2 of docs/stakeholder/preguntas.html), so its are
  hidden until its editor has finished. The TEI import never writes it, and the file never
  carries it.
  """
  use Ecto.Migration

  def up do
    alter table(:plays) do
      add :show_variants, :boolean, null: false, default: true
    end

    execute "UPDATE plays SET show_variants = false WHERE code = 'EMOTHE0010' OR code LIKE 'EMOTHE0010\\_%'"
  end

  def down do
    alter table(:plays) do
      remove :show_variants
    end
  end
end
```

Run: `mix ecto.migrate`, then check dev:

```bash
PGPASSWORD=postgres psql -h localhost -U postgres -d playcode_dev -Atc "select code, show_variants from plays where code like 'EMOTHE0010%'"
```

Expected: `EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark|f`.

- [ ] **Step 4: The field, the form, the import, the loader**

`lib/playcode/catalogue/play.ex`: `field :show_variants, :boolean, default: true` beside `is_complete`; `:show_variants` in `changeset/2`'s cast list after `:is_complete`; in the moduledoc, after the sentence on `is_complete`: "`show_variants` decides whether readers see the play's textual variants; like `is_complete` it is Playcode's, never written to or read from the TEI file."

`lib/playcode/import/tei_import.ex`: add `:show_variants` to `@platform_owned`, and replace `preserved_fields/1`'s filter:

```elixir
  # The platform-owned columns a curator has set: those that differ from a new play's.
  defp preserved_fields(%Play{} = play) do
    Enum.filter(@platform_owned, &(Map.get(play, &1) != Map.get(%Play{}, &1)))
  end
```

(`language` defaults to "es": a Spanish play's language is no longer listed as kept, which is what the list is for; the existing preview test sets "en".)

`lib/playcode/play_content.ex`:

```elixir
  def load_play_content(play_id, opts \\ []) do
    # … unchanged …
    divisions
    |> attach_elements(elements_by_division)
    |> without_variants(Keyword.get(opts, :variants, true))
    |> number_notes()
    |> name_witnesses(play_id)
  end

  # A play whose readers do not see its variants (Play.show_variants).
  defp without_variants(divisions, true), do: divisions

  defp without_variants(divisions, false),
    do: update_notes(divisions, &Enum.reject(&1, fn note -> Note.variant?(note) end))
```

and its doc gains: "`variants: false` leaves the variants out, as readers of a play whose `show_variants` is off see it."

`lib/playcode_web/live/admin/play_form_live.ex`, after the `is_complete` checkbox:

```heex
              <.input
                field={@form[:show_variants]}
                type="checkbox"
                label={gettext("Show variant readings")}
              />
```

`lib/playcode_web/live/play_show_live.ex`: `PlayContent.load_play_content(play.id, variants: play.show_variants)`.

`lib/playcode_web/live/play_comparison.ex`, `build_panel/1`: `divisions: PlayContent.load_play_content(play.id, variants: play.show_variants)`.

Gettext: `mix gettext.extract --merge`; "Show variant readings" → "Mostrar las variantes textuales".

- [ ] **Step 5: Run the tests and watch them pass**

Run: `mix test test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs`
Expected: PASS.

- [ ] **Step 6: Refactor while green**

Read the play form's surroundings: the checkbox sits with "Complete", both switches for what visitors see. Run Step 5 again, then:

Run: `mix test`
Expected: PASS.

Prove the tests bite: drop `:show_variants` from `@platform_owned` and from the cast list one at a time (the re-import or the save stops holding); make `without_variants/2`'s false clause return `divisions` (the page shows the asterisk). Put each back.

- [ ] **Step 7: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add priv/repo/migrations/20261016130000_add_show_variants_to_plays.exs lib/playcode/catalogue/play.ex lib/playcode/import/tei_import.ex lib/playcode/play_content.ex lib/playcode_web/live/admin/play_form_live.ex lib/playcode_web/live/play_show_live.ex lib/playcode_web/live/play_comparison.ex priv/gettext test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs
git commit -m "feat(play): Show variant readings, a play's switch, off for Hamlet

Readers of a play with it off see none of its variants; the file and the admin keep
them, and a re-import keeps the setting. The preview reports a kept column when it
differs from a new play's. Proved: each half undone turns its test red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The published site shows variants, with a "Variants" switch

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex` (load option, `:variants` field, `notes/4`)
- Modify: `lib/playcode/export/static_site/components.ex` (`play_rail/1`, `part/1`, `endnotes/1`)
- Modify: `lib/playcode/export/static_site/fingerprint.ex` (`@modules`)
- Modify: `priv/static_site/style.css`, `priv/static_site/site.js`
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: Task 3's `NoteMarkup.readings/2`, numbering and `sigla`; Task 4's `show_variants` and `load_play_content/2`.
- Produces: `Edition.variants` (true when the play's loaded divisions hold a variant); site marker `<button class="vref" popovertarget="var-N" aria-label="Textual variant N">*</button>`, pop-up `<li id="var-N" popover>`; `body[data-va="off"]` hides `.vref`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/static_site_play_test.exs`:

```elixir
  describe "textual variants" do
    @variant """
    <div1 type="jornada" n="1"><head>Jornada I</head>
      <sp><speaker>FENISA</speaker>
        <l n="72">mucho la hermosura llama<app n="908"><lem wit="#H">llama</lem><rdg wit="#P3">falta</rdg><note>Por la rima.</note></app>,<note n="1" type="editor"><p>Glosa.</p></note></l>
      </sp>
    </div1>
    """

    defp opened_by(page, label),
      do: page |> LazyHTML.query(~s(button[aria-label="#{label}"])) |> LazyHTML.attribute("popovertarget")

    defp variant_play! do
      play = import_tei!(tei(body: @variant))

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "siglum" => "H",
        "monogr_editors" => "Hartzenbusch, J. E.",
        "year_text" => "1860"
      })

      play
    end

    test "an asterisk opens the readings; the Notes page leaves them out" do
      play = variant_play!()
      dir = generate!([play], all: true)
      act = page(dir, play, "act-1.html")

      assert squish(LazyHTML.text(LazyHTML.query(act, "main"))) =~ "mucho la hermosura llama*,1"
      assert opened_by(act, "Textual variant 1") == ["var-1"]
      assert opened_by(act, "Editor's note 1") == ["note-1"]

      assert act |> LazyHTML.query("#var-1 p") |> Enum.map(&squish(LazyHTML.text(&1))) == [
               "H (Hartzenbusch, 1860) llama",
               "P3 falta",
               "Por la rima."
             ]

      assert act |> LazyHTML.query(~s(input[data-toggle="va"])) |> Enum.count() == 1
      refute squish(LazyHTML.text(page(dir, play, "notes.html"))) =~ "falta"
    end

    test "a play whose variants readers do not see has no asterisk and no switch" do
      play = variant_play!()
      {:ok, play} = Playcode.Catalogue.update_play(play, %{show_variants: false})
      act = page(generate!([play], all: true), play, "act-1.html")

      assert opened_by(act, "Textual variant 1") == []
      assert act |> LazyHTML.query(~s(input[data-toggle="va"])) |> Enum.count() == 0
      assert opened_by(act, "Editor's note 1") == ["note-1"]
    end
  end
```

(If the act's page of a one-act play is not `act-1.html`, use the name `@two_acts`'s tests use; `squish/1` comes from `Playcode.StaticSiteHelpers`.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/export/static_site_play_test.exs --only describe:"textual variants"`
Expected: FAIL: the variant is a numbered note ("Textual variant 1" opens nothing; the note is 2), no `va` switch.

- [ ] **Step 3: The edition, the marker, the pop-ups, the switch**

`lib/playcode/export/static_site/edition.ex`: add `:variants` to the struct's fields; in `load/1`:

```elixir
    divisions = PlayContent.load_play_content(id, variants: play.show_variants)
    # …
      variants: divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1),
```

and in `notes/4` the comprehension leaves variants out (the Notes page and the search index read it):

```elixir
    for %{note: note, anchor: anchor} = at <- Note.with_anchors(divisions),
        not Note.variant?(note),
        slug when not is_nil(slug) <- [slug_of[note.id]] do
```

with a line in its comment: "Variants are not listed: they are the apparatus, opened from the text."

`lib/playcode/export/static_site/components.ex` (alias `Playcode.Export.NoteMarkup`):

1. In `play_rail/1`, after "Verse forms":

```heex
      <label :if={@edition.variants}><input type="checkbox" data-toggle="va" checked /> Variants</label>
```

2. Replace the note clause of `part/1`:

```elixir
  # A note's marker: its number, a button that opens the note (endnotes/1) as a popover.
  # Its id is what a search result and the Notes page link to. A variant's is an asterisk,
  # which the "Variants" toggle hides.
  defp part(%{note: note}), do: if(Note.variant?(note), do: variant_ref(note), else: note_ref(note))

  defp note_ref(note) do
    # the existing body of the note clause, unchanged
  end

  defp variant_ref(note) do
    number = Integer.to_string(note.number)

    [
      ~s(<button type="button" class="vref" popovertarget="var-),
      number,
      ~s(" aria-label="),
      escape("#{PlayLabels.note_type_label(note.type)} #{number}"),
      ~s(">*</button>)
    ]
  end
```

3. `endnotes/1` splits them, the notes' section unchanged:

```elixir
  def endnotes(assigns) do
    {variants, notes} = Enum.split_with(assigns.notes, &Note.variant?/1)
    assigns = assign(assigns, notes: notes, variants: variants)

    ~H"""
    <section :if={@notes != []} class="notes" role="doc-endnotes" aria-label="Notes">
      <%!-- unchanged <ol> of notes --%>
    </section>
    <section :if={@variants != []} class="notes" aria-label="Textual variants">
      <ul>
        <li :for={variant <- @variants} id={"var-#{variant.number}"} popover>
          <button
            type="button"
            popovertarget={"var-#{variant.number}"}
            popovertargetaction="hide"
            aria-label="Close"
          >
            ×
          </button>
          <b>{PlayLabels.note_type_label(variant.type)}</b>
          {Phoenix.HTML.raw(NoteMarkup.readings(variant, :html))}
        </li>
      </ul>
    </section>
    """
  end
```

and its doc: "…in a browser without popover, they are the page's endnotes, its variants after them."

`lib/playcode/export/static_site/fingerprint.ex`: add `Playcode.Export.NoteMarkup` and `Playcode.PlayContent.Note.Reading` to `@modules` (the site now prints through the first, and the second's `sigla/1` decides what it prints; `fingerprint_test.exs` fails without the first).

`priv/static_site/style.css`: `.nref {` becomes `.nref, .vref {`; `.notes ol {` becomes `.notes ol, .notes ul {`; after `body[data-vf="off"] .l .vf { display: none; }` add `body[data-va="off"] .vref { display: none; }`; in the print block `.nref { color: inherit; }` becomes `.nref, .vref { color: inherit; }`.

`priv/static_site/site.js`, `initTools`: `['ln', 'sd', 'vf', 'va'].forEach(…)`. (If `test/js/` covers `initTools`' remembered keys, add `va` there.)

- [ ] **Step 4: Run the tests and watch them pass**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_test.exs test/playcode/export/fingerprint_test.exs`
Expected: PASS, the size budgets included.

Run: `node --test test/js/*.test.mjs`
Expected: PASS.

- [ ] **Step 5: Refactor while green**

`Components.part/1` and `PlayText.part_html/2` now hold the same dispatch; they stay apart, as their markers already did (ids by number on the site, by id on the page). Run Step 4 again, then:

Run: `mix test`
Expected: PASS.

Prove the tests bite: drop `not Note.variant?(note),` from `notes/4` ("falta" appears on the Notes page); take `variants:` out of `Edition.load/1` (the hidden play gets its asterisk). Put each back.

- [ ] **Step 6: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/static_site priv/static_site test/playcode/export/static_site_play_test.exs
git commit -m "feat(site): textual variants are asterisks opening their readings, with a Variants switch

The Notes page and the search leave them out; a play whose variants are hidden gets
neither asterisks nor switch. Proved: without the filter the Notes page lists them.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The downloads mark each variant and list them after each act's notes

**Files:**
- Modify: `lib/playcode/export/note_markup.ex` (`part/2`, `endnotes/2`)
- Modify: `lib/playcode/export/html.ex` (load option, CSS)
- Modify: `lib/playcode/export/epub.ex` (load option)
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: Task 3's `NoteMarkup.readings/2` and numbering; Task 4's `load_play_content/2`.
- Produces: in the HTML, `<sup class="vref"><a id="vref-N" href="#var-N">*</a></sup>` and, after an act's notes, `<section class="variants"><h3>Variants</h3><ul><li id="var-N">…</li></ul></section>`; in the EPUB, `<sup><a epub:type="noteref" href="#var-N">*</a></sup>` and `<aside epub:type="footnote" id="var-N">…</aside>`.

- [ ] **Step 1: Write the failing test**

In `test/playcode_web/controllers/export_controller_test.exs`:

```elixir
  # As the play page prints them: an asterisk in the line, the readings after the act's
  # notes; nothing for a play whose variants readers do not see.
  test "the HTML and EPUB downloads mark each variant and list it after the act's notes",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso<app n="1"><lem wit="#A">Verso</lem><rdg wit="#B">Canto</rdg></app> de prueba<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    doc = LazyHTML.from_document(html)

    assert doc |> LazyHTML.query(~s(a[href="#var-1"])) |> LazyHTML.text() == "*"
    assert doc |> LazyHTML.query("#var-1 p") |> Enum.map(&LazyHTML.text/1) == ["A Verso", "B Canto"]
    assert html =~ ~r{id="note-1".*id="var-1"}s

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    assert epub =~ ~s(<a epub:type="noteref" href="#var-1">*</a>)

    assert epub =~
             ~s(<aside epub:type="footnote" id="var-1"><p><i>A</i> Verso</p><p><i>B</i> Canto</p></aside>)

    {:ok, _} = Playcode.Catalogue.update_play(play, %{show_variants: false})
    refute response(get(conn, ~p"/export/#{play.id}/html"), 200) =~ "var-1"
  end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs`
Expected: FAIL: the variant is note 1 (`href="#note-1"` on "1"), there is no `#var-1`.

- [ ] **Step 3: The marker and the list**

`lib/playcode/export/note_markup.ex`, the moduledoc: "…each in-text note as a reference to its endnote and each variant as an asterisk to its entry, and an act's notes as endnotes, its variants after them." Replace the two note clauses of `part/2`:

```elixir
  defp part(%{note: note}, format), do: ref(note, Note.variant?(note), format)

  defp ref(%{number: n}, false, :html),
    do: ~s(<sup class="nref"><a id="ref-#{n}" href="#note-#{n}">#{n}</a></sup>)

  defp ref(%{number: n}, false, :epub),
    do: ~s(<sup><a epub:type="noteref" href="#note-#{n}">#{n}</a></sup>)

  defp ref(%{number: n}, true, :html),
    do: ~s(<sup class="vref"><a id="vref-#{n}" href="#var-#{n}" aria-label="Textual variant #{n}">*</a></sup>)

  defp ref(%{number: n}, true, :epub),
    do: ~s(<sup><a epub:type="noteref" href="#var-#{n}">*</a></sup>)
```

Rename the three `endnotes/2` clauses to a private `numbered/2`, and make `endnotes/2`:

```elixir
  @doc """
  An act's `notes` as endnotes, its variants (`Note.variant?/1`) after them: for `:html` an
  `<ol>` section and a "Variants" list, for `:epub` footnote asides.
  """
  def endnotes(notes, format) do
    {variants, notes} = Enum.split_with(notes, &Note.variant?/1)
    numbered(notes, format) <> variants(variants, format)
  end
```

and after `numbered/2`:

```elixir
  defp variants([], _format), do: ""

  defp variants(variants, :html) do
    items =
      Enum.map_join(variants, "\n", fn variant ->
        ~s(<li id="var-#{variant.number}">#{readings(variant, :html)}) <>
          ~s( <a href="#vref-#{variant.number}" aria-label="Back to the text">↩</a></li>)
      end)

    ~s(<section class="variants"><h3>Variants</h3><ul>\n#{items}\n</ul></section>\n)
  end

  defp variants(variants, :epub) do
    Enum.map_join(variants, "", fn variant ->
      ~s(<aside epub:type="footnote" id="var-#{variant.number}">#{readings(variant, :epub)}</aside>\n)
    end)
  end
```

`lib/playcode/export/html.ex`: `PlayContent.load_play_content(play.id, variants: play.show_variants)`; in the CSS, `.notes { … }` and `.notes li p { … }` become `.notes, .variants { … }` and `.notes li p, .variants li p { … }`.

`lib/playcode/export/epub.ex`: `PlayContent.load_play_content(play.id, variants: play.show_variants)`.

- [ ] **Step 4: Run it and watch it pass**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs test/playcode_web/controllers/pdf_download_test.exs`
Expected: PASS.

- [ ] **Step 5: Refactor while green**

`numbered/2` and `variants/2` share their shape per format; leave them two, each one screen. Run Step 4 again, then:

Run: `mix test`
Expected: PASS.

Prove the test bites: make `endnotes/2` return `numbered(notes ++ variants, format)` (no `#var-1`). Put it back.

- [ ] **Step 6: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/note_markup.ex lib/playcode/export/html.ex lib/playcode/export/epub.ex test/playcode_web/controllers/export_controller_test.exs
git commit -m "feat(export): the downloads mark each variant and list them after each act's notes

HTML, PDF and EPUB; none for a play whose variants readers do not see. Proved: with
variants listed as notes the test goes red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Variants are added, edited and removed in the editor

**Files:**
- Modify: `lib/playcode/play_content/note.ex` (new `summary/1`)
- Modify: `lib/playcode_web/live/admin/notes_component.ex` (Add variant, the variant's form, `readings_fields/1`, the list)
- Modify: `lib/playcode_web/live/admin/play_notes_live.ex` (the variant's form, its row, the filter)
- Modify: `lib/playcode_web/play_labels.ex` (`note_type_key/1`)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`, `test/playcode_web/live/admin/play_notes_live_test.exs`, `test/playcode_web/accessibility_test.exs`

**Interfaces:**
- Consumes: Task 1's `Note.variant/0`, `Note.variant?/1`, `Note.Reading`, the changeset's `readings_order`/`readings_delete`.
- Produces: `Note.summary(note)` → string; `NotesComponent.readings_fields(form: form)` function component.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/play_content_editor_live_test.exs`, in `describe "the note editor"`:

```elixir
    test "a variant is added to a verse with its readings, changed and deleted",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add variant")) |> render_click()

      # A variant has no type to choose: it stays a variant.
      refute has_element?(lv, "#note-form label", t("Type"))

      # "Add reading": a second row.
      lv |> form("#note-form") |> render_change(%{note: %{"readings_order" => ["0", "new"]}})

      lv
      |> form("#note-form",
        note: %{
          "offset" => "7",
          "readings" => %{
            "0" => %{"lemma" => "true", "wit" => "#H", "text" => "Segunda", "note" => "Corrección."},
            "1" => %{"wit" => "#P3", "text" => "Primera"}
          }
        }
      )
      |> render_submit()

      assert [
               %{
                 in: "l",
                 after: "Segunda",
                 readings: [
                   {"lem", "#H", "Segunda", "Corrección."},
                   {"rdg", "#P3", "Primera", nil}
                 ],
                 note: nil
               }
             ] = xml_apps(export_tei(play))

      assert xml_notes(export_tei(play)) == []

      # Review focus 2: with no note of its own, its row in the list shows its readings.
      assert render(lv) =~ "#H Segunda · #P3 Primera"

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form") |> render_change(%{note: %{"readings_delete" => ["1"]}})
      lv |> form("#note-form", note: %{"body" => "Comentario."}) |> render_submit()

      assert [%{readings: [{"lem", "#H", "Segunda", "Corrección."}], note: "Comentario."}] =
               xml_apps(export_tei(play))

      lv |> element("#{notes_section()} button", t("Delete")) |> render_click()
      assert xml_apps(export_tei(play)) == []
    end
```

In the same file's `describe "notes when their text is edited"`:

```elixir
    # Review focus 3: the offsets are carried for every play_notes row; this pins it.
    test "a line's variant follows its word through an edit, as a note does", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Buscad<app n="1"><rdg wit="#B">Mirad</rdg></app> por todas partes</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      lv = open_scene(conn, play)
      lv |> element("span[title='Buscad por todas partes']") |> render_click()

      lv
      |> element("form[id^='inline-edit-']")
      |> render_submit(%{"value" => "Ya buscad por todas partes"})

      assert [%{after: "Ya buscad"}] = xml_apps(export_tei(play))
    end
```

In `test/playcode_web/live/admin/play_notes_live_test.exs`:

```elixir
  # Review focus 2: a variant may have no note of its own.
  test "a variant is listed as a textual variant, filtered by, and edited with its readings",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>ANA</speaker><l n="1">mucho la hermosura llama<app type="substantive" n="908"><lem wit="#H">llama</lem><rdg wit="#P3">falta</rdg></app>, y<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
      )

    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture(role: :researcher))
      |> live(~p"/admin/plays/#{play.id}/notes")

    [variant, _note] = notes(play)

    view |> form("#notes-filter", filter: %{type: "variante"}) |> render_change()
    assert rows(view) == [row(variant)]
    assert texts(view, "##{row(variant)} .note-type") == [t("Textual variant")]
    assert texts(view, "##{row(variant)} .note-context") == ["mucho la hermosura llama*, y"]
    assert texts(view, "##{row(variant)} .note-body p") == ["#H llama · #P3 falta"]

    view |> element("##{row(variant)} button", t("Edit")) |> render_click()

    view
    |> form("#note-form",
      note: %{"readings" => %{"1" => %{"text" => "infama"}}, "body" => "Por la rima."}
    )
    |> render_submit()

    assert [
             %{
               n: "908",
               type: "substantive",
               readings: [{"lem", "#H", "llama", nil}, {"rdg", "#P3", "infama", nil}],
               note: "Por la rima."
             }
           ] = xml_apps(export_tei(play))
  end
```

In `test/playcode_web/accessibility_test.exs`, the clicks list gains:

```elixir
          {content, scene ++ [edit.(s.verse_line), {"button", t("Add variant")}]},
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/live/admin/play_notes_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: FAIL: no "Add variant" button; the Notes tab lists the variant as "Note" (filter key "other"), its context shows "1", its body is empty. "follows its word" passes already: Step 5 proves it bites.

- [ ] **Step 3: The summary, the filter key**

`lib/playcode/play_content/note.ex`, after `name_witnesses/2`:

```elixir
  @doc """
  A note's text, or a variant's readings, each its witnesses and text ("#H llama · #P3
  falta"), then its own note: what the admin's lists show of it.
  """
  def summary(%__MODULE__{} = note) do
    readings =
      Enum.map(note.readings, fn reading ->
        [reading.wit, reading.text] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
      end)

    (readings ++ List.wrap(note.body)) |> Enum.join(" · ")
  end
```

`lib/playcode_web/play_labels.ex`, before `note_type_key/1`'s clause:

```elixir
  def note_type_key("variante"), do: "variante"
```

and its doc gains: "A variant is a key of its own."

- [ ] **Step 4: The content editor's variant form**

`lib/playcode_web/live/admin/notes_component.ex` (add `alias Phoenix.LiveView.JS` and `alias Playcode.PlayContent.Note.Reading`; the moduledoc: "…a form to add a note or a variant, or change one."):

1. Events:

```elixir
  def handle_event("new_variant", _params, socket) do
    note = %Note{
      type: Note.variant(),
      offset: default_offset(socket.assigns.anchor),
      readings: [%Reading{lemma: true}]
    }

    {:noreply, assign(socket, editing: note, form: to_form(PlayContent.change_note(note)))}
  end

  # A reading added or removed, or a field typed in: the form shows the rows as they stand.
  def handle_event("change_note", %{"note" => params}, %{assigns: %{editing: %Note{}}} = socket) do
    %{editing: note} = socket.assigns
    {:noreply, assign(socket, :form, to_form(PlayContent.change_note(note, note_params(note, params))))}
  end

  def handle_event("change_note", _params, socket), do: {:noreply, socket}
```

2. In `save_note`, `params = Map.take(params, ~w(offset type term body))` becomes `params = note_params(note, params)`, and add:

```elixir
  # What a form may change: a variant's place, readings and note, never its type; a note's
  # type, place, term and text. A variant stays a variant and a note a note. The Notes tab
  # saves through it too.
  @doc false
  def note_params(note, params) do
    if Note.variant?(note),
      do:
        params
        |> Map.take(~w(offset body readings readings_order readings_delete))
        |> Map.put("type", note.type),
      else: Map.take(params, ~w(offset type term body))
  end
```

3. The list's text: `{String.slice(note.body, 0, 80)}` becomes `{String.slice(Note.summary(note), 0, 80)}`.

4. Beside "Add note":

```heex
      <button
        :if={is_nil(@form)}
        type="button"
        phx-click="new_variant"
        phx-target={@myself}
        class="btn btn-sm"
      >
        {gettext("Add variant")}
      </button>
```

5. The form: add `phx-change="change_note"` to `<.form … id="note-form">`; `:if={not Note.variant?(@editing)}` on the type select and the term input; after the offset select `<.readings_fields :if={Note.variant?(@editing)} form={@form} />`; the body textarea's label `label={if Note.variant?(@editing), do: gettext("Comment on the entry"), else: gettext("Text")}`.

6. The fields, public so the Notes tab uses them too:

```elixir
  attr :form, Phoenix.HTML.Form, required: true

  @doc "A variant's readings in a note form, to add to, change or remove."
  def readings_fields(assigns) do
    ~H"""
    <fieldset>
      <legend class="label-text font-medium">{gettext("Readings")}</legend>
      <.inputs_for :let={reading} field={@form[:readings]}>
        <input type="hidden" name={"#{@form.name}[readings_order][]"} value={reading.index} />
        <div class="mb-2 flex flex-wrap items-end gap-2">
          <div class="w-32"><.input field={reading[:wit]} type="text" label={gettext("Witnesses")} /></div>
          <div class="grow"><.input field={reading[:text]} type="text" label={gettext("Reading")} /></div>
          <div class="grow"><.input field={reading[:note]} type="text" label={gettext("Comment")} /></div>
          <div class="text-xs">
            <.input field={reading[:lemma]} type="checkbox" label={gettext("Edition's reading")} />
          </div>
          <button
            type="button"
            name={"#{@form.name}[readings_delete][]"}
            value={reading.index}
            phx-click={JS.dispatch("change")}
            class="btn btn-ghost btn-xs text-error"
          >
            {gettext("Remove")}
          </button>
        </div>
      </.inputs_for>
      <input type="hidden" name={"#{@form.name}[readings_delete][]"} />
      <button
        type="button"
        name={"#{@form.name}[readings_order][]"}
        value="new"
        phx-click={JS.dispatch("change")}
        class="btn btn-ghost btn-xs"
      >
        {gettext("Add reading")}
      </button>
    </fieldset>
    """
  end
```

- [ ] **Step 5: The Notes tab**

`lib/playcode_web/live/admin/play_notes_live.ex`:

1. `save`: `Map.take(params, ~w(offset type term body))` becomes `NotesComponent.note_params(note, params)`.

2. A change event for the readings' rows:

```elixir
  def handle_event("change", %{"note" => params}, %{assigns: %{editing: %Note{} = note}} = socket),
    do: {:noreply, assign(socket, :form, to_form(PlayContent.change_note(note, NotesComponent.note_params(note, params))))}

  def handle_event("change", _params, socket), do: {:noreply, socket}
```

and `phx-change="change"` on its `#note-form`.

3. In the form: `:if={not Note.variant?(@editing)}` on the type select and the term input; `<NotesComponent.readings_fields :if={Note.variant?(@editing)} form={@form} />` after the grid; the textarea's label as in the component.

4. The row: the context's `<sup>` prints `{if Note.variant?(entry.note), do: "*", else: entry.note.number}`; the body shows the summary for a variant:

```heex
              <p :for={paragraph <- shown_paragraphs(entry.note)}><.marked text={paragraph} /></p>
```

with

```elixir
  # A note's paragraphs; a variant's readings and note, on one line.
  defp shown_paragraphs(note),
    do: if(Note.variant?(note), do: [Note.summary(note)], else: Note.paragraphs(note))
```

5. `shown/2`'s text search reads `Note.summary(note)` instead of `note.body`: `Bibliography.fold("#{Note.summary(note)} #{note.term}")`.

Gettext: `mix gettext.extract --merge`; "Add variant" → "Añadir variante", "Readings" → "Lecturas", "Witnesses" → "Testimonios" (likely there already), "Reading" → "Lectura", "Comment" → "Comentario", "Edition's reading" → "Lectura de la edición", "Add reading" → "Añadir lectura", "Remove" → "Quitar" (likely there already), "Comment on the entry" → "Comentario de la variante". Check the fuzzy entries.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/live/admin/play_notes_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS.

Prove "follows its word" bites: in `PlayContent.update_element/2`, skip carrying the notes' offsets (return the update without the notes step); the test goes red ("Buscad" instead of "Ya buscad"). Put it back.

- [ ] **Step 7: Refactor while green**

The two forms now share `readings_fields/1` and `note_params/2`; check neither LiveView still takes params by hand. Run Step 6 again, then:

Run: `mix test`
Expected: PASS.

Prove the rest bites: drop `|> Map.put("type", note.type)` from `note_params/2` (a new variant saves as a note with no text and is refused); take the `"variante"` clause out of `note_type_key/1` (the filter finds nothing); put `note.body` back in the component's list (opening the line crashes on a variant with no note). Put each back.

- [ ] **Step 8: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/play_content/note.ex lib/playcode_web/live/admin/notes_component.ex lib/playcode_web/live/admin/play_notes_live.ex lib/playcode_web/play_labels.ex priv/gettext test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/live/admin/play_notes_live_test.exs test/playcode_web/accessibility_test.exs
git commit -m "feat(editor): a variant is added, edited and removed with its readings

In the content editor's notes and on the Notes tab, which lists and filters it as a
textual variant. Proved: each rule undone turns its test red; the offsets one by
skipping their carrying in update_element/2.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Docs, and the merge

**Files:**
- Modify: `CLAUDE.md` (TEI-XML Format; Database Schema: `play_notes`, `plays`; *Archiving and provenance*: `@platform_owned`; *The TEI file is a complete copy of a play*: the columns kept out of the file)
- Modify: `docs/stakeholder/ida-y-vuelta.html` (row "Variant readings (critical apparatus)")
- Modify: `docs/stakeholder/preguntas.html` (questions 1-4: built)
- Modify: `docs/backlog.md`, `docs/history.md`
- Modify: `docs/superpowers/specs/2026-10-16-critical-apparatus-design.md` (status)

- [ ] **Step 1: Ask the owner about the kept-out column**

`CLAUDE.md` says `is_complete` is "the one curated column kept out of the file on purpose". `show_variants` is a second. Ask the owner to agree before writing Step 2's last bullet; if they want it in the file instead, stop and plan that change.

- [ ] **Step 2: `CLAUDE.md`**

In *TEI-XML Format*, after the `note` in the play text line, add:

```
- `app` in the play text -> a variant, a `play_notes` row of type `variante` at its offset, as a `note` is (`n`; `variant_type` its `type`, `range_end` its `to`, both as written; `readings` its `lem` and `rdg`s, each with `wit` as written, its text and its own `note`; `body` its own note or nil); written back where it was. Inside a note an `app` reads as nothing, the note keeping the line's words, unless no entry of its element has its `n` (EMOTHE0530 `n="496"`): then it moves into the line, after the note. Readers see an asterisk opening the readings, each siglum followed by what it names (`Witnesses.short_names/1`), unless the play's `show_variants` is off
```

In *Database Schema*, extend the `play_notes` bullet: "…A variant of the critical apparatus is a row of type `variante` (`Note.variant?/1`) with `variant_type`, `range_end` and `readings` (JSONB, `Note.Reading`); its `body` may be nil. Variants are numbered apart from notes." Add to the `plays` bullet: "`show_variants` (\"Show variant readings\") hides a play's variants from readers, off for EMOTHE0010".

In *Archiving and provenance*, add `show_variants` to the list of columns a re-import does not write.

In *The TEI file is a complete copy of a play*, once the owner agrees: "**Whether a play is complete, and whether readers see its variants (`show_variants`), are the curated columns kept out of the file on purpose**: Playcode's switches for what visitors see, not part of the edition…"

- [ ] **Step 3: The round-trip page and the questions**

In `docs/stakeholder/ida-y-vuelta.html`, move the row "Variant readings (critical apparatus)" out of "In the source TEI files, not read yet" into the group above it, every cell `<span class="s yes">Yes</span>`, its "where" reworded: "In 6 plays, 542 entries, shown as on the old site, each witness named; hidden for Hamlet until its editor has finished · questions 1–4". Add a sentence to the page's "Updated" paragraph, and take "the variant readings" out of the note at the end that lists the projects still to do.

On `docs/stakeholder/preguntas.html`, add to the answered box of questions 1 to 4: "Built on 16 October 2026; readers see it once the six plays are re-imported."

- [ ] **Step 4: Backlog, history, spec**

Move the backlog item "`<app>` (critical apparatus) is pasted into the line" to `docs/history.md` as `[x]`, with what was built, the commits, the tests and the spec's *Out of scope*. Set the spec's status line to "implemented, 2026-10-16 (commits …)".

- [ ] **Step 5: Full checks, then merge**

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
node --test test/js/*.test.mjs
mix test --include slow
```

Expected: all green; the slow sweep's counts unchanged (no fixture holds an `<app>`), and `apparatus_corpus_test.exs` green on all six plays.

```bash
git add CLAUDE.md docs
git commit -m "docs: the critical apparatus is read, shown, edited and written back

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git checkout main
git merge --no-ff critical-apparatus -m "Merge branch 'critical-apparatus': textual variants read, shown, edited and written back

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Push only with the owner's go-ahead and no production run or site build going.

---

## Rollout (after the merge, each step with the owner's go-ahead)

1. Push `main`; wait for CI and the deploy (`gh run list --limit 3`). The migrations run on deploy: Hamlet's `show_variants` goes off. Nothing else changes until the six plays are re-imported.
2. Dev: `mix playcode.import.tei --force` (or the six files alone), then check: `select count(*) from play_notes where type = 'variante'` is 542, and EMOTHE0560's v. 72 reads "mucho la hermosura llama,".
3. Production: re-import the six plays (EMOTHE0010, 0187, 0435, 0460, 0530, 0560) from `doc/tei_corpus/` the way `docs/production-reimport.md` describes; stop on any "edited since their import" or "undoes N hand edit(s)" line and look at it with the project. Their note numbers go down: the readings' notes are no longer counted.
4. Check on production: EMOTHE0560 shows its asterisks and names "H (Hartzenbusch, 1860)"; EMOTHE0010 shows none.
5. Generate from `/admin/export` with the page open; the six plays rebuild. The owner checks the preview and Deploys.
6. Republish the Round Trip and Questions artifacts (`stakeholder-artifacts-account` memory).
