defmodule Playcode.Export.Download do
  @moduledoc """
  A play as its downloads print it: the front matter and each outline item, in one of two
  formats, `:html` (the HTML file, and the PDF printed from it) or `:epub` (an e-book's
  XHTML chapters). The formats differ only where the format does: the markup of a line
  break and a note (`NoteMarkup`), and a shared line's alignment, which the HTML leaves to
  the published site's script and an e-book reader, which may run no script, gets only
  for a short line.

  The callers own the document around it: `Export.Html` the page, its stylesheet and its
  script; `Export.Epub` the package, its stylesheet and its chapters. The class names
  written here are what those stylesheets style: `header`, `author`, `title`, `original`,
  `source-note`, `editors`, `role`, `verse-info`, `dating`, `publication`,
  `edition-notes`, `witnesses`, `paratext`, `division`, `child-division`, `act-heading`,
  `scene-heading`, `cast-list`, `cast-group`, `cast-item`, `cast-name`, `cast-desc`,
  `speech` (`aside`), `speaker`, `verse-line`, `content` (`indent`, `part-m`, `part-f`),
  `ghost` (`indent`), `line-number`, `stage-direction`, `prose-block`, `trailer`.
  """

  alias Playcode.Catalogue.{Paratext, Play}
  alias Playcode.Export.NoteMarkup
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{CastListEntry, Division, InlineMarkup, Note, SplitVerses}
  alias Playcode.Witnesses
  alias PlaycodeWeb.PlayLabels

  @act_types ~w(acto act acte jornada)

  @doc """
  `play` with what its front matter prints, and its divisions as the downloads print
  them: its variants if it shows them, each later part of a shared line with its lead.
  """
  def load(play) do
    play = Playcode.Repo.preload(play, [:editors, :sources, :paratexts])

    divisions =
      play.id
      |> PlayContent.load_play_content(variants: play.show_variants)
      |> SplitVerses.with_leads()

    {play, divisions}
  end

  @doc """
  The front matter: author and title, the original, the sources' notes, the editors, the
  verses, the dating, then the publication details, the notes on the edition and a
  critical edition's witnesses.
  """
  def front(play, divisions, format) do
    """
    <header class="header">
    <p class="author">#{escape(play.author_name)}</p>
    <h1 class="title">#{escape(play.title)}</h1>
    #{original(play)}
    #{sources(play.sources, format)}
    #{editors(play.editors)}
    #{verse_info(play)}
    #{dating(play)}
    </header>
    #{publication(play, format)}
    #{edition_notes(play, format)}
    #{witnesses(play, divisions)}
    """
  end

  @doc """
  One outline item (`Outline.items/2`): a paratext, or a division with its cast list if it
  is one, its opening lists, its elements, its other children and its endnotes.
  """
  def item(%Paratext{} = paratext, format) do
    heading = if paratext.heading, do: "<h3>#{inline(paratext.heading, format)}</h3>\n", else: ""

    trailer =
      if paratext.trailer,
        do: "<div class=\"trailer\">#{inline(paratext.trailer, format)}</div>\n",
        else: ""

    "<div class=\"paratext\">\n#{heading}#{paragraphs(paratext.content, format)}#{trailer}</div>"
  end

  def item(div, format) do
    {opening, children} = div |> Map.get(:children, []) |> Division.split_opening_lists()

    [
      "<div class=\"division\">\n",
      division_heading(div, format),
      cast_list(div, format),
      children(opening, format),
      elements(Map.get(div, :loaded_elements, []), format),
      children(children, format),
      "\n",
      NoteMarkup.endnotes(Note.reading_order(div), format),
      "</div>"
    ]
    |> IO.iodata_to_binary()
  end

  # --- Front matter ---

  # The play a translation or an adaptation is made from, by its title, as the published
  # site's title page names it (`StaticSite.Components.family/1`), in the downloads'
  # English; nothing for an original, or a play linked with no kind. Only a complete
  # original, whoever downloads: a PDF is rendered once and served to every reader
  # (`PdfCache`), so staff's copy may not name a draft.
  defp original(%{relationship_type: type, parent_play: %Play{is_complete: true} = original})
       when is_binary(type) do
    kind = in_english(fn -> PlayLabels.relationship_type_label(type) end)
    ~s(<p class="original">#{kind} of <cite>#{escape(original.title)}</cite></p>)
  end

  defp original(_play), do: ""

  defp sources(sources, format) do
    for %{note: note} when note != nil <- sources,
        do: "<p class=\"source-note\">#{inline(note, format)}</p>\n",
        into: ""
  end

  defp editors([]), do: ""

  defp editors(editors) do
    items =
      Enum.map_join(editors, "\n", fn ed ->
        "<span>#{escape(ed.person_name)} <span class=\"role\">(#{escape(ed.role)})</span></span>"
      end)

    "<div class=\"editors\">\n#{items}\n</div>"
  end

  defp verse_info(play) do
    cond do
      play.verse_count && play.is_verse ->
        "<p class=\"verse-info\">#{play.verse_count} verses</p>"

      play.verse_count ->
        "<p class=\"verse-info\">Prose</p>"

      true ->
        ""
    end
  end

  # The dating and the historical time, one line each, as the published site's title page
  # shows them (`StaticSite.Components.study/1`), in the downloads' English.
  defp dating(play) do
    [
      (play.composition_date_from || play.composition_date_note) &&
        dating_line("Composition", [Play.composition_years(play), play.composition_date_note]),
      play.historical_time &&
        dating_line("Historical time", [
          in_english(fn -> PlayLabels.historical_time_label(play.historical_time) end),
          play.historical_time_note
        ])
    ]
    |> Enum.filter(& &1)
    |> Enum.map_join("\n", &"<p class=\"dating\">#{escape(&1)}</p>")
  end

  defp dating_line(label, parts),
    do: "#{label}: " <> (parts |> Enum.reject(&is_nil/1) |> Enum.join(". "))

  # The edition's publication details, its identifiers, its licence and the project's
  # statement, a paragraph each and only those the play has, the code always (question 24);
  # not the editorial statement, the same paragraph in every file.
  defp publication(play, format) do
    inline = &if(filled?(&1), do: inline(&1, format))
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
    #{Enum.map_join(paragraphs, "\n", &"<p>#{&1}</p>")}
    </section>
    """
  end

  # The notes on the edition (`notesStmt`), a paragraph each, a witness list whole
  # (question 26).
  defp edition_notes(%{edition_notes: []}, _format), do: ""

  defp edition_notes(play, format) do
    """
    <section class="edition-notes">
    <h3>Notes on the edition</h3>
    #{Enum.map_join(play.edition_notes, "\n", &"<p>#{inline(&1, format)}</p>")}
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

  # A critical edition's witnesses, each as the play page and the published site print it
  # (`Witnesses.html/1`); nothing for any other play (question 24).
  defp witnesses(%{witnesses: [_ | _] = witnesses} = play, divisions) do
    if critical_edition?(play, divisions) do
      """
      <section class="witnesses">
      <h2>Witnesses</h2>
      <ul>
      #{Enum.map_join(witnesses, "\n", &"<li>#{Phoenix.HTML.safe_to_string(Witnesses.html(&1))}</li>")}
      </ul>
      </section>
      """
    else
      ""
    end
  end

  defp witnesses(_play, _divisions), do: ""

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

  # --- The outline ---

  # Each paragraph a <p>; NoteMarkup turns each line break into a <br>, inside the italics
  # too: an EPUB reader need not honour white-space: pre-line.
  defp paragraphs(content, format) do
    for paragraph <- String.split(content || "", "\n\n", trim: true), into: "" do
      "<p>#{inline(paragraph, format)}</p>\n"
    end
  end

  defp children(children, format) do
    Enum.map_join(children, "\n", fn child ->
      "<div class=\"child-division\">\n#{child_heading(child, format)}#{cast_list(child, format)}#{elements(Map.get(child, :loaded_elements, []), format)}</div>"
    end)
  end

  # A cast list's own entries (`CastListEntry.printed_groups/1`), each group under its
  # heading; nothing for a division of the text.
  defp cast_list(%{type: "elenco", entries: entries}, format) do
    case CastListEntry.printed_groups(entries) do
      [] ->
        ""

      groups ->
        "<div class=\"cast-list\">\n#{Enum.map_join(groups, "\n", &cast_group(&1, format))}\n</div>\n"
    end
  end

  defp cast_list(_division, _format), do: ""

  defp cast_group([first | _] = entries, format) do
    heading =
      if first.group_heading,
        do: "<p class=\"cast-group\">#{inline(first.group_heading, format)}</p>\n",
        else: ""

    heading <> Enum.map_join(entries, "\n", &cast_item(&1, format))
  end

  defp cast_item(entry, format) do
    desc =
      if entry.description,
        do: " <span class=\"cast-desc\">#{inline(entry.description, format)}</span>",
        else: ""

    "<div class=\"cast-item\"><span class=\"cast-name\">#{inline(entry.name, format)}</span>#{desc}</div>"
  end

  defp division_heading(%{title: title}, _format) when title in [nil, ""], do: ""

  defp division_heading(%{title: title, type: type} = div, format) when type in @act_types,
    do: "<h2 class=\"act-heading\">#{inline(title, div.notes, format)}</h2>\n"

  defp division_heading(div, format), do: child_heading(div, format)

  defp child_heading(%{title: title}, _format) when title in [nil, ""], do: ""

  defp child_heading(%{title: title} = div, format),
    do: "<h3 class=\"scene-heading\">#{inline(title, div.notes, format)}</h3>\n"

  defp elements(elements, format), do: Enum.map_join(elements, &element(&1, format))

  defp element(%{type: "speech"} = el, format) do
    aside_class = if el.is_aside, do: " aside", else: ""

    speaker =
      if el.speaker_label,
        do: "<div class=\"speaker\">#{inline(el.speaker_label, el.notes, format)}</div>\n",
        else: ""

    "<div class=\"speech#{aside_class}\">\n#{speaker}#{elements(Map.get(el, :children, []), format)}</div>\n"
  end

  # A group's heading ("A Song") centred and in italics, as a closing formula is.
  defp element(%{type: "line_group"} = el, format) do
    heading =
      if el.content,
        do: "<div class=\"trailer\">#{inline(el.content, el.notes, format)}</div>\n",
        else: ""

    heading <> elements(Map.get(el, :children, []), format)
  end

  defp element(%{type: "verse_line"} = el, format) do
    lead = lead(el, format)

    content_class =
      cond do
        lead && format == :epub -> "content"
        el.rend == "indent" -> "content indent"
        el.part == "F" -> "content part-f"
        el.part == "M" -> "content part-m"
        true -> "content"
      end

    "<div class=\"verse-line\"><span class=\"#{content_class}\">#{ghost(lead, format)}#{inline(el.content, el.notes, format)}</span><span class=\"line-number\">#{el.line_number}</span></div>\n"
  end

  defp element(%{type: "stage_direction"} = el, format),
    do: "<div class=\"stage-direction\">(#{inline(el.content, el.notes, format)})</div>\n"

  defp element(%{type: "prose"} = el, format),
    do: "<div class=\"prose-block\">#{inline(el.content, el.notes, format)}</div>\n"

  # An opening formula (the Arte nuevo's dedication) or a closing one, centred alike.
  defp element(%{type: type} = el, format) when type in ~w(opener trailer),
    do: "<div class=\"trailer\">#{inline(el.content, el.notes, format)}</div>\n"

  defp element(_element, _format), do: ""

  # A later part's earlier parts. The HTML draws each, invisible, and the published site's
  # script shows it where the line has room, or leaves the part its fixed step. An e-book
  # reader may run no script, so the EPUB draws it, shown, only when the whole line is
  # short enough for a phone at its default size (question 61: 45 characters, proposed
  # with the corpus's figures); a longer one takes the fixed step.
  @align_max 45

  defp lead(%{lead: nil}, _format), do: nil
  defp lead(%{lead: lead}, :html), do: lead
  defp lead(%{lead: lead}, :epub), do: if(fits?(lead.line), do: lead)

  defp fits?(line), do: line |> InlineMarkup.plain() |> String.length() <= @align_max

  defp ghost(nil, _format), do: ""

  defp ghost(%{lead: lead, indent: indent}, format),
    do:
      "<span class=\"ghost#{if indent, do: " indent"}\" aria-hidden=\"true\">#{inline(lead, format)} </span>"

  defp inline(text, notes \\ [], format), do: NoteMarkup.inline(text, notes, format)

  defp in_english(fun), do: Gettext.with_locale(PlaycodeWeb.Gettext, "en", fun)

  defp escape(nil), do: ""
  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
