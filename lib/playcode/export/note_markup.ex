defmodule Playcode.Export.NoteMarkup do
  @moduledoc """
  A line's text as HTML for the HTML (and so PDF) and EPUB downloads: italics as `<em>`,
  an inline stage direction as `<span class="stage">`, each of Hamlet's Folio passages as a
  `<span class="folio">` between two `<sup class="folio">F</sup>`, each in-text note as a
  reference to its endnote and each variant as an asterisk to its entry, and an act's notes
  as endnotes, its variants after them. The downloads have no Folio switch, so they always
  print the passages, in grey (question 38).
  `:html` links a superscript number or asterisk to its endnote or entry and back; `:epub`
  marks them `noteref` and `footnote`, which e-readers show as pop-ups. The labels are English, as
  the rest of the downloads are. `readings/2` prints a variant's readings, for the play
  page and the site as well.
  """

  alias Playcode.PlayContent.{InlineMarkup, Note}
  alias PlaycodeWeb.PlayLabels

  @doc """
  `text`, with `<<…>>` italics as `<em>`, each inline stage direction in a `<span class="stage">`
  (a note's number inside it when the note falls inside the stage), and its `notes`, as escaped HTML;
  each line break a `<br>` (`<br/>` in the EPUB), each printed line's number a `span.pn`, and
  each Folio passage's words a `span.folio` between its F's.
  """
  def inline(text, notes, format) do
    text
    |> InlineMarkup.parts(notes)
    |> InlineMarkup.folio_labels()
    |> Enum.map_join(&part(&1, format))
  end

  # A piece of an inline stage direction, a note's number among them.
  defp part(%{stage: %{}} = part, format),
    do: ~s(<span class="stage">) <> part(%{part | stage: nil}, format) <> "</span>"

  # Hamlet's Folio passages: an F where one starts and ends, and its words, in grey. Inside
  # a stage direction these come after the stage's own clause, so the stage's span wraps
  # them, as on the play page and the site.
  defp part(%{label: label}, _format), do: ~s(<sup class="folio">#{escape(label)}</sup>)

  defp part(%{folio: _} = part, format),
    do: ~s(<span class="folio">) <> part(Map.delete(part, :folio), format) <> "</span>"

  defp part(%{note: note}, format), do: ref(note, Note.variant?(note), format)

  defp part(%{number: n}, _format), do: ~s(<span class="pn">#{escape(n)}</span>)
  defp part(%{italic: true, text: text}, format), do: "<em>#{breaks(text, format)}</em>"
  defp part(%{text: text}, format), do: breaks(text, format)

  defp ref(%{number: n}, false, :html),
    do: ~s(<sup class="nref"><a id="ref-#{n}" href="#note-#{n}">#{n}</a></sup>)

  defp ref(%{number: n}, false, :epub),
    do: ~s(<sup><a epub:type="noteref" href="#note-#{n}">#{n}</a></sup>)

  defp ref(%{number: n}, true, :html),
    do:
      ~s(<sup class="vref"><a id="vref-#{n}" href="#var-#{n}" aria-label="Textual variant #{n}">*</a></sup>)

  defp ref(%{number: n}, true, :epub),
    do: ~s(<sup><a epub:type="noteref" href="#var-#{n}">*</a></sup>)

  # A line break: the EPUB is XHTML.
  defp breaks(text, :epub), do: text |> escape() |> String.replace("\n", "<br/>")
  defp breaks(text, :html), do: text |> escape() |> String.replace("\n", "<br>")

  @doc """
  An act's `notes` as endnotes, its variants (`Note.variant?/1`) after them: for `:html` an
  `<ol>` section and a "Variants" list, for `:epub` footnote asides.
  """
  def endnotes(notes, format) do
    {variants, notes} = Enum.split_with(notes, &Note.variant?/1)
    numbered(notes, format) <> variants(variants, format)
  end

  defp numbered([], _format), do: ""

  defp numbered(notes, :html) do
    items =
      Enum.map_join(notes, "\n", fn note ->
        ~s(<li id="note-#{note.number}" value="#{note.number}">#{body(note, "", :html)}) <>
          ~s( <a href="#ref-#{note.number}" aria-label="Back to the text">↩</a></li>)
      end)

    ~s(<section class="notes"><ol>\n#{items}\n</ol></section>\n)
  end

  defp numbered(notes, :epub) do
    Enum.map_join(notes, "", fn note ->
      ~s(<aside epub:type="footnote" id="note-#{note.number}">#{body(note, "#{note.number}. ", :epub)}</aside>\n)
    end)
  end

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

  @doc """
  A variant's readings as HTML paragraphs, one per reading in order: each siglum in italics
  followed by what it names in parentheses (`Note.Reading`, `sigla`), the reading, and the
  reading's own note in parentheses (a reading with nothing in it prints none); then the
  entry's own note. The play page, the site and the downloads print a variant so.
  """
  def readings(note, format) do
    readings = for reading <- note.readings, text = reading(reading, format), text != "", do: text

    Enum.map_join(readings, &"<p>#{&1}</p>") <>
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

  defp body(note, prefix, format) do
    label =
      Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
        PlayLabels.note_type_label(note.type)
      end)

    term = if note.term, do: " <i>#{inline(note.term, [], format)}</i>", else: ""
    paragraphs = Enum.map_join(Note.paragraphs(note), &"<p>#{inline(&1, [], format)}</p>")
    "<p><b>#{prefix}#{escape(label)}</b>#{term}</p>#{paragraphs}"
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
