defmodule Playcode.Export.Epub do
  @moduledoc """
  Generates an EPUB 3 ebook from a play record using the BUPE library.
  Reuses rendering patterns from `Playcode.Export.Html`.
  """

  alias Playcode.Export.{Html, NoteMarkup}
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{InlineMarkup, Note}
  alias PlaycodeWeb.PlayLabels

  @act_types ~w(acto act acte jornada)

  def generate(play) do
    play = Playcode.Repo.preload(play, [:editors, :sources, :paratexts])
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)
    {front, scene, back} = PlayLabels.split_paratexts(play.paratexts, divisions)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "playcode_epub_#{play.id}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    try do
      # Write CSS
      css_path = Path.join(tmp_dir, "style.css")
      File.write!(css_path, css())

      # Front matter: title, author, sources, editors, paratexts, cast list
      front_path =
        write_chapter(
          tmp_dir,
          "front",
          play.title,
          play.language,
          render_front(play, characters, front, scene)
        )

      # One chapter per top-level division
      chapter_entries =
        divisions
        |> Enum.with_index(1)
        |> Enum.map(fn {div, i} ->
          filename = "chapter-#{String.pad_leading("#{i}", 3, "0")}"
          title = if div.title, do: InlineMarkup.plain(div.title), else: "#{div.type} #{i}"

          path =
            write_chapter(
              tmp_dir,
              filename,
              title,
              play.language,
              render_division(div, characters)
            )

          {path, title}
        end)

      # One chapter per paratext after the text, named by its heading or its kind
      back_entries =
        back
        |> Enum.with_index(1)
        |> Enum.map(fn {paratext, i} ->
          title = PlayLabels.paratext_title(paratext)
          filename = "back-#{String.pad_leading("#{i}", 3, "0")}"

          {write_chapter(tmp_dir, filename, title, play.language, render_paratexts([paratext])),
           title}
        end)

      all_pages =
        [{front_path, play.title} | chapter_entries ++ back_entries]
        |> Enum.map(fn {path, title} ->
          %BUPE.Item{
            href: path,
            id: Path.basename(path, ".xhtml"),
            description: title
          }
        end)

      config =
        BUPE.Config.new(%{
          title: play.title,
          creator: play.author_name || "",
          language: play.language || "es",
          publisher: publisher_from(play),
          identifier: "urn:playcode:#{play.code}",
          unique_identifier: "EMOTHE",
          rights: play.licence_text || play.licence_url,
          description: play.original_title,
          date: play.publication_date,
          pages: all_pages,
          styles: [css_path],
          cover: false
        })

      output_path = Path.join(tmp_dir, "#{play.code}.epub")

      case BUPE.build(config, output_path, [:memory]) do
        {:ok, {_name, binary}} -> {:ok, binary}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp write_chapter(tmp_dir, filename, title, language, body_html) do
    lang = language || "es"

    xhtml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="#{lang}" lang="#{lang}">
    <head>
      <meta charset="utf-8"/>
      <title>#{escape(title)}</title>
      <link type="text/css" rel="stylesheet" href="style.css"/>
    </head>
    <body>
    #{body_html}
    </body>
    </html>
    """

    path = Path.join(tmp_dir, "#{filename}.xhtml")
    File.write!(path, xhtml)
    path
  end

  defp publisher_from(play) do
    case play.sources do
      [source | _] -> source.publisher
      _ -> nil
    end
  end

  # --- Front matter ---

  defp render_front(play, characters, front, scene) do
    """
    <div class="header">
      <p class="author">#{escape(play.author_name || "")}</p>
      <h1 class="title">#{escape(play.title)}</h1>
    #{render_sources(play.sources)}
    #{render_editors(play.editors)}
    #{render_verse_info(play)}
    #{render_dating(play)}
    </div>
    #{render_paratexts(front)}
    #{render_cast_list(characters)}
    #{render_paratexts(scene)}
    """
  end

  defp render_sources(sources) do
    sources
    |> Enum.map(fn s ->
      if s.note,
        do: "  <p class=\"source-note\">#{NoteMarkup.inline(s.note, [], :epub)}</p>",
        else: ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp render_dating(play),
    do: play |> Html.dating() |> Enum.map_join("\n", &"  <p class=\"dating\">#{escape(&1)}</p>")

  defp render_editors([]), do: ""

  defp render_editors(editors) do
    items =
      Enum.map(editors, fn ed ->
        "    <span>#{escape(ed.person_name)} <span class=\"role\">(#{escape(ed.role)})</span></span>"
      end)
      |> Enum.join("\n")

    "  <div class=\"editors\">\n#{items}\n  </div>"
  end

  defp render_verse_info(play) do
    cond do
      play.verse_count && play.is_verse ->
        "  <p class=\"verse-info\">#{play.verse_count} verses</p>"

      play.verse_count ->
        "  <p class=\"verse-info\">Prose</p>"

      true ->
        ""
    end
  end

  # Each paragraph a <p>; NoteMarkup turns each line break into a <br/>, inside the
  # italics too: an EPUB reader need not honour white-space: pre-line.
  defp paratext_paragraphs(content) do
    for paragraph <- String.split(content || "", "\n\n", trim: true), into: "" do
      "  <p>#{NoteMarkup.inline(paragraph, [], :epub)}</p>\n"
    end
  end

  defp render_paratexts(paratexts) do
    paratexts
    |> Enum.map(fn paratext ->
      heading =
        if paratext.heading,
          do: "  <h3>#{NoteMarkup.inline(paratext.heading, [], :epub)}</h3>\n",
          else: ""

      "<div class=\"paratext\">\n#{heading}#{paratext_paragraphs(paratext.content)}</div>"
    end)
    |> Enum.join("\n<hr class=\"paratext-sep\"/>\n")
  end

  defp render_cast_list(characters) do
    visible = Enum.reject(characters, & &1.is_hidden)
    if visible == [], do: "", else: do_render_cast_list(visible)
  end

  defp do_render_cast_list(characters) do
    items =
      Enum.map(characters, fn char ->
        desc =
          if char.description,
            do:
              " <span class=\"cast-desc\">#{NoteMarkup.inline(char.description, [], :epub)}</span>",
            else: ""

        "  <div class=\"cast-item\"><span class=\"cast-name\">#{NoteMarkup.inline(char.name, [], :epub)}</span>#{desc}</div>"
      end)
      |> Enum.join("\n")

    "<div class=\"cast-list\">\n#{items}\n</div>"
  end

  # --- Division rendering ---

  defp render_division(div, characters) do
    heading = division_heading(div)

    cast =
      if div.type == "elenco",
        do: render_cast_list(characters),
        else: ""

    elements = render_elements(Map.get(div, :loaded_elements, []))

    children =
      Map.get(div, :children, [])
      |> Enum.map(fn child ->
        ch = child_heading(child)
        ce = render_elements(Map.get(child, :loaded_elements, []))
        "<div class=\"child-division\">\n#{ch}#{ce}</div>"
      end)
      |> Enum.join("\n")

    notes = NoteMarkup.endnotes(Note.reading_order(div), :epub)

    "<div class=\"division\">\n#{heading}#{cast}#{elements}#{children}\n#{notes}</div>"
  end

  defp division_heading(%{title: nil}), do: ""
  defp division_heading(%{title: ""}), do: ""

  defp division_heading(%{title: title, type: type} = div) when type in @act_types do
    "<h2 class=\"act-heading\">#{NoteMarkup.inline(title, div.notes, :epub)}</h2>\n"
  end

  defp division_heading(%{title: title} = div) do
    "<h3 class=\"scene-heading\">#{NoteMarkup.inline(title, div.notes, :epub)}</h3>\n"
  end

  defp child_heading(%{title: nil}), do: ""
  defp child_heading(%{title: ""}), do: ""

  defp child_heading(%{title: title} = div),
    do: "<h3 class=\"scene-heading\">#{NoteMarkup.inline(title, div.notes, :epub)}</h3>\n"

  defp render_elements(elements) do
    Enum.map(elements, &render_element/1) |> Enum.join()
  end

  defp render_element(%{type: "speech"} = el) do
    aside_class = if el.is_aside, do: " aside", else: ""

    speaker =
      if el.speaker_label,
        do:
          "<div class=\"speaker\">#{NoteMarkup.inline(el.speaker_label, el.notes, :epub)}</div>\n",
        else: ""

    children = Map.get(el, :children, []) |> Enum.map(&render_element/1) |> Enum.join()
    "<div class=\"speech#{aside_class}\">\n#{speaker}#{children}</div>\n"
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

    "<div class=\"verse-line\"><span class=\"#{content_class}\">#{NoteMarkup.inline(el.content, el.notes, :epub)}</span>#{line_num}</div>\n"
  end

  defp render_element(%{type: "stage_direction"} = el) do
    "<div class=\"stage-direction\">(#{NoteMarkup.inline(el.content, el.notes, :epub)})</div>\n"
  end

  defp render_element(%{type: "prose"} = el) do
    "<div class=\"prose-block\">#{NoteMarkup.inline(el.content, el.notes, :epub)}</div>\n"
  end

  defp render_element(%{type: "trailer"} = el) do
    "<div class=\"trailer\">#{NoteMarkup.inline(el.content, el.notes, :epub)}</div>\n"
  end

  defp render_element(_), do: ""

  # --- CSS (adapted from Html export for EPUB readers) ---

  defp css do
    """
    * { margin: 0; padding: 0; box-sizing: border-box; }

    nav ol { list-style-type: none; padding-left: 0; }

    body {
      font-family: Georgia, "Times New Roman", Times, serif;
      line-height: 160%;
      color: #333;
    }

    .header {
      text-align: center;
      font-family: Georgia, "Times New Roman", Times, serif;
      border-bottom: 1px solid #ddd;
      padding-bottom: 1.5em;
      margin-bottom: 2em;
    }

    .header .author {
      font-size: 1.1em;
      color: #7E7B6A;
    }

    .header .title {
      font-size: 1.3em;
      font-weight: bold;
      text-transform: uppercase;
    }

    .header .source-note {
      margin-top: 1em;
      font-size: 0.75em;
      color: rgba(51, 51, 51, 0.5);
      font-style: italic;
    }

    .header .editors {
      margin-top: 0.75em;
      font-size: 0.75em;
      color: rgba(51, 51, 51, 0.5);
    }

    .header .editors .role {
      color: rgba(51, 51, 51, 0.35);
    }

    .header .verse-info,
    .header .dating {
      margin-top: 0.5em;
      font-size: 0.75em;
      color: rgba(51, 51, 51, 0.5);
    }

    .paratext {
      margin: 0 auto 1.5em;
      text-align: justify;
      font-size: 0.875em;
    }

    .paratext h3 {
      font-weight: bold;
      text-align: center;
      margin-bottom: 0.5em;
    }

    .paratext-sep {
      margin: 0 auto 1.5em;
      border: none;
      border-top: 1px solid #e5e7eb;
    }

    .cast-list {
      margin: 0 auto 1.5em;
    }

    .cast-item {
      padding: 0.25em 0;
      margin-left: 1em;
    }

    .cast-name {
      font-weight: bold;
      font-size: 0.8em;
      text-transform: uppercase;
    }

    .cast-desc { font-size: 0.875em; color: rgba(51, 51, 51, 0.55); }

    .act-heading {
      font-weight: bold;
      text-align: center;
      font-size: 1.125em;
      margin: 1.5em 0;
    }

    .scene-heading {
      font-weight: bold;
      text-align: center;
      font-size: 0.875em;
      margin: 1em 0;
    }

    .speech {
      margin-top: 0.5em;
      margin-bottom: 1.25em;
    }

    .speech.aside {
      padding-left: 2em;
      border-left: 2px solid #ccc;
    }

    .speaker {
      font-weight: bold;
      font-size: 0.8em;
      text-transform: uppercase;
      color: #333;
      margin-bottom: 0.125em;
    }

    .verse-line {
      margin-left: 1em;
    }

    .verse-line .content { display: inline; }
    .verse-line .content.indent { padding-left: 2em; }
    .verse-line .content.part-m { padding-left: 50px; }
    .verse-line .content.part-f { padding-left: 100px; }

    .line-number {
      font-size: 0.7em;
      color: #999;
      margin-left: 0.5em;
    }
    .pn {
      font-size: 0.7em;
      color: #999;
      vertical-align: super;
      padding-right: 0.2em;
    }

    .stage-direction {
      text-align: center;
      font-style: italic;
      color: #555;
      margin: 0.75em 2em;
    }

    .stage { font-style: italic; color: #555; }

    .trailer { text-align: center; margin: 1.5em 0 0.5em; }

    .prose-block {
      margin-left: 1em;
      margin-bottom: 0.5em;
      text-align: justify;
    }

    .division { margin-bottom: 2em; }
    .child-division { margin-bottom: 1.5em; }

    aside { font-size: 0.9em; }
    sup a { text-decoration: none; }
    """
  end

  # --- Escaping ---

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
