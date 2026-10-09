defmodule Playcode.Export.Html do
  @moduledoc """
  Generates a standalone HTML document for a play,
  styled to match the public play presentation page.
  """

  alias Playcode.Export.NoteMarkup
  alias Playcode.PlayContent
  alias Playcode.PlayContent.Note

  def generate(play) do
    play = Playcode.Repo.preload(play, [:editors, :sources, :editorial_notes])
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)

    """
    <!DOCTYPE html>
    <html lang="#{play.language || "es"}">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{escape(play.title)} — #{escape(play.author_name || "")}</title>
      <style>
    #{css()}
      </style>
    </head>
    <body>
      <div class="page">
        <header class="header">
          <p class="author">#{escape(play.author_name || "")}</p>
          <h1 class="title">#{escape(play.title)}</h1>
    #{render_sources(play.sources)}
    #{render_editors(play.editors)}
    #{render_verse_info(play)}
        </header>

    #{render_editorial_notes(play.editorial_notes)}

        <div class="play-text">
    #{render_divisions(divisions, characters)}
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp css do
    ~s"""
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
          background-color: #faf5ee;
          font-family: Verdana, Geneva, sans-serif;
          line-height: 160%;
          color: #333;
        }

        .page {
          max-width: 800px;
          margin: 0 auto;
          padding: 2rem 1.5rem;
        }

        /* Header — matches .play-header on the site */
        .header {
          text-align: center;
          font-family: Georgia, "Times New Roman", Times, serif;
          border-bottom: 1px solid #ddd;
          padding-bottom: 1.5rem;
          margin-bottom: 2rem;
        }

        .header .author {
          font-size: 17px;
          color: #7E7B6A;
        }

        .header .title {
          font-size: 20px;
          font-weight: bold;
          text-transform: uppercase;
        }

        .header .source-note {
          margin-top: 1rem;
          font-size: 0.75rem;
          color: rgba(51, 51, 51, 0.5);
          font-style: italic;
        }

        .header .editors {
          margin-top: 0.75rem;
          font-size: 0.75rem;
          color: rgba(51, 51, 51, 0.5);
        }

        .header .editors .role {
          color: rgba(51, 51, 51, 0.35);
        }

        .header .verse-info {
          margin-top: 0.5rem;
          font-size: 0.75rem;
          color: rgba(51, 51, 51, 0.5);
        }

        /* Editorial notes */
        .editorial-note {
          max-width: 640px;
          margin: 0 auto 1.5rem;
          text-align: justify;
          font-size: 0.875rem;
          white-space: pre-line;
        }

        .editorial-note h3 {
          font-weight: bold;
          text-align: center;
          margin-bottom: 0.5rem;
        }

        .editorial-note-sep {
          max-width: 640px;
          margin: 0 auto 1.5rem;
          border: none;
          border-top: 1px solid #e5e7eb;
        }

        /* Cast list (inline within elenco division) */
        .cast-list {
          max-width: 560px;
          margin: 0 auto 1.5rem;
        }

        .cast-item {
          display: flex;
          align-items: baseline;
          gap: 0.75rem;
          padding: 0.25rem 0;
          margin-left: 1rem;
        }

        .cast-name {
          font-weight: bold;
          font-size: x-small;
          text-transform: uppercase;
          flex-shrink: 0;
        }

        .cast-desc { font-size: 0.875rem; color: rgba(51, 51, 51, 0.55); }

        /* Division headings */
        .act-heading {
          font-weight: bold;
          text-align: center;
          font-size: 1.125rem;
          margin: 1.5rem 0;
        }

        .scene-heading {
          font-weight: bold;
          text-align: center;
          font-size: 0.875rem;
          margin: 1rem 0;
        }

        /* Speech blocks */
        .speech {
          margin-top: 0.5rem;
          margin-bottom: 1.25rem;
        }

        .speech.aside {
          padding-left: 2rem;
          border-left: 2px solid #ccc;
        }

        .speaker {
          font-weight: bold;
          font-size: x-small;
          text-transform: uppercase;
          color: #333;
          margin-bottom: 0.125rem;
        }

        /* Verse lines — content left, line number right */
        .verse-line {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
          margin-left: 1rem;
        }

        .verse-line .content { flex: 1; }
        .verse-line .content.indent { padding-left: 2rem; }
        .verse-line .content.part-m { padding-left: 50px; }
        .verse-line .content.part-f { padding-left: 100px; }

        .line-number {
          width: 2rem;
          text-align: left;
          flex-shrink: 0;
          font-size: x-small;
          color: #999;
          font-variant-numeric: tabular-nums;
          user-select: none;
        }

        /* Stage directions */
        .stage-direction {
          text-align: center;
          font-style: italic;
          color: #555;
          margin: 0.75rem 2rem;
        }

        /* Prose */
        .prose-block {
          margin-left: 1rem;
          margin-bottom: 0.5rem;
          text-align: justify;
        }

        .division { margin-bottom: 2rem; }
        .child-division { margin-bottom: 1.5rem; }

        /* A stage direction inside a line */
        .stage { font-style: italic; color: #555; }

        /* In-text notes: a number after the word, the act's notes listed after it */
        .nref { font-size: 0.7em; line-height: 0; }
        .nref a { text-decoration: none; }
        .notes { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #ddd; font-size: 0.9rem; }
        .notes li p { margin: 0.3rem 0; }

        @media print {
          body { background: white; }
          .page { max-width: 100%; padding: 0.5rem 0; }
          .header { border-bottom-color: #ccc; }
          .act-heading { page-break-before: always; }
          .speech { break-inside: avoid; }
          .verse-line { break-inside: avoid; }
          .cast-item { break-inside: avoid; }
        }
    """
  end

  defp render_sources(sources) do
    sources
    |> Enum.map(fn s ->
      if s.note,
        do: "      <p class=\"source-note\">#{escape(s.note)}</p>",
        else: ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_editors([]), do: ""

  defp render_editors(editors) do
    items =
      Enum.map(editors, fn ed ->
        "        <span>#{escape(ed.person_name)} <span class=\"role\">(#{escape(ed.role)})</span></span>"
      end)
      |> Enum.join("\n")

    "      <div class=\"editors\">\n#{items}\n      </div>"
  end

  defp render_verse_info(play) do
    cond do
      play.verse_count && play.is_verse ->
        "      <p class=\"verse-info\">#{play.verse_count} verses</p>"

      play.verse_count ->
        "      <p class=\"verse-info\">Prose</p>"

      true ->
        ""
    end
  end

  defp render_editorial_notes(notes) do
    notes
    |> Enum.map(fn note ->
      heading = if note.heading, do: "      <h3>#{escape(note.heading)}</h3>\n", else: ""

      "    <div class=\"editorial-note\">\n#{heading}      <div>#{escape(note.content)}</div>\n    </div>"
    end)
    |> Enum.join("\n    <hr class=\"editorial-note-sep\">\n")
  end

  defp render_inline_cast_list(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)
    if visible == [], do: "", else: do_render_inline_cast_list(visible)
  end

  defp do_render_inline_cast_list(characters) do
    items =
      Enum.map(characters, fn char ->
        desc =
          if char.description,
            do: " <span class=\"cast-desc\">#{escape(char.description)}</span>",
            else: ""

        "          <div class=\"cast-item\"><span class=\"cast-name\">#{escape(char.name)}</span>#{desc}</div>"
      end)
      |> Enum.join("\n")

    """
          <div class="cast-list">
    #{items}
          </div>
    """
  end

  @act_types ~w(acto act acte jornada)

  defp render_divisions(divisions, characters) do
    Enum.map(divisions, fn div ->
      heading = division_heading(div)

      # Render inline cast list for elenco divisions
      cast =
        if div.type == "elenco",
          do: render_inline_cast_list(characters),
          else: ""

      elements = render_elements(Map.get(div, :loaded_elements, []))

      children =
        Map.get(div, :children, [])
        |> Enum.map(fn child ->
          ch = child_heading(child)
          ce = render_elements(Map.get(child, :loaded_elements, []))
          "      <div class=\"child-division\">\n#{ch}#{ce}      </div>"
        end)
        |> Enum.join("\n")

      notes = NoteMarkup.endnotes(Note.reading_order(div), :html)

      "    <div class=\"division\">\n#{heading}#{cast}#{elements}#{children}\n#{notes}    </div>"
    end)
    |> Enum.join("\n")
  end

  defp division_heading(%{title: nil}), do: ""
  defp division_heading(%{title: ""}), do: ""

  defp division_heading(%{title: title, type: type} = div) when type in @act_types do
    "      <h2 class=\"act-heading\">#{NoteMarkup.inline(title, div.notes, :html)}</h2>\n"
  end

  defp division_heading(%{title: title} = div) do
    "      <h3 class=\"scene-heading\">#{NoteMarkup.inline(title, div.notes, :html)}</h3>\n"
  end

  defp child_heading(%{title: nil}), do: ""
  defp child_heading(%{title: ""}), do: ""

  defp child_heading(%{title: title} = div),
    do: "        <h3 class=\"scene-heading\">#{NoteMarkup.inline(title, div.notes, :html)}</h3>\n"

  defp render_elements(elements) do
    Enum.map(elements, &render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "speech"} = el) do
    aside_class = if el.is_aside, do: " aside", else: ""

    speaker =
      if el.speaker_label,
        do:
          "        <div class=\"speaker\">#{NoteMarkup.inline(el.speaker_label, el.notes, :html)}</div>\n",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
    "      <div class=\"speech#{aside_class}\">\n#{speaker}#{children}      </div>\n"
  end

  defp render_element(%{type: "line_group"} = el) do
    Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "verse_line"} = el) do
    content_class =
      cond do
        el.rend == "indent" -> "content indent"
        el.part == "F" -> "content part-f"
        el.part == "M" -> "content part-m"
        true -> "content"
      end

    line_num =
      if el.line_number,
        do: "<span class=\"line-number\">#{el.line_number}</span>",
        else: "<span class=\"line-number\"></span>"

    "        <div class=\"verse-line\"><span class=\"#{content_class}\">#{NoteMarkup.inline(el.content, el.notes, :html)}</span>#{line_num}</div>\n"
  end

  defp render_element(%{type: "stage_direction"} = el) do
    "        <div class=\"stage-direction\">(#{NoteMarkup.inline(el.content, el.notes, :html)})</div>\n"
  end

  defp render_element(%{type: "prose"} = el) do
    "        <div class=\"prose-block\">#{NoteMarkup.inline(el.content, el.notes, :html)}</div>\n"
  end

  defp render_element(_), do: ""

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
