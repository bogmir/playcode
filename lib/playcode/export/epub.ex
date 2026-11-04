defmodule Playcode.Export.Epub do
  @moduledoc """
  Generates an EPUB 3 ebook from a play record using the BUPE library: the front matter
  and one chapter per outline item from the text on, each as `Export.Download` prints it.
  """

  alias Playcode.Catalogue.Paratext
  alias Playcode.Export.Download
  alias Playcode.Outline
  alias Playcode.PlayContent.InlineMarkup
  alias PlaycodeWeb.PlayLabels

  def generate(play) do
    {play, divisions} = Download.load(play)

    {front, rest} =
      play.paratexts
      |> Outline.items(divisions)
      |> Outline.placement()
      |> Enum.split_with(&match?({:front, _}, &1))

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

      # Front matter: title, author, sources, editors, and the outline's items before the
      # text
      front_path =
        write_chapter(
          tmp_dir,
          "front",
          play.title,
          play.language,
          render_front(play, divisions, Enum.map(front, &elem(&1, 1)))
        )

      # One chapter per item from the first division of the text on, in outline order
      chapter_entries =
        rest
        |> Enum.with_index(1)
        |> Enum.map(fn {{_placement, item}, i} ->
          filename = "chapter-#{String.pad_leading("#{i}", 3, "0")}"
          title = chapter_title(item, i)

          {write_chapter(tmp_dir, filename, title, play.language, Download.item(item, :epub)),
           title}
        end)

      all_pages =
        [{front_path, play.title} | chapter_entries]
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

  defp render_front(play, divisions, items) do
    Download.front(play, divisions, :epub) <>
      Enum.map_join(items, "\n", &Download.item(&1, :epub))
  end

  defp chapter_title(%Paratext{} = paratext, _index), do: PlayLabels.paratext_title(paratext)

  defp chapter_title(%{title: title}, _index) when title not in [nil, ""],
    do: InlineMarkup.plain(title)

  defp chapter_title(%{type: "elenco"}, _index), do: "Dramatis personae"
  defp chapter_title(div, index), do: "#{div.type} #{index}"

  # --- CSS (adapted from Html export for EPUB readers) ---

  defp css do
    """
    * { margin: 0; padding: 0; box-sizing: border-box; }

    header, section, aside { display: block; }

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

    .header .original,
    .header .verse-info,
    .header .dating {
      margin-top: 0.5em;
      font-size: 0.75em;
      color: rgba(51, 51, 51, 0.5);
    }

    .publication { margin: 0 auto 2em; font-size: 0.75em; color: rgba(51, 51, 51, 0.5); text-align: justify; }
    .publication p + p { margin-top: 0.4em; }

    .edition-notes { margin: 0 auto 2em; font-size: 0.8em; text-align: justify; }
    .edition-notes h3 { font-size: 0.875em; text-align: center; margin-bottom: 0.5em; }
    .edition-notes p + p { margin-top: 0.4em; }

    .witnesses { margin: 0 auto 2em; font-size: 0.8em; }
    .witnesses h2 { font-size: 0.875em; text-align: center; margin-bottom: 0.5em; }
    .witnesses ul { list-style: none; }
    .witnesses li { padding-left: 1.5em; text-indent: -1.5em; margin-bottom: 0.25em; }

    .paratext {
      margin: 0 auto 1.5em;
      text-align: justify;
      font-size: 0.875em;
    }

    .paratext p + p { margin-top: 0.75em; }

    .paratext h3 {
      font-weight: bold;
      text-align: center;
      margin-bottom: 0.5em;
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

    .cast-group { font-weight: bold; font-size: 0.875em; margin: 0.5em 0 0 1em; }

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
    .ghost { visibility: hidden; }
    .ghost.indent { padding-left: 2em; }

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

    /* Hamlet's Folio passages: in grey, between their F's */
    .folio { color: #666; }
    sup.folio { font-size: 0.7em; line-height: 0; }

    .trailer { text-align: center; font-style: italic; margin: 1.5em 0 0.5em; }
    .trailer em { font-style: normal; }

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
