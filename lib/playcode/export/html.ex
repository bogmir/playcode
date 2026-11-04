defmodule Playcode.Export.Html do
  @moduledoc """
  Generates a standalone HTML document for a play,
  styled to match the public play presentation page.
  """

  alias Playcode.Export.Download
  alias Playcode.Outline

  # The published site's script, inlined: its EMOTHE.align lines up a shared line's later
  # parts where the line has room, on screen and once before ChromicPDF prints.
  @site_js_path Path.expand("../../../priv/static_site/site.js", __DIR__)
  @external_resource @site_js_path
  @site_js File.read!(@site_js_path)

  @doc """
  The play as one HTML page. `text_width:` pins the page to the printed text's width on
  screen too (the PDF's), so the script measures the lines as they will be printed.
  """
  def generate(play, opts \\ []) do
    {play, divisions} = Download.load(play)

    """
    <!DOCTYPE html>
    <html lang="#{play.language || "es"}">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{escape(play.title)} — #{escape(play.author_name || "")}</title>
      <style>
    #{css()}#{text_width(opts[:text_width])}
      </style>
    </head>
    <body>
      <div class="page">
    #{Download.front(play, divisions, :html)}
        <div class="play-text">
    #{play.paratexts |> Outline.items(divisions) |> Enum.map_join("\n", &Download.item(&1, :html))}
        </div>
      </div>
      <script>#{@site_js}</script>
    </body>
    </html>
    """
  end

  defp text_width(nil), do: ""

  defp text_width(width),
    do: "    @media screen { .page { max-width: none; width: #{width}; padding: 0.5rem 0; } }\n"

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

        .header .original,
        .header .verse-info,
        .header .dating {
          margin-top: 0.5rem;
          font-size: 0.75rem;
          color: rgba(51, 51, 51, 0.5);
        }

        /* The publication details, identifiers, licence and project statement */
        .publication {
          max-width: 640px;
          margin: 0 auto 2rem;
          font-size: 0.75rem;
          color: rgba(51, 51, 51, 0.5);
          text-align: justify;
        }

        .publication p + p { margin-top: 0.4rem; }

        /* A critical edition's witnesses, each a hanging indent as on the site */
        .witnesses {
          max-width: 640px;
          margin: 0 auto 2rem;
          font-size: 0.8rem;
        }

        .witnesses h2 {
          font-size: 0.875rem;
          text-align: center;
          margin-bottom: 0.5rem;
        }

        .witnesses ul { list-style: none; }
        .witnesses li { padding-left: 1.5rem; text-indent: -1.5rem; margin-bottom: 0.25rem; }

        /* Paratexts */
        .paratext {
          max-width: 640px;
          margin: 0 auto 1.5rem;
          text-align: justify;
          font-size: 0.875rem;
        }

        .paratext p + p { margin-top: 0.75rem; }

        .paratext h3 {
          font-weight: bold;
          text-align: center;
          margin-bottom: 0.5rem;
        }

        /* Cast lists */
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

        .cast-group { font-weight: bold; font-size: 0.875rem; margin: 0.5rem 0 0 1rem; }

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
        /* A later part lined up after the earlier ones, where the line has room (site.js) */
        .ghost { display: none; }
        [data-aligned] > .ghost { display: inline; visibility: hidden; }
        .ghost.indent { padding-left: 2rem; }
        .verse-line .content[data-aligned] { padding-left: 0; }

        .pn {
          font-size: x-small;
          color: #999;
          vertical-align: super;
          padding-right: 0.2em;
          font-variant-numeric: tabular-nums;
        }

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

        /* A division's closing formula, as emothe.uv.es set it; an italic word in it upright */
        .trailer {
          text-align: center;
          font-style: italic;
          margin: 1.5rem 0 0.5rem;
        }
        .trailer em { font-style: normal; }

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

        /* Hamlet's Folio passages: in grey, between their F's */
        .folio { color: #666; }

        /* In-text notes: a number after the word, the act's notes listed after it */
        .nref, .vref, sup.folio { font-size: 0.7em; line-height: 0; }
        .nref a, .vref a { text-decoration: none; }
        .notes, .variants { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #ddd; font-size: 0.9rem; }
        .notes li p, .variants li p { margin: 0.3rem 0; }

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

  defp escape(nil), do: ""

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
