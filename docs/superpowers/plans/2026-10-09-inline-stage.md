# Inline Stage Directions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `<stage>` inside a verse line or a prose paragraph stops being read as plain words of the line: it is kept as a marker in the line's text, written back as `<stage>` by the TEI export, shown in italics (hidden by the "Stage directions" toggle) on the static site, `/plays/:code` and the downloads, counted in statistics and search, and edited as text in the content editor.

**Architecture:** The line's `content` holds `<stage type="…">…</stage>` next to the existing `<<italics>>` markers. `InlineMarkup.parts/1` gives each part a `stage` (`nil`, or `%{type, run}`), and `plain/1` drops the tags, so note offsets and search text do not move. Every renderer already walks `InlineMarkup.parts`, so each gets one more clause. No table, no migration.

**Tech Stack:** Elixir 1.19.5 / OTP 28, Phoenix 1.8.3, LiveView 1.1.22, Saxy, XmlBuilder 2.4, LazyHTML in tests.

**Spec:** `docs/superpowers/specs/2026-10-09-inline-stage-design.md`

## Global Constraints

- Run mix plainly: `mix test`, `mix compile`. Never prefix `export PATH=…`.
- Test-driven, red → green → refactor, every task: write the test, run it and watch it fail for the right reason, write the least code that passes, run it green, then refactor while green. For each test added to prove a behaviour, break the line it covers, watch it go red, put it back, and say so in the commit message.
- Before any claim that something works: `mix test` (the whole suite) green, with the output.
- After every task: `mix format`, then `mix compile --warnings-as-errors`, then commit. Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Test through the outermost API (`CLAUDE.md`, *How To Work In This Repo*): TEI import/export as round trips through `ImportHelpers`, LiveViews with `live/2`, controllers with `get`. Read back through context functions, never `Repo`. `InlineMarkup` is a pure module whose note placement is intricate: it gets a direct unit test, with a comment saying so.
- An existing test that contradicts the deliberate change (a stage's words are no longer plain text of the line) is updated with a comment saying why. Check every failure before changing anything.
- The marker, verbatim from the spec: `<stage>…</stage>`, or `<stage type="delivery">…</stage>`; the type is a run of letters, digits and `_`, kept as written (`delivery_` stays); a stage is flat (no stage in a stage); italics may sit inside one; a stage inside italics is not allowed.
- `plain/1` drops the stage tags and keeps the stage's words. Note offsets count graphemes of that plain text.
- Aside lines and aside paragraphs are unchanged: they drop every stage they hold (`verse_line_content/2`, `aside_content/1`). Only `:mark` reading (the play text) keeps stages; the header and front matter still paste.
- Static site: no third-party requests, works opened as `file://`, `priv/static_site/site.js` untouched, `style.css` within its 25 KB budget (asserted in `static_site_test.exs`). The label "Stage directions" in the static site's toggle is English; the live page and the admin are Spanish through `priv/gettext/es/LC_MESSAGES/*.po`.
- After `mix gettext.extract --merge`, check every entry it marks fuzzy: `test/playcode_web/spanish_translations_test.exs` fails while any Spanish entry is fuzzy. A changeset message is a plain string that `gettext.extract` cannot see: add it by hand to `priv/gettext/errors.pot` and the `es` and `en` `errors.po` (`test/playcode_web/error_translations_test.exs` fails without the Spanish).
- Work in a git worktree off `main` (superpowers:using-git-worktrees). `main` is also being committed to from another session, and its working tree may hold someone else's uncommitted changes: never commit a file this plan does not name, and never `git add -A`. Merge `main` into the branch before the final review.
- Never run `mix playcode.import.tei --force` against the dev database without the project owner's explicit go-ahead.
- Never write `Emothe` as the application's name (`test/rename_guard_test.exs`).

## Review Focus

The inputs most likely to bite a reader or curator that no single feature test would naturally hit; each has its test in the task named.

- **Two stages touching** (`<stage>a</stage><stage>b</stage>`, typed in the editor; the importer always puts a space between): two stages on export, never one merged. Tasks 1 and 7.
- **A note at the very start or end of a stage:** at the start (offset before the stage) and at the end it sits outside, and the export → import → export round trip does not change it. Tasks 1 and 2.
- **`&` and `<` in a stage's text:** escaped in the TEI, the HTML and the EPUB's XHTML. Tasks 2 and 5.
- **Re-importing a file:** its stages are replaced, never doubled. Task 2.
- **A refused marker on Insert Above:** the later lines must not be renumbered by a save that then fails. Task 7.
- **A word both spoken and in a stage direction** in one line: one posting, flag 0 (spoken wins). Task 6.
- **Changing only a stage's type** in the editor leaves the line's notes where they were. Task 7.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/playcode/play_content/inline_markup.ex` | Stage parts in `parts/1` and `parts/2`, `well_formed?/1`, `stage_count/1`, `spoken/1`, `staged/1` |
| `lib/playcode/play_content/element.ex` | Refuses a malformed marker in `content`; moduledoc names the marker |
| `priv/gettext/errors.pot`, `priv/gettext/{es,en}/LC_MESSAGES/errors.po` | The refusal's message and its Spanish |
| `lib/playcode/import/tei_parser.ex` | A `<stage>` child of the play text read as a marker; `plain_length/1` counts its tags |
| `lib/playcode/export/tei_xml.ex` | `<stage>` written back around its run of parts |
| `lib/playcode/export/static_site/components.ex`, `priv/static_site/style.css` | `<span class="sdi">` and the rule the toggle uses |
| `lib/playcode_web/components/play_text.ex`, `assets/css/app.css` | The live page's stage spans and the toggle |
| `lib/playcode/export/note_markup.ex`, `html.ex`, `epub.ex`, `compare_html.ex` | `<span class="stage">` in the downloads; the comparison page through `NoteMarkup` |
| `lib/playcode/statistics.ex`, `lib/playcode/statistics/metrics.ex` | Inline stages counted; words spoken only |
| `lib/playcode/export/static_site/search.ex` | The stage flag per word |
| `lib/playcode_web/live/admin/play_content_editor_live.ex` | The syntax hint; validate before renumbering on insert |
| `priv/gettext/default.pot`, `priv/gettext/{es,en}/LC_MESSAGES/default.po` | The hint |
| `test/support/import_helpers.ex` | `xml_inline_stages/1` |
| `CLAUDE.md`, `docs/static-site-improvements.md`, the spec | The gap closed, the rollout and the limits |

---

### Task 1: The marker in `InlineMarkup`, and its validation

**Files:**
- Modify: `lib/playcode/play_content/inline_markup.ex`
- Modify: `lib/playcode/play_content/element.ex` (moduledoc, `changeset/2`)
- Modify: `priv/gettext/errors.pot`, `priv/gettext/es/LC_MESSAGES/errors.po`, `priv/gettext/en/LC_MESSAGES/errors.po`
- Create: `test/playcode/inline_markup_test.exs`
- Test: `test/playcode/play_content_test.exs`

**Interfaces:**
- Produces:
  - `InlineMarkup.parts(text) :: [%{text: binary, italic: boolean, stage: nil | %{type: binary | nil, run: non_neg_integer}}]`.
  - `InlineMarkup.parts(text, notes) :: [part | %{note: note, stage: nil | stage}]`: a note strictly inside a stage run, or between two parts of one run, carries that run's `stage`; a note at the start or end of a stage's text, or outside any stage, carries `nil`.
  - `InlineMarkup.plain(text) :: binary` (unchanged contract: the text without markers).
  - `InlineMarkup.well_formed?(text | nil) :: boolean`.
  - `InlineMarkup.stage_count(text | nil) :: non_neg_integer`.
  - `InlineMarkup.spoken(text | nil) :: binary` (the text outside every stage, a space where one was) and `InlineMarkup.staged(text | nil) :: binary` (the stages' text, joined by a space).
  - `Element.changeset/2` adds the error `{:content, "has a stage marker that is not well formed"}`.

- [ ] **Step 1: Write the failing tests**

Create `test/playcode/inline_markup_test.exs`:

```elixir
defmodule Playcode.PlayContent.InlineMarkupTest do
  # Text in, parts out: a unit test says it better than a round trip would. The round
  # trips in tei_roundtrip_test.exs prove the same pieces end to end.
  use ExUnit.Case, async: true

  alias Playcode.PlayContent.InlineMarkup

  defp at(offset, position \\ 0), do: %{offset: offset, position: position}

  describe "parts/1" do
    test "a stage is a part of its own, with its type and its run" do
      assert InlineMarkup.parts(~s(<stage type="exit">(Vase)</stage> Allez)) == [
               %{text: "(Vase)", italic: false, stage: %{type: "exit", run: 0}},
               %{text: " Allez", italic: false, stage: nil}
             ]
    end

    test "a stage with no type has a nil type" do
      assert [%{text: "(Vase)", stage: %{type: nil, run: 0}}] =
               InlineMarkup.parts("<stage>(Vase)</stage>")
    end

    test "touching stages are two runs; text between two stages belongs to neither" do
      assert [%{stage: %{run: 0}}, %{stage: %{run: 1}}] =
               InlineMarkup.parts("<stage>a</stage><stage>b</stage>")

      assert [%{stage: %{run: 0}}, %{stage: nil}, %{stage: %{run: 1}}] =
               InlineMarkup.parts("<stage>a</stage> y <stage>b</stage>")
    end

    test "italics inside a stage are italic parts of the same run" do
      assert InlineMarkup.parts("<stage>a <<b>> c</stage>") == [
               %{text: "a ", italic: false, stage: %{type: nil, run: 0}},
               %{text: "b", italic: true, stage: %{type: nil, run: 0}},
               %{text: " c", italic: false, stage: %{type: nil, run: 0}}
             ]
    end

    test "text with no marker has no stage" do
      assert InlineMarkup.parts("Dulce <<sueño>> mío") == [
               %{text: "Dulce ", italic: false, stage: nil},
               %{text: "sueño", italic: true, stage: nil},
               %{text: " mío", italic: false, stage: nil}
             ]
    end

    test "nil has no parts" do
      assert InlineMarkup.parts(nil) == []
    end
  end

  describe "plain/1, spoken/1, staged/1, stage_count/1" do
    @line ~s(Allez <stage type="exit">(Vase.)</stage> adieu, <stage>(bas)</stage> ami.)

    test "plain keeps a stage's words and drops its tags" do
      assert InlineMarkup.plain(@line) == "Allez (Vase.) adieu, (bas) ami."
    end

    test "spoken is the words outside every stage; staged is the stages' words" do
      assert @line |> InlineMarkup.spoken() |> String.split() == ["Allez", "adieu,", "ami."]
      assert InlineMarkup.staged(@line) == "(Vase.) (bas)"
    end

    test "stage_count counts the markers" do
      assert InlineMarkup.stage_count(@line) == 2
      assert InlineMarkup.stage_count("Dulce <<sueño>>") == 0
      assert InlineMarkup.stage_count(nil) == 0
    end

    test "nil is empty text" do
      assert {InlineMarkup.spoken(nil), InlineMarkup.staged(nil)} == {"", ""}
    end
  end

  describe "parts/2, where a note falls around a stage" do
    test "a note inside a stage splits it and goes inside" do
      assert [
               %{text: "(Ap", stage: %{run: 0}},
               %{note: %{offset: 3}, stage: %{run: 0}},
               %{text: "arte)", stage: %{run: 0}}
             ] = InlineMarkup.parts("<stage>(Aparte)</stage>", [at(3)])
    end

    test "a note at the end of a stage follows it, outside" do
      assert [
               %{text: "(Vase)", stage: %{run: 0}},
               %{note: _, stage: nil},
               %{text: " y", stage: nil}
             ] = InlineMarkup.parts("<stage>(Vase)</stage> y", [at(6)])
    end

    test "a note before a stage that opens the text is outside it" do
      assert [%{note: _, stage: nil}, %{text: "(Vase)", stage: %{run: 0}}] =
               InlineMarkup.parts("<stage>(Vase)</stage>", [at(0)])
    end

    test "a note between two pieces of one stage is inside it" do
      # "a " ends where the italic run starts, at offset 2.
      assert [
               %{text: "a ", stage: %{run: 0}},
               %{note: _, stage: %{run: 0}},
               %{text: "b", italic: true, stage: %{run: 0}}
             ] = InlineMarkup.parts("<stage>a <<b>></stage>", [at(2)])
    end

    test "a note past the end goes last, outside" do
      assert [%{text: "x", stage: %{run: 0}}, %{note: _, stage: nil}] =
               InlineMarkup.parts("<stage>x</stage>", [at(9)])
    end
  end

  describe "well_formed?/1" do
    test "accepts text with no stage, and stages that are closed and flat" do
      for text <- [
            nil,
            "",
            "Dulce <<sueño>> mío",
            "<stage>(Vase)</stage> Allez",
            ~s(a <stage type="delivery_">(bas)</stage> b <stage>(c)</stage>),
            "<stage>a <<b>> c</stage>",
            "<<a>> <stage>b</stage>"
          ] do
        assert InlineMarkup.well_formed?(text), inspect(text)
      end
    end

    test "refuses a stage that is not closed, not opened, nested, or has another attribute" do
      for text <- [
            "<stage>sin cerrar",
            "sin abrir</stage>",
            "<stage>a<stage>b</stage>c</stage>",
            ~s(<stage rend="x">y</stage>),
            ~s(<stage type="">y</stage>),
            ~s(<stage type="a b">y</stage>),
            "<<a <stage>b</stage> c>>"
          ] do
        refute InlineMarkup.well_formed?(text), inspect(text)
      end
    end
  end
end
```

In `test/playcode/play_content_test.exs`, add a new `describe` after the existing ones (the file already has `use Playcode.DataCase`, `import Playcode.TestFixtures` and the aliases):

```elixir
  describe "a stage marker in an element's text" do
    setup do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      attrs = fn content ->
        %{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: content,
          position: 9
        }
      end

      %{attrs: attrs}
    end

    test "is accepted when it is closed and flat", %{attrs: attrs} do
      assert {:ok, %{content: "<stage>(Vase)</stage> Allez"}} =
               PlayContent.create_element(attrs.("<stage>(Vase)</stage> Allez"))
    end

    test "is refused when it is not, on create and on update", %{attrs: attrs} do
      message = "has a stage marker that is not well formed"

      assert {:error, changeset} = PlayContent.create_element(attrs.("<stage>sin cerrar"))
      assert %{content: [^message]} = errors_on(changeset)

      {:ok, element} = PlayContent.create_element(attrs.("Allez"))
      assert {:error, changeset} = PlayContent.update_element(element, %{"content" => "a</stage>"})
      assert %{content: [^message]} = errors_on(changeset)
      assert PlayContent.get_element!(element.id).content == "Allez"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs`
Expected: FAIL. `InlineMarkup.parts/1` returns maps with no `stage` key, `well_formed?/1`, `stage_count/1`, `spoken/1` and `staged/1` are undefined, and the changeset accepts `<stage>sin cerrar`.

- [ ] **Step 3: Write the implementation**

Replace `lib/playcode/play_content/inline_markup.ex` with:

```elixir
defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content, and a `<stage>` inside a verse line or a paragraph as `<stage>…</stage>`
  (`<stage type="delivery">…</stage>` with a type; the type is letters, digits and `_`).
  A stage is flat: no stage in a stage, and no stage inside italics, though italics may
  sit inside a stage.

  `parts/1` turns that back into pieces a renderer can mark up; `plain/1` gives the
  text without the markers, stage words kept, for search and word counts; `spoken/1`
  and `staged/1` split the words by where they are said. `parts/2` also places a
  line's notes between the pieces. `well_formed?/1` says whether the markers are sound.
  """

  # The type and the text of one stage. Groups: type (empty when there is none), text.
  @stage ~r/<stage(?: type="([A-Za-z0-9_]+)")?>(.*?)<\/stage>/s

  @doc """
  Splits `text` into `%{text: binary, italic: boolean, stage: stage}` parts, in order.
  `stage` is nil outside a stage, else `%{type: binary | nil, run: integer}`, `run`
  counting the stages in the text, so two touching stages stay two.
  """
  def parts(nil), do: []

  def parts(text) do
    text = text |> String.replace("&lt;&lt;", "<<") |> String.replace("&gt;&gt;", ">>")

    {parts, _runs} =
      @stage
      |> Regex.split(text, include_captures: true)
      |> Enum.flat_map_reduce(0, fn piece, run ->
        case Regex.run(@stage, piece) do
          [_whole, type, inner] ->
            {italics(inner, %{type: if(type == "", do: nil, else: type), run: run}), run + 1}

          nil ->
            {italics(piece, nil), run}
        end
      end)

    Enum.reject(parts, &(&1.text == ""))
  end

  defp italics(text, stage) do
    ~r/<<(.*?)>>/s
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> %{text: inner, italic: true, stage: stage}
        nil -> %{text: part, italic: false, stage: stage}
      end
    end)
  end

  @doc """
  As `parts/1`, with each of `notes` placed as a `%{note: note, stage: stage}` part after
  the first `note.offset` graphemes of the plain text. A note at the end of a piece
  follows that piece; one inside an italic run splits it. `notes` are placed by
  `{offset, position}` whatever their order in the list, and a note past the end of the
  text goes last.

  A note strictly inside a stage, or between two pieces of one stage, carries that
  stage; one at the start or the end of a stage's text is outside it.
  """
  def parts(text, []), do: parts(text)

  def parts(text, notes) do
    notes = Enum.sort_by(notes, &{&1.offset, &1.position})

    {parts, {_at, rest}} =
      text
      |> parts()
      |> Enum.chunk_every(2, 1, [nil])
      |> Enum.flat_map_reduce({0, notes}, &place_notes/2)

    parts ++ Enum.map(rest, &%{note: &1, stage: nil})
  end

  # Splits `part` (which starts `at` graphemes into the text) at every note that falls
  # inside it or at its end. `next` is the part after it, or nil.
  defp place_notes([part, next], {at, notes}) do
    length = String.length(part.text)
    {here, later} = Enum.split_while(notes, &(&1.offset <= at + length))

    {pieces, cut} =
      Enum.reduce(here, {[], 0}, fn note, {pieces, cut} ->
        k = max(note.offset - at, cut)
        piece = %{part | text: String.slice(part.text, cut, k - cut)}
        inside = if k > 0 and (k < length or same_stage?(part, next)), do: part.stage
        {[%{note: note, stage: inside} | prepend_text(pieces, piece)], k}
      end)

    rest = %{part | text: String.slice(part.text, cut..-1//1)}
    {Enum.reverse(prepend_text(pieces, rest)), {at + length, later}}
  end

  defp same_stage?(%{stage: %{run: run}}, %{stage: %{run: run}}), do: true
  defp same_stage?(_part, _next), do: false

  defp prepend_text(pieces, %{text: ""}), do: pieces
  defp prepend_text(pieces, part), do: [part | pieces]

  @doc "`text` without the `<<` and `>>` markers and the stage tags."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)

  @doc "The text outside every stage, with a space where a stage was."
  def spoken(text),
    do: text |> parts() |> Enum.map_join(&if(&1.stage, do: " ", else: &1.text))

  @doc "The text of the stages only, one space between them."
  def staged(text),
    do: text |> parts() |> Enum.filter(& &1.stage) |> Enum.map_join(" ", & &1.text)

  @doc "How many stage markers `text` holds."
  def stage_count(nil), do: 0
  def stage_count(text), do: @stage |> Regex.scan(text) |> length()

  @doc """
  True when every `<stage` and `</stage>` in `text` belongs to a closed, flat marker with
  a valid type, and no stage sits inside italics.
  """
  def well_formed?(nil), do: true

  def well_formed?(text) do
    without_stages = Regex.replace(@stage, text, fn _all, _type, inner -> inner end)

    not (Regex.match?(~r/<\/?stage/, without_stages) or
           Regex.match?(~r/<<(?:(?!>>).)*?<\/?stage/s, text))
  end
end
```

In `lib/playcode/play_content/element.ex`, change the `content` sentence in the moduledoc to:

```elixir
  `content` is plain text with italics as `<<…>>` markers and a stage direction inside a
  line or paragraph as `<stage type="…">…</stage>` (see `InlineMarkup`).
```

and replace the end of `changeset/2` (`|> validate_inclusion(...)`) with:

```elixir
    |> validate_inclusion(
      :type,
      ~w(speech stage_direction verse_line prose line_group trailer unrecognized)
    )
    |> validate_stage_markers()
  end

  # A marker that is not closed, or is nested, would print as literal tags on every page
  # and could not be written back as <stage>.
  defp validate_stage_markers(changeset) do
    case get_change(changeset, :content) do
      nil ->
        changeset

      content ->
        if Playcode.PlayContent.InlineMarkup.well_formed?(content),
          do: changeset,
          else: add_error(changeset, :content, "has a stage marker that is not well formed")
    end
  end
```

Add the message to the three gettext error files, after the entry for `"must not be before the start year"` in each:

`priv/gettext/errors.pot` and `priv/gettext/en/LC_MESSAGES/errors.po`:
```
msgid "has a stage marker that is not well formed"
msgstr ""

```
`priv/gettext/es/LC_MESSAGES/errors.po`:
```
msgid "has a stage marker that is not well formed"
msgstr "tiene una marca de acotación que no está bien formada"

```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs test/playcode_web/error_translations_test.exs`
Expected: PASS.

- [ ] **Step 5: Prove the tests bite**

In `place_notes/2`, change `k < length or same_stage?(part, next)` to `k < length`: the "between two pieces of one stage" test goes red. Restore it. In `well_formed?/1`, drop the second `Regex.match?` (italics): the `<<a <stage>b</stage> c>>` refusal goes red. Restore it.

- [ ] **Step 6: Refactor, verify, commit**

Read the new module once for duplication (two `Regex` literals in `italics/2` are the only repeated shape; leave them). Then:

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green. If another test fails because it pattern-matches a part without a `stage` key, read it and adapt it with a comment.

```bash
git add lib/playcode/play_content/inline_markup.ex lib/playcode/play_content/element.ex priv/gettext/errors.pot priv/gettext/es/LC_MESSAGES/errors.po priv/gettext/en/LC_MESSAGES/errors.po test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs
git commit -m "feat(inline): a stage direction marker in a line's text, and its validation"
```

---

### Task 2: Stages survive a TEI round trip

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`text_content/2`, `plain_length/1`, new `read_child/2` and `stage_tag/1`)
- Modify: `lib/playcode/export/tei_xml.ex` (`inline_nodes`, `italic_run`)
- Modify: `test/support/import_helpers.ex` (new `xml_inline_stages/1`)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/roundtrip_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/1,2` with `stage`; the `<stage …>…</stage>` marker (Task 1).
- Produces: `ImportHelpers.xml_inline_stages(xml) :: [%{in: "l" | "p", type: binary | nil, text: binary, before: binary, after: binary}]`, one per `<stage>` that is a direct child of an `<l>` or `<p>` in the body, in document order; `before` and `after` are the rest of that line's text on either side, whitespace collapsed.

- [ ] **Step 1: Write the failing tests**

In `test/support/import_helpers.ex`, add after `xml_notes/1`'s private helpers (before `collect/3`):

```elixir
  @doc """
  Every `<stage>` that is a direct child of an `<l>` or `<p>` in the body, in document
  order, as a map: `in`, that line's tag; `type`; `text`; and `before` and `after`, the
  rest of the line's text on either side of it, whitespace collapsed.
  """
  def xml_inline_stages(xml) do
    xml
    |> parse()
    |> descendants("body")
    |> Enum.flat_map(&inline_stages/1)
  end

  defp inline_stages({name, _, children}) when name in ~w(l p) do
    children
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{"stage", attrs, _} = stage, i} ->
        {before, [_stage | rest]} = Enum.split(children, i)

        [
          %{
            in: name,
            type: Map.new(attrs)["type"],
            text: text(stage),
            before: text({name, [], before}),
            after: text({name, [], rest})
          }
        ]

      _other ->
        []
    end)
  end

  defp inline_stages({_name, _, children}), do: Enum.flat_map(children, &inline_stages/1)
  defp inline_stages(_text), do: []
```

In `test/playcode/tei_roundtrip_test.exs`, add a new `describe` after `"in-text notes"` (before the `# Exporting used to write…` fixpoint test):

```elixir
  describe "inline stage directions" do
    @staged """
    <div1 type="acto" n="1"><head>ACTO I</head>
      <div2 type="escena" n="1"><head>ESCENA I</head>
        <sp><speaker>CHIMÈNE</speaker>
          <l n="1"><stage xml:id="st1">(A Léonor.)</stage>Allez l'entretenir en cette galerie.</l>
          <l n="2">Je vous suis,<stage type="exit">(Vase.)</stage> adieu.</l>
          <l n="3">Il parle <stage type="business">(se lève)</stage>puis <stage>(sort)</stage></l>
          <p><stage>Entra</stage>El rey dijo<stage type="delivery_">(bajo)</stage> y salió.</p>
        </sp>
      </div2>
    </div1>
    """

    test "a stage comes back inside its line, where it was, with its type" do
      xml = roundtrip(tei(body: @staged))

      assert Enum.map(xml_inline_stages(xml), &{&1.in, &1.type, &1.text, &1.before, &1.after}) ==
               [
                 {"l", nil, "(A Léonor.)", "", "Allez l'entretenir en cette galerie."},
                 {"l", "exit", "(Vase.)", "Je vous suis,", "adieu."},
                 {"l", "business", "(se lève)", "Il parle", "puis (sort)"},
                 {"l", nil, "(sort)", "Il parle (se lève) puis", ""},
                 {"p", nil, "Entra", "", "El rey dijo (bajo) y salió."},
                 {"p", "delivery_", "(bajo)", "Entra El rey dijo", "y salió."}
               ]

      # The words are the ones the line had when the stage was plain text of it.
      assert reading_texts(xml, "l") == [
               "(A Léonor.) Allez l'entretenir en cette galerie.",
               "Je vous suis, (Vase.) adieu.",
               "Il parle (se lève) puis (sort)"
             ]
    end

    test "a stage is written out escaped" do
      xml =
        roundtrip(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage>(Tom &amp; Jerry &lt;bajo&gt;)</stage> dos</l></sp></div1>)
          )
        )

      assert [%{text: "(Tom & Jerry <bajo>)"}] = xml_inline_stages(xml)
      assert xml =~ "(Tom &amp; Jerry &lt;bajo&gt;)"
    end

    test "a stage type that is not a plain word is dropped, and the import goes on" do
      xml =
        roundtrip(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage type="a b">(x)</stage> dos</l></sp></div1>)
          )
        )

      assert [%{type: nil, text: "(x)"}] = xml_inline_stages(xml)
    end

    test "a note inside a stage stays inside it, and one at its end comes out after it" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <l n="1">Dijo <stage>(en voz <note n="1" type="editor"><p>Dentro.</p></note>baja)</stage> y calló.</l>
              <l n="2"><stage>(Vase)<note n="2" type="editor"><p>Fuera.</p></note></stage> Adiós</l>
            </sp></div1>
            """
          )
        )

      assert [{%{"n" => "1"}, "Dentro."}] = xml_elements(xml, "note", within: "stage")
      assert [%{n: "2", after: "(Vase)"}] = xml_notes(xml) |> Enum.filter(&(&1.n == "2"))
      assert length(xml_elements(xml, "note")) == 2
    end

    test "a stage in an aside line is dropped with the aside's delivery, as before" do
      xml =
        roundtrip(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1"><stage type="delivery">Aparte</stage><seg type="aside">qué haré</seg></l></sp></div1>)
          )
        )

      assert xml_inline_stages(xml) == []
      assert xml_texts(xml, "seg") == ["qué haré"]
    end

    test "importing a file again replaces its stages, never doubles them" do
      path =
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage>(x)</stage> dos</l></sp></div1>)
        )
        |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiParser.import_file(path)
      {:ok, play} = Playcode.Import.TeiParser.import_file(path)

      assert [%{text: "(x)"}] = play |> export_tei() |> xml_inline_stages()
    end

    test "exporting, re-importing and exporting again changes nothing" do
      body = """
      #{@staged}
      <div1 type="acto" n="2"><sp><speaker>A</speaker>
        <l n="9">Dijo <stage>(en voz <note n="1" type="editor"><p>Dentro.</p></note>baja)</stage> y calló.</l>
        <l n="10"><stage>(Vase)<note n="2" type="editor"><p>Fuera.</p></note></stage> Adiós</l>
        <p>Prosa <stage>(con <emph>énfasis</emph>)</stage> final.</p>
      </sp></div1>
      """

      first = tei(code: "STG1", body: body) |> roundtrip()
      second = first |> String.replace("STG1", "STG2") |> roundtrip()

      assert String.replace(second, "STG2", "STG1") == first
    end
  end
```

In `test/playcode/roundtrip_test.exs`:
- add `inline_stages` to `@fields` (after `notes`):
  ```elixir
  @fields ~w(acts scenes characters speeches verses line_groups stage_dirs asides
             split_parts verse_type_attrs hidden_chars heads front_notes speaker_refs notes
             inline_stages)a
  ```
- in `structural_counts/1`, after `notes: count_notes(xml)` add `inline_stages: count_inline_stages(body)` (add the comma after the previous line):
  ```elixir
        front_notes: count_front_note_divs(front),
        notes: count_notes(xml),
        inline_stages: count_inline_stages(body)
  ```
- add the counter after `count_aside_leaves/2`:
  ```elixir
  # <stage> children of <l> and <p> that the importer keeps, as markers in the line's
  # text: those of a line or paragraph that is not an aside, which drops every stage it
  # holds. An <l> is an aside when it has a <seg type="aside"> or a delivery <stage>
  # naming an aside; a <p> only by its <seg>.
  defp count_inline_stages(body) do
    clean = Regex.replace(~r/<\?xml[^?]*\?>/, body, "")
    {:ok, tree} = Saxy.SimpleForm.parse_string("<root>#{clean}</root>")
    count_inline_stage_leaves(tree)
  end

  defp count_inline_stage_leaves({_name, _attrs, children}) do
    Enum.reduce(children, 0, fn
      {tag, _attrs, inner}, acc when tag in ~w(l p) ->
        if aside_leaf?(tag, inner),
          do: acc,
          else: acc + Enum.count(inner, &match?({"stage", _, _}, &1))

      {_tag, _, _} = child, acc ->
        acc + count_inline_stage_leaves(child)

      _, acc ->
        acc
    end)
  end

  defp aside_leaf?(tag, inner) do
    Enum.any?(inner, fn
      {"seg", attrs, _} ->
        attr_val(attrs, "type") == "aside"

      {"stage", attrs, kids} ->
        tag == "l" and attr_val(attrs, "type") == "delivery" and
          Regex.match?(~r/aparte/i, plain_text(kids))

      _ ->
        false
    end)
  end

  defp plain_text(nodes) do
    Enum.map_join(nodes, fn
      text when is_binary(text) -> text
      {_name, _attrs, kids} -> plain_text(kids)
    end)
  end
  ```
  (`attr_val/2` already exists in this file.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/roundtrip_test.exs`
Expected: FAIL. The new tests find no `<stage>` in any `<l>` or `<p>` (the stage is exported as bare text), and `roundtrip: EMOTHE0746_LesOccasionsPerdues` and `roundtrip: EMOTHE0776_LosRivales` report `inline_stages` mismatches (the original holds some, the export none).

- [ ] **Step 3: Write the importer**

In `lib/playcode/import/tei_parser.ex`, in `text_content/2` change the non-emph branch to read children through `read_child/2`:

```elixir
    else
      children |> pieces(notes, &read_child(&1, notes)) |> squeeze()
    end
```

After `defp text_content(_, _notes), do: ""` add:

```elixir
  # A child of the element being read. Under :mark (the play text) a <stage> is kept as a
  # marker (InlineMarkup); the element being read is never wrapped, so a standalone stage
  # direction is not. A stage inside a stage is flattened: markers do not nest.
  defp read_child({"stage", attrs, _children} = stage, :mark) do
    case stage |> text_content(:mark) |> String.replace(~r/<\/?stage[^>]*>/, "") do
      "" -> ""
      text -> stage_tag(attrs) <> text <> "</stage>"
    end
  end

  defp read_child(child, notes), do: text_content(child, notes)

  # The type goes into the marker when it is the plain word the marker allows.
  defp stage_tag(attrs) do
    type = attr_value(attrs, "type")

    if type && type =~ ~r/\A[A-Za-z0-9_]+\z/, do: ~s(<stage type="#{type}">), else: "<stage>"
  end
```

Replace `plain_length/1` (and update the comment above `take_notes/2`, "the offset counting graphemes of the text without its << and >> markers", to say "without its << and >> markers and stage tags"):

```elixir
  @inline_marker ~r/<<|>>|<stage(?: type="[A-Za-z0-9_]+")?>|<\/stage>/

  # Graphemes of `text` without its markers, one marker at a time: a note inside an
  # italic run or a stage is read while the run is still open, so InlineMarkup.plain/1,
  # which needs the closing marker, cannot do it.
  defp plain_length(text), do: text |> String.replace(@inline_marker, "") |> String.length()
```

- [ ] **Step 4: Write the export**

In `lib/playcode/export/tei_xml.ex` add the stage clause **before** the existing `inline_nodes([%{italic: true} | _] = parts)` clause, and make `italic_run/1` match only top-level pieces:

```elixir
  # A stage direction: its pieces, the notes among them included, go inside one <stage>.
  # Its italics and notes nest as they would anywhere, so the pieces are read again with
  # the stage taken off.
  defp inline_nodes([%{stage: %{run: run} = stage} | _] = parts) do
    {inside, rest} = Enum.split_while(parts, &match?(%{stage: %{run: ^run}}, &1))
    attrs = if stage.type, do: %{type: stage.type}, else: %{}

    content =
      case inside |> Enum.map(&%{&1 | stage: nil}) |> inline_nodes() do
        [text] -> text
        nodes -> nodes
      end

    [element(:stage, attrs, content) | inline_nodes(rest)]
  end
```

and in `italic_run/1` change the pattern to `{notes, [%{italic: true, stage: nil} | _] = more}`. Update the comment above `inline_nodes` ("A note inside an italic run …") only if it no longer reads right; it still does.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/roundtrip_test.exs`
Expected: PASS, including the `roundtrip:` tests for `EMOTHE0746` (54 stages in `<l>`, 17 in aside lines, dropped) and `EMOTHE0776` (1 in `<p>`).

- [ ] **Step 6: Prove the tests bite**

(a) In `read_child/2`, return `""` for a stage: the round-trip tests go red. (b) In `plain_length/1`, use `String.length(text) - 2 * length(Regex.scan(~r/<<|>>/, text))` (the old formula): the "note inside a stage" test goes red (the note moves by the tag's length). (c) In `tei_xml.ex`, drop `stage: nil` from the `italic_run/1` pattern and re-import a line with an italic piece before a stage in the fixpoint test: if no test fails, add `<l n="11"><emph>uno</emph><stage>(x)</stage><emph>dos</emph></l>` to the fixpoint test's second body and look again. Restore each.

- [ ] **Step 7: Run the slow sweep once**

Run: `mix test test/playcode/roundtrip_test.exs --include slow`
Expected: PASS for all 83 fixtures (a few minutes; EMOTHE0732, 0735, 0755 and 0756 hold the most inline stages). A failure names the field and the play: read the play's lines before changing anything.

- [ ] **Step 8: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green. An existing test that read an inline stage's words out of a line's `content` and now sees tags is updated with a comment saying why.

```bash
git add lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex test/support/import_helpers.ex test/playcode/tei_roundtrip_test.exs test/playcode/roundtrip_test.exs
git commit -m "feat(tei): inline <stage> kept as a marker and written back in its line"
```

---

### Task 3: Inline stages on the static site

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex` (`part/1`, around line 531)
- Modify: `priv/static_site/style.css` (after the `.sd` rules, around line 136)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2` with `stage` on text and note parts (Task 1); stages stored by the importer (Task 2).
- Produces: each piece of a stage rendered as `<span class="sdi">…</span>`, with the note buttons inside it; `body[data-sd="off"] .sdi { display: none }` in the shipped stylesheet.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/static_site_play_test.exs`, add before the `describe "a division too long for one page"`:

```elixir
  describe "an inline stage direction" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>CHIMÈNE</speaker>
            <l n="1"><stage type="exit">(A Léonor.)</stage>Allez l'entretenir.</l>
            <p>Dijo <stage>(bajo<note n="1" type="editor"><p>Glosa.</p></note> y rápido)</stage> y salió.</p>
          </sp>
        </div1>
        """)

      %{act: page(dir, play, "act-1.html"), dir: dir}
    end

    # The class is the contract between the template and style.css; the last test here
    # holds the stylesheet to it.
    test "is set apart from the spoken words and stays in its line", %{act: act} do
      line = LazyHTML.query(act, "#l1")

      assert line |> LazyHTML.query(".sdi") |> Enum.map(&LazyHTML.text/1) == ["(A Léonor.)"]
      assert squish(LazyHTML.text(line)) =~ "(A Léonor.) Allez l'entretenir."
      refute LazyHTML.text(act) =~ "<stage"
    end

    test "is wrapped piece by piece when a note splits it, the note's number inside", %{act: act} do
      prose = LazyHTML.query(act, "p.pr")

      assert prose |> LazyHTML.query(".sdi") |> Enum.map(&LazyHTML.text/1) |> Enum.join() ==
               "(bajo1 y rápido)"

      assert prose |> LazyHTML.query(".sdi button.nref") |> Enum.count() == 1
    end

    test "is hidden by the rule the stage directions toggle sets", %{dir: dir} do
      assert read!(dir, "assets/style.css") =~ ~s(body[data-sd="off"] .sdi)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL. No `.sdi` element is found, and the stylesheet has no such rule.

- [ ] **Step 3: Write the implementation**

In `lib/playcode/export/static_site/components.ex`, add as the **first** `part/1` clause (before `defp part(%{note: note})`):

```elixir
  # A piece of an inline stage direction, a note's number among them: in a span the
  # "Stage directions" toggle hides.
  defp part(%{stage: %{}} = part),
    do: [~s(<span class="sdi">), part(%{part | stage: nil}), "</span>"]
```

In `priv/static_site/style.css`, after `body[data-sd="off"] .sd { display: none; }` add:

```css
.sdi { font-style: italic; color: var(--ink-2); }
body[data-sd="off"] .sdi { display: none; }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_test.exs test/playcode/export/static_site/fingerprint_test.exs`
Expected: PASS (the size-budget tests in `static_site_test.exs` still pass: one more rule in `style.css`).

- [ ] **Step 5: Prove the tests bite**

Remove the new `part/1` clause: the first two tests go red. Delete the `.sdi` rule that hides: the third goes red. Restore both.

- [ ] **Step 6: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green.

```bash
git add lib/playcode/export/static_site/components.ex priv/static_site/style.css test/playcode/export/static_site_play_test.exs
git commit -m "feat(static-site): inline stage directions in italics, hidden by the toggle"
```

---

### Task 4: Inline stages on `/plays/:code`

**Files:**
- Modify: `lib/playcode_web/components/play_text.ex` (`inline_content/1`, and its call sites in `render_element/1` for `verse_line`, `prose` and the fallback)
- Modify: `assets/css/app.css` (after `.play-text .stage-direction`)
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2` with `stage` (Task 1); stages stored by the importer (Task 2).
- Produces: `inline_content` takes `show_stage` (default `true`); a stage part renders in `<span class="inline-stage">` and is left out when `show_stage` is false.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/play_show_live_test.exs`, add after the first test (italics), before "a note is a number after its word…":

```elixir
  describe "an inline stage direction" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp><speaker>CHIMÈNE</speaker><lg><l n="1"><stage>(A Léonor.)</stage>Allez l'entretenir.</l></lg></sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, html: html}
    end

    defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

    test "reads in its line, set apart", %{html: html} do
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".inline-stage") |> Enum.map(&LazyHTML.text/1) == ["(A Léonor.)"]
      assert squish(LazyHTML.text(doc)) =~ "(A Léonor.) Allez l'entretenir."
      refute html =~ "&lt;stage"
    end

    # The checkbox is a plain input that pushes this event; LiveViewTest cannot click a label.
    test "goes when the stage directions are hidden, and the words stay", %{view: view} do
      html = render_click(view, "toggle_stage_directions")

      refute html =~ "(A Léonor.)"
      assert html =~ "Allez l'entretenir."
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: FAIL. `.inline-stage` is not in the page, and the toggle leaves `(A Léonor.)` shown.

- [ ] **Step 3: Write the implementation**

In `lib/playcode_web/components/play_text.ex`, replace `inline_content/1` (and the attrs above it) with an iodata version, as the static site builds its own, so a wrapper span can surround a piece without whitespace the formatter would add:

```elixir
  attr :text, :string, default: nil
  attr :notes, :list, default: []
  attr :show_stage, :boolean, default: true

  # One line, kept from the formatter by phx-no-format and built as iodata: a line break
  # between a word and its note's number would show as a space.
  defp inline_content(assigns) do
    html =
      assigns.text
      |> InlineMarkup.parts(assigns.notes)
      |> Enum.map(&part_html(&1, assigns.show_stage))

    assigns = assign(assigns, :html, html)

    ~H"""
    <span phx-no-format>{Phoenix.HTML.raw(@html)}</span>
    """
  end

  # A piece of an inline stage direction, a note's number among them: in a span, and left
  # out while the stage directions are hidden.
  defp part_html(%{stage: %{}}, false), do: ""

  defp part_html(%{stage: %{}} = part, true),
    do: [~s(<span class="inline-stage">), part_html(%{part | stage: nil}, true), "</span>"]

  defp part_html(%{note: note}, _show_stage) do
    [
      ~s(<button type="button" class="nref" popovertarget="note-),
      escape(note.id),
      ~s(" aria-label="),
      escape(note_label(note)),
      ~s(">),
      Integer.to_string(note.number),
      "</button>"
    ]
  end

  defp part_html(%{italic: true, text: text}, _show_stage), do: ["<em>", escape(text), "</em>"]
  defp part_html(%{text: text}, _show_stage), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
```

Pass the toggle to the three `inline_content` call sites that can hold a stage: in `render_element` for `verse_line`, `prose` and the fallback (`<div :if={@element.content}>`), add `show_stage={@show_stage_directions}`, e.g.:

```elixir
        <.inline_content
          text={@element.content}
          notes={@element.notes}
          show_stage={@show_stage_directions}
        />
```

(The speaker label, the stage direction's own text, the notes' terms and paragraphs keep the default.)

In `assets/css/app.css`, after the `.play-text .stage-direction { … }` rule:

```css
.play-text .inline-stage {
  font-style: italic;
  color: oklch(from var(--color-base-content) l c h / 0.55);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: PASS, including the existing note tests ("Nous voyent1 dans la ville", each note once).

- [ ] **Step 5: Prove the tests bite**

Remove `show_stage={@show_stage_directions}` from the verse line: the toggle test goes red. Make `part_html(%{stage: %{}} = part, true)` return the bare `part_html(%{part | stage: nil}, true)`: the first test goes red. Restore both.

- [ ] **Step 6: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green.

```bash
git add lib/playcode_web/components/play_text.ex assets/css/app.css test/playcode_web/live/play_show_live_test.exs
git commit -m "feat(plays): inline stage directions in italics, hidden by the toggle"
```

---

### Task 5: Inline stages in the downloads and the comparison page

**Files:**
- Modify: `lib/playcode/export/note_markup.ex` (`part/2`, moduledoc)
- Modify: `lib/playcode/export/html.ex` (CSS near `.nref`, around line 229)
- Modify: `lib/playcode/export/epub.ex` (CSS after `.stage-direction`, around line 432)
- Modify: `lib/playcode/export/compare_html.ex` (the three `render_element/2` clauses at about lines 395-403, CSS after `.stage-direction`, alias)
- Test: `test/playcode_web/controllers/admin/export_controller_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.parts/2` with `stage` (Task 1).
- Produces: `NoteMarkup.inline/3` wraps each piece of a stage in `<span class="stage">`; `CompareHtml` renders a line's text through `NoteMarkup.inline(content, [], :html)`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/controllers/admin/export_controller_test.exs`, add before `describe "a play with in-text notes"`:

```elixir
  describe "a play with an inline stage direction" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>CHIMÈNE</speaker>
                <l n="1"><stage type="exit">(A Léonor.)</stage>Allez l'entretenir.</l>
                <p>Dijo <stage>(Tom &amp; Jerry)</stage> y salió.</p>
              </sp>
            </div1>
            """
          )
        )

      %{staged: play}
    end

    test "the HTML download sets it apart, escaped, and prints no marker",
         %{conn: conn, staged: play} do
      doc =
        conn
        |> get(~p"/admin/plays/#{play.id}/export/html")
        |> response(200)
        |> LazyHTML.from_document()

      assert doc |> LazyHTML.query("span.stage") |> Enum.map(&LazyHTML.text/1) ==
               ["(A Léonor.)", "(Tom & Jerry)"]

      refute LazyHTML.text(doc) =~ "<stage"
    end

    test "the EPUB sets it apart in well-formed XHTML", %{conn: conn, staged: play} do
      conn = get(conn, ~p"/admin/plays/#{play.id}/export/epub")
      {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
      {_name, chapter} = Enum.find(files, fn {name, _} -> to_string(name) =~ "chapter-001" end)

      assert {:ok, _} =
               chapter
               |> String.replace(~r/<!DOCTYPE[^>]*>/, "")
               |> Saxy.SimpleForm.parse_string()

      assert chapter =~ ~s(<span class="stage">(A Léonor.)</span>)
      assert chapter =~ ~s(<span class="stage">(Tom &amp; Jerry)</span>)
    end

    test "the comparison page prints no marker either", %{conn: conn, staged: play} do
      other = play_fixture(%{"title" => "La otra versión"})
      conn = get(conn, ~p"/admin/plays/compare/export/html?#{[plays: "#{play.id},#{other.id}"]}")
      body = response(conn, 200)

      assert body |> LazyHTML.from_document() |> LazyHTML.query("span.stage")
             |> Enum.map(&LazyHTML.text/1) == ["(A Léonor.)", "(Tom & Jerry)"]

      refute body =~ "&lt;stage"
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode_web/controllers/admin/export_controller_test.exs`
Expected: FAIL. No `span.stage`, and the comparison page shows the marker escaped as `&lt;stage&gt;`.

- [ ] **Step 3: Write the implementation**

In `lib/playcode/export/note_markup.ex`, add as the first `part/2` clause:

```elixir
  # A piece of an inline stage direction, a note's number among them.
  defp part(%{stage: %{}} = part, format),
    do: ~s(<span class="stage">) <> part(%{part | stage: nil}, format) <> "</span>"
```

and extend the moduledoc's first sentence: "…italics as `<em>`, an inline stage direction as `<span class="stage">`, each in-text note …".

In `lib/playcode/export/html.ex`, next to the `.nref` rules add `.stage { font-style: italic; color: #555; }` (inside the same CSS heredoc, matching its indentation). In `lib/playcode/export/epub.ex`, after the `.stage-direction { … }` rule add `.stage { font-style: italic; color: #555; }`. In `lib/playcode/export/compare_html.ex`, after `.stage-direction { … }` add `.stage { font-style: italic; color: #555; }`.

In `lib/playcode/export/compare_html.ex`, add `alias Playcode.Export.NoteMarkup` and replace the three bodies:

```elixir
    "        <div class=\"verse-line\"><span class=\"#{content_class}\">#{NoteMarkup.inline(el.content, [], :html)}</span>#{line_num}</div>\n"
```
```elixir
    "        <div class=\"stage-direction\">(#{NoteMarkup.inline(el.content, [], :html)})</div>\n"
```
```elixir
    "        <div class=\"prose-block\">#{NoteMarkup.inline(el.content, [], :html)}</div>\n"
```

This also turns the page's `<<…>>` into `<em>`, closing that gap. If a test pinned the brackets, read it, update it and say why in a comment (a search of `test/` for `<<` in the comparison tests found none).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode_web/controllers/admin/export_controller_test.exs test/playcode_web/live/play_compare_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Prove the tests bite**

Remove the `part/2` clause: the HTML and EPUB tests go red. Put `escape(el.content || "")` back in `compare_html.ex`'s verse line: the comparison test goes red. Restore both.

- [ ] **Step 6: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green. `PdfCache.code_version/0` already covers `NoteMarkup` and `InlineMarkup`, so cached PDFs rebuild; `test/playcode/export/static_site/fingerprint_test.exs` still passes.

```bash
git add lib/playcode/export/note_markup.ex lib/playcode/export/html.ex lib/playcode/export/epub.ex lib/playcode/export/compare_html.ex test/playcode_web/controllers/admin/export_controller_test.exs
git commit -m "feat(export): inline stage directions in the downloads and the comparison page"
```

---

### Task 6: Statistics and search count inline stages

**Files:**
- Modify: `lib/playcode/statistics/metrics.ex` (`words/1`, around line 202)
- Modify: `lib/playcode/statistics.ex` (`@version`, `compute/1`, alias)
- Modify: `lib/playcode/export/static_site/search.ex` (`write_play/2`)
- Test: `test/playcode/statistics_test.exs`, `test/playcode/export/static_site_search_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.stage_count/1`, `spoken/1`, `staged/1` (Task 1); stages stored by the importer (Task 2).
- Produces: `Metrics.words/1` counts the words outside every stage; `"total_stage_directions"` adds the inline ones; `@version` is 3; a search posting is flagged as a stage direction when the word occurs only in a stage direction of its line.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/statistics_test.exs`, add after "get_statistics/1 computes and stores aggregate public metrics":

```elixir
  test "an inline stage direction is counted as a stage direction, and its words are not spoken" do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="jornada" n="1"><head>Jornada I</head>
            <stage>Sale ANA</stage>
            <sp><speaker>ANA</speaker><l n="1">Dulce <stage type="exit">(bajo)</stage> sueño mío</l></sp>
          </div1>
          """
        )
      )

    data = Statistics.get_statistics(play.id).data

    assert data["total_stage_directions"] == 2
    assert data["words"] == 3
  end
```

In `test/playcode/export/static_site_search_test.exs`, add before `describe "updating a generated site"`:

```elixir
  test "a word only an inline stage direction holds is a stage direction hit; a spoken word keeps its flag" do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="jornada" n="1"><head>Jornada I</head>
            <sp><speaker>Segismundo</speaker><l n="12">Decir que sueño es engaño <stage>(vase, sueño)</stage></l></sp>
          </div1>
          """
        )
      )

    dir = generate!([play], all: true)

    {"index", "va", va} = load_js!(dir, "search/index/va.js")
    {"index", "su", su} = load_js!(dir, "search/index/su.js")
    {"index", "en", en} = load_js!(dir, "search/index/en.js")

    # Play 0, one line (0), delta = line * 2 + flag.
    assert va["vase"] == [0, 1, 1]
    # In the stage and spoken in the same line: one posting, spoken.
    assert su["sueño"] == [0, 1, 0]
    assert en["engaño"] == [0, 1, 0]
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode/statistics_test.exs test/playcode/export/static_site_search_test.exs`
Expected: FAIL. `total_stage_directions` is 1 and `words` is 6 (`stage`, `type` and `exit` count as words); `vase` has flag 0.

- [ ] **Step 3: Write the implementation**

In `lib/playcode/statistics/metrics.ex`:

```elixir
  @doc """
  Number of spoken words in element content: the `<<`/`>>` markers and the words of an
  inline stage direction are not spoken.
  """
  def words(nil), do: 0

  def words(text),
    do: length(Regex.scan(~r/[\p{L}\p{N}]+/u, Playcode.PlayContent.InlineMarkup.spoken(text)))
```

(Use an `alias Playcode.PlayContent.InlineMarkup` at the top of the module instead if the file already aliases its siblings.)

In `lib/playcode/statistics.ex`: set `@version 3`, add `InlineMarkup` to the `alias Playcode.PlayContent.{…}` line, and change:

```elixir
      "total_stage_directions" =>
        count_by_type(all_elements, "stage_direction") + inline_stages(all_elements),
```
with, beside `count_by_type/2`:

```elixir
  defp inline_stages(elements),
    do: elements |> Enum.map(&InlineMarkup.stage_count(&1.content)) |> Enum.sum()
```

In `lib/playcode/export/static_site/search.ex`, add `stage_only: stage_only_words(item.element.content)` to each entry in `write_play/2`, and replace the posting construction:

```elixir
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, line} ->
      stage_line? = entry.kind == "s"

      entry.text
      |> words()
      |> Enum.uniq()
      |> Enum.map(fn word ->
        {word, {line, if(stage_line? or word in entry.stage_only, do: 1, else: 0)}}
      end)
    end)
```

and add:

```elixir
  # The words of a line that occur in its inline stage directions and nowhere in what is
  # spoken: those, and no others, are stage direction hits. Most lines hold no stage.
  defp stage_only_words(content) do
    if is_binary(content) and String.contains?(content, "</stage>") do
      spoken = content |> InlineMarkup.spoken() |> words() |> MapSet.new()
      content |> InlineMarkup.staged() |> words() |> Enum.reject(&MapSet.member?(spoken, &1))
    else
      []
    end
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode/statistics_test.exs test/playcode/export` and `node --test test/js/*.test.mjs`
Expected: PASS. (The index format is unchanged, so the browser half of search is untouched.)

- [ ] **Step 5: Prove the tests bite**

Return `Metrics.words/1` to the raw text: the statistics test goes red. Drop `or word in entry.stage_only`: the search test goes red on `vase`. Change the filter in `stage_only_words/1` so a spoken word is not rejected: `sueño` goes red. Restore each.

- [ ] **Step 6: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green. Existing statistics numbers asserted for plays without inline stages do not move.

```bash
git add lib/playcode/statistics.ex lib/playcode/statistics/metrics.ex lib/playcode/export/static_site/search.ex test/playcode/statistics_test.exs test/playcode/export/static_site_search_test.exs
git commit -m "feat(stats): inline stage directions counted; search flags stage-only words"
```

---

### Task 7: Researchers add and change inline stages in the editor

**Files:**
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (`save_element/2` around line 896; the verse-line and prose content fields around lines 2638 and 2853)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`, `priv/gettext/en/LC_MESSAGES/default.po` (through `mix gettext.extract --merge`)
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Consumes: the changeset refusal (Task 1); stages written back by the export (Task 2).
- Produces: a hint under the content field of the verse-line and prose forms; `save_element/2` validates a new element before renumbering later lines.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/play_content_editor_live_test.exs`, add after the `"notes when their text is edited"` describe:

```elixir
  describe "inline stage directions" do
    defp refusal,
      do:
        Gettext.dgettext(
          PlaycodeWeb.Gettext,
          "errors",
          "has a stage marker that is not well formed"
        )

    defp span(lv, text), do: element(lv, "span[title*='#{text}']")

    defp edit(lv, from, to) do
      lv |> span(from) |> render_click()
      lv |> element("form[id^='inline-edit-']") |> render_submit(%{"value" => to})
    end

    test "the verse form says how to mark one", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      assert has_element?(
               lv,
               "#element-form",
               t(~s(Stage direction in the text: <stage type="delivery">…</stage>))
             )
    end

    test "one typed into a line is a <stage> in the exported line", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit(lv, "Segunda línea", ~s(<stage type="exit">(Vase)</stage> Segunda línea))

      assert [%{in: "l", type: "exit", text: "(Vase)", after: "Segunda línea"}] =
               play |> export_tei() |> xml_inline_stages()
    end

    test "two typed touching stay two", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit(lv, "Segunda línea", "<stage>(a)</stage><stage>(b)</stage> Segunda línea")

      assert [%{text: "(a)"}, %{text: "(b)"}] = play |> export_tei() |> xml_inline_stages()
    end

    test "a marker that is not closed is refused in place, and the line is unchanged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      html = edit(lv, "Segunda línea", "<stage>sin cerrar")

      assert html =~ t("Could not save element.")
      assert {"Segunda línea", 2} in lines(play)
    end

    test "a refused marker in a new line renumbers nothing", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      html =
        lv
        |> form("#element-form", element: %{"content" => "<stage>sin cerrar"})
        |> render_submit()

      assert html =~ refusal()

      assert lines(play) == [
               {"Primera línea", 1},
               {"Segunda línea", 2},
               {"Tercera línea", 3}
             ]
    end
  end

  describe "a stage direction's type, changed in a line that has a note" do
    setup %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Dijo <stage>(bajo)</stage> que sí<note n="1" type="editor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
    end

    test "leaves the note where it was", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv |> element("span[title*='que sí ya']") |> render_click()

      lv
      |> element("form[id^='inline-edit-']")
      |> render_submit(%{"value" => ~s(Dijo <stage type="exit">(bajo)</stage> que sí ya)})

      assert [%{n: "1", after: "Dijo (bajo) que sí"}] = xml_notes(export_tei(play))
      assert [%{type: "exit"}] = xml_inline_stages(export_tei(play))
    end
  end
```

(The setup of `"notes when their text is edited"` defines `note_after/2` for its own describe only; these tests use `xml_notes/1` directly. `edit/3` and `span/2` are private to the file; if the file already defines helpers with those names, rename these.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs`
Expected: FAIL. No hint is on the form; the refused-insert test shows the later lines renumbered (`Primera línea` 1, `Segunda línea` 2, `Tercera línea` 4 — the shift ran before the create failed); the flash and error assertions fail only after Task 1's validation is in place (it is, so the inline refusal passes already: that test is a regression guard here).

- [ ] **Step 3: Write the implementation**

In `save_element/2`, validate a new element before `shift_line_numbers/2` can renumber anything:

```elixir
        nil ->
          el_params =
            el_params
            |> Map.put("play_id", play.id)
            |> Map.put("division_id", socket.assigns.selected_division_id)

          changeset = PlayContent.change_element(%PlayContent.Element{}, el_params)

          if changeset.valid? do
            if el_params["type"] == "verse_line" do
              case el_params["line_number"] do
                nil ->
                  :ok

                "" ->
                  :ok

                ln ->
                  line_num = if is_binary(ln), do: String.to_integer(ln), else: ln
                  PlayContent.shift_line_numbers(play.id, line_num)
              end
            end

            PlayContent.create_element(el_params)
          else
            # A refusal comes back before any later line is renumbered for a line that
            # will not be saved.
            {:error, %{changeset | action: :insert}}
          end
```

This replaces the `nil ->` branch of the `case socket.assigns.editing do` in `save_element/2`; the `element ->` branch below it is unchanged.

In the verse-line form (`@modal_element_type == "verse_line"`), after the content `<.input … />` add; and in the prose form after its `<.input field={@form[:content]} …/>`:

```heex
          <p class="mt-1 text-xs text-base-content/60">
            {gettext("Stage direction in the text: <stage type=\"delivery\">…</stage>")}
          </p>
```

Then run `mix gettext.extract --merge`, and in the three `default.po` files give the new entry its Spanish:

`priv/gettext/es/LC_MESSAGES/default.po`:
```
msgid "Stage direction in the text: <stage type=\"delivery\">…</stage>"
msgstr "Acotación dentro del texto: <stage type=\"delivery\">…</stage>"
```
Check every entry the merge marked `#, fuzzy` in `es/default.po` and clear the flag after fixing the translation.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/spanish_translations_test.exs test/playcode_web/error_translations_test.exs`
Expected: PASS.

- [ ] **Step 5: Prove the tests bite**

Move the `PlayContent.change_element` validation after `shift_line_numbers`: the "renumbers nothing" test goes red. Remove the hint paragraph: the hint test goes red. Restore both.

- [ ] **Step 6: Refactor, verify, commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all green.

```bash
git add lib/playcode_web/live/admin/play_content_editor_live.ex priv/gettext/default.pot priv/gettext/es/LC_MESSAGES/default.po priv/gettext/en/LC_MESSAGES/default.po test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit -m "feat(editor): mark a stage direction in a line, and refuse a bad marker before renumbering"
```

---

### Task 8: Documentation, the whole-branch check, and the look in a browser

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/static-site-improvements.md` (item 1)
- Modify: `docs/superpowers/specs/2026-10-09-inline-stage-design.md` (status; the Tests bullet about the default fixtures)

**Interfaces:**
- Consumes: everything above.
- Produces: the docs say what the code does.

- [ ] **Step 1: Update `CLAUDE.md`**

- Project structure: change the `inline_markup.ex` line to `# The <<…>> italics and <stage> markers`.
- *Database Schema*: add to the element-types paragraph (or after `play_notes`) one line: `play_elements.content` holds an inline stage direction as `<stage type="…">…</stage>` next to the `<<…>>` italics, written by the TEI importer from a `<stage>` child of an `<l>` or `<p>` and written back by the export; `Element.changeset` refuses a malformed marker. `/api/v1` returns `content` raw, markers included.
- *TEI-XML Format*: after the `stage` line add `` `stage` inside `l` or `p` -> a `<stage>` marker in the line's text (aside lines and paragraphs drop theirs) ``.
- *Known Roundtrip Gaps*: mark "Inline `<stage>` is flattened" `[x]` and rewrite it: kept as a marker, shown in italics and hidden by the "Stage directions" toggle, counted in statistics and search, edited in the content editor; limits: the 916 stages in aside lines and paragraphs are still dropped (the aside flag carries them), an inline stage's `xml:id` is not kept, a note at the end of a stage exports after it, content search in the editor also matches the marker text. Spec: `docs/superpowers/specs/2026-10-09-inline-stage-design.md`.
- The *Rollout* sentence in the `play_notes` bullet: add that the same re-import carries the inline stages, so one re-upload of the TEI files does both; the dev command is unchanged.
- *What Has Been Implemented*: in the real-fixture roundtrip bullet, "13 structural count fields (…, notes)" becomes 14 with `inline_stages`; the three default fixtures now also cover inline stages (EMOTHE0746: 54 in `<l>`, 17 in aside lines; EMOTHE0776: 1 in `<p>`).

- [ ] **Step 2: Update the other docs**

In `docs/static-site-improvements.md`, item 1's "Same root cause" paragraph: replace the last sentence with "Done (2026-10-09), see `superpowers/specs/2026-10-09-inline-stage-design.md`." In the spec, set the status line to `implemented, 2026-10-09 (commits … of the inline-stage branch)` with the real hashes, and change the Tests bullet "A fixture with inline stages joins the default set, as `EMOTHE0705` did for notes" to "`EMOTHE0746` (54 in `<l>`, 17 in aside lines) and `EMOTHE0776` (1 in `<p>`) already run by default".

- [ ] **Step 3: Run the whole suite, the slow sweep, and the browser half**

Run: `mix test` and `mix test --include slow` and `node --test test/js/*.test.mjs`
Expected: all green. Paste the final lines of each.

- [ ] **Step 4: Look at it in a browser**

Ask the project owner for the go-ahead to run `mix playcode.import.tei --force` on the dev database (it re-imports every play and replaces hand edits there). Without it, stop here and report the browser check as not done. With it, build Le Cid into the scratchpad (`mix playcode.export.site --plays EMOTHE0008_LeCid --all -o <scratchpad>/site`) and read it in headless Chrome, as the notes work was checked, and start `mix phx.server` for the live page. Check: line 137 shows "(A Léonor.)" in italics before "Allez l'entretenir…"; unticking "Stage directions" hides it and leaves the verse, on the static page and on `/plays/EMOTHE0008_LeCid`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/static-site-improvements.md docs/superpowers/specs/2026-10-09-inline-stage-design.md
git commit -m "docs: inline stage directions done; rollout and limits"
```

- [ ] **Step 6: Whole-branch review**

Merge `main` into the branch (`git merge main`; the other session's commits and uncommitted work may touch `tei_xml.ex` and its test: resolve keeping both sides), run `mix test` again, then hand the branch to a fresh reviewer on the most capable model with the spec, this plan and `git diff main...HEAD`.
