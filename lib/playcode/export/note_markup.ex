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
      Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
        PlayLabels.note_type_label(note.type)
      end)

    term = if note.term, do: " <i>#{inline(note.term, [], :html)}</i>", else: ""
    paragraphs = Enum.map_join(Note.paragraphs(note), &"<p>#{inline(&1, [], :html)}</p>")
    "<p><b>#{prefix}#{escape(label)}</b>#{term}</p>#{paragraphs}"
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
