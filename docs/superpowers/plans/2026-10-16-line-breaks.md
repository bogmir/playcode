# Line Breaks and Prose Line Numbers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep every `<lb/>`, `<lb n>` and `p@n` of the play text and its notes, show each break as a new line and each number inline, and write them all back to TEI.

**Architecture:** An unnumbered break is stored as `\n` (the way paratexts already are); a numbered one as a `<lb n="…"/>` marker in `content`, and `p@n` as that marker at the very start of a prose paragraph. `InlineMarkup.parts/1` gives the marker a part of its own; every renderer prints a text part's `\n` as `<br>` and a number part as `<span class="pn">`. The parser carries a break as a private character (`\u{E002}`) while it squeezes whitespace, and turns it into `\n` once the text is final.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Saxy (TEI parsing), XmlBuilder (TEI export), LazyHTML (tests).

**Spec:** `docs/superpowers/specs/2026-10-16-line-breaks-design.md`

## Global Constraints

- TDD, red-green-refactor: write the test, run it and watch it fail, write the least code, run it green, refactor while green, then `mix test` (whole suite) before claiming anything (`CLAUDE.md`).
- Prove each new test bites: break the line it covers, watch it go red, put it back; say so in the commit.
- Test through the outermost API: TEI as round trips (`roundtrip/1`, `xml_*` helpers), pages through `live/2` / `get`, the editor through its LiveView. `InlineMarkup` keeps its unit tests (`test/playcode/inline_markup_test.exs`).
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit. Run `mix` plainly, never with a `PATH` export.
- Work on branch `line-breaks`; merge to `main` with `git merge --no-ff line-breaks -m "Merge branch 'line-breaks': …"`. Do not push while a production run or a site build is going.
- Commit messages: `feat(…)`/`fix(…)`/`test(…)`/`docs:`, ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa
  ```
- The number marker is exactly `<lb n="…"/>`, the number matching `[A-Za-z0-9.\-]+`, kept as written.
- `line_number` stays the verse number only: no prose paragraph gets one.
- Muted text on Playcode's own pages is never lighter than `text-base-content/70`; `style.css` stays under 25 KB.
- No migration.

## Review Focus

1. **A paragraph holding a break, quick-edited in the content editor** — a browser strips newlines from an `<input type="text">`, so saving would glue the words ("años,dulce"). The quick edit must open the modal form instead (Task 6 test).
2. **A note placed right after a break** — the note must keep its offset, and no space may appear after the break on re-import ("años,\n dulce") (Task 2 test).
3. **An editor typing a bare `<lb/>` expecting a break** — it must be refused with the marker message, not stored as literal text (Task 1 test); a break is typed with Enter.
4. **A paratext's breaks after `Components.lines/1` is folded into `inline/1`** — a dedication's `\n` must still be a `<br>` on the site's title page (Task 3 test).
5. **A number inside italics or a stage** — it stays a number part of that italic run or stage, so it prints as a number and exports inside the `<emph>`/`<stage>` (Task 1 unit test, Task 2 round trip).

---

### Task 1: The number marker in `InlineMarkup` and its validation

**Files:**
- Modify: `lib/playcode/play_content/inline_markup.ex`
- Modify: `lib/playcode/play_content/element.ex:82-128`
- Modify: `priv/gettext/errors.pot`, `priv/gettext/en/LC_MESSAGES/errors.po`, `priv/gettext/es/LC_MESSAGES/errors.po`
- Test: `test/playcode/inline_markup_test.exs`, `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Produces:
  - A number part from `InlineMarkup.parts/1` and `parts/2`: `%{number: binary, text: "", italic: boolean, stage: nil | %{type: binary | nil, run: integer}}`. Text parts keep their exact shape `%{text: binary, italic: boolean, stage: …}` (no `number` key).
  - `InlineMarkup.number_marker(n :: binary) :: binary` — `~s(<lb n="#{n}"/>)`.
  - `InlineMarkup.paragraph_number(text :: binary | nil) :: {binary | nil, binary | nil}` — the number of a marker at the very start of `text`, and the rest; `{nil, text}` when there is none.
  - `InlineMarkup.numbers_well_formed?(text :: binary | nil) :: boolean`.
  - `plain/1` drops a number part's marker and keeps `\n` as text.

- [ ] **Step 1: Write the failing unit tests**

Add to `test/playcode/inline_markup_test.exs`, before `describe "junk text"`:

```elixir
  describe "line numbers and breaks" do
    test "a number is a part of its own, with no text, where its marker stood" do
      assert InlineMarkup.parts(~s(thanks, <lb n="1320"/>but)) == [
               %{text: "thanks, ", italic: false, stage: nil},
               %{number: "1320", text: "", italic: false, stage: nil},
               %{text: "but", italic: false, stage: nil}
             ]
    end

    test "a number inside italics or a stage belongs to them" do
      assert [_, %{number: "5", italic: true}, _] = InlineMarkup.parts(~s(<<a <lb n="5"/>b>>))

      assert [_, %{number: "6", stage: %{run: 0}}, _] =
               InlineMarkup.parts(~s(<stage>a <lb n="6"/>b</stage>))
    end

    test "plain drops the marker and keeps a line break" do
      assert InlineMarkup.plain(~s(<lb n="1319"/>Beggar, <lb n="1320"/>but\nthanks)) ==
               "Beggar, but\nthanks"
    end

    test "a note placed around a number keeps the number" do
      assert [%{text: "a "}, %{note: _}, %{number: "2"}, %{text: "b"}] =
               InlineMarkup.parts(~s(a <lb n="2"/>b), [at(2)])
    end

    test "a paragraph's number is the marker at its very start" do
      assert InlineMarkup.paragraph_number(~s(<lb n="1319"/>Beggar <lb n="1320"/>but)) ==
               {"1319", ~s(Beggar <lb n="1320"/>but)}

      assert InlineMarkup.paragraph_number(~s(Beggar <lb n="1320"/>but)) ==
               {nil, ~s(Beggar <lb n="1320"/>but)}

      assert InlineMarkup.paragraph_number(nil) == {nil, nil}
    end

    test "the marker is built as the importer stores it" do
      assert InlineMarkup.number_marker("1311-2") == ~s(<lb n="1311-2"/>)
    end

    test "numbers_well_formed? accepts numbers and refuses any other <lb" do
      assert InlineMarkup.numbers_well_formed?(nil)
      assert InlineMarkup.numbers_well_formed?("no marker\nat all")
      assert InlineMarkup.numbers_well_formed?(~s(a <lb n="1311-2"/>b <lb n="3610.01"/>c))
      refute InlineMarkup.numbers_well_formed?("a <lb/>b")
      refute InlineMarkup.numbers_well_formed?(~s(a <lb n="1 2"/>b))
      refute InlineMarkup.numbers_well_formed?(~s(a <lb n="12">b))
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/inline_markup_test.exs`
Expected: FAIL — the first test gets one text part holding the marker; `paragraph_number/1`, `number_marker/1`, `numbers_well_formed?/1` are undefined.

- [ ] **Step 3: Implement the number part**

In `lib/playcode/play_content/inline_markup.ex`, extend the moduledoc's first paragraph with: "A line break is `\n`, kept as text; where a printed line of the source starts, its number is a marker, `<lb n="1320"/>`, and a prose paragraph's own number is that marker at its very start." Then:

```elixir
  # A printed line's number. Group: the number, letters, digits, "." and "-".
  @number ~r/<lb n="([A-Za-z0-9.\-]+)"\/>/
```

Change `parts/1`'s rejects so a number part, whose text is empty, is kept:

```elixir
  def parts(text) do
    text = text |> String.replace("&lt;&lt;", "<<") |> String.replace("&gt;&gt;", ">>")

    if String.contains?(text, "<stage"),
      do: Enum.reject(with_stages(text), &empty?/1),
      else: Enum.reject(italics(text, nil), &empty?/1)
  end

  defp empty?(%{number: _}), do: false
  defp empty?(part), do: part.text == ""
```

Replace `italics/2` so each piece is split at its numbers:

```elixir
  defp italics(text, stage) do
    ~r/<<(.*?)>>/s
    |> Regex.split(text, include_captures: true)
    |> Enum.flat_map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> numbers(inner, true, stage)
        nil -> numbers(part, false, stage)
      end
    end)
  end

  defp numbers(text, italic, stage) do
    if String.contains?(text, "<lb") do
      @number
      |> Regex.split(text, include_captures: true)
      |> Enum.map(fn piece ->
        case Regex.run(@number, piece) do
          [_, n] -> %{number: n, text: "", italic: italic, stage: stage}
          nil -> %{text: piece, italic: italic, stage: stage}
        end
      end)
    else
      [%{text: text, italic: italic, stage: stage}]
    end
  end
```

In `parts/2`, a number part passes `place_notes/2` untouched (it has no text to split, and `prepend_text/2` would drop it). Add this clause above the existing `place_notes/2`:

```elixir
  defp place_notes([%{number: _} = part, _next], acc), do: {[part], acc}
```

Update `parts/1`'s `@doc` to name the number part: "A printed line's number is `%{number: binary, text: "", italic: boolean, stage: stage}`."

- [ ] **Step 4: Add the three functions**

After `stage_count/1`:

```elixir
  @doc "The marker the importer stores where printed line `n` of the source starts."
  def number_marker(n), do: ~s(<lb n="#{n}"/>)

  @doc """
  A prose paragraph's own number (TEI's `p@n`): the number of a marker at the very start
  of `text`, and the text after it. `{nil, text}` when it opens with none.
  """
  def paragraph_number(nil), do: {nil, nil}

  def paragraph_number(text) do
    case Regex.run(~r/\A<lb n="([A-Za-z0-9.\-]+)"\/>(.*)\z/s, text) do
      [_, n, rest] -> {n, rest}
      nil -> {nil, text}
    end
  end

  @doc "True when every `<lb` in `text` is a well-formed number marker."
  def numbers_well_formed?(nil), do: true
  def numbers_well_formed?(text), do: not Regex.match?(~r/<lb(?! n="[A-Za-z0-9.\-]+"\/>)/, text)
```

- [ ] **Step 5: Run the unit tests green**

Run: `mix test test/playcode/inline_markup_test.exs`
Expected: PASS, the existing tests included (their parts carry no `number` key).

- [ ] **Step 6: Write the failing editor test for the refusal**

In `test/playcode_web/live/admin/play_content_editor_live_test.exs`, after `describe "inline stage directions"` (whose `edit/3` and `span/2` helpers are module functions), add:

```elixir
  describe "line numbers in the text" do
    defp number_refusal,
      do:
        Gettext.dgettext(
          PlaycodeWeb.Gettext,
          "errors",
          "has a line number marker that is not well formed"
        )

    # A break is typed with Enter; a bare <lb/> would print as literal text.
    test "a bare <lb/> or a malformed number is refused, and the line is unchanged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      assert edit(lv, "Segunda línea", "Segunda <lb/>línea") =~ number_refusal()
      assert edit(lv, "Segunda línea", ~s(Segunda <lb n="1 2"/>línea)) =~ number_refusal()
      assert {"Segunda línea", 2} in lines(play)
    end
  end
```

- [ ] **Step 7: Run it and watch it fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs`
Expected: FAIL — the first edit saves and the page shows no refusal.

- [ ] **Step 8: Validate the markers in the changeset**

In `lib/playcode/play_content/element.ex`, pipe `|> validate_number_markers()` after `|> validate_stage_markers()` in `changeset/2`, and add:

```elixir
  # A malformed <lb would print as literal tags and could not be written back as <lb n>.
  # A bare <lb/> is refused too: a break is a newline in the text.
  defp validate_number_markers(changeset) do
    if changed?(changeset, :content) and
         not Playcode.PlayContent.InlineMarkup.numbers_well_formed?(
           get_field(changeset, :content)
         ),
       do: add_error(changeset, :content, "has a line number marker that is not well formed"),
       else: changeset
  end
```

Add the message to `priv/gettext/errors.pot` and `priv/gettext/en/LC_MESSAGES/errors.po` (after the stage marker's entry):

```
msgid "has a line number marker that is not well formed"
msgstr ""
```

and to `priv/gettext/es/LC_MESSAGES/errors.po`:

```
msgid "has a line number marker that is not well formed"
msgstr "tiene una marca de número de línea que no está bien formada"
```

- [ ] **Step 9: Run green, prove both tests bite, run the suite**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode/inline_markup_test.exs test/playcode/error_translations_test.exs`
Expected: PASS.
Bite: replace `numbers_well_formed?/1`'s body with `true`; the editor test and the unit test go red; restore. Remove the `place_notes/2` number clause; "a note placed around a number keeps the number" goes red; restore.
Run: `mix test`
Expected: all green.

- [ ] **Step 10: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/play_content/inline_markup.ex lib/playcode/play_content/element.ex priv/gettext test/playcode/inline_markup_test.exs test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit -m "feat(content): a printed line's number is a marker in the text, and a malformed one is refused

Each test seen red with numbers_well_formed?/1 always true, and with the
number clause of place_notes/2 removed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 2: The importer keeps breaks and numbers, the export writes them back

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`prose/2` ~1368, `text_content/2` ~1420, `read_child/3` ~1445, `extract_plain_text/2` ~1475, `squeeze/1` ~1483, `take_notes/2` ~1523, `@inline_marker`/`plain_length/1` ~1550, `parse_note/2` ~1572)
- Modify: `lib/playcode/export/tei_xml.ex` (`with_breaks/1` comment ~812, `paratext_element/1` ~822, `build_element(%{type: "prose"})` ~955, `build_inline_content/2` ~976, `inline_node/1` ~1031)
- Modify: `lib/playcode/statistics/metrics.ex:205-217` (`words/1`)
- Modify: `test/support/import_helpers.ex` (new `xml_lines/3`)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/roundtrip_test.exs`, `test/playcode/statistics_test.exs`, `test/playcode/export/tei_validator_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.number_marker/1`, `paragraph_number/1`, the number part (Task 1).
- Produces:
  - Stored content: `\n` for an unnumbered break; `<lb n="…"/>` (a space before it, none after) for a numbered one; `<lb n="…"/>` first in a prose paragraph's content for its `p@n`. A note's `body`: `\n` inside a paragraph, a blank line between paragraphs.
  - `ImportHelpers.xml_lines(xml, tag, opts \\ []) :: [{%{binary => binary}, binary}]` — each `tag` of the body outside notes (`in_notes: true`: inside them), `<lb/>` as " | ", `<lb n="X"/>` as " [X] ".

- [ ] **Step 1: Add the test helper**

In `test/support/import_helpers.ex`, after `reading_texts/2`:

```elixir
  @doc """
  Each `tag` element of the body, in document order, as `{attributes, text}`: its text
  with each `<lb/>` written " | " and each `<lb n="…"/>` " [n] ", its notes left out,
  whitespace collapsed. `in_notes: true` reads the `tag` elements inside the body's notes
  instead.
  """
  def xml_lines(xml, tag, opts \\ []) do
    body = xml |> parse() |> descendants("body") |> List.first()

    elements =
      if opts[:in_notes],
        do: body |> descendants("note") |> Enum.flat_map(&descendants(&1, tag)),
        else: outside_notes(body, tag)

    Enum.map(elements, fn {_name, attrs, children} ->
      text =
        children |> Enum.map_join(&lined/1) |> String.replace(~r/\s+/u, " ") |> String.trim()

      {Map.new(attrs), text}
    end)
  end

  defp lined({"lb", attrs, _}) do
    case Map.new(attrs)["n"] do
      nil -> " | "
      n -> " [#{n}] "
    end
  end

  defp lined({"note", _, _}), do: ""
  defp lined({_name, _attrs, children}), do: Enum.map_join(children, &lined/1)
  defp lined(text) when is_binary(text), do: text
```

- [ ] **Step 2: Write the failing round-trip tests**

In `test/playcode/tei_roundtrip_test.exs`, after `describe "inline stage directions"`, add:

```elixir
  # Questions 9 and 10 (docs/stakeholder/preguntas.html): every break is shown, and a
  # printed line's number with it. Until 2026-10-16 each <lb/> was read as a space.
  describe "line breaks and prose line numbers" do
    defp speech(paragraphs, code \\ nil) do
      opts = [body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>#{paragraphs}</sp></div1>)]
      tei(if code, do: [{:code, code} | opts], else: opts)
    end

    test "a paragraph's line breaks come back where the file had them" do
      xml =
        roundtrip(
          speech(~s(<p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué; <lb/>pero casarme.</p>))
        )

      assert xml_lines(xml, "p") ==
               [{%{}, "Yo amé en mis primeros años, | dulce cosa lo juzgué; | pero casarme."}]
    end

    test "a printed line's number and a paragraph's number come back as written" do
      xml =
        roundtrip(
          speech(
            ~s(<p n="1319">Beggar that I am, <lb n="1320"/>but I thank you, <lb n="1311-2"/>my thanks.</p>)
          )
        )

      assert xml_lines(xml, "p") ==
               [{%{"n" => "1319"}, "Beggar that I am, [1320] but I thank you, [1311-2] my thanks."}]
    end

    test "a number right after a paragraph's own stays a break inside it" do
      xml = roundtrip(speech(~s(<p n="5"><lb n="6"/>Uno.</p>)))

      assert xml_lines(xml, "p") == [{%{"n" => "5"}, "[6] Uno."}]
    end

    test "a break that opens a paragraph comes back" do
      xml = roundtrip(speech(~s(<p><lb/>Fausto maledetto!</p>)))

      assert xml_lines(xml, "p") == [{%{}, "| Fausto maledetto!"}]
    end

    test "a break inside italics, inside a stage and inside a note comes back there" do
      xml =
        roundtrip(
          speech(
            ~s(<p>Dijo <emph>sic <lb/>probo</emph> y <stage>(canta <lb/>bajo)</stage> fin<note n="1" type="editor"><p>Una glosa <lb/>en dos líneas.</p></note>.</p>)
          )
        )

      assert xml_lines(xml, "p") == [{%{}, "Dijo sic | probo y (canta | bajo) fin."}]
      assert xml_lines(xml, "emph") == [{%{}, "sic | probo"}]
      assert xml_lines(xml, "stage") == [{%{}, "(canta | bajo)"}]
      assert xml_lines(xml, "p", in_notes: true) == [{%{}, "Una glosa | en dos líneas."}]
    end

    test "a note just after a break keeps its place, and no space follows the break" do
      xml =
        roundtrip(speech(~s(<p>Uno, <lb/><note n="1" type="editor"><p>Glosa.</p></note>dos.</p>)))

      assert [%{n: "1", after: "Uno,"}] = xml_notes(xml)
      assert xml_lines(xml, "p") == [{%{}, "Uno, | dos."}]
      assert xml =~ "<lb/><note"
    end

    test "exporting, re-importing and exporting again changes nothing" do
      body =
        ~s(<p n="7">Uno, <lb/>dos <lb n="8"/>tres<note n="1" type="editor"><p>Glosa <lb/>larga.</p></note>.</p><p><lb/>Cuatro <emph>cinco <lb/>seis</emph>.</p>)

      first = speech(body, "LBR1") |> roundtrip()
      second = first |> String.replace("LBR1", "LBR2") |> roundtrip()

      assert String.replace(second, "LBR2", "LBR1") == first
    end
  end
```

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs --only describe:"line breaks and prose line numbers"`
Expected: FAIL — every `|` and `[n]` is missing and the paragraph has no `n` (the breaks come back as spaces).

- [ ] **Step 4: Read breaks and numbers in the parser**

In `lib/playcode/import/tei_parser.ex`, near `@stage_parents`:

```elixir
  # Where an <lb/> stood while the pieces of a text are joined and squeezed: a character
  # squeeze/1 does not take for whitespace, so the file's own line ends, which are, still
  # collapse. take_notes/2 and parse_note/2 turn it into the \n the text keeps.
  @break "\u{E002}"
```

Add a `read_child/3` clause above the generic one, and the two helpers:

```elixir
  # A line break in the play text (:mark) or a note's body (:breaks); elsewhere, a space.
  defp read_child({"lb", attrs, _children}, notes, _parent) when notes in [:mark, :breaks],
    do: line_break(attrs)
```

```elixir
  # An <lb/>: a break, or, with a number, where a printed line of the source starts. A
  # number the marker cannot hold is read as today, a space.
  defp line_break(attrs) do
    case attr_value(attrs, "n") do
      nil -> @break
      n -> printed_line(n)
    end
  end

  # The marker for printed line `n`, or nothing when `n` is absent or not a number the
  # marker can hold.
  defp printed_line(nil), do: ""

  defp printed_line(n),
    do: if(n =~ ~r/\A[A-Za-z0-9.\-]+\z/, do: InlineMarkup.number_marker(n), else: "")
```

(Add `alias Playcode.PlayContent.InlineMarkup` at the top of the module if it is not there.)

Make italics read their breaks too:

```elixir
  defp extract_plain_text(children, notes) when is_list(children),
    do: children |> pieces(notes, &emph_child(&1, notes)) |> squeeze()

  defp emph_child({"lb", attrs, _}, notes) when notes in [:mark, :breaks], do: line_break(attrs)
  defp emph_child({_name, _attrs, children}, notes), do: extract_plain_text(children, notes)
```

Keep the break and the number through `squeeze/1`:

```elixir
  # Pieces of text as one string, a space between them, whitespace collapsed. A break
  # takes the place of the spaces around it; a number keeps the space before it and none
  # after, as the text read before it was kept had them.
  defp squeeze(pieces) do
    pieces
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/ ?\x{E002} ?/u, @break)
    |> String.replace(~r/(<lb n="[^"]*"\/>) /, "\\1")
    |> String.trim()
  end
```

In `take_notes/2`, no space after a break, and the break becomes `\n` at the end:

```elixir
          [_, key, spaced] ->
            space =
              if spaced == "s" and text != "" and not String.ends_with?(text, @break),
                do: " ",
                else: ""

            {text <> space, [{plain_length(text), Map.fetch!(by_key, key)} | found]}
```

```elixir
    text = text |> String.trim_trailing() |> String.replace(@break, "\n")
```

Count the number marker as zero graphemes (the break counts one, as `\n` will):

```elixir
  @inline_marker ~r/<<|>>|<stage(?: type="[A-Za-z0-9_]+")?>|<\/stage>|<lb n="[A-Za-z0-9.\-]+"\/>/
```

Give a paragraph its own number (`prose/2`; its head becomes `defp prose({_name, attrs, children} = para, pos)`):

```elixir
    {content, notes} = take_notes(marked, para)
    # p@n: the number of the paragraph's first printed line, a marker at its very start.
    content = if content == "", do: content, else: printed_line(attr_value(attrs, "n")) <> content
```

Read a note's breaks (`parse_note/2`): use `text_content(&1, :breaks)` in both branches, and turn the break into `\n`:

```elixir
    body =
      case find_children(children, "p") do
        [] ->
          text_content({"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))}, :breaks)

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content(&1, :breaks))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end
      |> String.replace(@break, "\n")
```

Update `text_content/2`'s comment: ":breaks reads as :paste, but keeps each `<lb/>` as a break (a note's body)."

- [ ] **Step 5: Write breaks and numbers in the export**

In `lib/playcode/export/tei_xml.ex`, every text's `\n` becomes `<lb/>` (one rule, the paratexts' own): add `with_breaks/1` to `build_inline_content/2`:

```elixir
  defp build_inline_content(text, notes \\ []) do
    (text || "")
    |> InlineMarkup.parts(notes)
    |> inline_nodes()
    |> with_breaks()
    |> case do
      [] -> ""
      [single] when is_binary(single) -> single
      list -> list
    end
  end
```

and drop the now-redundant call in `paratext_element/1`:

```elixir
          do: inline_element(:p, %{}, build_inline_content(paragraph))
```

Reword `with_breaks/1`'s comment to: "A text's line breaks as `<lb/>`, wherever they fall, inside an `<emph>` or a `<stage>` too: the italics and stages are read first, so a break cannot leave their markers as text."

A number part is an `<lb n>` (above the `%{text: text}` clause):

```elixir
  defp inline_node(%{number: n}), do: element(:lb, %{n: n})
```

A paragraph's leading marker is its `n`:

```elixir
  defp build_element(%{type: "prose"} = el) do
    # The number at the very start of the text is the paragraph's own (p@n).
    {number, text} = InlineMarkup.paragraph_number(el.content)
    inline = build_inline_content(text, el.notes)

    content =
      if el.is_aside do
        [element(:seg, %{type: "aside"}, inline)]
      else
        inline
      end

    inline_element(:p, if(number, do: %{n: number}, else: %{}), content)
  end
```

- [ ] **Step 6: Run the round trips green**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS, the whole file. If an existing test now fails because a header text held a `\n` and now exports an `<lb/>`, read it first: an `<lb/>` is the right TEI for a line break there too; update the expectation with a comment saying why, or, if the field must not take `<lb/>`, record a ruling and keep `with_breaks/1` out of that caller.

- [ ] **Step 7: Count breaks and numbers in the corpus round trip**

In `test/playcode/roundtrip_test.exs`, add `line_breaks line_numbers paragraph_numbers` to `@fields`, these to `structural_counts/1`:

```elixir
      line_breaks: length(Regex.scan(~r/<lb\b(?![^>]*\sn=")[^>]*\/>/, body)),
      line_numbers: length(Regex.scan(~r/<lb\b[^>]*\sn="/, body)),
      paragraph_numbers: length(Regex.scan(~r/<p\b[^>]*\sn="/, body))
```

Run: `mix test test/playcode/roundtrip_test.exs`
Expected: PASS for the three default fixtures (EMOTHE0776: 4 breaks, 450 paragraph numbers; EMOTHE0705: 11 breaks). Seen red first: with Step 4's `read_child/3` clause removed, `line_breaks` differs; restore.
Then: `mix test --include slow test/playcode/roundtrip_test.exs` (minutes). A play whose counts differ is a finding: read which `<lb>` the importer did not keep (two breaks together in a note read as a paragraph break; a break in an aside stage that is dropped) and record a ruling for each shape before changing code.

- [ ] **Step 8: Write the failing word-count test**

In `test/playcode/statistics_test.exs`, after "an inline stage direction is counted…":

```elixir
  # The words a line had when every <lb/> was a space: a break and a number add none.
  test "a line break and a printed line's number add no word" do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><p n="7">Yo amé en mis primeros años, <lb/>dulce cosa <lb n="8"/>lo juzgué.</p></sp></div1>)
        )
      )

    assert Statistics.get_statistics(play.id).data["words"] == 10
  end
```

Run: `mix test test/playcode/statistics_test.exs`
Expected: FAIL — 16: `words/1` reads each marker's `lb`, `n` and number as three words.

- [ ] **Step 9: Count words without the markers**

In `lib/playcode/statistics/metrics.ex` `words/1`, read a line with a number marker through `InlineMarkup.spoken/1`, as a line with a stage:

```elixir
        String.contains?(text, ["</stage>", "<lb "]) -> InlineMarkup.spoken(text)
```

Update the `@doc`: "…the `<<`/`>>` markers, a printed line's number and the words of an inline stage direction are not spoken."

Run: `mix test test/playcode/statistics_test.exs`
Expected: PASS. Bite: revert the line, red; restore.

- [ ] **Step 10: Add the schema test**

In `test/playcode/export/tei_validator_test.exs` (`@moduletag :slow`), inside `describe "validate/1"`:

```elixir
    # TEI allows <lb> in <p>, <note>, <emph> and <stage>, and an n on <p>.
    test "a play with line breaks and prose line numbers exports as schema-valid TEI" do
      play =
        Playcode.ImportHelpers.tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><p n="7">Uno, <lb/>dos <lb n="8"/><emph>tres <lb/>cuatro</emph><note n="1" type="editor"><p>Glosa <lb/>larga.</p></note>.</p></sp></div1>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ ~s(<p n="7">)
      assert xml =~ ~s(<lb n="8"/>)
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end
```

Run: `mix test --include slow test/playcode/export/tei_validator_test.exs`
Expected: PASS (about 15 s per test).

- [ ] **Step 11: Prove the round trips bite, run the suite**

Bite: remove the `inline_node(%{number: n})` clause — "a printed line's number…" goes red; remove the `space` guard in `take_notes/2` — "a note just after a break…" goes red; remove `|> with_breaks()` from `build_inline_content/2` — "a paragraph's line breaks…" goes red. Restore each.
Run: `mix test`
Expected: all green.

- [ ] **Step 12: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add test/playcode/export/tei_validator_test.exs lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex lib/playcode/statistics/metrics.ex test/support/import_helpers.ex test/playcode/tei_roundtrip_test.exs test/playcode/roundtrip_test.exs test/playcode/statistics_test.exs
git commit -m "feat(tei): a line break and a printed line's number are kept and written back

<lb/> is stored as \n, <lb n> as a marker, p@n as that marker at the start of
the paragraph; a note's body keeps its breaks. Seen red with the lb clause, the
number node, the space guard and with_breaks/1 removed each in turn.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 3: The published site shows breaks and numbers

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex:580-660` (`inline/1`, `lines/1`, `part/1`)
- Modify: `lib/playcode/export/static_site/pages/title.html.heex:49,65`
- Modify: `priv/static_site/style.css:136` and the `@media print` block
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: the number part (Task 1); stored `\n` and markers (Task 2).
- Produces: `<br>` for a `\n`; `<span class="pn">N</span>`, with ` m5` when N is a whole multiple of 5. `Components.lines/1` is removed; its callers use `Components.inline/1`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/static_site_play_test.exs`, after `describe "an inline stage direction"`:

```elixir
  describe "line breaks and prose line numbers" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>LUCRECIA</speaker>
            <p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué.</p>
            <p n="1319">Beggar that I am, <lb n="1320"/>but I thank you, <lb n="1311-2"/>my thanks.</p>
          </sp>
        </div1>
        """)

      %{act: page(dir, play, "act-1.html"), dir: dir}
    end

    test "a break is a new line in its paragraph", %{act: act} do
      [song, _hamlet] = act |> LazyHTML.query("p.pr") |> Enum.to_list()

      assert song |> LazyHTML.query("br") |> Enum.count() == 1
      assert squish(LazyHTML.text(song)) == "Yo amé en mis primeros años,dulce cosa lo juzgué."
    end

    test "a number shows where its printed line starts, every fifth marked", %{act: act} do
      [_song, hamlet] = act |> LazyHTML.query("p.pr") |> Enum.to_list()

      assert hamlet |> LazyHTML.query(".pn") |> Enum.map(&LazyHTML.text/1) ==
               ["1319", "1320", "1311-2"]

      assert hamlet |> LazyHTML.query(".pn.m5") |> Enum.map(&LazyHTML.text/1) == ["1320"]
      refute LazyHTML.text(act) =~ "<lb"
    end

    test "the line-number control and print hide the numbers", %{dir: dir} do
      css = read!(dir, "assets/style.css")

      assert css =~ ~s(body[data-ln="off"] .pn)
      assert css =~ ~s(body[data-ln="5"] .pn:not(.m5))
      assert css =~ ".pn:not(.m5) { display: none !important; }"
    end
  end

  # Components.lines/1, the paratexts' renderer, folded into inline/1 on 2026-10-16.
  test "a dedication's line breaks are still new lines on the title page" do
    play =
      import_tei!(
        tei(
          front: ~s(<div type="dedicatoria"><head>DEDICATORIA</head><p>My Lord,<lb/>Whether the world</p></div>),
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">Verso</l></sp></div1>)
        )
      )

    dir = generate!([play], all: true)

    assert html!(dir, "plays/#{play.code}/index.html") |> LazyHTML.to_html() =~
             ~r{My Lord,<br/?>Whether the world}
  end
```

(`squish/1` is the module's own helper; the title page is `plays/CODE/index.html`, written from `title.html.heex`.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL — no `br` (the `\n` is printed as text), no `.pn` (the number part prints nothing), no CSS rule. The dedication test passes already: it guards Step 3's removal of `lines/1`.

- [ ] **Step 3: Print a break and a number**

In `components.ex`, after the stage clause of `part/1`:

```elixir
  # Where a printed line of the source starts, in prose: its number, which the "Line
  # numbers" control hides (style.css), every fifth kept by "5". Not a link: a play that
  # counts its paragraphs restarts at 1, so an id built from the number would repeat.
  defp part(%{number: n}),
    do: [~s(<span class="pn), if(fifth?(n), do: " m5", else: ""), ~s(">), escape(n), "</span>"]
```

and change the two text clauses so a `\n` is a `<br>`:

```elixir
  defp part(%{italic: true, text: text}),
    do: ["<em>", breaks(text), "</em>"]

  defp part(%{text: text}), do: breaks(text)

  defp breaks(text), do: text |> escape() |> String.replace("\n", "<br>")

  defp fifth?(n), do: match?({i, ""} when rem(i, 5) == 0, Integer.parse(n))
```

Delete `lines/1` with its `attr` and `@doc`; in `paratexts` (line ~327) and `title.html.heex` (lines 49, 65) replace `<.lines text={paragraph} />` / `<Components.lines text={paragraph} />` with `<.inline text={paragraph} />` / `<Components.inline text={paragraph} />`. Add to `inline/1`'s `@doc` (write one if it has none): "Each line break a `<br>`, inside the italics too; a printed line's number a `span.pn`."

- [ ] **Step 4: Style and hide the numbers**

In `priv/static_site/style.css`, after line 136:

```css
.pn { font: .6875rem/1 var(--sans); color: var(--faint); vertical-align: super; padding-right: .2em; font-variant-numeric: tabular-nums; }
body[data-ln="5"] .pn:not(.m5), body[data-ln="off"] .pn { display: none; }
```

and inside `@media print`, after the two `.l .n` rules:

```css
  .pn:not(.m5) { display: none !important; }
```

- [ ] **Step 5: Run green, prove they bite, run the suite**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_test.exs`
Expected: PASS, the size budget included.
Bite: make `breaks/1` only escape — the break test and the dedication test go red; drop the `m5` branch — the fifth test goes red. Restore.
Run: `mix test` and `node --test test/js/*.test.mjs`
Expected: all green.

- [ ] **Step 6: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/static_site priv/static_site/style.css test/playcode/export/static_site_play_test.exs
git commit -m "feat(site): a prose break is a new line and a printed line's number shows inline

One renderer for a line break: the paratexts' lines/1 is inline/1 now. The
numbers follow the All / 5 / Off control and print. Seen red with breaks/1
not turning \\n into <br>, and with the m5 class dropped.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 4: `/plays/:code` shows breaks and numbers, and the switch hides the numbers

**Files:**
- Modify: `lib/playcode_web/components/play_text.ex:236-340` (prose `render_element/1`, `inline_content/1`, `part_html/2`)
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: the number part (Task 1), stored text (Task 2).
- Produces: `PlayText.inline_content/1` gains `attr :show_numbers, :boolean, default: true`; a `\n` prints `<br>`, a number `<span class="pn …">N</span>`, nothing when `show_numbers` is false.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/play_show_live_test.exs`, after `describe "an inline stage direction"`:

```elixir
  describe "prose line breaks and numbers" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Act II</head>
            <sp><speaker>HAMLET</speaker><p n="1319">Beggar that I am, <lb n="1320"/>but I thank you. <lb/>Come, come.</p></sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, html: html}
    end

    test "a break is a new line and the numbers show where printed lines start", %{html: html} do
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".pn") |> Enum.map(&LazyHTML.text/1) == ["1319", "1320"]
      # The page's HTML as LiveViewTest serialises it: a void <br> may come out as <br/>.
      assert html =~ ~r{thank you\.<br/?>Come, come\.}
      refute html =~ "&lt;lb"
    end

    # The checkbox is a plain input that pushes this event, as the stage directions' does.
    test "the numbers go when the line numbers are hidden, and the words stay", %{view: view} do
      html = render_click(view, "toggle_line_numbers")
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".pn") |> Enum.count() == 0
      assert squish(LazyHTML.text(doc)) =~ "Beggar that I am, but I thank you."
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: FAIL — no `.pn`, no `<br>`.

- [ ] **Step 3: Render them**

In `play_text.ex`, `inline_content/1`:

```elixir
  attr :text, :string, default: nil
  attr :notes, :list, default: []
  attr :show_stage, :boolean, default: true
  attr :show_numbers, :boolean, default: true

  @doc """
  Stored text as readers see it: `<<…>>` italics as emphasis, inline stage directions,
  note numbers and printed line numbers in place, each line break a `<br>`. Kept on one
  line by phx-no-format and built as iodata: a line break between a word and its note's
  number would show as a space.
  """
  def inline_content(assigns) do
    show = %{stage: assigns.show_stage, numbers: assigns.show_numbers}
    html = assigns.text |> InlineMarkup.parts(assigns.notes) |> Enum.map(&part_html(&1, show))
    assigns = assign(assigns, :html, html)

    ~H"""
    <span phx-no-format>{Phoenix.HTML.raw(@html)}</span>
    """
  end
```

`part_html/2` with the `show` map:

```elixir
  defp part_html(%{stage: %{}}, %{stage: false}), do: ""

  defp part_html(%{stage: %{}} = part, show),
    do: [~s(<span class="inline-stage">), part_html(%{part | stage: nil}, show), "</span>"]

  # Where a printed line of the source starts; gone while the line numbers are hidden.
  defp part_html(%{number: _}, %{numbers: false}), do: ""

  defp part_html(%{number: n}, _show),
    do: [~s(<span class="pn text-xs align-super text-base-content/70 select-none">), escape(n), "</span>"]
```

Rename the `_show_stage` argument of the note clause to `_show`, and make the text clauses print breaks:

```elixir
  defp part_html(%{italic: true, text: text}, _show), do: ["<em>", breaks(text), "</em>"]
  defp part_html(%{text: text}, _show), do: breaks(text)

  defp breaks(text), do: text |> escape() |> String.replace("\n", "<br>")
```

In the prose `render_element/1`, pass the switch:

```elixir
      <.inline_content
        text={@element.content}
        notes={@element.notes}
        show_stage={@show_stage_directions}
        show_numbers={@show_line_numbers}
      />
```

- [ ] **Step 4: Run green, prove they bite, run the suite**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode_web/live/play_compare_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS.
Bite: remove `show_numbers={@show_line_numbers}` — the switch test goes red; restore.
Run: `mix test`
Expected: all green.

- [ ] **Step 5: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode_web/components/play_text.ex test/playcode_web/live/play_show_live_test.exs
git commit -m "feat(play): the play page shows prose breaks and printed line numbers

The numbers follow the Line numbers switch. Seen red with the switch not passed
to the prose paragraph.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 5: The downloads and the comparison page show breaks and numbers

**Files:**
- Modify: `lib/playcode/export/note_markup.ex:18-33`
- Modify: `lib/playcode/export/epub.ex:198-204` (`paratext_paragraphs/1`) and its CSS (~469)
- Modify: `lib/playcode/export/html.ex` CSS (~207), `lib/playcode/export/compare_html.ex` CSS (~177)
- Test: `test/playcode_web/controllers/export_controller_test.exs`, `test/playcode_web/controllers/admin/export_controller_test.exs`

**Interfaces:**
- Consumes: the number part (Task 1).
- Produces: `NoteMarkup.inline/3` prints `\n` as `<br>` (`:html`) or `<br/>` (`:epub`), a number as `<span class="pn">N</span>`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/controllers/export_controller_test.exs`:

```elixir
  test "the HTML and EPUB downloads print a prose break as a new line, and its numbers",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><p n="5">Uno, <lb/>dos <lb n="6"/>tres.</p></sp></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    assert html =~ ~s(<span class="pn">5</span>Uno,<br>dos <span class="pn">6</span>tres.)
    assert epub =~ ~s(<span class="pn">5</span>Uno,<br/>dos <span class="pn">6</span>tres.)
  end
```

In `test/playcode_web/controllers/admin/export_controller_test.exs`:

```elixir
  test "the comparison page prints a prose break as a new line, and its number",
       %{conn: conn, play: play} do
    other =
      import_tei!(
        tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><p n="5">Uno, <lb/>dos.</p></sp></div1>))
      )

    body =
      conn
      |> get(~p"/admin/plays/compare/export/html?#{[plays: "#{play.id},#{other.id}"]}")
      |> response(200)

    assert body =~ ~s(<span class="pn">5</span>Uno,<br>dos.)
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs test/playcode_web/controllers/admin/export_controller_test.exs`
Expected: FAIL — the `\n` is printed raw and the numbers are missing.

- [ ] **Step 3: Print them in `NoteMarkup`**

After the stage clause of `part/2`:

```elixir
  defp part(%{number: n}, _format), do: ~s(<span class="pn">#{escape(n)}</span>)
```

and the text clauses:

```elixir
  defp part(%{italic: true, text: text}, format), do: "<em>#{breaks(text, format)}</em>"
  defp part(%{text: text}, format), do: breaks(text, format)

  # A line break: the EPUB is XHTML.
  defp breaks(text, :epub), do: text |> escape() |> String.replace("\n", "<br/>")
  defp breaks(text, :html), do: text |> escape() |> String.replace("\n", "<br>")
```

Extend the `@doc` of `inline/3`: "each line break a `<br>` (`<br/>` in the EPUB), each printed line's number a `span.pn`."

In `epub.ex` `paratext_paragraphs/1`, drop `|> String.replace("\n", "<br/>")` (NoteMarkup does it) and reword its comment to "Each paragraph a `<p>`; NoteMarkup turns each line break into a `<br/>`, inside the italics too."

Add to the CSS of `html.ex`, `epub.ex` and `compare_html.ex`, beside `.line-number`:

```css
        .pn {
          font-size: x-small;
          color: #999;
          vertical-align: super;
          padding-right: 0.2em;
          font-variant-numeric: tabular-nums;
        }
```

(indented as the surrounding rules are in each file).

- [ ] **Step 4: Run green, prove they bite, run the suite**

Run: `mix test test/playcode_web/controllers/export_controller_test.exs test/playcode_web/controllers/admin/export_controller_test.exs`
Expected: PASS.
Bite: make `breaks(text, :epub)` use `<br>` — the EPUB assertion goes red; restore.
Run: `mix test`
Expected: all green; the paratext tests of the HTML and EPUB downloads still pass (their breaks now come from NoteMarkup).

- [ ] **Step 5: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/note_markup.ex lib/playcode/export/epub.ex lib/playcode/export/html.ex lib/playcode/export/compare_html.ex test/playcode_web/controllers
git commit -m "feat(export): the downloads and the comparison page show prose breaks and numbers

NoteMarkup prints a line break as <br> (<br/> in the EPUB) for the text and the
paratexts alike. Seen red with the EPUB break written as <br>.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 6: The editor keeps breaks and says how to type a number

**Files:**
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex:2478-2489` (the row's text span), `:2970-2984` (prose fields)
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Consumes: stored `\n` (Task 2), the changeset validation (Task 1).
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing tests**

In the `describe "line numbers in the text"` block from Task 1, add:

```elixir
    defp play_with_a_song do
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <sp><speaker>ANA</speaker><p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué.</p></sp>
            </div2>
          </div1>
          """
        )
      )
    end

    # A browser strips the newlines from an <input type="text">: saving the quick edit
    # would glue "años," to "dulce".
    test "a paragraph with a break opens in the form, never the one-line quick edit",
         %{conn: conn} do
      play = play_with_a_song()
      lv = open_scene(conn, play)

      lv |> span("dulce cosa") |> render_click()

      assert has_element?(lv, "#element-form textarea")
      refute has_element?(lv, "form[id^='inline-edit-']")
    end

    test "a break typed in the form is kept, and written back as <lb/>", %{conn: conn} do
      play = play_with_a_song()
      lv = open_scene(conn, play)

      lv |> span("dulce cosa") |> render_click()

      lv
      |> form("#element-form", element: %{"content" => "Yo amé,\ndulce cosa,\nlo juzgué."})
      |> render_submit()

      assert play |> export_tei() |> xml_lines("p") == [{%{}, "Yo amé, | dulce cosa, | lo juzgué."}]
    end

    test "the prose form says how to type a printed line's number", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv |> element("button", t("Prose")) |> render_click()

      assert has_element?(
               lv,
               "#element-form",
               t(~s|Number of a printed line in the text: <lb n="1320"/>|)
             )
    end
```

(The scene's toolbar holds the "Prose" button, as it holds "Stage Dir.", which the existing test finds with `element("button", t("Stage Dir."))`. If the per-element insert menus make `t("Prose")` match more than once, open the form the way "the verse form says how to mark one" does, through a card's `Insert Above`, and pick prose there.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs`
Expected: FAIL — the click opens the one-line quick edit, and the hint is absent. The second test may pass already once the first click is fixed; it guards the textarea path.

- [ ] **Step 3: Route a text with a break to the form, add the hint**

In the row's text span, the click opens the form for a text holding a break:

```heex
          <span
            :if={@element.content && !@is_inline_editing}
            id={"el-text-#{@element.id}"}
            phx-click={
              if String.contains?(@element.content, "\n"), do: "edit_element", else: "inline_edit"
            }
            phx-value-id={@element.id}
```

Under the prose form's stage hint:

```heex
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Number of a printed line in the text: <lb n=\"1320\"/>")}
        </p>
```

Run `mix gettext.extract --merge`, then check every entry it marks fuzzy, and set the Spanish:

```
msgid "Number of a printed line in the text: <lb n=\"1320\"/>"
msgstr "Número de una línea impresa en el texto: <lb n=\"1320\"/>"
```

- [ ] **Step 4: Run green, prove they bite, run the suite**

Run: `mix test test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS.
Bite: set the span's `phx-click` back to `"inline_edit"` — the quick-edit test goes red; restore.
Run: `mix test`
Expected: all green.

- [ ] **Step 5: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/playcode_web/live/admin/play_content_editor_live.ex priv/gettext test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit -m "feat(editor): a paragraph with a break opens in the form, and the form says how to type a number

The one-line quick edit would have dropped the breaks. Seen red with the row
routed back to the quick edit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

---

### Task 7: Docs, and the merge

**Files:**
- Modify: `CLAUDE.md` (TEI-XML Format; Database Schema, the `play_elements.content` bullet)
- Modify: `docs/stakeholder/ida-y-vuelta.html` (rows "Line breaks in prose, letters and songs", "Line numbers of prose")
- Modify: `docs/backlog.md` (the `<lb/>` item), `docs/history.md`
- Modify: `docs/stakeholder/preguntas.html` (questions 9 and 10: built)
- Modify: `docs/superpowers/specs/2026-10-16-line-breaks-design.md` (status)

- [ ] **Step 1: `CLAUDE.md`**

In *TEI-XML Format*, after the `stage` inside `l`, `p` or `seg` line, add:

```
- `lb` in the play text and its notes -> a line break, `\n`, as in paratexts; `lb@n` -> a `<lb n="…"/>` marker where a printed line of the source starts, and `p@n` that marker at the very start of the paragraph (the export tells them apart by position). Shown as a new line and an inline number; the `xml:id` of an `lb` is dropped
```

In *Database Schema*, extend the `play_elements.content` bullet: "…and a printed line's number as `<lb n="…"/>` (a prose paragraph's own at its very start); a line break is `\n`. `Element.changeset` refuses a malformed `<lb`."

- [ ] **Step 2: The round-trip page**

In `docs/stakeholder/ida-y-vuelta.html`, the two rows: every cell `<span class="s yes">Yes</span>`, except "Edited": `<span class="s yes">Yes</span>` with a footnote saying a break is typed with Enter and a number as `<lb n="1320"/>`; reword their "where" to "In 178 plays, 26,571 breaks; shown as on the old site since 16 October" and "In 40 plays, numbered by printed line; 44 more count paragraphs". Add a sentence to the page's "Updated" paragraph.

- [ ] **Step 3: Backlog, history, questions, spec**

Move the backlog item "`<lb/>` is flattened to a space in the play text" to `docs/history.md` as `[x]` with what was built, the commits, the tests and the known limits (the spec's *Out of scope*). On `docs/stakeholder/preguntas.html`, add to the answered box of questions 9 and 10: "Built on 16 October 2026; readers see it once the plays are re-imported." Set the spec's status to "implemented, 2026-10-16 (commits …)".

- [ ] **Step 4: Full checks, then merge**

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
node --test test/js/*.test.mjs
mix test --include slow
```

Expected: all green; the slow sweep's counts equal (or every difference a recorded ruling).

```bash
git add CLAUDE.md docs
git commit -m "docs: line breaks and prose line numbers are kept, shown and written back

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
git checkout main
git merge --no-ff line-breaks -m "Merge branch 'line-breaks': line breaks and prose line numbers kept, shown and written back

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0114qUfMRzuiFc6gGC1USDpa"
```

Push only with the owner's go-ahead and no production run or site build going.

---

## Rollout (after the merge, each step with the owner's go-ahead)

1. Push `main`; wait for CI and the deploy (`gh run list --limit 3`). Nothing changes until plays are re-imported.
2. Dev: `mix playcode.import.tei --force`.
3. Production: `mix playcode.fly.reimport prepare` (whole corpus); stop on any "edited since their import" or "undoes N hand edit(s)" line and look at it with the project; then `mix playcode.fly.reimport run` (~1 hour).
4. Check on production: a lineated play (EMOTHE0010) shows its prose numbers; a song (EMOTHE0053) its lines.
5. Generate from `/admin/export` with the page open (or a request every 20 seconds); a full rebuild. The owner checks the preview and Deploys.
6. Republish the Round Trip and Questions artifacts (`stakeholder-artifacts-account` memory).
