defmodule Playcode.Import.TeiParser do
  @moduledoc """
  Reads a TEI-XML file into a plain description of a play, touching no database.

  `parse_file/1` returns everything `Playcode.Import.TeiImport` writes, in document order
  and with every position already counted:

      %{
        play: %{code: "EMOTHE0010", title: "…", …},
        editors: [%{person_name, role, organization, position}],
        sources: [%{title, author, editor, editor_role, publisher, pub_place, pub_date,
                    note, language, distributor, position}],
        witnesses: [%{siglum, witness_type, title, …}],
        places: [%{attrs: %{"slug" => …, …}, slug_declared: boolean, places: [place]}],
        settings: [%{slug, role, position, note}],
        characters: [%{xml_id, name, description, actor, is_hidden, position}],
        paratexts: [%{kind, heading, content, position, back}],
        divisions: [%{type, number, title, position, notes, elements, divisions}],
        bibliography: [%{description, volume, pages}]
      }

  An element is `%{type, position, notes, elements}` plus its columns, and a speech's
  `who` the xml_ids it names. A reference of the bibliography is its
  `Bibliography.Entry.description/1` and where the play sits in it. A note is `%{offset, n, type, term, body}`. An entry of
  the critical apparatus is a note of type "variante" that also carries `variant_type`,
  `range_end` and `readings` (`%{lemma, wit, text, note}`), its `body` possibly nil. Nothing
  here knows a row: ids, `play_id` and `origin` are the writer's.

  Handles UTF-16 encoded files (common in the EMOTHE corpus) by converting them to UTF-8
  before parsing with Saxy.
  """

  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue.Play
  alias Playcode.Places
  alias Playcode.PlayContent.{InlineMarkup, Note}
  alias Playcode.Witnesses

  require Logger

  @title_small_words MapSet.new([
                       "a",
                       "al",
                       "and",
                       "as",
                       "at",
                       "d",
                       "da",
                       "das",
                       "de",
                       "del",
                       "des",
                       "di",
                       "do",
                       "dos",
                       "e",
                       "el",
                       "en",
                       "et",
                       "i",
                       "la",
                       "las",
                       "le",
                       "les",
                       "los",
                       "of",
                       "or",
                       "the",
                       "to",
                       "y"
                     ])

  @doc """
  Reads the play at `path`: `{:ok, tei}` (see the moduledoc) or `{:error, reason}`, the
  reason `File.read/1`'s, `{:xml_parse_error, _}`, `:encoding_error` or
  `:missing_tei_header`.
  """
  def parse_file(path) do
    with {:ok, {_name, _attrs, children}} <- read_tree(path) do
      case find_child(children, "teiHeader") do
        nil ->
          {:error, :missing_tei_header}

        {_name, _attrs, header} ->
          {:ok, Map.merge(header(header), text(find_child(children, "text")))}
      end
    end
  end

  defp read_tree(path) do
    with {:ok, raw} <- File.read(path),
         xml when is_binary(xml) <- normalize_encoding(raw),
         {:ok, tree} <- parse_xml(xml) do
      {:ok, drop_folio_wrappers(tree)}
    else
      {:error, reason} ->
        {:error, reason}

      {:incomplete, _, _} = err ->
        Logger.error("Encoding conversion failed for #{path}: #{inspect(err)}")
        {:error, :encoding_error}

      other ->
        Logger.error("Unexpected error reading #{path}: #{inspect(other)}")
        {:error, other}
    end
  end

  # --- HTML typed as text ---

  # Seven files hold HTML typed into <code> as text (docs/tei-apparatus-and-code.md). On
  # the old site a <span class="folio"> hid Hamlet's Folio passages, each marked by a
  # superscript F at either end. A file with no such F (The Rover, the Spanish version of
  # The Spanish Tragedy) uses the wrapper for nothing the project wants hidden, so it goes
  # and its words stay. Hamlet's wait for its editor (question 36).
  @folio_wrapper [~s(<span class="folio">), "</span>"]
  @folio_label ["<sup>", "F", "</sup>"]

  defp drop_folio_wrappers(tree),
    do: if(folio_labels?(tree), do: tree, else: without_folio_wrappers(tree))

  defp folio_labels?({_name, _attrs, children}) do
    labelled =
      children
      |> Enum.map(&typed_text/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.member?(@folio_label)

    labelled or Enum.any?(children, &folio_labels?/1)
  end

  defp folio_labels?(_text), do: false

  defp without_folio_wrappers({name, attrs, children}) do
    {name, attrs,
     for(
       child <- children,
       typed_text(child) not in @folio_wrapper,
       do: without_folio_wrappers(child)
     )}
  end

  defp without_folio_wrappers(text), do: text

  # A <code>'s text or a text node, trimmed; nil for any other element.
  defp typed_text({"code", _attrs, children}),
    do: children |> Enum.filter(&is_binary/1) |> Enum.join() |> String.trim()

  defp typed_text(text) when is_binary(text), do: String.trim(text)
  defp typed_text(_element), do: nil

  # --- Encoding ---

  defp normalize_encoding(raw) do
    # Detect UTF-16 BOM (little-endian or big-endian)
    case raw do
      <<0xFF, 0xFE, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :little})

      <<0xFE, 0xFF, rest::binary>> ->
        :unicode.characters_to_binary(rest, {:utf16, :big})

      # Check for null bytes pattern typical of UTF-16LE without BOM
      <<first, 0x00, _rest::binary>> when first != 0x00 ->
        :unicode.characters_to_binary(raw, {:utf16, :little})

      # UTF-8 BOM
      <<0xEF, 0xBB, 0xBF, rest::binary>> ->
        rest

      _ ->
        raw
    end
  end

  # --- XML Parsing ---

  defp parse_xml(xml) do
    # Strip XML declaration and stylesheet processing instructions
    xml = String.replace(xml, ~r/<\?xml[^?]*\?>/, "")
    xml = String.replace(xml, ~r/<\?xml-stylesheet[^?]*\?>/, "")
    xml = String.trim(xml)

    case Saxy.SimpleForm.parse_string(xml) do
      {:ok, tree} -> {:ok, tree}
      {:error, reason} -> {:error, {:xml_parse_error, reason}}
    end
  end

  # --- Header ---

  defp header(children) do
    file_desc = find_child(children, "fileDesc")
    profile_desc = find_child(children, "profileDesc")

    %{
      play: extract_play_attrs(file_desc, find_child(children, "encodingDesc"), profile_desc),
      editors: editors(file_desc),
      sources: sources(file_desc),
      witnesses: witnesses(file_desc),
      places: places(profile_desc),
      settings: settings(profile_desc)
    }
  end

  defp extract_play_attrs(file_desc, encoding_desc, profile_desc) do
    title_stmt = file_desc && find_child(elem(file_desc, 2), "titleStmt")
    publication_stmt = file_desc && find_child(elem(file_desc, 2), "publicationStmt")
    extent = file_desc && find_child(elem(file_desc, 2), "extent")

    titles = if title_stmt, do: find_children(elem(title_stmt, 2), "title"), else: []
    authors = if title_stmt, do: find_children(elem(title_stmt, 2), "author"), else: []

    # Title selection: prefer <title type="traduccion">, then first <title> without key/type, then fallback
    traduccion_title =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "traduccion" end)

    plain_title =
      Enum.find(titles, fn {_, attrs, _} ->
        !has_attr?(attrs, "key") and !has_attr?(attrs, "type")
      end)

    main_title =
      traduccion_title || plain_title ||
        Enum.find(titles, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)

    sort_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)
    code_title = Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "key") == "archivo" end)

    original_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "original" end)

    edition_title_el =
      Enum.find(titles, fn {_, attrs, _} -> attr_value(attrs, "type") == "edicion" end)

    # Determine relationship type from title types
    relationship_type = if traduccion_title, do: "traduccion", else: nil

    # Extract sponsor and funder from titleStmt
    sponsor_el = if title_stmt, do: find_child(elem(title_stmt, 2), "sponsor"), else: nil
    funder_el = if title_stmt, do: find_child(elem(title_stmt, 2), "funder"), else: nil

    main_author = Enum.find(authors, fn {_, attrs, _} -> !has_attr?(attrs, "key") end)
    sort_author = Enum.find(authors, fn {_, attrs, _} -> attr_value(attrs, "key") == "orden" end)

    # Extract code from either archivo title or idno
    code = if code_title, do: text_content(code_title), else: extract_idno(publication_stmt)

    # Extract verse count from extent
    verse_count = if extent, do: extract_verse_count(extent), else: nil

    # Extract publication info
    {pub_place, pub_date, publisher_text, availability, licence_url, licence_text, authority_text} =
      extract_publication(publication_stmt)

    # Extract EMOTHE-specific idno
    emothe_id = extract_emothe_idno(publication_stmt)

    # Extract project/editorial from encodingDesc
    {project_desc, editorial_decl} = extract_encoding(encoding_desc)

    # Extract play language from profileDesc/langUsage/language[@ident]
    language = extract_language_code(profile_desc)

    {composition_from, composition_to, composition_note} = extract_creation(profile_desc)
    {historical_time, historical_time_note} = extract_historical_time(profile_desc)

    attribution =
      if main_author do
        attr_value(elem(main_author, 1), "ana")
      end

    %{
      title: safe_text(main_title) |> normalize_imported_title(),
      title_sort: safe_text(sort_title),
      code: clean_code(code || "UNKNOWN"),
      original_title: safe_text(original_title_el),
      author_name: safe_text(main_author),
      author_sort: safe_text(sort_author),
      author_attribution: attribution,
      verse_count: verse_count,
      is_verse: verse_count != nil && verse_count > 0,
      pub_place: pub_place,
      publication_date: pub_date,
      publisher: publisher_text,
      availability_note: availability,
      licence_url: licence_url,
      licence_text: licence_text,
      emothe_id: emothe_id,
      sponsor: safe_text(sponsor_el),
      funder: safe_text(funder_el),
      authority: authority_text,
      project_description: project_desc,
      editorial_declaration: editorial_decl,
      edition_title: safe_text(edition_title_el),
      relationship_type: relationship_type,
      pending_original_code: original_code(file_desc),
      edition_notes: edition_notes(file_desc),
      language: language || "es",
      composition_date_from: composition_from,
      composition_date_to: composition_to,
      composition_date_note: composition_note,
      historical_time: historical_time,
      historical_time_note: historical_time_note
    }
  end

  # Extract the 2-letter language code from profileDesc/langUsage/language[@ident]
  # e.g. ident="it-IT" -> "it", ident="fr-FR" -> "fr"
  defp extract_language_code(nil), do: nil

  defp extract_language_code({_name, _attrs, children}) do
    with lang_usage when not is_nil(lang_usage) <- find_child(children, "langUsage"),
         lang_el when not is_nil(lang_el) <- find_child(elem(lang_usage, 2), "language"),
         ident when not is_nil(ident) <- attr_value(elem(lang_el, 1), "ident"),
         code <- ident |> String.split("-") |> List.first() |> String.downcase(),
         true <- code in Play.valid_languages() do
      code
    else
      _ -> nil
    end
  end

  # profileDesc/creation/date. @when is a single year; @notBefore + @notAfter a range.
  #
  # Anything the changeset would reject is dropped here instead — a lone endpoint, an
  # inverted range, a year outside `Play.composition_year_range/0`. The changeset's
  # strictness is right for curator input, but an unusable attribute in a TEI file must
  # not roll back the import: a rollback discards the text, the characters and the acts
  # too. Per the S2c spec, a file that carries no machine dating is the
  # file's problem, not an import failure. The date's words are the note either way: with
  # no usable year they are a dating in words.
  defp extract_creation(nil), do: {nil, nil, nil}

  defp extract_creation({_name, _attrs, children}) do
    with creation when not is_nil(creation) <- find_child(children, "creation"),
         date when not is_nil(date) <- find_child(elem(creation, 2), "date") do
      {from, to} = creation_years(elem(date, 1))

      if usable_creation_years?(from, to),
        do: {from, to, non_blank_text(date)},
        else: {nil, nil, non_blank_text(date)}
    else
      _ -> {nil, nil, nil}
    end
  end

  defp usable_creation_years?(from, to) do
    range = Play.composition_year_range()
    from in range and to in range and from <= to
  end

  defp creation_years(attrs) do
    case creation_year(attr_value(attrs, "when")) do
      nil ->
        {creation_year(attr_value(attrs, "notBefore")),
         creation_year(attr_value(attrs, "notAfter"))}

      exact ->
        {exact, exact}
    end
  end

  defp creation_year(nil), do: nil

  defp creation_year(value) do
    case Integer.parse(String.trim(value)) do
      {year, _rest} -> year
      :error -> nil
    end
  end

  defp non_blank_text(element) do
    case element |> text_content() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  # settingDesc/setting/time: the period as @type, its note as the text. A period the
  # changeset would reject is dropped, as an unusable creation year is, and the words kept.
  defp extract_historical_time(profile_desc) do
    with {_name, _attrs, children} <- setting_desc_child(profile_desc, "setting"),
         {_name, attrs, _children} = time <- find_child(children, "time") do
      period = attr_value(attrs, "type")
      {if(period in Play.historical_times(), do: period), non_blank_text(time)}
    else
      nil -> {nil, nil}
    end
  end

  defp extract_idno(nil), do: nil

  defp extract_idno({_name, _attrs, children}) do
    idno = find_child(children, "idno")
    if idno, do: text_content(idno), else: nil
  end

  # Extract the EMOTHE-specific idno (type="EMOTHE")
  defp extract_emothe_idno(nil), do: nil

  defp extract_emothe_idno({_name, _attrs, children}) do
    idnos = find_children(children, "idno")

    emothe_idno =
      Enum.find(idnos, fn {_, attrs, _} -> attr_value(attrs, "type") == "EMOTHE" end)

    if emothe_idno, do: text_content(emothe_idno), else: nil
  end

  # <notesStmt><note>: the notes on the edition, a <lb/> a line break in one.
  defp edition_notes(nil), do: []

  defp edition_notes({_name, _attrs, children}) do
    case find_child(children, "notesStmt") do
      {_, _, notes} -> notes |> find_children("note") |> Enum.map(&lines_text/1)
      nil -> []
    end
  end

  # <notesStmt><relatedItem type="original" target="EMOTHE0530"/>: the play this one
  # translates, by its short code. The import waits for it
  # (Catalogue.link_waiting_translations/0).
  defp original_code(nil), do: nil

  defp original_code({_name, _attrs, children}) do
    with {_, _, notes} <- find_child(children, "notesStmt"),
         {_, attrs, _} <-
           notes
           |> find_children("relatedItem")
           |> Enum.find(&(attr_value(elem(&1, 1), "type") == "original")),
         target when is_binary(target) <- attr_value(attrs, "target"),
         code when code != "" <- target |> String.trim() |> Play.short_code() do
      code
    else
      _ -> nil
    end
  end

  defp extract_verse_count({_name, _attrs, _children} = extent) do
    text = text_content(extent)

    case Regex.run(~r/(\d+)/, text) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp extract_publication(nil), do: {nil, nil, nil, nil, nil, nil, nil}

  defp extract_publication({_name, _attrs, children}) do
    pub_place = find_child(children, "pubPlace")
    date = find_child(children, "date")
    publisher = find_child(children, "publisher")
    availability = find_child(children, "availability")
    authority = find_child(children, "authority")

    # Extract licence details from within availability
    {licence_url, licence_text} =
      case availability do
        {_, _, avail_children} ->
          licence_el = find_child(avail_children, "licence")

          case licence_el do
            {_, attrs, _} ->
              url = attr_value(attrs, "target")
              text = text_content(licence_el)
              {url, text}

            _ ->
              {nil, nil}
          end

        _ ->
          {nil, nil}
      end

    # availability_note: only the <p> text, not the licence text
    availability_text =
      case availability do
        {_, _, avail_children} ->
          avail_children
          |> Enum.filter(fn
            {"p", _, _} -> true
            _ -> false
          end)
          |> Enum.map(&text_content/1)
          |> Enum.join("\n\n")
          |> String.trim()
          |> case do
            "" -> nil
            t -> t
          end

        _ ->
          safe_text(availability)
      end

    {
      safe_text(pub_place),
      safe_text(date),
      safe_text(publisher),
      availability_text,
      licence_url,
      licence_text,
      safe_text(authority)
    }
  end

  defp extract_encoding(nil), do: {nil, nil}

  defp extract_encoding({_name, _attrs, children}) do
    project_desc = find_child(children, "projectDesc")
    editorial_decl = find_child(children, "editorialDecl")

    {
      safe_text(project_desc),
      safe_text(editorial_decl)
    }
  end

  # --- Editors ---

  # The principal investigator, the titleStmt's <editor>s, then the respStmts of the
  # titleStmt (from position 100) and of the editionStmt (from 200).
  defp editors(nil), do: []

  defp editors({_name, _attrs, children}) do
    title_stmt = find_child(children, "titleStmt")

    principal(title_stmt) ++
      title_editors(title_stmt) ++
      resp_stmt_editors(title_stmt, 100) ++
      resp_stmt_editors(find_child(children, "editionStmt"), 200)
  end

  defp principal(nil), do: []

  defp principal({_name, _attrs, children}) do
    case find_child(children, "principal") do
      nil -> []
      principal -> [%{person_name: text_content(principal), role: "principal", position: 0}]
    end
  end

  # <editor role="…"> in titleStmt: translators, researchers and the editor of the
  # critical edition the text is based on. Any other role (canon60) is skipped.
  defp title_editors(nil), do: []

  defp title_editors({_name, _attrs, children}) do
    children
    |> find_children("editor")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_, attrs, ed_children}, idx} ->
      case editor_role(attr_value(attrs, "role")) do
        nil ->
          []

        role ->
          # Name may be in <persName> or direct text
          person_name =
            case find_child(ed_children, "persName") do
              nil -> text_content({"editor", attrs, ed_children})
              el -> text_content(el)
            end

          [
            %{
              person_name: person_name,
              role: role,
              organization: safe_text(find_child(ed_children, "orgName")),
              position: idx
            }
          ]
      end
    end)
  end

  defp editor_role("translator"), do: "translator"
  defp editor_role("traductor"), do: "translator"
  defp editor_role("researcher"), do: "researcher"
  defp editor_role("edicion_critica"), do: "critical_editor"
  defp editor_role(_role), do: nil

  # Every <persName> of every respStmt, one editor each, numbered from `first`. The people
  # of one respStmt share its resp and orgName.
  defp resp_stmt_editors(nil, _first), do: []

  defp resp_stmt_editors({_name, _attrs, children}, first) do
    children
    |> find_children("respStmt")
    |> Enum.flat_map(fn {_name, _attrs, resp_children} ->
      role = resp_role(safe_text(find_child(resp_children, "resp")))
      organization = safe_text(find_child(resp_children, "orgName"))

      resp_children
      |> find_children("persName")
      |> Enum.map(&%{person_name: text_content(&1), role: role, organization: organization})
    end)
    |> Enum.with_index(first)
    |> Enum.map(fn {editor, position} -> Map.put(editor, :position, position) end)
  end

  defp resp_role(resp) when is_binary(resp) do
    cond do
      String.contains?(resp, "Edición") -> "editor"
      String.contains?(resp, "Revisión") -> "reviewer"
      true -> "digital_editor"
    end
  end

  defp resp_role(nil), do: "digital_editor"

  # --- Sources ---

  # <bibl> directly under <sourceDesc>, or inside <listBibl>.
  defp sources(nil), do: []

  defp sources({_name, _attrs, children}) do
    case find_child(children, "sourceDesc") do
      nil ->
        []

      {_name, _attrs, desc_children} ->
        bibls =
          case find_child(desc_children, "listBibl") do
            nil -> find_children(desc_children, "bibl")
            {_name, _attrs, list_children} -> find_children(list_children, "bibl")
          end

        bibls |> Enum.with_index() |> Enum.map(&source/1)
    end
  end

  defp source({{_name, _attrs, children}, position}) do
    editor_el = find_child(children, "editor")

    %{
      title: safe_text(find_child(children, "title")),
      author: safe_text(find_child(children, "author")),
      editor: safe_text(editor_el),
      editor_role: editor_el && attr_value(elem(editor_el, 1), "role"),
      publisher: safe_text(find_child(children, "publisher")),
      pub_place: safe_text(find_child(children, "pubPlace")),
      pub_date: safe_text(find_child(children, "date")),
      note: safe_text(find_child(children, "note")),
      language: safe_text(find_child(children, "lang")),
      distributor: safe_text(find_child(children, "distributor")),
      position: position
    }
  end

  # --- Witnesses ---

  # `sourceDesc/listWit`, nested lists read in order (S3). Which of them the play keeps
  # depends on the sigla it already has, so that is the writer's call.
  defp witnesses(nil), do: []

  defp witnesses({_name, _attrs, children}) do
    with {_name, _attrs, desc_children} <- find_child(children, "sourceDesc"),
         {_name, _attrs, _children} = list_wit <- find_child(desc_children, "listWit") do
      list_wit |> witness_elements() |> Enum.map(&witness_attrs/1)
    else
      nil -> []
    end
  end

  defp witness_elements({_name, _attrs, children}) do
    Enum.flat_map(children, fn
      {"witness", _, _} = witness -> [witness]
      {"listWit", _, _} = nested -> witness_elements(nested)
      _other -> []
    end)
  end

  # A <bibl> written field by field, as the export writes one, maps back to its columns.
  # Plain words (EMOTHE0460's "anon. [no title page]. London: printed by Richard Pynson…")
  # are kept whole as the note rather than guessed into fields.
  defp witness_attrs({"witness", attrs, children}) do
    {bibl_attrs, parts} =
      case find_child(children, "bibl") do
        {_, bibl_attrs, bibl_children} -> {bibl_attrs, bibl_children}
        nil -> {[], children}
      end

    base = %{
      siglum: attr_value(attrs, "n") || attr_value(attrs, "xml:id"),
      witness_type:
        Witnesses.type_from_tei(attr_value(bibl_attrs, "type"), attr_value(bibl_attrs, "subtype"))
    }

    if Enum.any?(
         parts,
         &match?(
           {name, _, _} when name in ~w(title author pubPlace publisher date extent idno),
           &1
         )
       ) do
      Map.merge(base, %{
        title: parts |> typed("title", nil) |> lines_text(),
        normalized_title: parts |> typed("title", "normalized") |> lines_text(),
        attribution: lines_text(find_child(parts, "author")),
        pub_place: lines_text(find_child(parts, "pubPlace")),
        publisher: lines_text(find_child(parts, "publisher")),
        date: safe_text(find_child(parts, "date")),
        format: lines_text(find_child(parts, "extent")),
        shelfmark: parts |> typed("idno", "shelfmark") |> safe_text(),
        note: lines_text(find_child(parts, "note"))
      })
    else
      Map.put(base, :note, text_content({"bibl", [], parts}))
    end
  end

  # A witness's field with each <lb/> read as a line break, the rest as text_content/1
  # reads it.
  defp lines_text(nil), do: nil

  defp lines_text({name, attrs, children}) do
    children
    |> Enum.chunk_while(
      [],
      fn
        {"lb", _, _}, line -> {:cont, Enum.reverse(line), []}
        child, line -> {:cont, [child | line]}
      end,
      &{:cont, Enum.reverse(&1), []}
    )
    |> Enum.map_join("\n", &text_content({name, attrs, &1}))
  end

  # The first `name` child whose @type is `type` (nil: no @type).
  defp typed(children, name, type), do: with_attr(children, name, "type", type)

  # The first `name` child whose `attr` is `value` (nil: no such attribute).
  defp with_attr(children, name, attr, value),
    do: children |> find_children(name) |> Enum.find(&(attr_value(elem(&1, 1), attr) == value))

  # --- Places ---

  # `listPlace` supplies the places and their containment; `setting` supplies this
  # play's links. Reading them separately is what keeps a pure container — Italia in
  # `<place xml:id="italia">…<place xml:id="roma">` — from becoming a setting.
  defp places(profile_desc) do
    case setting_desc_child(profile_desc, "listPlace") do
      nil -> []
      list_place -> list_places(list_place)
    end
  end

  defp settings(profile_desc) do
    case setting_desc_child(profile_desc, "setting") do
      nil -> []
      setting -> setting_links(setting)
    end
  end

  defp setting_desc_child(nil, _name), do: nil

  defp setting_desc_child({_name, _attrs, children}, name) do
    with {_n, _a, setting_children} <- find_child(children, "settingDesc"),
         do: find_child(setting_children, name)
  end

  defp list_places({_name, _attrs, children}) do
    for {"place", _, _} = place <- children, do: place(place)
  end

  # A place and the places nested in it. `slug_declared` is false when the slug was
  # derived from the name, which the writer warns about if it finds that slug taken.
  defp place({_name, attrs, children} = place_el) do
    declared_slug = attr_value(attrs, "xml:id")
    {latitude, longitude} = place_geo(children)

    place_attrs =
      %{
        "slug" => declared_slug || Places.slugify(first_place_name(children)),
        "type" => attr_value(attrs, "type") || "other",
        "is_fictional" => attr_value(attrs, "subtype") == "fictional",
        "latitude" => latitude,
        "longitude" => longitude,
        "note" => place_note(children),
        "names" => place_names(children)
      }
      |> Map.merge(place_idno(children))

    %{attrs: place_attrs, slug_declared: declared_slug != nil, places: list_places(place_el)}
  end

  defp place_names(children) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, _c} = el, index} ->
      language = attr_value(attrs, "xml:lang")

      %{
        "name" => text_content(el),
        "language" => language,
        "is_historical" => attr_value(attrs, "type") == "historical",
        "is_preferred" => attr_value(attrs, "type") != "historical",
        "position" => index
      }
    end)
    |> Enum.reject(&(&1["name"] in [nil, ""]))
    |> dedupe_preferred()
  end

  # The partial index allows one preferred name per language; a file with two
  # non-historical names in the same language would violate it, so the first wins.
  defp dedupe_preferred(names) do
    {names, _seen} =
      Enum.map_reduce(names, MapSet.new(), fn name, seen ->
        key = name["language"]

        if name["is_preferred"] and not MapSet.member?(seen, key) do
          {name, MapSet.put(seen, key)}
        else
          {Map.put(name, "is_preferred", false), seen}
        end
      end)

    names
  end

  defp first_place_name(children) do
    case Enum.find(children, &match?({"placeName", _, _}, &1)) do
      nil -> "place"
      el -> text_content(el)
    end
  end

  defp place_geo(children) do
    with {_n, _a, location_children} <- find_child(children, "location"),
         geo when not is_nil(geo) <- find_child(location_children, "geo"),
         [lat, long] <- geo |> text_content() |> String.split(~r/\s+/, trim: true),
         {latitude, _} <- Float.parse(lat),
         {longitude, _} <- Float.parse(long) do
      {latitude, longitude}
    else
      _ -> {nil, nil}
    end
  end

  defp place_idno(children) do
    case find_child(children, "idno") do
      {_n, attrs, _c} = el ->
        authority = attr_value(attrs, "type")

        if authority in Places.Place.authorities() do
          %{"authority" => authority, "authority_id" => text_content(el)}
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  # A place's own note is `<note type="place">`, a direct child of `<place>`. Do not
  # match a bare `<note>` here — that shape belongs to a link's note nested inside
  # `<setting>/<placeName>` (see setting_note/1), one level deeper and without the
  # type attribute. See task-10-report.md for the export side of this contract.
  defp place_note(children) do
    case Enum.find(children, &match?({"note", _, _}, &1)) do
      {_n, attrs, _c} = el ->
        if attr_value(attrs, "type") == "place" do
          text_content(el)
        else
          Logger.info("TEI import: <note> under <place> without type=\"place\", skipped")
          nil
        end

      nil ->
        nil
    end
  end

  defp setting_links({_name, _attrs, children}) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, name_children}, index} ->
      %{
        slug: attrs |> attr_value("ref") |> to_string() |> String.trim_leading("#"),
        role: attr_value(attrs, "ana") || "setting",
        position: index,
        note: setting_note(name_children)
      }
    end)
  end

  # A link's note is a bare `<note>` inside `<setting>/<placeName>` — no `type`
  # attribute, and one tree level deeper than a place's own `<note type="place">`.
  defp setting_note(children) do
    case find_child(children, "note") do
      nil -> nil
      el -> text_content(el)
    end
  end

  # --- Text (front, body) ---

  defp text(nil), do: %{characters: [], paratexts: [], divisions: [], bibliography: []}

  defp text({_name, _attrs, children}) do
    front = front(find_child(children, "front"))
    body = body(find_child(children, "body"), front.next_position)
    back = find_child(children, "back")

    %{
      characters: front.characters,
      paratexts: front.paratexts ++ back_matter(back, front.next_position + length(body)),
      divisions: front.divisions ++ body,
      bibliography: bibliography(back)
    }
  end

  # --- Back: paratexts after the text ---

  # Each div but the bibliography, read as a front paratext is, positions continuing
  # after the body's. Not read: a cast list (0404, 0718; question 29) and a div in verse,
  # two files' commendatory sonnet, though it has a heading (question 30).
  defp back_matter(nil, _first), do: []

  defp back_matter({_name, _attrs, children}, first) do
    for(
      {"div", attrs, div_children} <- children,
      type = attr_value(attrs, "type") || "front",
      type not in ~w(bibliografia elenco),
      find_child(div_children, "lg") == nil,
      do: {type, div_children}
    )
    |> Enum.with_index(first)
    |> Enum.flat_map(fn {{type, div_children}, pos} -> paratext(type, div_children, pos) end)
    |> Enum.map(&%{&1 | back: true})
  end

  # --- Back: the bibliography ---

  # Every biblStruct of a bibliography's listBibls, read into the entry it describes, as
  # Entry.description/1 gives it, with where the play sits in it (its citedRanges). A
  # bibliography in prose, as seven source files give theirs, has no listBibl: nothing.
  defp bibliography(nil), do: []

  defp bibliography({_name, _attrs, children}) do
    for {"div", attrs, parts} <- children,
        attr_value(attrs, "type") == "bibliografia",
        {"listBibl", list_attrs, structs} <- parts,
        {"biblStruct", _, _} = struct <- structs do
      reference(struct, Entry.kind_from_tei_list(attr_value(list_attrs, "type")))
    end
  end

  defp reference({_name, attrs, children}, kind) do
    analytic = children_of(find_child(children, "analytic"))
    monogr = children_of(find_child(children, "monogr"))
    imprint = children_of(find_child(monogr, "imprint"))
    series = children_of(find_child(children, "series"))

    entry = %Entry{
      kind: kind,
      pub_type: Entry.pub_type_from_tei(attr_value(attrs, "type")),
      language: attr_value(attrs, "xml:lang"),
      analytic_author: analytic |> find_children("author") |> people(),
      analytic_title: analytic |> typed("title", nil) |> running_text(),
      analytic_editors: analytic |> editors(nil) |> people(),
      analytic_translators: analytic |> editors("translator") |> people(),
      monogr_author: monogr |> find_children("author") |> people(),
      monogr_title: monogr |> typed("title", nil) |> running_text(),
      monogr_editors: monogr |> editors(nil) |> people(),
      monogr_translators: monogr |> editors("translator") |> people(),
      original_title: monogr |> typed("title", "original") |> running_text(),
      siglum: monogr |> typed("idno", "siglum") |> running_text(),
      edition: running_text(find_child(monogr, "edition")),
      volumes_total: monogr |> find_child("extent") |> running_text() |> volumes(),
      volume: monogr |> with_attr("biblScope", "unit", "volume") |> running_text(),
      issue: monogr |> with_attr("biblScope", "unit", "issue") |> running_text(),
      pages: monogr |> with_attr("biblScope", "unit", "page") |> running_text(),
      pub_place: running_text(find_child(imprint, "pubPlace")),
      publisher: running_text(find_child(imprint, "publisher")),
      year_text: imprint |> typed("date", nil) |> running_text(),
      url_accessed_on: imprint |> typed("date", "access") |> running_text(),
      series: running_text(find_child(series, "title")),
      public_note: running_text(find_child(children, "note")),
      url: children |> find_child("ptr") |> attrs_of() |> attr_value("target")
    }

    %{
      description: Entry.description(entry),
      volume: children |> with_attr("citedRange", "unit", "volume") |> running_text(),
      pages: children |> with_attr("citedRange", "unit", "page") |> running_text()
    }
  end

  # A bibliography field's text as it runs: italics as <<…>>, whitespace collapsed but none
  # added. text_content/1 joins an element's pieces with a space, which would put one
  # between "<<Adonis y Venus>>" and ": hacia", and a reference is matched on its words.
  defp running_text(nil), do: nil

  defp running_text(element),
    do: element |> run() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp run(text) when is_binary(text), do: text
  # A line break the export wrote for a curator's Enter: whitespace, as it was before.
  defp run({"lb", _attrs, _children}), do: " "

  # The italics keep their spaces: the export wrote them on one line, so a space inside
  # an <emph> is the curator's ("<<Foo >>bar"), not indentation.
  defp run({name, attrs, children}) do
    text = Enum.map_join(children, &run/1)
    if emph_element?(name, attrs), do: "<<" <> text <> ">>", else: text
  end

  defp run(_other), do: ""

  # One element per person in the file, one field in Playcode: joined with "; ", as FileMaker
  # keeps several people (Entry.people/1). Nil for none.
  defp people(elements) do
    case elements |> Enum.map(&running_text/1) |> Enum.reject(&(&1 == "")) do
      [] -> nil
      names -> Enum.join(names, "; ")
    end
  end

  # The <editor>s of a level whose @role is `role` (nil: an editor; "translator").
  defp editors(children, role),
    do:
      children
      |> find_children("editor")
      |> Enum.filter(&(attr_value(elem(&1, 1), "role") == role))

  # The export writes a total of volumes as "6 vols.".
  defp volumes(nil), do: nil
  defp volumes(text), do: String.replace_suffix(text, " vols.", "")

  defp children_of({_name, _attrs, children}), do: children
  defp children_of(nil), do: []

  defp attrs_of({_name, attrs, _children}), do: attrs
  defp attrs_of(nil), do: []

  # --- Front matter ---

  # Each <div> of the front takes a position, which the body's divisions continue; the
  # title page and anything else take none. A cast list is the play's characters and an
  # `elenco` division; any other div is a paratext.
  defp front(nil), do: %{characters: [], paratexts: [], divisions: [], next_position: 0}

  defp front({_name, _attrs, children}) do
    divs =
      for(
        {"div", attrs, div_children} <- children,
        do: {attr_value(attrs, "type") || "front", div_children}
      )
      |> Enum.with_index()

    %{
      characters:
        Enum.flat_map(divs, fn
          {{"elenco", div_children}, _pos} -> cast_list(find_child(div_children, "castList"))
          _other -> []
        end),
      divisions:
        for({{"elenco", div_children}, pos} <- divs, do: elenco_division(div_children, pos)),
      paratexts:
        Enum.flat_map(divs, fn
          {{"elenco", _div_children}, _pos} -> []
          {{type, div_children}, pos} -> paratext(type, div_children, pos)
        end) ++
          for(
            {"set", _attrs, set_children} <- children,
            scene <- paratext("lugar_accion", set_children, length(divs)),
            do: scene
          ),
      next_position: length(divs)
    }
  end

  defp elenco_division(children, pos) do
    %{
      type: "elenco",
      number: nil,
      title: safe_text(find_child(children, "head")),
      position: pos,
      notes: [],
      elements: [],
      divisions: []
    }
  end

  # A paratext (dedication, editor's introduction, …), kept when it has a heading or
  # paragraphs: 12 head titles are a heading alone.
  defp paratext(type, children, pos) do
    heading = with "" <- safe_text(find_child(children, "head")), do: nil

    # Each <lb/> a line break; an empty line between two (before a signature, in 140
    # plays) is the blank line that parts paragraphs, so it reads as a new one.
    paragraphs =
      children
      |> find_children("p")
      |> Enum.map_join("\n\n", &lines_text/1)
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if heading == nil and paragraphs == "" do
      []
    else
      [
        %{
          kind: kind(type),
          heading: heading,
          content: if(paragraphs != "", do: paragraphs),
          position: pos,
          back: false
        }
      ]
    end
  end

  # The file's own word, kept as a stage direction's is. The scene of the action, which 45
  # files give as a div, is TEI's <set>; nota (0784's only) and a div with no type are a
  # note on the digital edition.
  defp kind("circunstancia_accion"), do: "lugar_accion"
  defp kind(type) when type in ~w(nota front), do: "nota_edicion_digital"
  defp kind(type), do: type

  # --- Cast list ---

  defp cast_list(nil), do: []

  defp cast_list({_name, _attrs, children}) do
    children
    |> find_children("castItem")
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_name, attrs, item_children}, idx} ->
      case find_child(item_children, "role") do
        nil ->
          []

        {_role_name, role_attrs, _role_children} = role ->
          name = role |> text_content() |> String.trim()
          xml_id = attr_value(role_attrs, "xml:id") || attr_value(role_attrs, "id")

          [
            %{
              # Clean xml_id (some have newlines)
              xml_id: if(xml_id, do: String.trim(xml_id), else: name),
              name: name,
              description: safe_text(find_child(item_children, "roleDesc")),
              actor: safe_text(find_child(item_children, "actor")),
              is_hidden: attr_value(attrs, "ana") == "oculto",
              position: idx
            }
          ]
      end
    end)
  end

  # --- Body (acts, scenes, speeches, etc.) ---

  defp body(nil, _first), do: []

  defp body({_name, _attrs, children}, first) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ["div1", "div"], &1))
    |> Enum.with_index(first)
    |> Enum.map(fn {{_name, attrs, act_children}, pos} ->
      {heading, notes} = text_and_notes(find_child(act_children, "head"))
      {elements, scenes} = act_content(act_children)

      %{
        type: (attr_value(attrs, "type") || "acto") |> String.downcase(),
        number: parse_int(attr_value(attrs, "n")),
        title: heading,
        position: pos,
        notes: notes,
        elements: elements,
        divisions: scenes
      }
    end)
  end

  # An act's own elements and its scenes. The act's elements and its scenes' share one
  # position counter: a scene's first element follows the last element before it.
  defp act_content(children) do
    {_el_pos, _scene_pos, elements, scenes} =
      Enum.reduce(children, {0, 0, [], []}, fn
        {"div2", attrs, scene_children}, {el_pos, scene_pos, elements, scenes} ->
          {heading, notes} = text_and_notes(find_child(scene_children, "head"))
          scene_elements = scene_content(scene_children, el_pos)

          scene = %{
            type: (attr_value(attrs, "type") || "escena") |> String.downcase(),
            number: parse_int(attr_value(attrs, "n")),
            title: heading,
            position: scene_pos,
            notes: notes,
            elements: scene_elements,
            divisions: []
          }

          {el_pos + length(scene_elements), scene_pos + 1, elements, [scene | scenes]}

        child, {el_pos, scene_pos, elements, scenes} = acc ->
          case act_element(child, el_pos) do
            nil -> acc
            element -> {el_pos + 1, scene_pos, [element | elements], scenes}
          end
      end)

    {Enum.reverse(elements), Enum.reverse(scenes)}
  end

  # An element directly in an act; nil for anything else (the head is the act's title).
  defp act_element({"sp", attrs, children}, pos), do: speech(attrs, children, pos)
  defp act_element({"stage", _, _} = stage, pos), do: stage_direction(stage, pos)
  defp act_element({"p", _, _} = para, pos), do: prose(para, pos)
  defp act_element({"lg", attrs, children}, pos), do: line_group(attrs, children, pos)
  defp act_element({"trailer", _, _} = trailer, pos), do: trailer(trailer, pos)
  defp act_element(_other, _pos), do: nil

  # A scene's speeches, stage directions and trailer, numbered from `first`. Nothing else
  # in a scene is read.
  defp scene_content(children, first) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(sp stage trailer), &1))
    |> Enum.with_index(first)
    |> Enum.map(fn {child, pos} -> act_element(child, pos) end)
  end

  # --- Speech ---

  defp speech(attrs, children, pos) do
    {speaker_label, notes} = text_and_notes(find_child(children, "speaker"))

    %{
      type: "speech",
      position: pos,
      speaker_label: speaker_label,
      who: who(attr_value(attrs, "who")),
      notes: notes,
      elements: speech_content(children)
    }
  end

  # A speech's line groups, lines, stage directions and paragraphs.
  defp speech_content(children) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(lg l stage p), &1))
    |> Enum.with_index()
    |> Enum.map(fn
      {{"lg", attrs, lg_children}, pos} -> line_group(attrs, lg_children, pos)
      {{"l", _, _} = line, pos} -> verse_line(line, pos)
      {{"stage", _, _} = stage, pos} -> stage_direction(stage, pos)
      {{"p", _, _} = para, pos} -> prose(para, pos)
    end)
  end

  # who can be "#ALFONSO" (single) or "#ALB #COR" (multi-character, space-separated)
  defp who(nil), do: []

  defp who(who) do
    who
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&(&1 |> String.replace("#", "") |> String.trim()))
  end

  # --- Line group ---

  defp line_group(attrs, children, pos) do
    %{
      type: "line_group",
      position: pos,
      verse_type: attr_value(attrs, "type"),
      part: attr_value(attrs, "part"),
      notes: [],
      elements:
        children
        |> Enum.filter(&match?({name, _, _} when name in ~w(l stage), &1))
        |> Enum.with_index()
        |> Enum.map(fn
          {{"l", _, _} = line, line_pos} -> verse_line(line, line_pos)
          {stage, stage_pos} -> stage_direction(stage, stage_pos)
        end)
    }
  end

  # --- Verse line ---

  defp verse_line({_name, attrs, children} = line, pos) do
    is_aside = aside_delivery?(children)
    {content, notes} = line |> verse_line_content(is_aside) |> take_notes(line)

    %{
      type: "verse_line",
      position: pos,
      content: content,
      line_number: parse_int(attr_value(attrs, "n")),
      line_id: attr_value(attrs, "xml:id") || attr_value(attrs, "id"),
      part: attr_value(attrs, "part"),
      rend: attr_value(attrs, "rend"),
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # Returns true if the children of an <l> element indicate an aside, either via:
  # - <stage type="delivery">[Aparte.]</stage>
  # - <seg type="aside">...</seg>
  defp aside_delivery?(children) when is_list(children) do
    Enum.any?(children, fn
      {"stage", attrs, stage_children} ->
        stage_type(attrs) == "delivery" and
          String.match?(
            text_content({"stage", attrs, stage_children}),
            ~r/aparte/i
          )

      {"seg", attrs, _} ->
        attr_value(attrs, "type") == "aside"

      _ ->
        false
    end)
  end

  defp aside_delivery?(_), do: false

  # The spoken text of a verse line, read with note marks (text_content/2). An aside line
  # is aside_text/1; with no <seg>, the line without its delivery <stage>, its entries kept.
  defp verse_line_content({_name, _attrs, children} = line, true) do
    if aside_in_children?(children) do
      aside_text(line)
    else
      children
      |> without_stages()
      |> pieces(:mark, &text_content(&1, :mark))
      |> squeeze()
    end
  end

  defp verse_line_content(line, false), do: text_content(line, :mark)

  defp aside_seg?({"seg", attrs, _}), do: attr_value(attrs, "type") == "aside"
  defp aside_seg?(_), do: false

  # --- Stage direction, trailer, prose ---

  defp stage_direction({_name, attrs, _children} = stage, pos) do
    {content, notes} = text_and_notes(stage)

    %{
      type: "stage_direction",
      position: pos,
      content: content,
      stage_type: stage_type(attrs),
      notes: notes,
      elements: []
    }
  end

  defp trailer(trailer, pos) do
    {content, notes} = text_and_notes(trailer)
    %{type: "trailer", position: pos, content: content, notes: notes, elements: []}
  end

  defp prose({_name, attrs, children} = para, pos) do
    is_aside = aside_in_children?(children)
    marked = if is_aside, do: aside_text(para), else: text_content(para, :mark)
    {content, notes} = take_notes(marked, para)
    # p@n: the number of the paragraph's first printed line, a marker at its very start.
    content =
      if content == "", do: content, else: printed_line(attr_value(attrs, "n")) <> content

    %{
      type: "prose",
      position: pos,
      content: content,
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # Check if children contain a <seg type="aside"> element
  defp aside_in_children?(children) when is_list(children), do: Enum.any?(children, &aside_seg?/1)

  defp aside_in_children?(_), do: false

  # A line or paragraph holding a <seg type="aside">. All aside, when every word is in a
  # seg: the segs' text, with the element's own notes and breaks, its stages dropped (the
  # delivery, "(Aparte)", is what is_aside says) but their entries kept (without_stages/1). Partly aside: the whole text, each seg an
  # <aside> marker (read_child/3).
  defp aside_text({_name, _attrs, children} = element) do
    if Enum.any?(children, &spoken_outside_aside?/1),
      do: text_content(element, :mark),
      else: aside_content(children)
  end

  defp spoken_outside_aside?(text) when is_binary(text), do: String.trim(text) != ""

  defp spoken_outside_aside?({name, _, _} = child),
    do: name not in ~w(stage note app) and not aside_seg?(child) and text_content(child) != ""

  defp spoken_outside_aside?(_), do: false

  defp aside_content(children) do
    children
    |> without_stages()
    |> Enum.filter(&(aside_seg?(&1) or match?({name, _, _} when name in ~w(note app lb), &1)))
    |> pieces(:mark, fn
      {"lb", attrs, _} -> line_break(attrs)
      seg -> text_content(seg, :mark)
    end)
    |> squeeze()
  end

  # --- XML helpers ---

  defp find_child(children, name) when is_list(children) do
    Enum.find(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_child(_, _), do: nil

  defp find_children(children, name) when is_list(children) do
    Enum.filter(children, fn
      {^name, _, _} -> true
      _ -> false
    end)
  end

  defp find_children(_, _), do: []

  # The text of an element, whitespace collapsed, italics as <<…>>. A <note> inside it is
  # pasted in (:paste, what the header and the front matter read) or left as a mark
  # (:mark, the play text), which take_notes/2 turns into the note's offset. :breaks reads
  # as :paste, but keeps each <lb/> as a break (a note's body).
  defp text_content(element, notes \\ :paste)

  defp text_content({name, attrs, children}, notes) do
    if emph_element?(name, attrs) do
      "<<" <> extract_plain_text(children, notes) <> ">>"
    else
      children |> pieces(notes, &read_child(&1, notes, name)) |> squeeze()
    end
  end

  defp text_content(text, _notes) when is_binary(text), do: String.trim(text)
  defp text_content(_, _notes), do: ""

  @stage_parents ~w(l p seg)
  @leading_marks ~r/\A((?:\x{E000}\d+[sn]\x{E001} ?)*)(.*)\z/su

  # A child of the element `parent` being read. Under :mark (the play text) a <stage>
  # child of an <l>, <p> or <seg> is kept as a marker (InlineMarkup). Anywhere else (a
  # speaker label, a heading, a stage inside a standalone stage direction) its words are
  # pasted as text of the parent: TEI allows no <stage> there, and markers do not nest.
  defp read_child({"stage", attrs, _children} = stage, :mark, parent)
       when parent in @stage_parents,
       do: marker(stage, stage_tag(attrs), "</stage>")

  # A <seg type="aside"> of a line or paragraph partly aside (aside_text/1), likewise.
  defp read_child({"seg", _attrs, _children} = seg, :mark, parent) when parent in ~w(l p) do
    if aside_seg?(seg), do: marker(seg, "<aside>", "</aside>"), else: text_content(seg, :mark)
  end

  # A line break in the play text (:mark) or a note's body (:breaks); elsewhere, a space.
  defp read_child({"lb", attrs, _children}, notes, _parent) when notes in [:mark, :breaks],
    do: line_break(attrs)

  defp read_child(child, notes, _parent), do: text_content(child, notes)

  # `element` read as a marker opened by `open`. A note at its very start goes in front of
  # the tag, and a marker left with no words is dropped, its notes staying in the line.
  # The note leads with a space ("s") because the pieces of the element are joined by
  # one: the offset the first import stores is the one a re-import of the export
  # computes, a note before the marker.
  defp marker(element, open, close) do
    [_all, lead, words] = Regex.run(@leading_marks, text_content(element, :mark))
    lead = Regex.replace(~r/\A(\x{E000}\d+)[sn]/u, String.trim(lead), "\\1s")

    case String.trim(words) do
      "" -> lead
      words -> lead <> open <> words <> close
    end
  end

  # Where an <lb/> stood while the pieces of a text are joined and squeezed: a character
  # squeeze/1 does not take for whitespace, so the file's own line ends, which are, still
  # collapse. take_notes/2 and parse_note/2 turn it into the \n the text keeps.
  @break "\u{E002}"

  # An <lb/>: a break, or, with a number, where a printed line of the source starts. A
  # number the marker cannot hold is read as before, a space.
  defp line_break(attrs) do
    case attr_value(attrs, "n") do
      nil -> @break
      n -> printed_line(n)
    end
  end

  # The marker for printed line `n`, or nothing when `n` is absent or not a number the
  # marker can hold.
  defp printed_line(nil), do: ""

  defp printed_line(n),
    do: if(n =~ ~r/\A[A-Za-z0-9.\-]+\z/, do: InlineMarkup.number_marker(n), else: "")

  # The type goes into the marker when it is the plain word the marker allows.
  defp stage_tag(attrs) do
    type = stage_type(attrs)

    if type && type =~ ~r/\A[A-Za-z0-9_]+\z/, do: ~s(<stage type="#{type}">), else: "<stage>"
  end

  # A <stage>'s @type. 24 source files spell TEI's "delivery" "delivery_".
  defp stage_type(attrs) do
    case attr_value(attrs, "type") do
      "delivery_" -> "delivery"
      type -> type
    end
  end

  defp emph_element?("emph", _attrs), do: true

  defp emph_element?("hi", attrs),
    do: attr_value(attrs, "rend") in ["italic", "italics"]

  defp emph_element?(_, _), do: false

  defp extract_plain_text(children, notes) when is_list(children),
    do: children |> pieces(notes, &emph_child(&1, notes)) |> squeeze()

  defp emph_child({"lb", attrs, _}, notes) when notes in [:mark, :breaks], do: line_break(attrs)
  defp emph_child({_name, _attrs, children}, notes), do: extract_plain_text(children, notes)

  # Pieces of text as one string, a space between them, whitespace collapsed. A break
  # takes the place of the spaces around it; a number keeps the space before it and none
  # after, as the text read before it was kept had them.
  defp squeeze(pieces) do
    pieces
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/ ?\x{E002} ?/u, @break)
    |> String.replace(~r/(<lb n="[^"]*"\/>) /, "\\1")
    |> String.trim()
  end

  # What leaves the play text and is stored at its offset: a note, and an entry of the
  # critical apparatus.
  @apart ~w(note app)

  # `children` with each <stage> replaced by its own entries, where the stage stood: a line
  # that drops its stages (the delivery, "(Aparte)", is what is_aside says) keeps their
  # entries. A note inside the stage goes with it, and so does an entry that note copies.
  defp without_stages(children) do
    Enum.flat_map(children, fn
      {"stage", _, _} = stage -> for {"app", _, _} = app <- outermost(stage, @apart), do: app
      child -> [child]
    end)
  end

  # Each child's text, read by `fun`. Under :mark (the play text) a <note> or <app> child is
  # its mark instead; elsewhere (a note's own text) an <app> is left out, its neighbours
  # joined as written: a note that copies its line's entry keeps the line's words.
  defp pieces(children, notes, fun) do
    children = if notes == :mark, do: children, else: without(children, "app")

    children
    |> Enum.with_index()
    |> Enum.map(fn
      {{name, _, _} = note, i} when notes == :mark and name in @apart ->
        note_mark(note, children, i)

      {text, _} when is_binary(text) ->
        String.trim(text)

      {child, _} when is_tuple(child) ->
        fun.(child)

      _ ->
        ""
    end)
  end

  # Where a note was in the text being read: "\u{E000}<key><s|n>\u{E001}". The key finds
  # the note again among the element's (take_notes/2); "s" records that the source had
  # whitespace beside the note, so the words either side stay apart, and "n" that it had
  # none, so "Iliria<note/>." reads "Iliria.".
  defp note_mark(note, siblings, i) do
    before = if i > 0, do: Enum.at(siblings, i - 1)
    next = Enum.at(siblings, i + 1)

    spaced =
      (is_binary(before) and before =~ ~r/\s\z/u) or (is_binary(next) and next =~ ~r/\A\s/u)

    "\u{E000}#{:erlang.phash2(note)}#{if spaced, do: "s", else: "n"}\u{E001}"
  end

  @note_mark ~r/ ?\x{E000}(\d+)([sn])\x{E001} ?/u

  # Takes the note marks out of `marked`, text `element` was read into with :mark.
  # Returns the text and its notes (parse_note/2), each offset counting graphemes of the text
  # without its << and >> markers and stage tags, as InlineMarkup.plain/1 does. A note
  # whose mark the reading dropped (inside a stripped aside <stage>) is dropped with it.
  # So is a note with no text. An entry inside a note that copies none of the element's
  # comes out after the note (strays/2).
  # ponytail: two adjacent notes each with whitespace beside them ("a <note/><note/> b")
  # store "a  b" and the second note one grapheme later; the corpus has no note after a
  # space. Carry a pending space to the next text if one turns up.
  defp take_notes(marked, element) do
    by_key = Map.new(outermost(element, @apart), &{Integer.to_string(:erlang.phash2(&1)), &1})

    own =
      for {"app", attrs, _} <- outermost(element, @apart),
          into: MapSet.new(),
          do: attr_value(attrs, "n")

    {text, found} =
      @note_mark
      |> Regex.split(marked, include_captures: true)
      |> Enum.reduce({"", []}, fn piece, {text, found} ->
        case Regex.run(@note_mark, piece) do
          [_, key, spaced] ->
            space =
              if spaced == "s" and text != "" and not String.ends_with?(text, @break),
                do: " ",
                else: ""

            {text <> space, [{plain_length(text), Map.fetch!(by_key, key)} | found]}

          nil ->
            {text <> piece, found}
        end
      end)

    text = text |> String.trim_trailing() |> String.replace(@break, "\n")
    last = plain_length(text)

    {text,
     found
     |> Enum.reverse()
     |> Enum.flat_map(fn {offset, note} ->
       offset = min(offset, last)
       parse_note(note, offset) ++ Enum.flat_map(strays(note, own), &parse_note(&1, offset))
     end)}
  end

  # The <app>s inside a note that copy none of its element's entries (`own`, their `n`s):
  # EMOTHE0530's n="496", only in the note on "ne". They move into the line, after the
  # note; the others are copies of the line's entry, which the note's text leaves out.
  defp strays({"note", _, _} = note, own),
    do: note |> outermost(["app"]) |> Enum.reject(&(attr_value(elem(&1, 1), "n") in own))

  defp strays(_app, _own), do: []

  @inline_marker ~r/<<|>>|<stage(?: type="[A-Za-z0-9_]+")?>|<\/stage>|<\/?aside>|<lb n="[A-Za-z0-9.\-]+"\/>/

  # Graphemes of `text` without its markers, one marker at a time: a note inside an
  # italic run or a stage is read while the run is still open, so InlineMarkup.plain/1,
  # which needs the closing marker, cannot do it.
  defp plain_length(text), do: text |> String.replace(@inline_marker, "") |> String.length()

  # The elements named `names` inside `element`, not counting those inside them: a line's
  # notes and entries, not a note's own entries or an entry's readings' notes.
  defp outermost({_name, _attrs, children}, names) do
    Enum.flat_map(children, fn
      {name, _, _} = child -> if name in names, do: [child], else: outermost(child, names)
      _text -> []
    end)
  end

  # An element of the play text read with its notes taken out: `{text, [note]}`, or
  # `{nil, []}` for no element.
  defp text_and_notes(nil), do: {nil, []}
  defp text_and_notes(element), do: element |> text_content(:mark) |> take_notes(element)

  # A note's fields at `offset`, as a list: empty when the note has no text, since there is
  # nothing to show (the empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children} = note, offset) do
    case note_text(note) do
      nil ->
        []

      body ->
        term = safe_text(find_child(children, "term"))

        [
          %{
            offset: offset,
            n: attr_value(attrs, "n"),
            type: attr_value(attrs, "type"),
            term: if(term in [nil, ""], do: nil, else: term),
            body: body
          }
        ]
    end
  end

  # An entry of the critical apparatus: a variant (Note.variant/0) at `offset`, its readings
  # in order, each without its own note, which is the reading's; the entry's own note is its
  # body. An empty entry is kept: Hamlet's damaged ones are written back as they are.
  defp parse_note({"app", attrs, children}, offset) do
    [
      %{
        offset: offset,
        n: attr_value(attrs, "n"),
        type: Note.variant(),
        variant_type: attr_value(attrs, "type"),
        range_end: attr_value(attrs, "to"),
        body: note_text(find_child(children, "note")),
        readings:
          for {name, reading_attrs, reading_children} <- children, name in ~w(lem rdg) do
            %{
              lemma: name == "lem",
              wit: attr_value(reading_attrs, "wit"),
              text: text_content({name, reading_attrs, without(reading_children, "note")}),
              note: note_text(find_child(reading_children, "note"))
            }
          end
      }
    ]
  end

  # A note's text: its paragraphs, a blank line between them, its <term> left out; nil for
  # no note, or one with no text (a note of nothing but breaks, EMOTHE0299's <p><lb/></p>).
  defp note_text(nil), do: nil

  defp note_text({"note", attrs, children}) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content(
            {"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))},
            :breaks
          )

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content(&1, :breaks))
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end
      |> String.replace(@break, "\n")

    if String.trim(body) == "", do: nil, else: body
  end

  # `children` without the `name` elements, the text either side joined as written: "is" and
  # "»" around an <app> read "is»", not "is »".
  defp without(children, name) do
    children
    |> Enum.reject(&match?({^name, _, _}, &1))
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = texts when is_binary(text) -> [Enum.join(texts)]
      elements -> elements
    end)
  end

  defp safe_text(nil), do: nil
  defp safe_text(element) when is_tuple(element), do: text_content(element)
  defp safe_text(text) when is_binary(text), do: String.trim(text)

  defp attr_value(attrs, key) when is_list(attrs) do
    case List.keyfind(attrs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp attr_value(_, _), do: nil

  defp has_attr?(attrs, key), do: attr_value(attrs, key) != nil

  defp parse_int(nil), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp clean_code(code) do
    code
    |> String.trim()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "")
  end

  defp normalize_imported_title(nil), do: nil

  defp normalize_imported_title(title) when is_binary(title) do
    normalized_title = String.trim(title)

    if all_caps_text?(normalized_title) do
      normalized_title
      |> then(&Regex.split(~r/(\s+)/u, &1, include_captures: true))
      |> Enum.reduce({[], true}, fn segment, {acc, first_word?} ->
        if Regex.match?(~r/^\s+$/u, segment) do
          {[segment | acc], first_word?}
        else
          formatted_segment = format_title_segment(segment, first_word?)
          {[formatted_segment | acc], false}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.join()
    else
      normalized_title
    end
  end

  defp all_caps_text?(text) do
    String.match?(text, ~r/\p{L}/u) && text == String.upcase(text) &&
      text != String.downcase(text)
  end

  defp format_title_segment(segment, first_word?) do
    case Regex.run(~r/^([^\p{L}\p{N}]*)([\p{L}\p{N}'’\-]+)([^\p{L}\p{N}]*)$/u, segment) do
      [_, leading, core, trailing] ->
        downcased_core = String.downcase(core)

        formatted_core =
          cond do
            Regex.match?(~r/^[ivxlcdm]+$/iu, core) ->
              String.upcase(core)

            not first_word? and MapSet.member?(@title_small_words, downcased_core) ->
              downcased_core

            true ->
              String.capitalize(downcased_core)
          end

        leading <> formatted_core <> trailing

      _ ->
        segment
    end
  end
end
