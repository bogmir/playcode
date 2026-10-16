# Hamlet's Folio Passages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read Hamlet's 132 Folio passages (the words only the 1623 Folio prints, typed as HTML between superscript F's) into a `<folio>` marker in the text, write them back as `<app type="folio">` or, when they cross elements, in the file's own form, and give readers a "Folio interpolations" switch, off by default, that shows them in grey between their F's.

**Architecture:** A passage is a `<folio>…</folio>` marker in an element's `content` or a speech's `speaker_label`, like `<aside>`, with `part="I|M|F"` on each piece of a passage that crosses elements. `InlineMarkup.parts/2` marks the parts inside a passage with `:folio`, so every renderer and the TEI export see them through the one function they already call; `InlineMarkup.folio_labels/1` adds the superscript F's for readers. The parser rewrites the XML tree before reading the text: labels become marker text in the text nodes beside them (the spacing kept), the spans go, and an element a passage enters or leaves open is flagged so its text is wrapped once read. No migration.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Saxy (TEI parsing), XmlBuilder (TEI export), LazyHTML (tests).

**Spec:** `docs/superpowers/specs/2026-10-16-hamlet-folio-passages-design.md` (background: `docs/tei-apparatus-and-code.md`, *`<code>`: literal HTML in the text*)

## Global Constraints

- TDD, red-green-refactor: write the test, run it and watch it fail, write the least code, run it green, refactor while green (clear names, no duplication, the helper the code already has), then `mix test` (whole suite) before claiming anything (`CLAUDE.md`).
- Prove each new test bites: break the line it covers, watch it go red, put it back; say so in the commit.
- Test through the outermost API: TEI as round trips (`roundtrip/1`, `xml_apps/1`, `reading_texts/2`, `xml_elements/3`), the changeset through `PlayContent.create_element/1`, pages through `live/2` / `get`, the site through `generate!/2`, the editor through its LiveView. Read back through context functions, never `Repo`.
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit. Run `mix` plainly, never with a `PATH` export.
- Work on branch `hamlet-folio` (already created, holding the spec and this plan). Commit messages `feat(…)`/`fix(…)`/`test(…)`/`docs:`, ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014pT6MejxyentAYW2FAJibW
  ```
- The marker is exactly `<folio>`, `<folio part="I">`, `<folio part="M">`, `<folio part="F">` and `</folio>`. The export's sigla are exactly `#Q2` (the `lem`) and `#F1` (the `rdg`); the printed label is `F`.
- The changeset's error is exactly `"has a Folio marker that is not well formed"`, Spanish (errors.po) `"tiene una marca del Folio que no está bien formada"`.
- The switch: play page label `gettext("Folio interpolations")` (Spanish `"Interpolaciones del Folio"`), `data-folio="on|off"` on `.play-text`, event `"toggle_folio"`; the site's toggle key `fo` (`data-toggle="fo"`, `body[data-fo="off"]`), label "Folio interpolations". **Off by default** in both, unlike every other switch.
- Hamlet's `show_variants` stays off and does not govern the Folio switch.
- Muted text on Playcode's own pages is never lighter than `text-base-content/70`; the downloads' grey is `#666` (5.7:1 on white). `style.css` stays under 25 KB, `site.js` under 15 KB.
- Every new user-visible string goes through `gettext` with its Spanish in `priv/gettext/es/LC_MESSAGES/`; after `mix gettext.extract --merge`, check every entry it marks fuzzy.

## Review Focus

1. **A passage glued to punctuation** ("Very like`<F>`, very like`<F>`. Stayed it long?", 10 or so in the file) — the words keep the file's spacing on import and on export; no space appears before the "." in the Q2 text (Task 2 test).
2. **A passage that opens at a speaker label and closes inside the speech's paragraph** (v. 3224) — the label is Folio-only, the paragraph's last words are Q2's; switched off, the label goes and the words stay (Task 3 import test, Task 4 page test).
3. **A note anchored inside a passage** — it is hidden with the passage and written back inside the reading; one at a passage's edge stays outside (Task 1 parts test, Task 2 round trip).
4. **A hand edit that breaks a marker** (`part="I"` mid-line, a passage inside italics, one holding an aside) — refused with the message, so the export can never write a passage the import would read back differently (Task 1).
5. **A numbered paragraph wholly inside a passage** (`<p n="1288">`) — the number stays before the marker and goes back as `p@n` (Task 3 test).

---

### Task 1: The `<folio>` marker: its parts, its labels, and the changeset

**Files:**
- Modify: `lib/playcode/play_content/inline_markup.ex`
- Modify: `lib/playcode/play_content/element.ex` (`changeset/2`, new `validate_folio_markers/1`)
- Modify: `lib/playcode/statistics/metrics.ex` (`words/1`, the marker list)
- Modify: `priv/gettext/errors.pot`, `priv/gettext/es/LC_MESSAGES/errors.po`
- Test: `test/playcode/inline_markup_test.exs`, `test/playcode/play_content_test.exs`, `test/playcode/statistics_test.exs`

**Interfaces:**
- Produces: `InlineMarkup.parts/1,2`: a part inside a passage has `:folio => %{part: nil | "I" | "M" | "F", run: non_neg_integer}`; the key is **absent** outside a passage (so every existing test's exact maps still hold). A note part strictly inside a passage, or between two pieces of one, carries the passage's `:folio`; one at its start or end has none. Stage runs are numbered across the whole text, so a stage inside a passage and one outside never share a run.
- Produces: `InlineMarkup.folio_labels(parts)` → the parts with `%{label: "F", text: "", italic: false, stage: nil, folio: folio}` before each passage's first part (unless its part is `"M"` or `"F"`) and after its last (unless `"I"` or `"M"`).
- Produces: `InlineMarkup.whole_folio?(text | nil)` → true when the text holds a passage and no word outside one (a printed line's number marker aside).
- Produces: `InlineMarkup.folios_well_formed?(text | nil)`.
- Produces: the changeset refuses a malformed marker in `content` (allowed in `verse_line`, `prose`, `stage_direction`) or `speaker_label` (allowed in `speech`), with the error on that field.

- [ ] **Step 1: Write the failing tests for the parts**

Add to `test/playcode/inline_markup_test.exs` (it already imports or aliases `InlineMarkup` as `parts/1` is called bare in it; follow the file's own style):

```elixir
  describe "a Folio passage" do
    test "is a run of parts of its own, with its part; the text around it has none" do
      assert [%{text: "O God, "} = before, %{text: "O", folio: %{part: nil, run: 0}}, after] =
               parts("O God, <folio>O</folio> God,")

      refute Map.has_key?(before, :folio)
      assert %{text: " God,"} = after
      refute Map.has_key?(after, :folio)

      assert [%{text: "unto", folio: %{part: "I", run: 0}}] =
               parts(~s(<folio part="I">unto</folio>))
    end

    test "holds italics, stages and printed lines' numbers" do
      assert [
               %{text: "Within", stage: %{type: "delivery"}, folio: %{part: "F", run: 0}},
               %{text: "Mother", italic: true, folio: %{run: 0}},
               %{number: "12", folio: %{run: 0}}
             ] =
               parts(
                 ~s(<folio part="F"><stage type="delivery">Within</stage><<Mother>><lb n="12"/></folio>)
               )
    end

    test "a stage inside it and one outside are two runs" do
      assert [%{stage: %{run: 0}}, %{stage: %{run: 1}, folio: %{run: 0}}] =
               parts("<stage>a</stage><folio><stage>b</stage></folio>")
    end

    test "a note inside it goes with it; one at either edge stays outside" do
      notes = for offset <- [7, 8, 10], do: %{id: offset, offset: offset, position: 0}
      placed = parts("O God, <folio>O O</folio> God,", notes)

      folio_of = fn id ->
        placed |> Enum.find(&match?(%{note: %{id: ^id}}, &1)) |> Map.get(:folio)
      end

      assert folio_of.(7) == nil
      assert %{run: 0} = folio_of.(8)
      assert folio_of.(10) == nil
    end

    test "folio_labels/1 marks where a passage starts and ends, not a part's inner edge" do
      labelled = fn text ->
        text
        |> parts()
        |> InlineMarkup.folio_labels()
        |> Enum.map_join(fn
          %{label: label} -> "[#{label}]"
          %{text: text} -> text
        end)
      end

      assert labelled.("O God, <folio>O</folio> God,") == "O God, [F]O[F] God,"
      assert labelled.(~s(her. <folio part="I">She kneels</folio>)) == "her. [F]She kneels"
      assert labelled.(~s(<folio part="M">Prison, my lord?</folio>)) == "Prison, my lord?"
      assert labelled.(~s(<folio part="F">him.</folio> He takes)) == "him.[F] He takes"
      assert labelled.("<folio>a</folio><folio>b</folio>") == "[F]a[F][F]b[F]"
    end

    test "plain and spoken keep its words and drop its tags" do
      text = "Very like<folio>, very like</folio>. Stayed it long?"
      assert InlineMarkup.plain(text) == "Very like, very like. Stayed it long?"
      assert InlineMarkup.spoken(text) == "Very like, very like. Stayed it long?"
    end

    test "whole_folio?/1: every word in a passage, a paragraph's own number aside" do
      assert InlineMarkup.whole_folio?(~s(<folio part="M">Prison, my lord?</folio>))
      assert InlineMarkup.whole_folio?(~s(<lb n="1288"/><folio part="M">Prison?</folio>))
      assert InlineMarkup.whole_folio?("<folio>For he himself is subject to his birth:</folio>")
      refute InlineMarkup.whole_folio?("O God, <folio>O</folio> God,")
      refute InlineMarkup.whole_folio?("no passage")
      refute InlineMarkup.whole_folio?(nil)
    end
  end
```

- [ ] **Step 2: Write the failing tests for the changeset and the word count**

Add to `test/playcode/play_content_test.exs`, after `describe "an aside marker in an element's text"`, with the same `setup` (copy it: `play_with_structure_fixture/0` and the `attrs` function):

```elixir
  describe "a Folio marker in an element's text" do
    setup do
      # (the same setup as "an aside marker in an element's text")
    end

    test "is kept in a line, a paragraph, a stage direction and a speaker label",
         %{attrs: attrs} do
      for {type, field, text} <- [
            {"verse_line", :content, "O God, <folio>O</folio> God,"},
            {"prose", :content, ~s(<lb n="1288"/><folio part="M">Prison, my lord?</folio>)},
            {"stage_direction", :content, ~s(her. <folio part="I">She kneels</folio>)},
            {"speech", :speaker_label, ~s(<folio part="I">hamlet</folio>)}
          ] do
        assert {:ok, element} =
                 attrs.(nil) |> Map.merge(%{type: type}) |> Map.put(field, text) |> PlayContent.create_element()

        assert Map.fetch!(element, field) == text
      end
    end

    test "is refused when it is not sound, or not where a passage can stand",
         %{attrs: attrs} do
      message = "has a Folio marker that is not well formed"

      for content <- [
            "<folio>sin cerrar",
            "a</folio>b",
            "<folio></folio>",
            "<folio>a <folio>b</folio></folio>",
            ~s(<folio part="X">a</folio>),
            "<<a <folio>b>></folio>",
            "<stage>(a <folio>b</folio>)</stage>",
            "<folio>a <aside>b</aside></folio>",
            ~s(<folio part="I">a</folio> b),
            ~s(a <folio part="F">b</folio>),
            ~s(a <folio part="M">b</folio>)
          ] do
        assert {:error, changeset} = PlayContent.create_element(attrs.(content))
        assert %{content: [^message]} = errors_on(changeset), content
      end

      assert {:error, changeset} =
               PlayContent.create_element(%{attrs.("<folio>Vase</folio>") | type: "trailer"})

      assert %{content: [^message]} = errors_on(changeset)

      assert {:error, changeset} =
               attrs.(nil)
               |> Map.merge(%{type: "speech", speaker_label: "<folio>hamlet"})
               |> PlayContent.create_element()

      assert %{speaker_label: [^message]} = errors_on(changeset)
    end
  end
```

And in `test/playcode/statistics_test.exs`, beside the case that counts `"Dulce <aside>sueño</aside> mío"`, a line `"O God, <folio>O</folio> God,"` counts 4 words (the Folio's "O" counted, as the statistics count the whole text; no `folio` token). Read the existing test first and add the line where it fits its shape.

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs test/playcode/statistics_test.exs`
Expected: FAIL — `folio` keys missing, `folio_labels/1` and `whole_folio?/1` undefined, the changeset accepts the bad markers, the word count counts `folio`.

- [ ] **Step 4: Implement the marker in `InlineMarkup`**

Extend the moduledoc with one paragraph:

```
  A Folio passage (Hamlet's words only the 1623 Folio prints) is `<folio>…</folio>`, flat,
  outside any stage or italics and holding no aside, though it may sit inside one; a passage
  that crosses elements is a marker in each, with `part="I"` (its start, ending the text),
  `"M"` (all of it) or `"F"` (its end, starting the text). Its parts carry `:folio`.
```

Add the regex beside `@stage`:

```elixir
  # One Folio passage. Groups: the part ("I", "M", "F", or empty for a passage inside one
  # text), the words. Flat, like a stage.
  @folio ~r/<folio(?: part="([IMF])")?>((?:(?!<\/?folio[\s>]).)+?)<\/folio>/s
```

Rewrite `parts/1` so a passage is split out first and the stage runs are counted across the text:

```elixir
  def parts(text) do
    text =
      text
      |> String.replace("&lt;&lt;", "<<")
      |> String.replace("&gt;&gt;", ">>")
      |> String.replace(["<aside>", "</aside>"], "")

    {parts, _runs} =
      if String.contains?(text, "<folio"),
        do: with_folios(text),
        else: unmarked(text, 0)

    parts
  end

  # The parts of each passage carry it; stages are counted through the whole text.
  defp with_folios(text) do
    {parts, {_folios, stages}} =
      @folio
      |> Regex.split(text, include_captures: true)
      |> Enum.flat_map_reduce({0, 0}, fn piece, {folios, stages} ->
        case Regex.run(@folio, piece) do
          [_whole, part, inner] ->
            folio = %{part: if(part == "", do: nil, else: part), run: folios}
            {parts, stages} = unmarked(inner, stages)
            {Enum.map(parts, &Map.put(&1, :folio, folio)), {folios + 1, stages}}

          nil ->
            {parts, stages} = unmarked(piece, stages)
            {parts, {folios, stages}}
        end
      end)

    {parts, stages}
  end

  defp unmarked(text, stages) do
    {parts, stages} =
      if String.contains?(text, "<stage"),
        do: with_stages(text, stages),
        else: {italics(text, nil), stages}

    {Enum.reject(parts, &empty?/1), stages}
  end
```

`with_stages/1` becomes `with_stages(text, runs)`, starting its `flat_map_reduce` at `runs` and returning `{parts, runs}`.

In `parts/2`'s `place_notes/2`, a note takes the passage as it takes the stage. Replace `same_stage?/2` with one helper for both:

```elixir
        inside = if k > 0 and (k < length or same_run?(part, next, :stage)), do: part.stage
        folio = if k > 0 and (k < length or same_run?(part, next, :folio)), do: Map.get(part, :folio)
        italic = part.italic and k > 0 and k < length
        note = %{note: note, stage: inside, italic: italic}
        note = if folio, do: Map.put(note, :folio, folio), else: note
        {[note | prepend_text(pieces, piece)], k}
```

```elixir
  # Two touching parts of one stage, or of one passage.
  defp same_run?(part, next, key) do
    case {Map.get(part, key), next && Map.get(next, key)} do
      {%{run: run}, %{run: run}} -> true
      _ -> false
    end
  end
```

Add the three public functions after `staged/1`:

```elixir
  @doc """
  `parts` with an F where each Folio passage starts and where it ends, as readers see it:
  `%{label: "F", text: "", italic: false, stage: nil, folio: folio}`. A piece with part
  "M" or "F" opens no passage and one with "M" or "I" closes none: the passage goes on in
  the element before or after.
  """
  def folio_labels(parts) do
    parts
    |> Enum.chunk_by(&folio_run/1)
    |> Enum.flat_map(fn
      [%{folio: folio} | _] = run ->
        label = %{label: "F", text: "", italic: false, stage: nil, folio: folio}
        open = if folio.part in ["M", "F"], do: [], else: [label]
        close = if folio.part in ["M", "I"], do: [], else: [label]
        open ++ run ++ close

      outside ->
        outside
    end)
  end

  defp folio_run(part) do
    case Map.get(part, :folio) do
      %{run: run} -> run
      nil -> nil
    end
  end

  @doc "True when every word of `text` is in a Folio passage, a printed line's number aside."
  def whole_folio?(nil), do: false

  def whole_folio?(text) do
    String.contains?(text, "<folio") and
      @folio |> Regex.replace(text, "") |> String.replace(@number, "") |> String.trim() == ""
  end

  @doc """
  True when every `<folio` and `</folio>` in `text` belongs to a closed, flat marker with
  words in it and a valid part, none sits inside italics or a stage, none holds an aside,
  and each part is where its passage meets the text's edge: "I" ends it, "F" starts it,
  "M" is all of it (a paragraph's own number before them aside).
  """
  def folios_well_formed?(nil), do: true

  def folios_well_formed?(text) do
    without_folios = Regex.replace(@folio, text, "")
    {_number, edges} = text |> String.trim() |> paragraph_number()
    edges = String.trim(edges)

    not (String.contains?(without_folios, ["<folio", "</folio>"]) or
           Regex.match?(~r/<<(?:(?!>>).)*?<\/?folio/s, text) or
           Regex.match?(~r/<stage[^>]*>(?:(?!<\/stage>).)*?<\/?folio/s, text) or
           Regex.match?(~r/<folio[^>]*>(?:(?!<\/folio>).)*?<\/?aside>/s, text) or
           Regex.match?(~r/<folio part="[IM]">(?:(?!<\/folio>).)*<\/folio>\s*\S/s, edges) or
           Regex.match?(~r/\S\s*<folio part="[MF]">/s, edges))
  end
```

(`@number` is the printed line's number regex already in the module.) Update the `plain/1` doc to say the passage tags go too.

- [ ] **Step 5: Validate the marker in `Element.changeset/2`**

Add `|> validate_folio_markers()` after `validate_aside_markers()`, and:

```elixir
  # A Folio marker (InlineMarkup) is sound or refused, in the text of a line, a paragraph
  # or a stage direction, or a speech's speaker label: printed anywhere else it would show
  # its tags, and the export could not write it back.
  defp validate_folio_markers(changeset) do
    Enum.reduce(
      [content: ~w(verse_line prose stage_direction), speaker_label: ~w(speech)],
      changeset,
      fn {field, types}, changeset ->
        text = get_field(changeset, field)

        cond do
          not String.contains?(text || "", ["<folio", "</folio>"]) ->
            changeset

          get_field(changeset, :type) in types and
              Playcode.PlayContent.InlineMarkup.folios_well_formed?(text) ->
            changeset

          true ->
            add_error(changeset, field, "has a Folio marker that is not well formed")
        end
      end
    )
  end
```

Add one sentence to the moduledoc's `content` paragraph: "A passage only the Folio prints is `<folio>…</folio>` (`InlineMarkup`), in a line's, a paragraph's or a stage direction's text, or a speech's `speaker_label`."

Add the msgid to `priv/gettext/errors.pot` and its Spanish to `priv/gettext/es/LC_MESSAGES/errors.po`, beside the aside one.

- [ ] **Step 6: Count the words of a passage, not its tags**

In `Playcode.Statistics.Metrics.words/1`, add `"</folio>"` to the list that sends the text through `InlineMarkup.spoken/1`, and "a Folio passage's tags" to the doc.

- [ ] **Step 7: Run the tests and watch them pass**

Run: `mix test test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs test/playcode/statistics_test.exs`
Expected: PASS. Then prove the tests bite: drop the `same_run?(part, next, :folio)` term (the note test goes red), drop the `\S\s*<folio part="[MF]">` check (two refusal cases go red); put them back.

- [ ] **Step 8: Refactor while green, then the whole suite**

Run `mix format`, `mix test`, `mix compile --warnings-as-errors`. Expected: green.

- [ ] **Step 9: Commit**

```bash
git add lib/playcode/play_content/inline_markup.ex lib/playcode/play_content/element.ex lib/playcode/statistics/metrics.ex priv/gettext test/playcode/inline_markup_test.exs test/playcode/play_content_test.exs test/playcode/statistics_test.exs
git commit -m "feat(text): a <folio> marker for the words only the Folio prints"
```

(with the trailer, and the bite proofs in the body)

---

### Task 2: A passage inside one element is read, from the file's marks or an `<app type="folio">`, and written back as the `<app>`

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`read_tree/1`, the `# --- HTML typed as text ---` section, `@inline_marker`)
- Modify: `lib/playcode/export/tei_xml.ex` (`inline_nodes/1`)
- Test: `test/playcode/tei_roundtrip_test.exs` (`describe "HTML typed into the text"`)

**Interfaces:**
- Consumes: Task 1's `<folio>` marker and the `:folio` key of `InlineMarkup.parts/2`.
- Produces: in a file with superscript labels, `TeiImport.import_file/1` stores each passage inside one element as `<folio>…</folio>` in that element's text; an `<app type="folio">` of exactly the shape `<lem wit="#Q2"/>` + `<rdg wit="#F1">…</rdg>` becomes the same marker in any file; `TeiXml.generate/1` writes a `<folio>` (no part) as `<app type="folio"><lem wit="#Q2"/><rdg wit="#F1">…</rdg></app>`.
- Produces (parser internals Task 3 extends): `passages/2` (`{node, inside}` threaded through the tree in document order), `label_marks/2` (children → `{marks, inside}`, a label an `:open` or `:close` atom), `folio_tags/1` (atoms → marker strings), `merge_text/1`.

- [ ] **Step 1: Write the failing round trips**

In `describe "HTML typed into the text"`, replace the test "a file that marks Folio passages with a superscript F keeps its wrappers" (its behaviour is what this task changes; say so in a comment above the new tests) with:

```elixir
    @f "#{@sup_open}F#{@sup_close}"

    # Hamlet's Folio passages (questions 5 and 36): the words only the 1623 Folio prints,
    # between two superscript F's. They used to stay as typed (this replaces "a file that
    # marks Folio passages with a superscript F keeps its wrappers"). A passage inside one
    # element is now the <app type="folio"> question 36 agreed, the spans gone, the words
    # spaced as the file spaces them.
    test "a passage inside one element goes back as an app the base text lacks" do
      body = """
      <div1 type="acto" n="1"><head>ACT I</head>
        <sp><speaker>HAMLET</speaker>
          <l n="316">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,</l>
          <l n="435">Very like#{@folio_open}#{@f}, very like#{@f}#{@folio_close}. Stayed it long?</l>
          <p n="1223">blessing, but #{@folio_open}#{@f}not#{@f}#{@folio_close} as your daughter
            <lb n="1224"/>may conceive. <seg type="aside">’A is far gone, #{@folio_open}#{@f}far gone,#{@f}#{@folio_close} and truly</seg></p>
        </sp>
        <stage type="business">Enter a king and a queen, #{@folio_open}#{@f}very lovingly,#{@f}#{@folio_close} the queen embracing</stage>
      </div1>
      """

      first = roundtrip(tei(code: "FOL1", body: body))

      refute first =~ "span"
      assert reading_texts(first, "l") == ["O God, God,", "Very like. Stayed it long?"]

      assert for(app <- xml_apps(first), do: {app.in, app.type, app.readings}) == [
               {"l", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "O", nil}]},
               {"l", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", ", very like", nil}]},
               {"p", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "not", nil}]},
               {"p", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "far gone,", nil}]},
               {"stage", "folio",
                [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "very lovingly,", nil}]}
             ]

      # The aside keeps the Folio words inside it.
      assert [{_attrs, "’A is far gone, far gone, and truly"}] = xml_elements(first, "seg")

      second = first |> String.replace("FOL1", "FOL2") |> roundtrip()
      assert String.replace(second, "FOL2", "FOL1") == first
    end

    # The form a re-encoded file will use (question 36) reads as the same passage. An
    # <app type="folio"> of any other shape is an entry of the apparatus, kept as written:
    # read as a passage, its witness would be lost.
    test "the app form reads back as the passage; any other folio app stays an entry" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="316">O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O</rdg></app> God,</l>
        <l n="319">Fie, <app type="folio"><lem wit="#Q2"/><rdg wit="#F2">fie,</rdg></app> ’tis</l>
      </sp></div1>
      """

      first = roundtrip(tei(code: "FOL3", body: body))

      assert [
               %{type: "folio", readings: [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "O", nil}]},
               %{type: "folio", readings: [{"lem", "#Q2", "", nil}, {"rdg", "#F2", "fie,", nil}]}
             ] = xml_apps(first)

      assert reading_texts(first, "l") == ["O God, God,", "Fie, ’tis"]

      second = first |> String.replace("FOL3", "FOL4") |> roundtrip()
      assert String.replace(second, "FOL4", "FOL3") == first
    end
```

(`reading_texts/2` leaves `<app>`s out, so a line reads as Q2's text: "Very like. Stayed it long?" would read "Very like . Stayed" if the import had spaced the marker.)

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: FAIL — the export still holds `<span class="folio">` as text.

- [ ] **Step 3: Read the passages in the parser**

In `read_tree/1`, `{:ok, drop_folio_wrappers(tree)}` becomes `{:ok, folio_text(tree)}`. Rewrite the section `# --- HTML typed as text ---`, keeping `@folio_wrapper`, `folio_labels?/1`, `without_folio_wrappers/1` and `typed_text/1`:

```elixir
  # Seven files hold HTML typed into <code> as text (docs/tei-apparatus-and-code.md). On
  # the old site a <span class="folio"> hid Hamlet's Folio passages, each between two
  # superscript F's. A file with such an F has its passages read into <folio> markers
  # (InlineMarkup); a file with none (The Rover, the Spanish version of The Spanish
  # Tragedy) uses the wrapper for nothing the project wants hidden, so it goes and its
  # words stay. An <app type="folio"> of the agreed form is a passage in any file.
  defp folio_text(tree) do
    tree = folio_apps(tree)

    if folio_labels?(tree),
      do: tree |> passages(false) |> elem(0),
      else: without_folio_wrappers(tree)
  end
```

The `<app>` form:

```elixir
  # The form question 36 agreed: an empty <lem wit="#Q2"/> and one <rdg wit="#F1">. The
  # reading's contents go between markers in the text beside the <app>. Any other <app
  # type="folio"> stays an entry of the apparatus, which keeps everything it says.
  defp folio_apps({name, attrs, children}) do
    children = Enum.map(children, &folio_apps/1)

    if Enum.any?(children, &folio_app?/1) do
      children =
        Enum.flat_map(children, fn
          {"app", _, readings} = app ->
            if folio_app?(app),
              do: ["<folio>" | folio_reading(readings)] ++ ["</folio>"],
              else: [app]

          child ->
            [child]
        end)

      {name, attrs, merge_text(children)}
    else
      {name, attrs, children}
    end
  end

  defp folio_apps(text), do: text

  defp folio_app?({"app", [{"type", "folio"}], children}) do
    case Enum.reject(children, &blank?/1) do
      [{"lem", [{"wit", "#Q2"}], lem}, {"rdg", [{"wit", "#F1"}], _}] -> Enum.all?(lem, &blank?/1)
      _ -> false
    end
  end

  defp folio_app?(_), do: false

  defp folio_reading(readings) do
    {"rdg", _, words} = Enum.find(readings, &match?({"rdg", _, _}, &1))
    words
  end

  defp blank?(child), do: is_binary(child) and String.trim(child) == ""
```

The labels:

```elixir
  # Elements whose children are elements of the text, not its words.
  @folio_containers ~w(TEI text front body back group div div1 div2 div3 div4 div5 sp lg)

  # `node` with its Folio passages read, and whether a passage is open after it, threaded
  # through the tree in document order. A passage runs from one superscript label to the
  # next, whatever the spans say (Hamlet's file misplaces two): the labels become markers in
  # the text nodes beside them, so the words keep their spacing, and the spans go.
  defp passages({name, attrs, children}, inside) when name in @folio_containers do
    {children, inside} = Enum.map_reduce(children, inside, &passages/2)
    {{name, attrs, children}, inside}
  end

  defp passages({name, attrs, children} = element, inside) do
    if inside or labelled?(element) do
      {marks, after} = label_marks(children, inside)
      {{name, attrs, marks |> folio_tags() |> merge_text()}, after}
    else
      {without_folio_wrappers(element), inside}
    end
  end

  defp passages(text, inside), do: {text, inside}

  defp labelled?({_name, _attrs, children}) do
    children |> Enum.chunk_every(3, 1, :discard) |> Enum.any?(fn [a, b, c] -> label?(a, b, c) end) or
      Enum.any?(children, &(is_tuple(&1) and labelled?(&1)))
  end

  defp labelled?(_text), do: false

  # <sup>, its text, </sup>, each typed as text: an F, or once in Hamlet "and" (v. 3315).
  defp label?(open, text, close),
    do: typed_text(open) == "<sup>" and is_binary(text) and typed_text(close) == "</sup>"

  # The children with each label an :open or a :close (its words, when they are not the F,
  # kept inside the passage) and the spans dropped. A child read while no passage is open
  # may hold one of its own (a <seg> aside); one read inside a passage goes in whole.
  defp label_marks([a, b, c | rest] = children, inside) do
    if label?(a, b, c) do
      label =
        case {String.trim(b), inside} do
          {"F", true} -> [:close]
          {"F", false} -> [:open]
          {words, true} -> [" " <> words, :close]
          {words, false} -> [:open, words <> " "]
        end

      {marks, inside} = label_marks(rest, not inside)
      {label ++ marks, inside}
    else
      next_mark(children, inside)
    end
  end

  defp label_marks(children, inside), do: next_mark(children, inside)

  defp next_mark([], inside), do: {[], inside}

  defp next_mark([child | rest], inside) do
    {child, inside} =
      cond do
        typed_text(child) in @folio_wrapper -> {[], inside}
        is_tuple(child) and not inside -> child |> passages(false) |> then(fn {c, i} -> {[c], i} end)
        is_tuple(child) -> {[without_folio_wrappers(child)], inside}
        true -> {[child], inside}
      end

    {marks, inside} = label_marks(rest, inside)
    {child ++ marks, inside}
  end

  # The marks as marker text: a passage opened and closed here is <folio>…</folio>.
  defp folio_tags(marks) do
    marks
    |> Enum.map(fn
      :open -> "<folio>"
      :close -> "</folio>"
      other -> other
    end)
  end

  # Touching text nodes as one, so a marker sits against the words beside it.
  defp merge_text(children) do
    children
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) -> [Enum.join(texts)]
      elements -> elements
    end)
  end
```

Remove `drop_folio_wrappers/1` (no caller left). Add the passage tags to `@inline_marker`, so a note's offset counts no tag: `…|<\/?aside>|<folio(?: part="[IMF]")?>|<\/folio>|<lb n=…`.

The reading machinery needs no other change: the markers are text, read by `pieces/3` and `squeeze/1` as any words are, and a `<seg type="aside">` holding a passage is read with `marker/3` around it.

- [ ] **Step 4: Write a passage back as the `<app>`**

In `TeiXml`, before the stage clause of `inline_nodes/1`:

```elixir
  # A Folio passage (InlineMarkup): inside one element, the <app type="folio"> question 36
  # agreed, the base text (Q2) lacking what the Folio (F1) reads. Its stages, numbers and
  # notes nest in the reading as they would anywhere.
  defp inline_nodes([%{folio: %{run: run} = folio} | _] = parts) do
    {inside, rest} = Enum.split_while(parts, &match?(%{folio: %{run: ^run}}, &1))
    words = inside |> Enum.map(&Map.delete(&1, :folio)) |> inline_nodes()
    folio_nodes(folio.part, words) ++ inline_nodes(rest)
  end
```

```elixir
  defp folio_nodes(nil, words),
    do: [
      element(:app, %{type: "folio"}, [
        element(:lem, %{wit: "#Q2"}, []),
        element(:rdg, %{wit: "#F1"}, words)
      ])
    ]
```

If XmlBuilder writes `<lem wit="#Q2"></lem>` rather than `<lem wit="#Q2"/>` for `[]`, pass `nil` instead; the round trip test pins whichever the importer reads back.

- [ ] **Step 5: Run the tests and watch them pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS. Prove they bite: make `folio_app?/1` accept any `wit` (the second test goes red: `#F2` comes back `#F1`); remove `merge_text/1` from `passages/2` (the first goes red on the spacing); put them back.

- [ ] **Step 6: Refactor while green, then the whole suite**

`mix format`, `mix test`, `mix compile --warnings-as-errors`. Also run `mix test --include slow test/playcode/roundtrip_test.exs` once (the corpus sweep imports Hamlet's test file, whose crossing passages Task 3 handles: if it fails only on Hamlet's crossing passages, note it in the report and leave it for Task 3).

- [ ] **Step 7: Commit**

```bash
git add lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex test/playcode/tei_roundtrip_test.exs
git commit -m "feat(tei): a Folio passage inside one element is read and written back as <app type=\"folio\">"
```

---

### Task 3: Passages that cross elements: their parts, and the file's own form until question 37

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`passages/2`, `folio_tags/1`, new `folio_edges/3` and `with_folio_edges/2`; `speech/3`, `verse_line/2`, `stage_direction/2`, `prose/2`)
- Modify: `lib/playcode/export/tei_xml.ex` (`folio_nodes/2`)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/apparatus_corpus_test.exs` (slow)

**Interfaces:**
- Consumes: Task 2's `passages/2`, `label_marks/2`, `folio_tags/1`.
- Produces: a passage crossing elements stored as `<folio part="I">` where it opens (running to the end of that text), `<folio part="M">` around the whole text of each element inside it (a line, a paragraph after its own number, a stage direction, a speaker label), `<folio part="F">` where it closes; written back as `<code>&lt;span class="folio"&gt;</code>`, an F label (`<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>`) after it on `I` and before the closing span on `F`, the words, `<code>&lt;/span&gt;</code>`.

- [ ] **Step 1: Write the failing round trips**

```elixir
    # 13 of Hamlet's 132 passages cross elements, the longest 14 speeches. Each element is a
    # piece with its part, written back in the file's own form until question 37 settles a
    # TEI one: one span per element, an F where the passage starts and where it ends.
    test "a passage across speeches and stage directions goes back in the file's form" do
      body = """
      <div1 type="acto" n="2"><head>ACT II</head>
        <sp><speaker>hamlet</speaker>
          <p n="1284">Then is doomsday near. #{@folio_open}#{@f}Let me question more: what have #{@folio_close}
            <lb n="1286"/>#{@folio_open}you deserved?#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}guildenstern#{@folio_close}</speaker>
          <p n="1288">#{@folio_open}Prison, my lord?#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}hamlet#{@folio_close}</speaker>
          <p n="1289">#{@folio_open}Denmark’s a prison.#{@f}#{@folio_close} But, in the beaten way</p>
        </sp>
        <stage type="entrance">Lords attendant.] #{@folio_open}#{@f}with #{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}his Guard carrying torches.#{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}Sound a Flourish.#{@f}#{@folio_close}</stage>
      </div1>
      """

      first = roundtrip(tei(code: "FOL5", body: body))
      span = ~s(<span class="folio">)

      assert reading_texts(first, "p") == [
               "Then is doomsday near. #{span}<sup>F</sup>Let me question more: what have you deserved?</span>",
               "#{span}Prison, my lord?</span>",
               "#{span}Denmark’s a prison.<sup>F</sup></span> But, in the beaten way"
             ]

      assert reading_texts(first, "speaker") == ["hamlet", "#{span}guildenstern</span>", "#{span}hamlet</span>"]

      assert reading_texts(first, "stage") == [
               "Lords attendant.] #{span}<sup>F</sup>with</span>",
               "#{span}his Guard carrying torches.</span>",
               "#{span}Sound a Flourish.<sup>F</sup></span>"
             ]

      # A paragraph's own number stays its own.
      assert for({attrs, _} <- xml_elements(first, "p"), do: attrs["n"]) == ~w(1284 1288 1289)
      assert xml_apps(first) == []

      second = first |> String.replace("FOL5", "FOL6") |> roundtrip()
      assert String.replace(second, "FOL6", "FOL5") == first
    end

    # Hamlet's file has three slips in its marks: a </span> set before the passage's words
    # (v. 3057), a span opened twice (v. 1322) and a closing label typed "and" (v. 3315).
    # The labels say where each passage runs; the "and" is kept as the passage's last word
    # until the editor says otherwise (question 39).
    test "the labels, not the spans, say where a passage runs" do
      body = """
      <div1 type="acto" n="5"><sp><speaker>hamlet</speaker>
        <p n="3057">my sudden #{@folio_open}#{@f}#{@folio_close}and more strange#{@f}#{@folio_close} return.</p>
        <p n="3315">I do not lie in’t, #{@folio_open}#{@f}Oh!#{@sup_open}and#{@sup_close}#{@folio_close} yet it is mine.</p>
        <p n="1322">to th’court? #{@folio_open}#{@folio_open}#{@f}for, by my fay#{@f}#{@folio_close} I cannot</p>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert for(app <- xml_apps(xml), do: List.last(app.readings)) == [
               {"rdg", "#F1", "and more strange", nil},
               {"rdg", "#F1", "Oh! and", nil},
               {"rdg", "#F1", "for, by my fay", nil}
             ]

      assert reading_texts(xml, "p") == [
               "my sudden return.",
               "I do not lie in’t, yet it is mine.",
               "to th’court? I cannot"
             ]
    end
```

Check `xml_elements/3`'s attribute shape before relying on `attrs["n"]` (it returns `{attributes, text}`; if the attributes are a keyword list or list of tuples, build the map with `Map.new/1`).

In `test/playcode/apparatus_corpus_test.exs` (slow, needs `doc/tei_corpus/`): the count of entries for EMOTHE0010 now leaves the Folio's out (`Enum.reject(xml_apps(first), &(&1.type == "folio"))`, and the same filter in the comparison of the two exports if needed), and add for EMOTHE0010:

```elixir
      # Hamlet's 132 Folio passages: 119 inside one element, 13 across elements, each of
      # those with an F at its start and its end.
      if @code == "EMOTHE0010" do
        assert Enum.count(xml_apps(first), &(&1.type == "folio")) == 119
        assert first |> xml_texts("code") |> Enum.count(&(&1 == "<sup>")) == 26
        assert xml_texts(second, "code") == xml_texts(first, "code")
      end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: FAIL — an open passage at an element's end leaves an unclosed `<folio>`, so the import is refused ("has a Folio marker that is not well formed").

- [ ] **Step 3: Give a passage's pieces their parts in the parser**

`passages/2` for a text element flags where a passage meets its edges, and `folio_tags/1` gives an opening that does not close here part `I`:

```elixir
  # The attributes that say a passage open before this element runs into it, and one open
  # after it runs out of it: its text, once read, starts with <folio part="F"> (part "M"
  # when no label here closes it) and ends with </folio> (with_folio_edges/2).
  @folio_lead "playcode-folio-lead"
  @folio_trail "playcode-folio-trail"

  defp passages({name, attrs, children} = element, inside) do
    if inside or labelled?(element) do
      {marks, after} = label_marks(children, inside)
      attrs = attrs ++ folio_edges(inside, after, marks)
      {{name, attrs, marks |> folio_tags() |> merge_text()}, after}
    else
      {without_folio_wrappers(element), inside}
    end
  end

  defp folio_edges(inside, after, marks) do
    lead =
      cond do
        inside and :close not in marks -> [{@folio_lead, "M"}]
        inside -> [{@folio_lead, "F"}]
        true -> []
      end

    if after, do: lead ++ [{@folio_trail, "true"}], else: lead
  end

  # The marks as marker text: a passage opened and closed here is <folio>…</folio>; one
  # opened here and still open at the end is part "I", closed when the text is read.
  defp folio_tags(marks) do
    {tags, _closed_later} =
      marks
      |> Enum.reverse()
      |> Enum.map_reduce(false, fn
        :close, _closed_later -> {"</folio>", true}
        :open, true -> {"<folio>", false}
        :open, false -> {~s(<folio part="I">), false}
        other, closed_later -> {other, closed_later}
      end)

    Enum.reverse(tags)
  end

  # `text`, the text of an element read, with the edges its passage gives it.
  defp with_folio_edges(text, _attrs) when text in [nil, ""], do: text

  defp with_folio_edges(text, attrs) do
    lead =
      case attr_value(attrs, @folio_lead) do
        nil -> ""
        part -> ~s(<folio part="#{part}">)
      end

    trail = if attr_value(attrs, @folio_trail), do: "</folio>", else: ""
    lead <> text <> trail
  end
```

Apply `with_folio_edges/2` to the text each reader returns, after `take_notes/2` (the tags count nothing in a note's offset):

- `verse_line/2`: `content = with_folio_edges(content, attrs)`.
- `prose/2`: on `content` before `printed_line(…) <> content`, so the paragraph's number stays before the marker.
- `stage_direction/2`: `{_name, attrs, _children} = stage` is already bound; `content = with_folio_edges(content, attrs)`.
- `speech/3`: the speaker element's own attributes: `speaker = find_child(children, "speaker")`, read it with `text_and_notes(speaker)`, then `with_folio_edges(label, elem(speaker, 1))` when it is not nil.

A label child of the `<speaker>` is read by `read_child/3` as any text is, so `<folio part="I">2 clown` there needs nothing else.

- [ ] **Step 4: Write a piece back in the file's form**

```elixir
  # A piece of a passage that crosses elements: the file's own form, until question 37
  # settles a TEI one. One span around the element's words; the F where the passage starts
  # (part "I") or ends ("F").
  defp folio_nodes(part, words) do
    label = [element(:code, "<sup>"), "F", element(:code, "</sup>")]

    [element(:code, ~s(<span class="folio">))] ++
      if(part == "I", do: label, else: []) ++
      words ++
      if(part == "F", do: label, else: []) ++ [element(:code, "</span>")]
  end
```

(XmlBuilder escapes the strings into `&lt;span class="folio"&gt;`, as the files write them; check the export against the test rather than this note if it quotes differently.)

- [ ] **Step 5: Run the tests and watch them pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs` and `mix test --include slow test/playcode/apparatus_corpus_test.exs test/playcode/roundtrip_test.exs`
Expected: PASS (the slow ones need `doc/tei_corpus/`; if it is missing, say so). Prove they bite: make `folio_edges/3` always answer `"M"` for the lead (the first test goes red on the third paragraph); turn the `" " <> words` back into `[:close]` alone (the second goes red on "Oh! and"); put them back.

- [ ] **Step 6: Refactor while green, then the whole suite**

`mix format`, `mix test`, `mix compile --warnings-as-errors`.

- [ ] **Step 7: Commit**

```bash
git add lib/playcode/import/tei_parser.ex lib/playcode/export/tei_xml.ex test/playcode/tei_roundtrip_test.exs test/playcode/apparatus_corpus_test.exs
git commit -m "feat(tei): Folio passages across elements, written back in the file's form"
```

---

### Task 4: The play page's "Folio interpolations" switch

**Files:**
- Modify: `lib/playcode/play_content/element.ex` (new `folio_only?/1`, `folio_passages?/1`)
- Modify: `lib/playcode_web/components/play_text.ex` (`play_body/1`, `render_element/1`, `inline_content/1`, `part_html/2`)
- Modify: `lib/playcode_web/live/play_show_live.ex` (assigns, `handle_event("toggle_folio", …)`, the switch, `play_body` call)
- Modify: `assets/css/app.css`
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/play_show_live_test.exs`, `test/playcode_web/live/play_compare_live_test.exs`

**Interfaces:**
- Consumes: `InlineMarkup.folio_labels/1`, `whole_folio?/1`; the `:folio` key of parts.
- Produces: `Element.folio_only?(element)` — a line, paragraph or stage direction: `whole_folio?(content)`; a speech: speaker label nil, empty or whole Folio, and at least one part, all `folio_only?`; a line group: at least one line, all `folio_only?` (children under `:children`, as `load_play_content/2` gives them). `Element.folio_passages?(divisions)` — true when any element of the divisions (their `:loaded_elements`, nested `:children`, and sub-divisions' `:children`) holds `<folio` in its content or speaker label. Both used again by Task 5.
- Produces: `PlayText.play_body/1` attr `show_folio` (default `false`), `.play-text[data-folio="on|off"]`; a passage's parts in `span.folio`, its labels `sup.folio.folio-f`, an element `folio_only?` given the class `folio` on its wrapper; app.css hides `.play-text[data-folio="off"] .folio`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/play_show_live_test.exs`, a new describe (use the file's own helpers for a complete play: `import_tei!/1`, `TestFixtures.mark_complete!/1`, `live/2`):

```elixir
  describe "Hamlet's Folio passages" do
    @folio_open ~s(<code>&lt;span class="folio"&gt;</code>)
    @folio_close ~s(<code>&lt;/span&gt;</code>)
    @f ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

    # A passage in a line, a line all the Folio's, and a passage that opens at a speaker
    # label and closes at the end of the speech, so the whole speech is the Folio's.
    @folio_body """
    <div1 type="acto" n="1"><head>ACT I</head>
      <sp><speaker>HAMLET</speaker>
        <l n="316">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,</l>
        <l n="481">#{@folio_open}#{@f}For he himself is subject to his birth:#{@f}#{@folio_close}</l>
      </sp>
      <sp><speaker>#{@folio_open}#{@f}guildenstern#{@folio_close}</speaker>
        <p>#{@folio_open}Prison, my lord?#{@f}#{@folio_close}</p>
      </sp>
    </div1>
    """

    setup %{conn: conn} do
      play = tei(body: @folio_body) |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      %{play: play, view: view}
    end

    test "are hidden until the switch shows them, in grey between their F's", %{view: view} do
      assert has_element?(view, "label", t("Folio interpolations"))
      assert has_element?(view, ~s(#play-tab-text [data-folio="off"]))

      doc = view |> render() |> LazyHTML.from_fragment()
      text = LazyHTML.query(doc, "#play-tab-text")

      assert text |> LazyHTML.query("sup.folio") |> Enum.map(&LazyHTML.text/1) == ~w(F F F F F F)
      assert text |> LazyHTML.query("span.folio") |> Enum.map(&LazyHTML.text/1) |> Enum.take(1) == ["O"]

      # The line all the Folio's, and the speech all the Folio's, go with their words.
      assert text |> LazyHTML.query(".verse-line.folio") |> Enum.count() == 1
      assert text |> LazyHTML.query(".speech.folio") |> Enum.count() == 1

      render_click(view, "toggle_folio")
      assert has_element?(view, ~s(#play-tab-text [data-folio="on"]))
    end

    test "is not governed by Show variant readings", %{conn: conn, play: play} do
      {:ok, play} = Playcode.Catalogue.update_play(play, %{show_variants: false})
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      assert has_element?(view, "label", t("Folio interpolations"))
    end
  end
```

And, in the same describe or beside the Variants test, a play with no Folio passage has no switch (`refute has_element?(plain_view, "label", t("Folio interpolations"))`). Run `t("Folio interpolations")` only after the Spanish is in the .po (Step 3), or the test compares against the English.

In `test/playcode_web/live/play_compare_live_test.exs`, the comparison page shows the Folio passages hidden: a pair where one play has a passage renders `[data-folio="off"]` and no "Folio interpolations" label. Follow how that file builds a compared pair.

The selectors name classes because the hiding is the stylesheet's (the variants' `.vref` is tested the same way); there is no browser in the suite.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode_web/live/play_compare_live_test.exs`
Expected: FAIL — no switch, no `data-folio`, the passages in plain text.

- [ ] **Step 3: Implement**

`Element`:

```elixir
  @doc """
  True when every word of `element` is the Folio's alone (`InlineMarkup.whole_folio?/1`):
  a line's, a paragraph's or a stage direction's text; a speech's speaker label, if it has
  one, and all its parts; all a line group's lines. Readers who hide the Folio's passages
  see none of it.
  """
  def folio_only?(%{type: type} = element) when type in ~w(speech line_group) do
    children = Map.get(element, :children, [])
    label = Map.get(element, :speaker_label)

    children != [] and Enum.all?(children, &folio_only?/1) and
      (label in [nil, ""] or InlineMarkup.whole_folio?(label))
  end

  def folio_only?(element), do: InlineMarkup.whole_folio?(Map.get(element, :content))

  @doc "True when an element of `divisions`, as `PlayContent.load_play_content/2` gives them, holds a Folio passage."
  def folio_passages?(divisions) do
    Enum.any?(divisions, fn division ->
      Enum.any?(Map.get(division, :loaded_elements, []), &holds_folio?/1) or
        folio_passages?(Map.get(division, :children, []))
    end)
  end

  defp holds_folio?(element) do
    Enum.any?([element.content, element.speaker_label], &(&1 && String.contains?(&1, "<folio"))) or
      Enum.any?(Map.get(element, :children, []), &holds_folio?/1)
  end
```

(Alias `Playcode.PlayContent.InlineMarkup` in `Element`. Check the shape `load_play_content/2` returns: if the sub-divisions live under another key, follow it.)

`PlayText`: `attr :show_folio, :boolean, default: false`; the wrapper `<div class="play-text" data-variants=… data-folio={if @show_folio, do: "on", else: "off"}>`. In `inline_content/1`, `InlineMarkup.parts(assigns.notes) |> InlineMarkup.folio_labels() |> Enum.map(&part_html(&1, show))`, and two clauses first in `part_html/2`:

```elixir
  # Hamlet's Folio passages: an F where one starts and ends, and its words, in grey; gone
  # while the "Folio interpolations" switch is off (app.css), a note inside one with it.
  defp part_html(%{label: label}, _show),
    do: [~s(<sup class="folio folio-f">), escape(label), "</sup>"]

  defp part_html(%{folio: _} = part, show),
    do: [~s(<span class="folio">), part_html(Map.delete(part, :folio), show), "</span>"]
```

In `render_element/1`, add `Element.folio_only?(@element) && "folio"` to the class list of the speech wrapper, the line group wrapper, the verse line row, the stage direction and the prose block, and to the speaker label's div `InlineMarkup.whole_folio?(@element.speaker_label) && "folio"`.

`app.css`, after the `.vref` rules:

```css
/* Hamlet's Folio passages: grey, a superscript F where each starts and ends; gone, with
   any line or speech left without words, while the "Folio interpolations" switch is off. */
.play-text .folio {
  color: color-mix(in oklab, var(--color-base-content) 70%, transparent);
}

.play-text .folio-f {
  font-size: 0.65em;
  line-height: 0;
  vertical-align: super;
  padding: 0 0.1em;
}

.play-text[data-folio="off"] .folio {
  display: none;
}
```

(`text-base-content/70` is the floor for muted text; use the variable the theme defines if it is named otherwise.)

`PlayShowLive`: assign `:show_folio, false` and `:has_folio, Element.folio_passages?(divisions)` beside `:has_variants`; `handle_event("toggle_folio", _, socket)` flips it; the switch, beside the Variants one and built the same way, `:if={@has_folio}`, labelled `{gettext("Folio interpolations")}`, `checked={@show_folio}`, `phx-click="toggle_folio"`; pass `show_folio={@show_folio}` to `play_body`. `mix gettext.extract --merge`, then the Spanish `"Interpolaciones del Folio"` in `default.po`; check every fuzzy entry.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode_web/live/play_compare_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS. Prove they bite: drop the speech's `folio` class (the `.speech.folio` count goes red), drop `folio_labels/1` from `inline_content/1` (the F's go); put them back.

- [ ] **Step 5: Refactor while green, then the whole suite**

`mix format`, `mix test`, `mix compile --warnings-as-errors`.

- [ ] **Step 6: Commit**

```bash
git add lib/playcode/play_content/element.ex lib/playcode_web assets/css/app.css priv/gettext test/playcode_web
git commit -m "feat(play): a Folio interpolations switch, off by default"
```

---

### Task 5: The published site's switch

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex` (a `folio` field beside `variants`)
- Modify: `lib/playcode/export/static_site/components.ex` (`<body>`, `play_rail/1`, `el/1`, `inline/1`, `part/1`)
- Modify: `priv/static_site/site.js`, `priv/static_site/style.css`
- Test: `test/playcode/export/static_site_play_test.exs`; `test/js/*.test.mjs` if one covers the remembered toggles

**Interfaces:**
- Consumes: `Element.folio_only?/1`, `Element.folio_passages?/1`, `InlineMarkup.folio_labels/1`, `InlineMarkup.whole_folio?/1`.
- Produces: `%Edition{folio: boolean}`; every page's `<body data-ln="5" data-fo="off">`; the rail's `<input type="checkbox" data-toggle="fo">` (not checked) labelled "Folio interpolations" on a play with passages; a passage's parts in `span.fo`, its labels `sup.fo.fl`, an element `folio_only?` given the class `fo`; `body[data-fo="off"] .fo { display: none }`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/static_site_play_test.exs`, a describe beside "textual variants", with the same `@folio_body` as Task 4 (copy it; the file builds its plays with `import_tei!/1` and `generate!/2`, its act pages with `page/3`):

```elixir
    test "are hidden by default, with a switch that shows them in grey between their F's" do
      play = import_tei!(tei(body: @folio_body))
      act = page(generate!([play], all: true), play, "act-1.html")

      assert act |> LazyHTML.query(~s(input[data-toggle="fo"])) |> Enum.count() == 1
      assert act |> LazyHTML.query(~s(input[data-toggle="fo"][checked])) |> Enum.count() == 0
      assert act |> LazyHTML.query(~s(body[data-fo="off"])) |> Enum.count() == 1
      assert act |> LazyHTML.query("sup.fl") |> Enum.map(&LazyHTML.text/1) == ~w(F F F F F F)
      assert act |> LazyHTML.query(".l.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query(".sp.fo") |> Enum.count() == 1
    end

    test "a play with none has no switch" do
      play = import_tei!(tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)))
      act = page(generate!([play], all: true), play, "act-1.html")
      assert act |> LazyHTML.query(~s(input[data-toggle="fo"])) |> Enum.count() == 0
    end
```

If `test/js/` holds a test of the remembered toggles, add `fo` to it.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

- `Edition`: `folio: Element.folio_passages?(divisions)` where `variants:` is computed.
- `Components`: `<body data-ln="5" data-fo="off">`; in `play_rail/1`, after the Variants label, `<label :if={@edition.folio}><input type="checkbox" data-toggle="fo" /> Folio interpolations</label>`; `inline/1` through `InlineMarkup.folio_labels/1`; `part/1` clauses first:

```elixir
  # Hamlet's Folio passages: an F where one starts and ends, and its words, in grey; gone
  # while the "Folio interpolations" toggle is off, its default (style.css).
  defp part(%{label: label}), do: [~s(<sup class="fo fl">), escape(label), "</sup>"]

  defp part(%{folio: _} = part),
    do: [~s(<span class="fo">), part(Map.delete(part, :folio)), "</span>"]
```

  and the class `fo` on `div.sp`, `div.lg`, `div.l`, `p.sd`, `p.pr` when `Element.folio_only?/1`, on `p.spk` when `InlineMarkup.whole_folio?(@el.speaker_label)`.
- `site.js`: `['ln', 'sd', 'vf', 'va', 'fo']` in the remembered keys (the toggle code reads the body's `off` as unchecked already).
- `style.css`, beside `body[data-va="off"] .vref`: `.fo { color: var(--muted); } .fl { font-size: .65em; line-height: 0; vertical-align: super; } body[data-fo="off"] .fo { display: none; }` (in the file's own compact style; check `--muted` is the token its muted text uses).

- [ ] **Step 4: Run the tests and watch them pass**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_test.exs test/playcode/export/static_site/` and `node --test test/js/*.test.mjs`
Expected: PASS, the size budgets included. Prove they bite: leave `data-fo="off"` off the body; put it back.

- [ ] **Step 5: Refactor while green, then the whole suite**

`mix format`, `mix test`, `mix compile --warnings-as-errors`.

- [ ] **Step 6: Commit**

```bash
git add lib/playcode/export/static_site priv/static_site test/playcode/export test/js
git commit -m "feat(site): a Folio interpolations toggle, off by default"
```

---

### Task 6: The downloads and the comparison download print the passages in grey between their F's

**Files:**
- Modify: `lib/playcode/export/note_markup.ex` (`inline/3`, `part/2`)
- Modify: `lib/playcode/export/html.ex`, `lib/playcode/export/epub.ex` (their stylesheets)
- Modify: `lib/playcode/export/compare_html.ex` (stylesheet; the speaker label through `NoteMarkup.inline/3`)
- Test: `test/playcode_web/controllers/export_controller_test.exs`; the comparison download's test (find it with `grep -rn "compare" test/playcode_web`)

**Interfaces:**
- Consumes: `InlineMarkup.folio_labels/1`, the `:folio` key.
- Produces: in the HTML (and so PDF) and EPUB downloads and the comparison download, a passage's words in `<span class="folio">`, its labels `<sup class="folio">F</sup>`, `.folio { color: #666; }`.

- [ ] **Step 1: Write the failing tests**

In `export_controller_test.exs`, beside the variants test:

```elixir
  # The downloads have no switch, so they print Hamlet's Folio passages, in grey between
  # their F's, rather than lose them (question 38).
  test "the HTML and EPUB downloads print a Folio passage in grey between its F's", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>HAMLET</speaker><l n="316">O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O</rdg></app> God,</l></sp></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    assert html =~ ~s(O God, <sup class="folio">F</sup><span class="folio">O</span><sup class="folio">F</sup> God,)
    assert html =~ ".folio {"

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)
    assert epub =~ ~s(<span class="folio">O</span>)
  end
```

For the comparison download, a pair whose first play holds `<speaker><code>&lt;span class="folio"&gt;</code><code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>guildenstern<code>&lt;/span&gt;</code></speaker>` and a line closing the passage: the download holds `<span class="folio">guildenstern</span>` in its speaker div, and no `&lt;folio`.

- [ ] **Step 2: Run them and watch them fail**

Expected: FAIL — the words are printed as plain text, the speaker label with its tags escaped.

- [ ] **Step 3: Implement**

`NoteMarkup.inline/3`: `text |> InlineMarkup.parts(notes) |> InlineMarkup.folio_labels() |> Enum.map_join(&part(&1, format))`, and first among the `part/2` clauses:

```elixir
  # Hamlet's Folio passages, which the downloads print, having no switch: in grey, between
  # their F's (question 38).
  defp part(%{label: label}, _format), do: ~s(<sup class="folio">#{escape(label)}</sup>)

  defp part(%{folio: _} = part, format),
    do: ~s(<span class="folio">) <> part(Map.delete(part, :folio), format) <> "</span>"
```

The stylesheets of `Html`, `Epub` and `CompareHtml`: `.folio { color: #666; }`. `CompareHtml`'s speaker label: `NoteMarkup.inline(el.speaker_label, [], :html)` in place of `escape(el.speaker_label)` (it holds `<<…>>` italics too, which it printed as text). Update the moduledoc of `NoteMarkup`.

`PdfCache`'s key already holds `Html`, `NoteMarkup` and `InlineMarkup`; nothing to add.

- [ ] **Step 4: Run the tests and watch them pass; prove they bite (drop `folio_labels/1` from `inline/3`); refactor while green; the whole suite; commit**

```bash
git commit -m "feat(downloads): Folio passages printed in grey between their F's"
```

---

### Task 7: The editor's hint, the docs, and the questions for the project

**Files:**
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (the hints of the verse line, prose and stage direction forms)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`
- Modify (docs): `CLAUDE.md`, `CONTEXT.md`, `docs/backlog.md`, `docs/history.md`, `docs/tei-apparatus-and-code.md`, `docs/static-site.md`, `docs/stakeholder/ida-y-vuelta.html`, `docs/stakeholder/preguntas.html`, the spec's status line

- [ ] **Step 1: The hint (red, green, refactor)**

In the test "the verse form says how to mark one", add `assert has_element?(lv, "#element-form", t("Words only the Folio prints: <folio>…</folio>"))`; run it red; add `<p class="mt-1 text-xs text-base-content/70">{gettext("Words only the Folio prints: <folio>…</folio>")}</p>` after the aside hint in the verse line and prose forms (and in the stage direction form, if it has hints of its own); Spanish `"Palabras que solo imprime el Folio: <folio>…</folio>"`; run green.

- [ ] **Step 2: The docs**

- `CLAUDE.md`, the `play_elements.content` bullet: one sentence: a passage only the Folio prints is `<folio>…</folio>`, `part="I|M|F"` when it crosses elements, in a line's, paragraph's or stage direction's text or a speech's speaker label, read from Hamlet's `<code>` marks or `<app type="folio">`, written back as the `<app>` or, across elements, the file's marks (question 37). *TEI-XML Format*: an `app[@type="folio"]` line and the `<code>` marks line. Keep the file's terse style; change nothing else.
- `CONTEXT.md`: "Folio passage" (the words only the Folio prints, hidden by default, Hamlet only) beside "textual variant".
- `docs/backlog.md`: the `<code>` item: Hamlet's passages built; left: the Additions (question 37) and the crossing passages' TEI form (question 37); a Q2-only statistics item; the "unknown `<code>` string refused" item stays. *Production rollout*: EMOTHE0010 is re-imported with the six apparatus plays, and the first Generate after it rebuilds the whole site.
- `docs/history.md`: the project, its counts (132 passages, 119 + 13), the three slips, the commits.
- `docs/tei-apparatus-and-code.md`: under the Hamlet bullet, built 2026-10-16, how it is stored and written back; the working order.
- `docs/static-site.md`: the `fo` toggle, off by default.
- `docs/stakeholder/ida-y-vuelta.html`: the "HTML typed into the text" row and note 24 (Hamlet's passages read, shown behind a switch, written back; the Additions wait on 37).
- `docs/stakeholder/preguntas.html`: question 36's answered box gets "Built on 16 October 2026: …"; **question 38**, at the end, *Decided by Playcode on 16 October 2026*: "The downloads (HTML, PDF, EPUB) have no switch, so they print Hamlet's Folio passages, in grey between their F's, rather than lose them", with "Change this answer" and options (print them in grey between their F's / leave them out, as the page does by default / not sure); **question 39**, open, for Hamlet's editor: v. 3315 reads `Oh!<sup>and</sup>`: is the Folio passage "Oh! and", or "Oh!" with its closing F mistyped as "and"? Playcode reads "Oh! and" until told; the two span slips (vv. 3057, 1322) need no answer. Both under the "HTML typed into the text" topic (its TOC numbers become "5–8, 36–39"), the meta "39 questions, 19 of them answered (nine decided by Playcode)". Keep the page's markup balanced (`python3 -c` with `html.parser`, as before).
- The spec's status: "implemented 2026-10-16 (commits …)".

- [ ] **Step 3: The whole suite, the slow suite, commit**

`mix format`, `mix test`, `mix test --include slow` (needs `doc/tei_corpus/`), `mix compile --warnings-as-errors`, `node --test test/js/*.test.mjs`, `mix test test/rename_guard_test.exs`.

```bash
git commit -m "docs: Hamlet's Folio passages are read, shown behind a switch and written back"
```

---

## Rollout (after the merge, each step with the owner's go-ahead)

1. Push `main`; CI and the Fly deploy follow.
2. Re-import EMOTHE0010 on production with the six apparatus plays (`docs/production-reimport.md`), then Generate: the first build after it rebuilds the whole site (the renderers changed).
3. Republish the Questions and Round Trip pages (the memory recipe).
