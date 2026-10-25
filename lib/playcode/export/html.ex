defmodule Playcode.Export.Html do
  @moduledoc """
  Generates a standalone HTML document for a play,
  styled to match the public play presentation page.
  """

  alias Playcode.Catalogue.{Paratext, Play}
  alias Playcode.Export.NoteMarkup
  alias Playcode.Outline
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{CastListEntry, Division, InlineMarkup, Note}
  alias Playcode.Witnesses
  alias PlaycodeWeb.PlayLabels

  def generate(play) do
    play = Playcode.Repo.preload(play, [:editors, :sources, :paratexts])
    divisions = PlayContent.load_play_content(play.id, variants: play.show_variants)

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
    #{original(play)}
    #{render_sources(play.sources)}
    #{render_editors(play.editors)}
    #{render_verse_info(play)}
    #{render_dating(play)}
        </header>
    #{publication(play, :html)}
    #{witnesses(play, divisions)}

        <div class="play-text">
    #{play.paratexts |> Outline.items(divisions) |> Enum.map_join("\n", &render_item/1)}
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
          white-space: pre-line;
        }

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

  defp render_sources(sources) do
    sources
    |> Enum.map(fn s ->
      if s.note,
        do: "      <p class=\"source-note\">#{NoteMarkup.inline(s.note, [], :html)}</p>",
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

  @doc """
  The dating and the historical time, one line each, as the published site's title page
  shows them (`StaticSite.Components.study/1`), in the downloads' English. The EPUB
  prints the same lines.
  """
  def dating(play) do
    [
      (play.composition_date_from || play.composition_date_note) &&
        dating_line("Composition", [Play.composition_years(play), play.composition_date_note]),
      play.historical_time &&
        dating_line("Historical time", [
          Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
            PlayLabels.historical_time_label(play.historical_time)
          end),
          play.historical_time_note
        ])
    ]
    |> Enum.filter(& &1)
  end

  defp dating_line(label, parts),
    do: "#{label}: " <> (parts |> Enum.reject(&is_nil/1) |> Enum.join(". "))

  defp render_dating(play),
    do: play |> dating() |> Enum.map_join("\n", &"      <p class=\"dating\">#{escape(&1)}</p>")

  @doc """
  The play a translation or an adaptation is made from, by its title, as the published
  site's title page names it (`StaticSite.Components.family/1`), in the downloads'
  English; nothing for an original, or a play linked with no kind. The play's
  `parent_play` is the one `Catalogue.get_play_with_all!/2` loads, so a visitor's
  download never names a draft. The EPUB prints the same line.
  """
  def original(%{relationship_type: type, parent_play: %Play{} = original})
      when is_binary(type) do
    kind =
      Gettext.with_locale(PlaycodeWeb.Gettext, "en", fn ->
        PlayLabels.relationship_type_label(type)
      end)

    ~s(<p class="original">#{kind} of <cite>#{escape(original.title)}</cite></p>)
  end

  def original(_play), do: ""

  @doc """
  The edition's publication details, its identifiers, its licence and the project's
  statement, a paragraph each and only those the play has, the code always (question 24);
  not the editorial statement, the same paragraph in every file. The EPUB prints the same
  block.
  """
  def publication(play, format) do
    inline = &if(filled?(&1), do: NoteMarkup.inline(&1, [], format))
    catalogue_number = if filled?(play.emothe_id), do: "EMOTHE " <> play.emothe_id
    project = String.split(play.project_description || "", ~r/\n\s*\n/, trim: true)

    paragraphs =
      [
        labelled(
          "Publication",
          Enum.map([play.publisher, play.pub_place, play.publication_date], inline)
        ),
        labelled("Authority", [inline.(play.authority)]),
        labelled("Identifiers", Enum.map([play.code, catalogue_number], inline)),
        labelled("Licence", [inline.(play.licence_text), licence_link(play.licence_url)], " "),
        inline.(play.availability_note)
        | Enum.map(project, inline)
      ]
      |> Enum.filter(& &1)

    """
        <section class="publication">
    #{Enum.map_join(paragraphs, "\n", &"      <p>#{&1}</p>")}
        </section>
    """
  end

  # "Label: " and the parts the play has, or nil when it has none.
  defp labelled(label, parts, separator \\ ", ") do
    case Enum.filter(parts, & &1) do
      [] -> nil
      parts -> "#{label}: " <> Enum.join(parts, separator)
    end
  end

  # Linked only when it is a web address, as the site links it.
  defp licence_link(url) do
    cond do
      not filled?(url) ->
        nil

      String.starts_with?(url, ["http://", "https://"]) ->
        ~s(<a href="#{escape(url)}">#{escape(url)}</a>)

      true ->
        escape(url)
    end
  end

  defp filled?(text), do: text not in [nil, ""]

  @doc """
  A critical edition's witnesses, each as the play page and the published site print it
  (`Witnesses.html/1`); nothing for any other play (question 24). The EPUB prints the same
  list.
  """
  def witnesses(%{witnesses: [_ | _] = witnesses} = play, divisions) do
    if critical_edition?(play, divisions) do
      """
          <section class="witnesses">
            <h2>Witnesses</h2>
            <ul>
      #{Enum.map_join(witnesses, "\n", &"        <li>#{Phoenix.HTML.safe_to_string(Witnesses.html(&1))}</li>")}
            </ul>
          </section>
      """
    else
      ""
    end
  end

  def witnesses(_play, _divisions), do: ""

  # A play with variants as printed, or a critical apparatus after the text (decided by
  # Playcode, 2026-10-19). With its variants hidden, no reading names a witness.
  # ponytail: the apparatus is known by its heading, the only mark the corpus gives it
  # (EMOTHE0460, 0644); one headed in another language needs its word added here.
  defp critical_edition?(play, divisions) do
    Enum.any?(Note.reading_order(divisions), &Note.variant?/1) or
      Enum.any?(play.paratexts, &apparatus?/1)
  end

  defp apparatus?(%Paratext{heading: nil}), do: false

  defp apparatus?(%Paratext{heading: heading}),
    do:
      heading |> InlineMarkup.plain() |> String.trim() |> String.downcase() ==
        "critical apparatus"

  # The outline's items in order: a paratext where it stands, a division with its cast list
  # if it is one, its elements and its children.
  defp render_item(%Paratext{} = paratext) do
    heading =
      if paratext.heading,
        do: "      <h3>#{NoteMarkup.inline(paratext.heading, [], :html)}</h3>\n",
        else: ""

    trailer =
      if paratext.trailer,
        do:
          "      <div class=\"trailer\">#{NoteMarkup.inline(paratext.trailer, [], :html)}</div>\n",
        else: ""

    "    <div class=\"paratext\">\n#{heading}      <div>#{NoteMarkup.inline(paratext.content, [], :html)}</div>\n#{trailer}    </div>"
  end

  defp render_item(div) do
    heading = division_heading(div)
    cast = render_cast_list(div)
    elements = render_elements(Map.get(div, :loaded_elements, []))

    {opening, children} = div |> Map.get(:children, []) |> Division.split_opening_lists()
    notes = NoteMarkup.endnotes(Note.reading_order(div), :html)

    "    <div class=\"division\">\n#{heading}#{cast}#{render_children(opening)}#{elements}#{render_children(children)}\n#{notes}    </div>"
  end

  defp render_children(children) do
    children
    |> Enum.map(fn child ->
      ch = child_heading(child)
      cc = render_cast_list(child)
      ce = render_elements(Map.get(child, :loaded_elements, []))
      "      <div class=\"child-division\">\n#{ch}#{cc}#{ce}      </div>"
    end)
    |> Enum.join("\n")
  end

  # A cast list's own entries (`CastListEntry.printed_groups/1`), each group under its
  # heading; nothing for a division of the text.
  defp render_cast_list(%{type: "elenco", entries: entries}) do
    case CastListEntry.printed_groups(entries) do
      [] ->
        ""

      groups ->
        """
              <div class="cast-list">
        #{Enum.map_join(groups, "\n", &render_cast_group/1)}
              </div>
        """
    end
  end

  defp render_cast_list(_division), do: ""

  defp render_cast_group([first | _] = entries) do
    heading =
      if first.group_heading,
        do:
          "          <p class=\"cast-group\">#{NoteMarkup.inline(first.group_heading, [], :html)}</p>\n",
        else: ""

    heading <> Enum.map_join(entries, "\n", &render_cast_item/1)
  end

  defp render_cast_item(entry) do
    desc =
      if entry.description,
        do:
          " <span class=\"cast-desc\">#{NoteMarkup.inline(entry.description, [], :html)}</span>",
        else: ""

    "          <div class=\"cast-item\"><span class=\"cast-name\">#{NoteMarkup.inline(entry.name, [], :html)}</span>#{desc}</div>"
  end

  @act_types ~w(acto act acte jornada)

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

  # An opening formula (the Arte nuevo's dedication) or a closing one, centred alike.
  defp render_element(%{type: type} = el) when type in ~w(opener trailer) do
    "        <div class=\"trailer\">#{NoteMarkup.inline(el.content, el.notes, :html)}</div>\n"
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
