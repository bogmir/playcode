defmodule Playcode.Export.TeiXml do
  @moduledoc """
  Generates TEI-XML from a play record and its content.
  """

  alias Playcode.PlayContent
  import XmlBuilder

  @body_types ~w(acto jornada prologo argumento act acte play prologue induction epilogue
                 interlude dumb_show auto)

  def generate(play) do
    play =
      Playcode.Repo.preload(play, [
        :editors,
        :sources,
        :editorial_notes,
        play_places: [place: :names]
      ])

    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.load_play_content(play.id)

    tei =
      element(
        :TEI,
        %{"xml:lang" => play.language || "es", "xmlns" => "http://www.tei-c.org/ns/1.0"},
        [
          build_header(play),
          build_text(play, characters, divisions)
        ]
      )

    "<?xml version=\"1.0\" ?>\n" <>
      XmlBuilder.generate(tei, format: :indent, encoding: nil)
  end

  # --- Header ---

  defp build_header(play) do
    element(:teiHeader, [
      build_file_desc(play),
      build_encoding_desc(play),
      build_profile_desc(play)
    ])
  end

  defp build_file_desc(play) do
    element(:fileDesc, [
      build_title_stmt(play),
      build_edition_stmt(play),
      build_extent(play),
      build_publication_stmt(play),
      build_source_desc(play)
    ])
  end

  defp build_title_stmt(play) do
    # Main title — use type="traduccion" if this is a translation
    main_title_attrs =
      if play.relationship_type == "traduccion", do: %{type: "traduccion"}, else: %{}

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

    # Translators and the critical edition's editor as <editor role="…"><persName>…
    translators =
      play.editors
      |> Enum.filter(&(&1.role == "translator"))
      |> Enum.map(fn e ->
        element(:editor, %{role: "translator"}, [element(:persName, e.person_name)])
      end)

    critical_editors =
      play.editors
      |> Enum.filter(&(&1.role == "critical_editor"))
      |> Enum.map(fn e ->
        org = if e.organization, do: [element(:orgName, e.organization)], else: []
        element(:editor, %{role: "edicion_critica"}, [element(:persName, e.person_name) | org])
      end)

    # respStmt for digital editors in titleStmt (from titleStmt import)
    resp_stmts =
      play.editors
      |> Enum.filter(
        &(&1.role in ["digital_editor", "editor", "reviewer"] and &1.position >= 100 and
            &1.position < 200)
      )
      |> Enum.map(fn e ->
        resp_label =
          case e.role do
            "editor" -> "Edición"
            "reviewer" -> "Revisión"
            _ -> "Electronic edition"
          end

        children = [element(:resp, resp_label), element(:persName, e.person_name)]

        children =
          if e.organization,
            do: children ++ [element(:orgName, e.organization)],
            else: children

        element(:respStmt, children)
      end)

    principal =
      play.editors
      |> Enum.filter(&(&1.role == "principal"))
      |> Enum.map(fn e -> element(:principal, e.person_name) end)

    sponsor =
      if play.sponsor,
        do: [element(:sponsor, [element(:orgName, play.sponsor)])],
        else: []

    funder =
      if play.funder,
        do: [element(:funder, [element(:orgName, play.funder)])],
        else: []

    element(
      :titleStmt,
      titles ++
        authors ++ translators ++ critical_editors ++ sponsor ++ funder ++ resp_stmts ++ principal
    )
  end

  defp build_edition_stmt(play) do
    # Positions 100..199 are titleStmt's respStmts, already written there by
    # build_title_stmt/1. Writing them here too made a re-import create each one twice.
    editors =
      play.editors
      |> Enum.filter(&(&1.role in ["editor", "digital_editor", "reviewer"]))
      |> Enum.reject(&(&1.position in 100..199))
      |> Enum.map(fn e ->
        resp_label =
          case e.role do
            "editor" -> "Edición"
            "reviewer" -> "Revisión"
            _ -> "Edición digital"
          end

        children = [
          element(:resp, resp_label),
          element(:persName, e.person_name)
        ]

        children =
          if e.organization,
            do: children ++ [element(:orgName, e.organization)],
            else: children

        element(:respStmt, children)
      end)

    element(:editionStmt, [
      element(:edition, "Edición electrónica de '#{play.title}'")
      | editors
    ])
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
          do: acc ++ [element(:p, play.availability_note)],
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
            if(source.title, do: element(:title, source.title)),
            if(source.author, do: element(:author, source.author)),
            if source.editor do
              attrs = if source.editor_role, do: %{role: source.editor_role}, else: %{}
              element(:editor, attrs, source.editor)
            end,
            if(source.publisher, do: element(:publisher, source.publisher)),
            if(source.pub_place, do: element(:pubPlace, source.pub_place)),
            if(source.pub_date, do: element(:date, source.pub_date)),
            if(source.language, do: element(:lang, source.language)),
            if(source.note, do: element(:note, source.note))
          ]
          |> Enum.reject(&is_nil/1)

        element(:bibl, children)
      end)

    element(:sourceDesc, if(bibls == [], do: [element(:p, "")], else: bibls))
  end

  defp build_encoding_desc(play) do
    children = []

    children =
      if play.project_description,
        do: children ++ [element(:projectDesc, [element(:p, play.project_description)])],
        else: children

    children =
      if play.editorial_declaration,
        do: children ++ [element(:editorialDecl, [element(:p, play.editorial_declaration)])],
        else: children

    element(:encodingDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  @language_ident_labels %{
    "es" => {"es-ES", "Español"},
    "en" => {"en-EN", "English"},
    "it" => {"it-IT", "Italiano"},
    "ca" => {"ca-ES", "Català"},
    "fr" => {"fr-FR", "Français"},
    "pt" => {"pt-PT", "Português"}
  }

  defp build_profile_desc(play) do
    {ident, label} = Map.get(@language_ident_labels, play.language || "es", {"es-ES", "Español"})

    children =
      build_creation(play) ++
        [element(:langUsage, [element(:language, %{ident: ident}, label)])]

    element(:profileDesc, children ++ build_setting_desc(play))
  end

  # <creation> is where TEI records when the text *in this file* was composed. Emitted
  # only when we hold machine-readable years, so a note with no dating stays out of the
  # XML rather than arriving as an undated <date>. The note is the element's text — the
  # human-readable form of the machine attributes.
  defp build_creation(%{composition_date_from: nil}), do: []

  defp build_creation(play) do
    attrs =
      if play.composition_date_from == play.composition_date_to do
        %{when: to_string(play.composition_date_from)}
      else
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

  # Two elements, on purpose. `listPlace` nests every place the play needs *plus every
  # ancestor*, so containment is complete — which means a `<place>` may be a pure
  # container. `setting` is therefore what says which of them the play actually
  # references, because "the leaves are the settings" is wrong: a play can be set in
  # Italy itself.
  defp build_setting_desc(%{play_places: []}), do: []

  defp build_setting_desc(%{play_places: links}) when is_list(links) do
    gazetteer = Playcode.Places.gazetteer()
    ordered = Enum.sort_by(links, fn link -> {link.role != "setting", link.position} end)

    roots =
      ordered
      |> Enum.map(& &1.place)
      |> Enum.flat_map(fn place ->
        [place | Playcode.Places.ancestors(place, gazetteer)]
      end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(&is_nil(&1.parent_place_id))

    wanted =
      ordered
      |> Enum.map(& &1.place)
      |> Enum.flat_map(fn place -> [place | Playcode.Places.ancestors(place, gazetteer)] end)
      |> MapSet.new(& &1.id)

    [
      element(:settingDesc, [
        element(:listPlace, Enum.map(roots, &build_place(&1, gazetteer, wanted))),
        element(:setting, Enum.map(ordered, &build_setting_ref/1))
      ])
    ]
  end

  defp build_setting_desc(_play), do: []

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
  # (see build_setting_ref/1) — same element name, different scope, and a bare <note>
  # sitting among <placeName>/<location>/<idno>/<place> siblings would otherwise be
  # unreadable to a parser without positional guesswork.
  defp build_place_note(place), do: [element(:note, %{type: "place"}, place.note)]

  # `@ana` normally points at an interpretation element; a bare token is a project
  # convention, chosen over `@type` because `@type` on a `<placeName>` already means
  # historical-versus-current inside `<listPlace>`, and one attribute with two meanings
  # in one file is how a parser acquires a bug.
  defp build_setting_ref(link) do
    attrs = [{"ref", "##{link.place.slug}"}, {"ana", link.role}]

    case link.note do
      note when is_binary(note) and note != "" ->
        element(:placeName, attrs, [element(:note, note)])

      _ ->
        element(:placeName, attrs, nil)
    end
  end

  # --- Back: the bibliography (S4) ---

  @list_types %{
    "modern_edition" => "ediciones_modernas",
    "criticism" => "critica",
    "translation" => "traducciones",
    "adaptation" => "adaptaciones"
  }

  # FileMaker's own type names (T12.11), as the corpus spells its other types in Spanish.
  @bibl_types %{
    "article" => "articulo_revista",
    "book_section" => "seccion_libro",
    "scholarly_edition" => "edicion_estudioso",
    "book" => "libro",
    "proceedings" => "acta",
    "prologue" => "prologo",
    "festschrift" => "homenaje",
    "electronic" => "publicacion_electronica",
    "thesis" => "tesis_doctorado",
    "collection" => "coleccion"
  }

  defp build_back([]), do: element(:back)

  defp build_back(groups) do
    element(:back, [
      element(
        :div,
        %{type: "bibliografia"},
        Enum.map(groups, fn {kind, subgroups} ->
          element(
            :listBibl,
            %{type: @list_types[kind]},
            for({_language, links} <- subgroups, link <- links, do: build_bibl_struct(link))
          )
        end)
      )
    ])
  end

  # In the order TEI requires. The entry's `note` and the link's are for researchers and
  # never leave Playcode: this file is published with the static site.
  defp build_bibl_struct(%{entry: e} = link) do
    attrs =
      %{"type" => @bibl_types[e.pub_type], "xml:lang" => e.language}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    element(
      :biblStruct,
      attrs,
      [
        build_analytic(e),
        build_monogr(e, link),
        if(filled?(e.series),
          do: element(:series, [element(:title, %{level: "s"}, build_inline_content(e.series))])
        ),
        if(filled?(e.public_note), do: element(:note, build_inline_content(e.public_note))),
        # ponytail: only an http(s) address is a valid target; the FileMaker strays
        # (". http://…") stay in the database for curators to clean.
        if(filled?(e.url) and String.trim(e.url) =~ ~r{\Ahttps?://\S+\z}i,
          do: element(:ptr, %{target: String.trim(e.url)})
        )
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
                do: element(:title, %{level: "a"}, build_inline_content(e.analytic_title))
              )
            ],
          &is_nil/1
        )
      )
    end
  end

  defp build_monogr(e, link) do
    volume = if filled?(link.volume), do: link.volume, else: e.volume
    pages = if filled?(link.pages), do: link.pages, else: e.pages
    level = if e.pub_type == "article", do: "j", else: "m"

    element(
      :monogr,
      Enum.reject(
        bibl_people(e.monogr_author, e.monogr_editors, e.monogr_translators) ++
          [
            element(:title, %{level: level}, build_inline_content(e.monogr_title)),
            if(filled?(e.original_title),
              do: element(:title, %{type: "original"}, build_inline_content(e.original_title))
            ),
            if(filled?(e.siglum), do: element(:idno, %{type: "siglum"}, e.siglum)),
            if(filled?(e.edition), do: element(:edition, e.edition)),
            build_imprint(e),
            if(filled?(e.volumes_total), do: element(:extent, "#{e.volumes_total} vols.")),
            bibl_scope("volume", volume),
            bibl_scope("issue", e.issue),
            bibl_scope("page", pages)
          ],
        &is_nil/1
      )
    )
  end

  defp bibl_people(author, editors, translators) do
    [
      if(filled?(author), do: element(:author, build_inline_content(author))),
      if(filled?(editors), do: element(:editor, editors)),
      if(filled?(translators), do: element(:editor, %{role: "translator"}, translators))
    ]
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

  defp filled?(value), do: is_binary(value) and String.trim(value) != ""

  # --- Text ---

  defp build_text(play, characters, divisions) do
    body_divisions = Enum.filter(divisions, fn d -> d.type in @body_types end)

    element(:text, [
      build_front(play, characters),
      build_body(body_divisions),
      build_back(Playcode.Bibliography.list_for_play(play.id))
    ])
  end

  defp build_front(play, characters) do
    title_page =
      element(
        :titlePage,
        [
          element(:docTitle, [element(:titlePart, [element(:title, play.title)])]),
          if(play.author_name, do: element(:docAuthor, play.author_name), else: nil)
        ]
        |> Enum.reject(&is_nil/1)
      )

    # Editorial notes as front divs with their stored section_type
    note_divs =
      play.editorial_notes
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn note ->
        head = if note.heading, do: [element(:head, note.heading)], else: []

        paragraphs =
          note.content
          |> String.split("\n\n")
          |> Enum.map(&element(:p, &1))

        element(:div, %{type: note.section_type}, head ++ paragraphs)
      end)

    # Cast list
    cast_list =
      if characters != [] do
        cast_items =
          Enum.map(characters, fn char ->
            role_attrs = %{"xml:id" => char.xml_id}

            children = [element(:role, role_attrs, char.name)]

            children =
              if char.description,
                do: children ++ [element(:roleDesc, char.description)],
                else: children

            item_attrs = if char.is_hidden, do: %{ana: "oculto"}, else: %{}
            element(:castItem, item_attrs, children)
          end)

        [element(:div, %{type: "elenco"}, [element(:castList, cast_items)])]
      else
        []
      end

    element(:front, [title_page] ++ note_divs ++ cast_list)
  end

  defp build_body(body_divisions) do
    divs =
      Enum.map(body_divisions, fn div ->
        attrs = %{type: div.type}
        attrs = if div.number, do: Map.put(attrs, :n, to_string(div.number)), else: attrs

        children = if div.title, do: [element(:head, div.title)], else: []

        # Add elements from the division. TEI only allows a trailer at the end, so the
        # act's trailers follow its scenes.
        {trailers, elements} =
          div |> Map.get(:loaded_elements, []) |> Enum.split_with(&(&1.type == "trailer"))

        element_xml = Enum.map(elements, &build_element/1) |> Enum.reject(&is_nil/1)

        # Add sub-divisions (scenes, etc.)
        sub_divs =
          Map.get(div, :children, [])
          |> Enum.map(fn child ->
            child_attrs = %{type: child.type}

            child_attrs =
              if child.number,
                do: Map.put(child_attrs, :n, to_string(child.number)),
                else: child_attrs

            child_head = if child.title, do: [element(:head, child.title)], else: []

            child_elements =
              Map.get(child, :loaded_elements, [])
              |> Enum.map(&build_element/1)
              |> Enum.reject(&is_nil/1)

            element(:div2, child_attrs, child_head ++ child_elements)
          end)

        element(
          :div1,
          attrs,
          children ++ element_xml ++ sub_divs ++ Enum.map(trailers, &build_element/1)
        )
      end)

    element(:body, divs)
  end

  defp build_element(%{type: "speech"} = el) do
    children = []

    children =
      if el.speaker_label, do: [element(:speaker, el.speaker_label) | children], else: children

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

    inline = build_inline_content(el.content)

    content =
      if el.is_aside do
        [element(:seg, %{type: "aside"}, inline)]
      else
        inline
      end

    element(:l, attrs, content)
  end

  defp build_element(%{type: "stage_direction"} = el) do
    attrs = if el.stage_type, do: %{type: el.stage_type}, else: %{}
    element(:stage, attrs, build_inline_content(el.content))
  end

  defp build_element(%{type: "prose"} = el) do
    inline = build_inline_content(el.content)

    content =
      if el.is_aside do
        [element(:seg, %{type: "aside"}, inline)]
      else
        inline
      end

    element(:p, content)
  end

  defp build_element(%{type: "trailer"} = el),
    do: element(:trailer, build_inline_content(el.content))

  defp build_element(_), do: nil

  # Converts <<text>> markers to <emph> elements for TEI export.
  # Uses <emph> to match existing EMOTHE corpus convention.
  # Could also use <hi rend="italic"> per TEI P5 for purely typographic italics.
  defp build_inline_content(nil), do: ""

  defp build_inline_content(text) do
    parts =
      Regex.split(~r/<<(.*?)>>/, text, include_captures: true)
      |> Enum.map(fn part ->
        case Regex.run(~r/^<<(.*)>>$/, part) do
          [_, inner] -> element(:emph, inner)
          nil -> part
        end
      end)
      |> Enum.reject(fn
        p when is_binary(p) -> p == ""
        _ -> false
      end)

    case parts do
      [] -> ""
      [single] when is_binary(single) -> single
      list -> list
    end
  end
end
