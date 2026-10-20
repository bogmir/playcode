defmodule Playcode.Export.TeiXml do
  @moduledoc """
  Generates TEI-XML from a play record and its content.
  """

  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Paratext
  alias Playcode.Outline
  alias Playcode.Performances
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Division, Element, InlineMarkup, Note}
  alias Playcode.Places
  alias Playcode.Witnesses
  import XmlBuilder, except: [element: 2, element: 3]

  # Attributes in alphabetical order. An atom-keyed map lists its keys in the order the
  # running VM created those atoms, so two builds wrote <date notBefore notAfter> in
  # either order and unchanged files changed.
  defp element(name, attrs) when is_map(attrs), do: XmlBuilder.element(name, sorted(attrs), nil)
  defp element(name, content), do: XmlBuilder.element(name, content)
  defp element(name, attrs, content), do: XmlBuilder.element(name, sorted(attrs), content)

  defp sorted(attrs) when is_map(attrs), do: Enum.sort_by(attrs, &to_string(elem(&1, 0)))
  defp sorted(attrs), do: attrs

  @title_editor_roles %{
    "translator" => "translator",
    "researcher" => "researcher",
    "critical_editor" => "edicion_critica"
  }

  # The roles written as a respStmt, in the titleStmt or the editionStmt.
  @resp_roles ~w(editor digital_editor reviewer)

  @doc """
  The play's TEI document. `opts` may hand in `:divisions` (as
  `PlayContent.load_play_content/1` returns them) and `:performances` (as
  `Performances.list_for_play/1` returns them) already loaded, as the static site does for
  every play; otherwise they are loaded here.
  """
  def generate(play, opts \\ []) do
    play =
      play
      |> Playcode.Repo.preload([
        :editors,
        :sources,
        :paratexts,
        :witnesses,
        play_places: [place: :names]
      ])
      # The credits are written in their order, which a preload does not keep.
      |> Map.update!(:editors, &Enum.sort_by(&1, fn editor -> editor.position end))

    divisions =
      Keyword.get_lazy(opts, :divisions, fn -> PlayContent.load_play_content(play.id) end)

    performances =
      Keyword.get_lazy(opts, :performances, fn -> Performances.list_for_play(play.id) end)

    gazetteer = gazetteer(play, performances)

    tei =
      element(
        :TEI,
        %{"xml:lang" => play.language || "es", "xmlns" => "http://www.tei-c.org/ns/1.0"},
        [
          build_header(play, performances, gazetteer),
          build_text(play, divisions, performances, gazetteer)
        ]
      )

    "<?xml version=\"1.0\" ?>\n" <>
      XmlBuilder.generate(tei, format: :indent, encoding: nil)
  end

  # The places the play links and its performances name are written with their ancestors and
  # states, which the whole gazetteer knows; a play naming none loads nothing.
  defp gazetteer(play, performances) do
    if play.play_places != [] or Enum.any?(performances, &(&1.place_id || &1.historical_state_id)),
      do: Places.gazetteer(),
      else: %{}
  end

  # --- Header ---

  defp build_header(play, performances, gazetteer) do
    element(
      :teiHeader,
      [
        build_file_desc(play),
        build_encoding_desc(play),
        build_profile_desc(play, performances, gazetteer)
      ] ++ build_revision_desc(play)
    )
  end

  # The revision history, each change in the order the files use: the date (an empty one
  # if none, as 48 files have), the revisers, the words saying what was done, the note; a
  # space between, so a reader of the text gets words.
  defp build_revision_desc(%{revisions: []}), do: []

  defp build_revision_desc(play) do
    changes =
      Enum.map(play.revisions, fn change ->
        note =
          if change.note,
            do: [inline_element(:note, %{}, build_inline_content(change.note))],
            else: []

        parts =
          [[element(:date, change.date || "")]] ++
            people(change.people, &[element(:persName, &1)]) ++
            [inline_children(change.description), note]

        inline_element(
          :change,
          %{},
          parts |> Enum.reject(&(&1 == [])) |> Enum.intersperse([" "]) |> Enum.concat()
        )
      end)

    [element(:revisionDesc, changes)]
  end

  defp build_file_desc(play) do
    element(
      :fileDesc,
      [
        build_title_stmt(play),
        build_edition_stmt(play),
        build_extent(play),
        build_publication_stmt(play)
      ] ++ build_notes_stmt(play) ++ [build_source_desc(play)]
    )
  end

  # The notes on the edition, then the play this one translates, adapts or reworks, by its
  # short code, so an import can link the two whichever arrives first
  # (Catalogue.link_waiting_translations/0).
  defp build_notes_stmt(play) do
    notes =
      Enum.map(play.edition_notes, fn note ->
        inline_element(:note, %{}, lines(note, &build_inline_content/1))
      end)

    original =
      case Catalogue.original_code(play) do
        nil -> []
        code -> [element(:relatedItem, %{type: "original", target: code})]
      end

    case notes ++ original do
      [] -> []
      children -> [element(:notesStmt, children)]
    end
  end

  defp build_title_stmt(play) do
    # The main title's type is the kind of play: traduccion, adaptacion, refundicion, version
    main_title_attrs = if play.relationship_type, do: %{type: play.relationship_type}, else: %{}

    titles = [element(:title, main_title_attrs, play.title)]

    titles =
      if play.original_title,
        do: [element(:title, %{type: "original"}, play.original_title) | titles],
        else: titles

    titles =
      if play.edition_title,
        do: titles ++ [element(:title, %{type: "edicion"}, play.edition_title)],
        else: titles

    titles =
      if play.title_sort,
        do: titles ++ [element(:title, %{key: "orden"}, play.title_sort)],
        else: titles

    titles = titles ++ [element(:title, %{key: "archivo"}, play.code)]

    authors =
      if play.author_name do
        author_attrs = if play.author_attribution, do: %{ana: play.author_attribution}, else: %{}

        [element(:author, author_attrs, play.author_name)] ++
          if play.author_sort do
            [element(:author, %{key: "orden"}, play.author_sort)]
          else
            []
          end
      else
        []
      end

    # The credits in their order, which TeiParser reads back from the order of the
    # editors and respStmts: translators, researchers and the critical edition's editor
    # as <editor role="…"><persName>…<orgName>…, the role the word TeiParser reads back,
    # and the editors, digital editors and reviewers of positions 100..199 as respStmts.
    title_credits =
      for e <- play.editors, title_credit?(e) do
        case @title_editor_roles[e.role] do
          nil ->
            resp_stmt(e)

          role ->
            org = if e.organization, do: [element(:orgName, e.organization)], else: []
            element(:editor, %{role: role}, [element(:persName, e.person_name) | org])
        end
      end

    # Last, as the files write it; TeiParser reads it back first, wherever it is.
    principal =
      for e <- play.editors, e.role == "principal", do: element(:principal, e.person_name)

    sponsor =
      if play.sponsor,
        do: [element(:sponsor, [element(:orgName, play.sponsor)])],
        else: []

    funder =
      if play.funder,
        do: [element(:funder, [element(:orgName, play.funder)])],
        else: []

    element(:titleStmt, titles ++ authors ++ sponsor ++ funder ++ title_credits ++ principal)
  end

  defp build_edition_stmt(play) do
    # The respStmts the titleStmt does not hold. Writing those here too made a re-import
    # create each one twice.
    editors =
      for e <- play.editors, e.role in @resp_roles, not title_credit?(e), do: resp_stmt(e)

    element(:editionStmt, [
      element(:edition, "Edición electrónica de '#{play.title}'")
      | editors
    ])
  end

  # Where a credit is written: the titleStmt's translators, researchers and critical
  # editor, and the respStmts a file gave there, which TeiParser numbers from 100.
  defp title_credit?(editor) do
    Map.has_key?(@title_editor_roles, editor.role) or
      (editor.role in @resp_roles and editor.position in 100..199)
  end

  # The resp is the wording TeiParser reads the role back from: anything with "Edición"
  # is an editor, so a digital editor is written in English.
  defp resp_stmt(editor) do
    resp =
      case editor.role do
        "editor" -> "Edición"
        "reviewer" -> "Revisión"
        "digital_editor" -> "Electronic edition"
      end

    org = if editor.organization, do: [element(:orgName, editor.organization)], else: []
    element(:respStmt, [element(:resp, resp), element(:persName, editor.person_name) | org])
  end

  defp build_extent(play) do
    if play.verse_count do
      element(:extent, %{ana: "verso"}, "#{play.verse_count} versos")
    else
      element(:extent, "")
    end
  end

  defp build_publication_stmt(play) do
    idno_children = [element(:idno, %{type: "code"}, play.code)]

    idno_children =
      if play.emothe_id,
        do: idno_children ++ [element(:idno, %{type: "EMOTHE"}, play.emothe_id)],
        else: idno_children

    children =
      idno_children ++
        [
          element(:pubPlace, play.pub_place || ""),
          element(:date, play.publication_date || "")
        ]

    children =
      if play.publisher,
        do: [element(:publisher, [element(:orgName, play.publisher)]) | children],
        else: children

    children =
      if play.authority,
        do: children ++ [element(:authority, [element(:orgName, play.authority)])],
        else: children

    # Build availability with optional <p> and <licence>
    availability_children =
      []
      |> then(fn acc ->
        if play.availability_note,
          do: acc ++ paragraphs(play.availability_note),
          else: acc
      end)
      |> then(fn acc ->
        if play.licence_url || play.licence_text do
          licence_attrs = if play.licence_url, do: %{target: play.licence_url}, else: %{}
          acc ++ [element(:licence, licence_attrs, play.licence_text || "")]
        else
          acc
        end
      end)

    children =
      if availability_children != [],
        do: children ++ [element(:availability, availability_children)],
        else: children

    element(:publicationStmt, children)
  end

  defp build_source_desc(play) do
    bibls =
      Enum.map(play.sources, fn source ->
        children =
          [
            if(source.title, do: inline_element(:title, %{}, build_inline_content(source.title))),
            if(source.author, do: element(:author, source.author)),
            if source.editor do
              attrs = if source.editor_role, do: %{role: source.editor_role}, else: %{}
              element(:editor, attrs, source.editor)
            end,
            if(source.publisher, do: element(:publisher, source.publisher)),
            if(source.pub_place, do: element(:pubPlace, source.pub_place)),
            if(source.pub_date, do: element(:date, source.pub_date)),
            if(source.language, do: element(:lang, source.language)),
            if(source.note, do: inline_element(:note, %{}, build_inline_content(source.note))),
            if(source.distributor, do: element(:distributor, source.distributor))
          ]
          |> Enum.reject(&is_nil/1)

        element(:bibl, children)
      end)

    # The schema takes paragraphs, or bibls and lists, never both: the empty <p/> stands in
    # only when there is nothing else.
    children = Enum.reject(bibls ++ [build_list_wit(play)], &is_nil/1)
    element(:sourceDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  # The play's witnesses (S3). @n is the siglum verbatim and @xml:id what an apparatus
  # points at (Witnesses.xml_id/1). The modern editions a reading may also cite stay in
  # <back>, with their siglum.
  defp build_list_wit(%{witnesses: []}), do: nil

  defp build_list_wit(play) do
    element(:listWit, play.witnesses |> Enum.sort_by(& &1.position) |> Enum.map(&build_witness/1))
  end

  defp build_witness(w) do
    attrs = Map.reject(%{"n" => w.siglum, "xml:id" => Witnesses.xml_id(w)}, &is_nil(elem(&1, 1)))
    {type, subtype} = Witnesses.tei_type(w.witness_type) || {nil, nil}
    bibl_attrs = Map.reject(%{type: type, subtype: subtype}, &is_nil(elem(&1, 1)))
    date = if filled?(w.date), do: String.trim(w.date)

    children =
      Enum.reject(
        [
          if(filled?(w.title),
            do: inline_element(:title, %{}, lines(w.title, &build_inline_content/1))
          ),
          if(filled?(w.normalized_title),
            do:
              inline_element(
                :title,
                %{type: "normalized"},
                lines(w.normalized_title, &build_inline_content/1)
              )
          ),
          if(filled?(w.attribution), do: inline_element(:author, %{}, lines(w.attribution))),
          if(filled?(w.pub_place), do: inline_element(:pubPlace, %{}, lines(w.pub_place))),
          if(filled?(w.publisher), do: inline_element(:publisher, %{}, lines(w.publisher))),
          if(date,
            do: element(:date, if(date =~ ~r/^\d{4}$/, do: %{when: date}, else: %{}), date)
          ),
          if(filled?(w.format), do: inline_element(:extent, %{}, lines(w.format))),
          if(filled?(w.shelfmark), do: element(:idno, %{type: "shelfmark"}, w.shelfmark)),
          if(filled?(w.note),
            do: inline_element(:note, %{}, lines(w.note, &build_inline_content/1))
          )
        ],
        &is_nil/1
      )

    element(:witness, attrs, [element(:bibl, bibl_attrs, children)])
  end

  # A witness's field, its line breaks (FileMaker's, a title page's lines) as <lb/>s. A row
  # saved before the changeset kept breaks as \n may still hold FileMaker's \r.
  defp lines(text, build \\ & &1) do
    case String.split(text, ~r/\r\n?|\n/) do
      [line] ->
        build.(line)

      lines ->
        lines
        |> Enum.map(&List.wrap(build.(&1)))
        |> Enum.intersperse([element(:lb)])
        |> Enum.concat()
    end
  end

  # A text whose paragraphs are parted by a blank line, one <p> each, its italics as <emph>.
  defp paragraphs(text) do
    for paragraph <- Note.paragraphs(text),
        do: inline_element(:p, %{}, build_inline_content(paragraph))
  end

  defp build_encoding_desc(play) do
    children = []

    children =
      if play.project_description,
        do: children ++ [element(:projectDesc, paragraphs(play.project_description))],
        else: children

    children =
      if play.editorial_declaration,
        do: children ++ [element(:editorialDecl, paragraphs(play.editorial_declaration))],
        else: children

    children = children ++ build_class_decl(play)

    element(:encodingDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  # The library classification of the source files, the Universal Decimal Classification
  # number for drama in the play's language. It follows the language one for one, so it is
  # written from it and never stored; the Portuguese files have none.
  @cdu %{"es" => "821.134.2-2", "fr" => "821.133-2", "en" => "821.111-2", "it" => "821.131-2"}

  defp cdu(play), do: Map.get(@cdu, play.language || "es")

  defp build_class_decl(play) do
    if cdu(play) do
      taxonomy =
        element(:taxonomy, %{"xml:id" => "CDU"}, [
          element(:bibl, "Clasificación Decimal Universal")
        ])

      [element(:classDecl, [taxonomy])]
    else
      []
    end
  end

  defp build_text_class(play) do
    case cdu(play) do
      nil -> []
      cdu -> [element(:textClass, [element(:classCode, %{"scheme" => "#CDU"}, cdu)])]
    end
  end

  @language_ident_labels %{
    "es" => {"es-ES", "Español"},
    "en" => {"en-EN", "English"},
    "it" => {"it-IT", "Italiano"},
    "ca" => {"ca-ES", "Català"},
    "fr" => {"fr-FR", "Français"},
    "pt" => {"pt-PT", "Português"}
  }

  defp build_profile_desc(play, performances, gazetteer) do
    {ident, label} = Map.get(@language_ident_labels, play.language || "es", {"es-ES", "Español"})

    children =
      build_creation(play) ++
        [element(:langUsage, [element(:language, %{ident: ident}, label)])] ++
        build_text_class(play)

    element(:profileDesc, children ++ build_setting_desc(play, performances, gazetteer))
  end

  # <creation> is where TEI records when the text *in this file* was composed. The years
  # are the attributes and the note is the element's text, the human-readable form of
  # them; a dating only in words ("posterior 1590 y anterior 1595") is a <date> with no
  # attributes.
  defp build_creation(%{composition_date_from: nil, composition_date_note: nil}), do: []

  defp build_creation(play) do
    attrs =
      cond do
        is_nil(play.composition_date_from) ->
          %{}

        play.composition_date_from == play.composition_date_to ->
          %{when: to_string(play.composition_date_from)}

        true ->
          %{
            notBefore: to_string(play.composition_date_from),
            notAfter: to_string(play.composition_date_to)
          }
      end

    date =
      case play.composition_date_note do
        nil -> element(:date, attrs)
        note -> element(:date, attrs, note)
      end

    [element(:creation, [date])]
  end

  # The places are a `listPlace` and their links in `<setting>`; the historical time is a
  # `<time>` in the same `<setting>`, the period as @type and its note as the text. A play
  # whose only places are its performances' has the `listPlace` alone.
  defp build_setting_desc(play, performances, gazetteer) do
    {list_place, setting_refs} = build_places(play, performances, gazetteer)

    setting =
      case setting_refs ++ build_historical_time(play) do
        [] -> []
        setting -> [element(:setting, setting)]
      end

    case list_place ++ setting do
      [] -> []
      children -> [element(:settingDesc, children)]
    end
  end

  # Two elements, on purpose. `listPlace` nests every place the play needs (each link's
  # place and its historical state) *plus every ancestor*, so containment is complete —
  # which means a `<place>` may be a pure container. `setting` is therefore what says
  # which of them the play actually references, because "the leaves are the settings" is
  # wrong: a play can be set in Italy itself. The places and states of the performances are
  # in the `listPlace` too, and in no `setting`: each performance names its own.
  defp build_places(%{play_places: links}, performances, gazetteer) do
    ordered = Enum.sort_by(links, fn link -> {link.role != "setting", link.position} end)

    performance_places =
      for performance <- performances,
          id <- [performance.place_id, performance.historical_state_id],
          id,
          do: id

    if ordered == [] and performance_places == [] do
      {[], []}
    else
      needed =
        (Enum.flat_map(ordered, &[&1.place, Map.get(gazetteer, &1.historical_state_id)]) ++
           Enum.map(performance_places, &Map.get(gazetteer, &1)))
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&[&1 | Places.ancestors(&1, gazetteer)])
        |> Enum.uniq_by(& &1.id)

      wanted = MapSet.new(needed, & &1.id)
      roots = Enum.filter(needed, &is_nil(&1.parent_place_id))

      {[element(:listPlace, Enum.map(roots, &build_place(&1, gazetteer, wanted)))],
       Enum.map(ordered, &build_setting_ref(&1, gazetteer))}
    end
  end

  defp build_historical_time(%{historical_time: nil, historical_time_note: nil}), do: []

  defp build_historical_time(play) do
    attrs = if play.historical_time, do: %{type: play.historical_time}, else: %{}

    case play.historical_time_note do
      nil -> [element(:time, attrs)]
      note -> [element(:time, attrs, note)]
    end
  end

  defp build_place(place, gazetteer, wanted) do
    attrs =
      [{"xml:id", place.slug}, {"type", place.type}]
      |> then(fn attrs ->
        if place.is_fictional, do: attrs ++ [{"subtype", "fictional"}], else: attrs
      end)

    children =
      Enum.map(place.names, &build_place_name/1) ++
        build_location(place) ++
        build_place_idno(place) ++
        build_place_note(place) ++
        child_places(place, gazetteer, wanted)

    element(:place, attrs, children)
  end

  defp child_places(place, gazetteer, wanted) do
    gazetteer
    |> Map.values()
    |> Enum.filter(&(&1.parent_place_id == place.id and MapSet.member?(wanted, &1.id)))
    |> Enum.sort_by(& &1.slug)
    |> Enum.map(&build_place(&1, gazetteer, wanted))
  end

  defp build_place_name(name) do
    attrs = if name.language, do: [{"xml:lang", name.language}], else: []
    attrs = if name.is_historical, do: attrs ++ [{"type", "historical"}], else: attrs
    element(:placeName, attrs, name.name)
  end

  defp build_location(%{latitude: nil}), do: []
  defp build_location(%{longitude: nil}), do: []

  defp build_location(place) do
    [element(:location, [element(:geo, "#{place.latitude} #{place.longitude}")])]
  end

  defp build_place_idno(%{authority: nil}), do: []
  defp build_place_idno(%{authority_id: nil}), do: []

  defp build_place_idno(place) do
    [element(:idno, %{type: place.authority}, place.authority_id)]
  end

  defp build_place_note(%{note: nil}), do: []
  defp build_place_note(%{note: ""}), do: []

  # type="place" disambiguates this from the link-note nested inside <setting>/<placeName>
  # (see build_setting_ref/2) — same element name, different scope, and a bare <note>
  # sitting among <placeName>/<location>/<idno>/<place> siblings would otherwise be
  # unreadable to a parser without positional guesswork.
  defp build_place_note(place), do: [element(:note, %{type: "place"}, place.note)]

  # `@ana` normally points at an interpretation element; a bare token is a project
  # convention, chosen over `@type` because `@type` on a `<placeName>` already means
  # historical-versus-current inside `<listPlace>`, and one attribute with two meanings
  # in one file is how a parser acquires a bug.
  #
  # The link's historical state comes first, as TEI's `<country>` for a country and a
  # nested `<placeName>` for any other kind; the note stays a bare `<note>` after it.
  defp build_setting_ref(link, gazetteer) do
    attrs = [{"ref", "##{link.place.slug}"}, {"ana", link.role}]
    state = Map.get(gazetteer, link.historical_state_id)

    element(:placeName, attrs, build_state_ref(state) ++ build_link_note(link.note))
  end

  defp build_state_ref(nil), do: []

  defp build_state_ref(%{type: "country"} = state),
    do: [element(:country, %{ref: "##{state.slug}"})]

  defp build_state_ref(state), do: [element(:placeName, %{ref: "##{state.slug}"})]

  defp build_link_note(note) when is_binary(note) and note != "", do: [element(:note, note)]
  defp build_link_note(_note), do: []

  # --- Back: the items after the text, then the bibliography (S4) ---

  defp build_back(items, groups), do: element(:back, items ++ build_bibliography(groups))

  defp build_bibliography([]), do: []

  defp build_bibliography(groups) do
    [
      element(
        :div,
        %{type: "bibliografia"},
        Enum.map(groups, fn {kind, subgroups} ->
          element(
            :listBibl,
            %{type: Entry.tei_list(kind)},
            for({_language, links} <- subgroups, link <- links, do: build_bibl_struct(link))
          )
        end)
      )
    ]
  end

  # In the order TEI requires. The entry's `note` and the link's are for researchers and
  # never leave Playcode: this file is published with the static site. A field that may
  # hold italics goes out on one line (inline_element/3): an indented one would put a space
  # between "<<Adonis y Venus>>" and ": hacia", and a reference is matched on its words.
  defp build_bibl_struct(%{entry: e} = link, extra \\ %{}) do
    attrs =
      %{"type" => Entry.tei_type(e.pub_type), "xml:lang" => e.language}
      |> Map.merge(extra)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    element(
      :biblStruct,
      attrs,
      [
        build_analytic(e),
        build_monogr(e),
        if(filled?(e.series),
          do:
            element(:series, [
              inline_element(:title, %{level: "s"}, build_inline_content(e.series))
            ])
        ),
        if(filled?(e.public_note),
          do: inline_element(:note, %{}, build_inline_content(e.public_note))
        ),
        ptr(Entry.tei_url(e.url)),
        # Where this play sits in the edition, apart from the edition's own volume and pages.
        cited_range("volume", link.volume),
        cited_range("page", link.pages)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    )
  end

  defp build_analytic(e) do
    if Enum.any?(
         [e.analytic_author, e.analytic_title, e.analytic_editors, e.analytic_translators],
         &filled?/1
       ) do
      element(
        :analytic,
        Enum.reject(
          bibl_people(e.analytic_author, e.analytic_editors, e.analytic_translators) ++
            [
              if(filled?(e.analytic_title),
                do: inline_element(:title, %{level: "a"}, build_inline_content(e.analytic_title))
              )
            ],
          &is_nil/1
        )
      )
    end
  end

  defp build_monogr(e) do
    level = if e.pub_type == "article", do: "j", else: "m"

    element(
      :monogr,
      Enum.reject(
        bibl_people(e.monogr_author, e.monogr_editors, e.monogr_translators) ++
          [
            inline_element(:title, %{level: level}, build_inline_content(e.monogr_title)),
            if(filled?(e.original_title),
              do:
                inline_element(
                  :title,
                  %{type: "original"},
                  build_inline_content(e.original_title)
                )
            ),
            if(filled?(e.siglum), do: element(:idno, %{type: "siglum"}, e.siglum)),
            if(filled?(e.edition), do: element(:edition, e.edition)),
            build_imprint(e),
            if(filled?(e.volumes_total), do: element(:extent, "#{e.volumes_total} vols.")),
            bibl_scope("volume", e.volume),
            bibl_scope("issue", e.issue),
            bibl_scope("page", e.pages)
          ],
        &is_nil/1
      )
    )
  end

  defp bibl_people(author, editors, translators) do
    people(author, &inline_element(:author, %{}, build_inline_content(&1))) ++
      people(editors, &element(:editor, &1)) ++
      people(translators, &element(:editor, %{role: "translator"}, &1))
  end

  # One element per person: FileMaker keeps several in one field ("Morris, Brian; Gill,
  # Roma"), TEI gives each their own. The import joins them again (Entry.people/1).
  defp people(field, build) do
    if filled?(field),
      do: field |> Entry.people() |> Enum.map(build),
      else: []
  end

  defp build_imprint(e) do
    year = if filled?(e.year_text), do: String.trim(e.year_text)

    children =
      Enum.reject(
        [
          if(filled?(e.pub_place), do: element(:pubPlace, e.pub_place)),
          if(filled?(e.publisher), do: element(:publisher, e.publisher)),
          if(year,
            do: element(:date, if(year =~ ~r/^\d{4}$/, do: %{when: year}, else: %{}), year)
          ),
          if(filled?(e.url_accessed_on),
            do: element(:date, %{type: "access"}, e.url_accessed_on)
          )
        ],
        &is_nil/1
      )

    # The schema needs something inside an <imprint>.
    element(:imprint, if(children == [], do: [element(:date)], else: children))
  end

  defp bibl_scope(unit, value),
    do: if(filled?(value), do: element(:biblScope, %{unit: unit}, value))

  defp ptr(nil), do: nil
  defp ptr(url), do: element(:ptr, %{target: url})

  defp cited_range(unit, value),
    do: if(filled?(value), do: element(:citedRange, %{unit: unit}, value))

  defp filled?(value), do: is_binary(value) and String.trim(value) != ""

  # --- Text ---

  # The outline in order, each item where its place puts it (`Outline.placement/1`): in
  # <front> before the first division of the text, in <body> between, in <back> after.
  defp build_text(play, divisions, performances, gazetteer) do
    divisions = with_folio_parts(divisions)
    lists = cast_lists(divisions)

    cast = %{
      declaring: declaring_entries(lists),
      # The list a performance takes its actors from (`corresp="#castlist"`): the first.
      castlist:
        if(Enum.any?(performances, & &1.cast_from_cast_list),
          do: Enum.find_value(lists, &(&1.entries != [] && &1.id))
        )
    }

    placed = Outline.placement(Outline.items(play.paratexts, divisions))
    section = fn name -> for {^name, item} <- placed, do: item end

    element(:text, [
      element(
        :front,
        [title_page(play)] ++
          Enum.map(section.(:front), &outer_item(&1, :front, cast)) ++
          build_performances(performances, gazetteer)
      ),
      element(:body, Enum.map(section.(:body), &body_item(&1, cast))),
      build_back(
        Enum.map(section.(:back), &outer_item(&1, :back, cast)),
        Playcode.Bibliography.list_for_play(play.id)
      )
    ])
  end

  defp title_page(play) do
    element(
      :titlePage,
      [
        element(:docTitle, [element(:titlePart, [element(:title, play.title)])]),
        if(play.author_name, do: element(:docAuthor, play.author_name), else: nil)
      ]
      |> Enum.reject(&is_nil/1)
    )
  end

  # An item before or after the text.
  defp outer_item(%Paratext{} = paratext, section, _cast), do: paratext_element(paratext, section)
  defp outer_item(%Division{} = list, _section, cast), do: cast_list_div(list, :div, cast)

  # An item between the divisions of the text: a paratext or a cast list as a div1 of its
  # own, as the files' prologues and dumb shows are.
  defp body_item(%Paratext{} = paratext, _cast), do: paratext_element(paratext, :body)
  defp body_item(%Division{type: "elenco"} = list, cast), do: cast_list_div(list, :div1, cast)
  defp body_item(%Division{} = division, cast), do: build_div1(division, cast)

  # --- Cast lists ---

  # The play's cast lists in outline order: those an act holds after it.
  defp cast_lists(divisions) do
    divisions
    |> Enum.flat_map(&[&1 | &1.children])
    |> Enum.filter(&(&1.type == "elenco"))
  end

  # Each character's first entry, which declares it (`xml:id`); a later one refers to it.
  defp declaring_entries(lists) do
    lists
    |> Enum.flat_map(& &1.entries)
    |> Enum.filter(& &1.character_id)
    |> Enum.uniq_by(& &1.character_id)
    |> MapSet.new(& &1.id)
  end

  # A cast list in a div (div1, div2) of its own, its heading the div's; one with no entries
  # yet is the div and its heading alone, a castList holding at least one castItem.
  defp cast_list_div(list, tag, cast),
    do: element(tag, %{type: "elenco"}, heading(list.title) ++ cast_list(list, [], cast))

  defp cast_list(%{entries: []}, _head, _cast), do: []

  defp cast_list(list, head, cast) do
    attrs = if list.id == cast.castlist, do: %{"xml:id" => "castlist"}, else: %{}
    [element(:castList, attrs, head ++ cast_items(list.entries, cast))]
  end

  defp heading(nil), do: []
  defp heading(text), do: [inline_element(:head, %{}, build_inline_content(text))]

  # The entries in order, consecutive ones under one group heading in a castGroup.
  defp cast_items(entries, cast) do
    entries
    |> Enum.chunk_by(& &1.group_heading)
    |> Enum.flat_map(fn
      [%{group_heading: nil} | _] = items ->
        Enum.map(items, &cast_item(&1, cast))

      [%{group_heading: group} | _] = items ->
        [element(:castGroup, heading(group) ++ Enum.map(items, &cast_item(&1, cast)))]
    end)
  end

  defp cast_item(entry, cast) do
    character = entry.character
    declares? = MapSet.member?(cast.declaring, entry.id)

    role_attrs =
      cond do
        character == nil -> %{}
        declares? -> %{"xml:id" => character.xml_id}
        true -> %{"corresp" => "##{character.xml_id}"}
      end

    description =
      if entry.description,
        do: [inline_element(:roleDesc, %{}, build_inline_content(entry.description))],
        else: []

    actor = if declares? and character.actor, do: [element(:actor, character.actor)], else: []
    item_attrs = if character && character.is_hidden, do: %{ana: "oculto"}, else: %{}

    element(
      :castItem,
      item_attrs,
      [inline_element(:role, role_attrs, build_inline_content(entry.name))] ++
        description ++ actor
    )
  end

  # --- Performances (S5) ---

  # In the list's order, each named by its place in it: `performance-1` is the file's own
  # name for it, never a database id.
  defp build_performances(performances, gazetteer) do
    performances
    |> Enum.with_index(1)
    |> Enum.map(fn {performance, number} ->
      build_performance(performance, number, gazetteer)
    end)
  end

  # The details in a <p>, the cast, the note and the source, in the order TEI's content model
  # gives them. The <p> is always there: the schema wants one paragraph-level element at
  # least, and a performance of a note alone has no other.
  defp build_performance(performance, number, gazetteer) do
    attrs = %{"xml:id" => "performance-#{number}"}

    attrs =
      if performance.cast_from_cast_list, do: Map.put(attrs, :corresp, "#castlist"), else: attrs

    element(
      :performance,
      attrs,
      Enum.reject(
        [
          element(:p, performance_details(performance, gazetteer)),
          build_performance_cast(performance.cast),
          performance.note && element(:note, paragraphs(performance.note)),
          build_performance_source(performance)
        ],
        &is_nil/1
      )
    )
  end

  # When, where and by whom, each as TEI's own element: the date as written with its years
  # as attributes, the venue's name with its type, the town with the state it then belonged
  # to (as a play's setting does), the company.
  defp performance_details(performance, gazetteer) do
    Enum.reject(
      [
        build_performance_date(performance),
        build_venue(performance),
        build_performance_place(performance, gazetteer),
        if(performance.company,
          do: inline_element(:orgName, %{}, build_inline_content(performance.company.name))
        )
      ],
      &is_nil/1
    )
  end

  # A single year is `when`; a span, or one end of it, `notBefore` and `notAfter`.
  defp build_performance_date(%{date_text: nil, year_from: nil, year_to: nil}), do: nil

  defp build_performance_date(performance) do
    attrs =
      case {performance.year_from, performance.year_to} do
        {nil, nil} ->
          %{}

        {year, year} ->
          attributes(when: to_string(year))

        {from, to} ->
          attributes(notBefore: from && to_string(from), notAfter: to && to_string(to))
      end

    inline_element(:date, attrs, build_inline_content(performance.date_text))
  end

  # Empty when only a type is known.
  defp build_venue(%{venue: nil, venue_type: nil}), do: nil

  defp build_venue(performance),
    do:
      inline_element(
        :rs,
        attributes(type: "venue", subtype: performance.venue_type),
        build_inline_content(performance.venue)
      )

  defp build_performance_place(%{place: nil, historical_state_id: nil}, _gazetteer), do: nil

  defp build_performance_place(performance, gazetteer) do
    state = Map.get(gazetteer, performance.historical_state_id)
    attrs = if performance.place, do: %{ref: "##{performance.place.slug}"}, else: %{}

    element(:placeName, attrs, build_state_ref(state))
  end

  defp build_performance_cast([]), do: nil

  defp build_performance_cast(cast),
    do: element(:castList, Enum.map(cast, &build_performance_cast_item/1))

  defp build_performance_cast_item(member) do
    role =
      if member.role,
        do: [inline_element(:role, %{}, build_inline_content(member.role))],
        else: []

    element(:castItem, role ++ [build_actor(member.actor)])
  end

  @actor_sex %{"man" => "M", "woman" => "F"}

  # TEI's own parts of a name, the nickname an `addName`; the sex as `actor@sex`.
  defp build_actor(actor) do
    names =
      Enum.reject(
        [
          actor.forename && inline_element(:forename, %{}, build_inline_content(actor.forename)),
          actor.surname && inline_element(:surname, %{}, build_inline_content(actor.surname)),
          actor.nickname &&
            inline_element(:addName, %{type: "nickname"}, build_inline_content(actor.nickname))
        ],
        &is_nil/1
      )

    element(:actor, attributes(sex: @actor_sex[actor.sex]), [element(:persName, names)])
  end

  # The performance carries its source whole, kind included: question 12 keeps a performance's
  # source out of the play's bibliography, so no listBibl says what kind it is.
  defp build_performance_source(%{source: nil}), do: nil

  defp build_performance_source(performance) do
    build_bibl_struct(
      %{
        entry: performance.source,
        volume: performance.source_volume,
        pages: performance.source_pages
      },
      %{"ana" => Entry.tei_source_kind(performance.source.kind)}
    )
  end

  # A passage that crosses elements is a piece in each (InlineMarkup), and the file marks
  # where it starts and where it ends with an F. The export pairs the pieces again in the
  # order the file is read, not by their stored parts alone: an edit can delete the piece
  # before or after one, or put a text between two, and the stored parts would then write
  # an F with no partner, which the import reads as the start of a passage, inverting every
  # one after it. Two neighbouring texts join when the last piece of the first is part "I"
  # or "M" and the first piece of the second is part "M" or "F". Each run of joined pieces
  # then opens once and closes once, and a piece joined on neither side is a passage of its
  # own, written as the <app>.
  defp with_folio_parts(divisions) do
    {_divisions, texts} = map_reduce_texts(divisions, [], &{&1, [&1 | &2]})

    if Enum.any?(texts, &String.contains?(&1, "<folio part=")) do
      parts =
        ([nil | Enum.reverse(texts)] ++ [nil])
        |> Enum.chunk_every(3, 1, :discard)
        |> Enum.map(fn [before, text, next] ->
          rejoined(text, joined?(before, text), joined?(text, next))
        end)

      {divisions, []} =
        map_reduce_texts(divisions, parts, fn _text, [text | rest] -> {text, rest} end)

      divisions
    else
      divisions
    end
  end

  # Whether `text` and the `next` one join. A part says where its piece stands
  # (Element.changeset): an "I" or "M" piece ends its text, an "M" or "F" one starts it.
  defp joined?(nil, _next), do: false
  defp joined?(_text, nil), do: false

  defp joined?(text, next) do
    String.contains?(text, [~s(<folio part="I">), ~s(<folio part="M">)]) and
      String.contains?(next, [~s(<folio part="M">), ~s(<folio part="F">)])
  end

  # `text` with the parts its joins give its pieces: the first ("M" or "F") comes from the
  # text before only when joined to it, the last ("I" or "M") goes on only when joined to
  # the next.
  defp rejoined(text, open_before, goes_on) do
    Regex.replace(~r/<folio part="([IMF])">/, text, fn _tag, part ->
      folio_tag(part in ~w(M F) and open_before, part in ~w(I M) and goes_on)
    end)
  end

  defp folio_tag(true, true), do: ~s(<folio part="M">)
  defp folio_tag(true, false), do: ~s(<folio part="F">)
  defp folio_tag(false, true), do: ~s(<folio part="I">)
  defp folio_tag(false, false), do: "<folio>"

  # The texts of the body that may hold a piece, in the order the file reads them, each
  # through `fun` with an accumulator: a speech's label, then its lines, paragraphs and
  # stage directions. Headings and trailers hold none, and the import reads through them.
  defp map_reduce_texts(nodes, acc, fun) when is_list(nodes),
    do: Enum.map_reduce(nodes, acc, &map_reduce_texts(&1, &2, fun))

  defp map_reduce_texts(%Division{} = division, acc, fun) do
    {elements, acc} = map_reduce_texts(division.loaded_elements, acc, fun)
    {children, acc} = map_reduce_texts(division.children, acc, fun)
    {%{division | loaded_elements: elements, children: children}, acc}
  end

  defp map_reduce_texts(%Element{type: type} = element, acc, fun)
       when type in ~w(speech line_group) do
    {label, acc} = map_reduce_text(element.speaker_label, acc, fun)
    {children, acc} = map_reduce_texts(element.children, acc, fun)
    {%{element | speaker_label: label, children: children}, acc}
  end

  defp map_reduce_texts(%Element{type: type} = element, acc, fun)
       when type in ~w(verse_line prose stage_direction) do
    {content, acc} = map_reduce_text(element.content, acc, fun)
    {%{element | content: content}, acc}
  end

  defp map_reduce_texts(other, acc, _fun), do: {other, acc}

  defp map_reduce_text(text, acc, _fun) when text in [nil, ""], do: {text, acc}
  defp map_reduce_text(text, acc, fun), do: fun.(text, acc)

  # A text's line breaks as <lb/>, wherever they fall, inside an <emph> or a <stage> too:
  # the italics and stages are read first, so a break cannot leave their markers as text.
  defp with_breaks(text) when is_binary(text), do: lines(text)

  defp with_breaks(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &List.wrap(with_breaks(&1)))

  # XmlBuilder holds a string inside an element as a text node, {nil, nil, text}: not an
  # element named nil (EMOTHE0488's glued italics ending in breaks exported as `<>…</>`).
  defp with_breaks({nil, nil, text}) when is_binary(text), do: lines(text)
  defp with_breaks({name, attrs, content}), do: {name, attrs, with_breaks(content)}
  defp with_breaks(other), do: other

  # A paratext: a div of its kind before or after the text, a div1 between the divisions
  # of the text. The scene of the action is the front's <set>; elsewhere, where TEI has no
  # <set>, a div of the files' own `circunstancia_accion`.
  defp paratext_element(paratext, section) do
    paragraphs =
      for paragraph <- String.split(paratext.content || "", "\n\n", trim: true),
          do: inline_element(:p, %{}, build_inline_content(paragraph))

    content = heading(paratext.heading) ++ paragraphs

    tag = if section == :body, do: :div1, else: :div

    case {Paratext.scene?(paratext.kind), section} do
      {true, :front} -> element(:set, content)
      {true, _section} -> element(tag, %{type: "circunstancia_accion"}, content)
      {false, _section} -> element(tag, paratext_attrs(paratext.kind, section), content)
    end
  end

  # Between the acts a paratext whose kind is also a division's type (`prologo`,
  # `argumento`) says it is one, `ana="paratexto"`, or the import would read a division.
  defp paratext_attrs(kind, :body) do
    if kind in Division.body_types(),
      do: %{type: kind, ana: "paratexto"},
      else: %{type: kind}
  end

  defp paratext_attrs(kind, _section), do: %{type: kind}

  # An act: its heading, the cast lists that open it before any element (a bare castList,
  # its head inside), its own elements, then its scenes and its other lists in their order,
  # then its trailers, as TEI allows a trailer only at the end.
  defp build_div1(div, cast) do
    attrs = %{type: div.type}
    attrs = if div.number, do: Map.put(attrs, :n, to_string(div.number)), else: attrs

    {trailers, elements} =
      div |> Map.get(:loaded_elements, []) |> Enum.split_with(&(&1.type == "trailer"))

    {opening, children} = div |> Map.get(:children, []) |> Division.split_opening_lists()

    element(
      :div1,
      attrs,
      division_heading(div) ++
        Enum.flat_map(opening, &cast_list(&1, heading(&1.title), cast)) ++
        (Enum.map(elements, &build_element/1) |> Enum.reject(&is_nil/1)) ++
        Enum.map(children, &build_div2(&1, cast)) ++
        Enum.map(trailers, &build_element/1)
    )
  end

  defp build_div2(%{type: "elenco"} = list, cast), do: cast_list_div(list, :div2, cast)

  defp build_div2(scene, _cast) do
    attrs = %{type: scene.type}
    attrs = if scene.number, do: Map.put(attrs, :n, to_string(scene.number)), else: attrs

    elements =
      scene
      |> Map.get(:loaded_elements, [])
      |> Enum.map(&build_element/1)
      |> Enum.reject(&is_nil/1)

    element(:div2, attrs, division_heading(scene) ++ elements)
  end

  # An act's or a scene's head, with the notes in it.
  defp division_heading(%{title: nil}), do: []

  defp division_heading(division),
    do: [inline_element(:head, %{}, build_inline_content(division.title, division.notes))]

  defp build_element(%{type: "speech"} = el) do
    children = []

    children =
      if el.speaker_label,
        do: [
          inline_element(:speaker, %{}, build_inline_content(el.speaker_label, el.notes))
          | children
        ],
        else: children

    child_elements =
      Map.get(el, :children, [])
      |> Enum.map(&build_element/1)
      |> Enum.reject(&is_nil/1)

    chars = Playcode.PlayContent.Element.characters(el)

    attrs =
      case chars do
        [] -> %{}
        list -> %{who: Enum.map_join(list, " ", &"##{&1.xml_id}")}
      end

    element(:sp, attrs, children ++ child_elements)
  end

  defp build_element(%{type: "line_group"} = el) do
    attrs = %{}
    attrs = if el.verse_type, do: Map.put(attrs, :type, el.verse_type), else: attrs
    attrs = if el.part, do: Map.put(attrs, :part, el.part), else: attrs

    lines = Map.get(el, :children, []) |> Enum.map(&build_element/1) |> Enum.reject(&is_nil/1)
    element(:lg, attrs, lines)
  end

  defp build_element(%{type: "verse_line"} = el) do
    attrs = %{}
    attrs = if el.line_id, do: Map.put(attrs, "xml:id", el.line_id), else: attrs

    attrs =
      if el.line_number,
        do: Map.put(attrs, :n, String.pad_leading(to_string(el.line_number), 4, "0")),
        else: attrs

    attrs = if el.part, do: Map.put(attrs, :part, el.part), else: attrs
    attrs = if el.rend, do: Map.put(attrs, :rend, el.rend), else: attrs

    inline_element(:l, attrs, spoken_content(el, el.content))
  end

  defp build_element(%{type: "stage_direction"} = el) do
    attrs = if el.stage_type, do: %{type: el.stage_type}, else: %{}
    inline_element(:stage, attrs, build_inline_content(el.content, el.notes))
  end

  defp build_element(%{type: "prose"} = el) do
    # The number at the very start of the text is the paragraph's own (p@n).
    {number, text} = InlineMarkup.paragraph_number(el.content)
    inline_element(:p, if(number, do: %{n: number}, else: %{}), spoken_content(el, text))
  end

  defp build_element(%{type: "trailer"} = el),
    do: inline_element(:trailer, %{}, build_inline_content(el.content, el.notes))

  defp build_element(_), do: nil

  # The text of a line or paragraph: in one <seg type="aside"> when it is all aside, and
  # when it is partly, each <aside> marker a seg, a note at an aside's end inside it.
  defp spoken_content(el, text) do
    cond do
      Element.whole_aside?(el) ->
        [element(:seg, %{type: "aside"}, build_inline_content(text, el.notes))]

      el.is_aside ->
        {nodes, _} =
          ~r{<aside>.*?</aside>}s
          |> Regex.split(text, include_captures: true, trim: true)
          |> Enum.flat_map_reduce({0, el.notes}, &aside_piece/2)

        nodes

      true ->
        build_inline_content(text, el.notes)
    end
  end

  # One piece of a text partly aside, starting `at` graphemes into its plain form, with the
  # notes not yet placed. Its notes go in with offsets counted from its own start.
  defp aside_piece(piece, {at, notes}) do
    {aside?, words} =
      case piece do
        "<aside>" <> rest -> {true, String.replace_suffix(rest, "</aside>", "")}
        words -> {false, words}
      end

    stop = at + String.length(InlineMarkup.plain(words))
    {here, later} = Enum.split_with(notes, &(&1.offset <= stop))
    inline = build_inline_content(words, Enum.map(here, &%{&1 | offset: &1.offset - at}))

    nodes =
      if aside?, do: [element(:seg, %{type: "aside"}, inline)], else: List.wrap(inline)

    {nodes, {stop, later}}
  end

  # A text as TEI: <<…>> becomes <emph>, as the EMOTHE corpus writes italics (<hi
  # rend="italic"> would do too, per TEI P5), and each note goes back at its offset
  # (InlineMarkup.parts/2). The bibliography has no notes.
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

  # A Folio passage (InlineMarkup): inside one element, the <app type="folio"> question 36
  # agreed, the base text (Q2) lacking what the Folio (F1) reads. Its stages, numbers and
  # notes nest in the reading as they would anywhere.
  defp inline_nodes([%{folio: %{run: run} = folio} | _] = parts) do
    {inside, rest} = Enum.split_while(parts, &match?(%{folio: %{run: ^run}}, &1))
    words = inside |> Enum.map(&Map.delete(&1, :folio)) |> inline_nodes()
    folio_nodes(folio.part, words) ++ inline_nodes(rest)
  end

  # A stage direction: its pieces, the notes among them included, go inside one <stage>.
  # Its italics and notes nest as they would anywhere, so the pieces are read again with
  # the stage taken off.
  defp inline_nodes([%{stage: %{run: run} = stage} | _] = parts) do
    {inside, rest} = Enum.split_while(parts, &match?(%{stage: %{run: ^run}}, &1))
    attrs = if stage.type, do: %{type: stage.type}, else: %{}

    content =
      case inside |> Enum.map(&%{&1 | stage: nil}) |> inline_nodes() do
        [text] when is_binary(text) -> text
        nodes -> nodes
      end

    [element(:stage, attrs, content) | inline_nodes(rest)]
  end

  # A note inside an italic run, which InlineMarkup.parts/2 splits there, goes back inside
  # its <emph>, as the source had it: split, the space after the note would open the
  # second <emph>, and the importer, which trims italics, would glue the words together.
  defp inline_nodes([%{italic: true} | _] = parts) do
    {run, rest} = italic_run(parts)

    emph =
      case Enum.map(run, &inline_node/1) do
        [text] -> text
        nodes -> nodes
      end

    [element(:emph, emph) | inline_nodes(rest)]
  end

  defp inline_nodes([part | rest]), do: [inline_node(part) | inline_nodes(rest)]
  defp inline_nodes([]), do: []

  defp folio_nodes(nil, words),
    do: [
      element(:app, %{type: "folio"}, [
        element(:lem, %{wit: "#Q2"}, []),
        element(:rdg, %{wit: "#F1"}, words)
      ])
    ]

  # A piece of a passage that crosses elements: the file's own form, until question 37
  # settles a TEI one. One span around the element's words; the F where the passage starts
  # (part "I") or ends ("F").
  defp folio_nodes(part, words) do
    label = [element(:code, "<sup>"), "F", element(:code, "</sup>")]
    opening = [element(:code, ~s(<span class="folio">))] ++ if(part == "I", do: label, else: [])
    closing = if(part == "F", do: label, else: []) ++ [element(:code, "</span>")]

    opening ++ words ++ closing
  end

  # An italic piece and the italic pieces that follow it: the halves of one a note split
  # merge into a single <emph>. Two runs side by side (`<<a>><<b>>`) stay two, as the file
  # wrote them, which the importer now reads glued. A note after an italic run ends it, and
  # so does a Folio passage, which holds its own italics.
  defp italic_run([piece | rest]) do
    case Enum.split_while(rest, &match?(%{note: _, italic: true}, &1)) do
      {[_ | _] = notes, [%{italic: true, stage: nil} = next | _] = more}
      when not is_map_key(next, :folio) ->
        {run, rest} = italic_run(more)
        {[piece | notes] ++ run, rest}

      _ ->
        {[piece], rest}
    end
  end

  defp inline_node(%{note: note}),
    do: if(Note.variant?(note), do: build_app(note), else: build_note(note))

  defp inline_node(%{number: n}), do: element(:lb, %{n: n})
  defp inline_node(%{text: text}), do: text

  defp build_note(note) do
    attrs = attributes(n: note.n, type: note.type)
    term = if note.term, do: [element(:term, build_inline_content(note.term))], else: []
    paragraphs = Enum.map(Note.paragraphs(note), &element(:p, build_inline_content(&1)))
    element(:note, attrs, term ++ paragraphs)
  end

  # A variant (Note.variant?/1) as the <app> it was read from: its readings in order, a
  # reading's note inside it, the entry's own note last.
  defp build_app(note) do
    readings =
      Enum.map(note.readings, fn reading ->
        element(
          if(reading.lemma, do: :lem, else: :rdg),
          attributes(wit: reading.wit),
          inline_children(reading.text) ++ note_element(reading.note)
        )
      end)

    element(
      :app,
      attributes(type: note.variant_type, n: note.n, to: note.range_end),
      readings ++ note_element(note.body)
    )
  end

  # The pairs that have a value, as attributes.
  defp attributes(pairs), do: for({key, value} <- pairs, value, into: %{}, do: {key, value})

  # A text as an element's children: none when it is empty.
  defp inline_children(text) do
    case build_inline_content(text) do
      "" -> []
      nodes -> List.wrap(nodes)
    end
  end

  # A text as a <note> of paragraphs, or nothing for none.
  defp note_element(nil), do: []

  defp note_element(text),
    do: [element(:note, Enum.map(Note.paragraphs(text), &element(:p, build_inline_content(&1))))]

  # An element whose text holds others (<emph>, <note>) goes out on one line, its text
  # exactly as it runs: :indent would put line breaks inside it, and a break before a
  # <note> reads back as a space between the word and what follows it.
  defp inline_element(name, attrs, content) when is_list(content),
    do: {:iodata, XmlBuilder.generate(element(name, attrs, content), format: :none)}

  defp inline_element(name, attrs, content), do: element(name, attrs, content)
end
